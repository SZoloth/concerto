defmodule SymphonyElixir.Claude.AppServer do
  @moduledoc """
  Client for Claude Code's print mode (`claude -p`) with streaming JSON output.

  Unlike the Codex app-server which maintains a persistent JSON-RPC connection,
  Claude Code's print mode is one-shot per turn: each `run_turn` spawns a new
  `claude -p` process, sends the prompt via a temp file on stdin, parses
  stream-json output, and waits for the process to exit.

  Multi-turn context is preserved via `--session-id` and `--continue` flags,
  which persist session state to disk between invocations.

  Tool injection (e.g. linear_graphql) is handled via MCP servers passed
  through `--mcp-config`, so no tool call interception is needed on the
  orchestrator side. Permissions are handled via `--permission-mode bypassPermissions`.
  """

  require Logger
  alias SymphonyElixir.{Claude.McpConfig, Config, PathSafety, SSH}

  @port_line_bytes 1_048_576
  @max_stream_log_bytes 1_000

  @type session :: %{
          session_id: String.t(),
          workspace: Path.t(),
          worker_host: String.t() | nil,
          mcp_config_path: Path.t() | nil,
          turn_count: non_neg_integer()
        }

  @spec run(Path.t(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run(workspace, prompt, issue, opts \\ []) do
    with {:ok, session} <- start_session(workspace, opts) do
      try do
        run_turn(session, prompt, issue, opts)
      after
        stop_session(session)
      end
    end
  end

  @spec start_session(Path.t(), keyword()) :: {:ok, session()} | {:error, term()}
  def start_session(workspace, opts \\ []) do
    worker_host = Keyword.get(opts, :worker_host)

    with {:ok, expanded_workspace} <- validate_workspace_cwd(workspace, worker_host),
         {:ok, mcp_config_path} <- write_mcp_config(expanded_workspace, worker_host) do
      session_id = generate_session_id()

      {:ok,
       %{
         session_id: session_id,
         workspace: expanded_workspace,
         worker_host: worker_host,
         mcp_config_path: mcp_config_path,
         turn_count: 0
       }}
    end
  end

  @spec run_turn(session(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def run_turn(session, prompt, issue, opts \\ []) do
    on_message = Keyword.get(opts, :on_message, &default_on_message/1)
    turn_number = session.turn_count + 1

    Logger.info("Claude turn starting for #{issue_context(issue)} session_id=#{session.session_id} turn=#{turn_number}")

    with {:ok, prompt_path} <- write_prompt_file(prompt) do
      try do
        with {:ok, command} <- build_command(session, turn_number, issue),
             {:ok, port} <- start_port(command, session.workspace, prompt_path, session.worker_host) do
          metadata = port_metadata(port, session.worker_host)

          emit_message(
            on_message,
            :session_started,
            %{
              session_id: session.session_id,
              turn_number: turn_number
            },
            metadata
          )

          case await_completion(port, on_message, metadata) do
            {:ok, result} ->
              Logger.info("Claude turn completed for #{issue_context(issue)} session_id=#{session.session_id} turn=#{turn_number}")

              {:ok,
               %{
                 result: result,
                 session_id: session.session_id,
                 turn_number: turn_number
               }}

            {:error, reason} ->
              Logger.warning("Claude turn ended with error for #{issue_context(issue)} session_id=#{session.session_id} turn=#{turn_number}: #{inspect(reason)}")

              emit_message(
                on_message,
                :turn_ended_with_error,
                %{session_id: session.session_id, reason: reason},
                metadata
              )

              {:error, reason}
          end
        end
      after
        cleanup_prompt_file(prompt_path)
      end
    end
  end

  @spec stop_session(session()) :: :ok
  def stop_session(%{mcp_config_path: mcp_config_path}) do
    McpConfig.cleanup(mcp_config_path)
    :ok
  end

  # -- Command building --

  defp build_command(session, turn_number, issue) do
    claude_config = Config.settings!().claude
    base = claude_config.command

    flags =
      [
        "--output-format",
        "stream-json",
        "--verbose",
        "--model",
        resolve_model(claude_config, issue, turn_number),
        "--session-id",
        session.session_id,
        "--permission-mode",
        claude_config.permission_mode
      ]
      |> maybe_add_continue(turn_number)
      |> maybe_add_mcp_config(session.mcp_config_path)
      |> maybe_add_timeout(claude_config.turn_timeout_ms)

    {:ok, Enum.join([base | flags], " ")}
  end

  defp resolve_model(claude_config, issue, turn_number) do
    {model, reason} =
      cond do
        turn_number == 1 and is_binary(claude_config.planning_model) ->
          {claude_config.planning_model, "planning turn"}

        turn_number > 1 and is_binary(claude_config.execution_model) ->
          resolve_with_upgrades(claude_config, issue, claude_config.execution_model)

        upgraded_by_label?(claude_config, issue) ->
          {claude_config.upgrade_model, "label match"}

        upgraded_by_priority?(claude_config, issue) ->
          {claude_config.upgrade_model, "priority #{Map.get(issue, :priority)}"}

        true ->
          {claude_config.model, "default"}
      end

    if model != claude_config.model do
      Logger.info("Model resolved to #{model} for #{Map.get(issue, :identifier, "unknown")} (#{reason})")
    end

    model
  end

  defp resolve_with_upgrades(claude_config, issue, base_model) do
    cond do
      upgraded_by_label?(claude_config, issue) ->
        {claude_config.upgrade_model, "label match (execution)"}

      upgraded_by_priority?(claude_config, issue) ->
        {claude_config.upgrade_model, "priority #{Map.get(issue, :priority)} (execution)"}

      true ->
        {base_model, "execution turn"}
    end
  end

  defp upgraded_by_label?(%{upgrade_labels: []}, _issue), do: false

  defp upgraded_by_label?(%{upgrade_labels: upgrade_labels}, %{labels: labels})
       when is_list(labels) do
    normalized_upgrade = MapSet.new(upgrade_labels, &String.downcase/1)
    Enum.any?(labels, &MapSet.member?(normalized_upgrade, String.downcase(&1)))
  end

  defp upgraded_by_label?(_config, _issue), do: false

  defp upgraded_by_priority?(%{upgrade_priorities: []}, _issue), do: false

  defp upgraded_by_priority?(%{upgrade_priorities: priorities}, %{priority: priority})
       when is_integer(priority) do
    priority in priorities
  end

  defp upgraded_by_priority?(_config, _issue), do: false

  defp maybe_add_continue(flags, turn_number) when turn_number > 1, do: flags ++ ["--continue"]
  defp maybe_add_continue(flags, _turn_number), do: flags

  defp maybe_add_mcp_config(flags, nil), do: flags
  defp maybe_add_mcp_config(flags, path), do: flags ++ ["--mcp-config", shell_escape(path)]

  defp maybe_add_timeout(flags, _timeout_ms), do: flags

  # -- Port management --

  defp start_port(command, workspace, prompt_path, nil) do
    executable = System.find_executable("bash")

    if is_nil(executable) do
      {:error, :bash_not_found}
    else
      full_command = "#{command} < #{shell_escape(prompt_path)}"

      port =
        Port.open(
          {:spawn_executable, String.to_charlist(executable)},
          [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: [~c"-lc", String.to_charlist(full_command)],
            cd: String.to_charlist(workspace),
            line: @port_line_bytes
          ]
        )

      {:ok, port}
    end
  end

  defp start_port(command, workspace, prompt_path, worker_host) when is_binary(worker_host) do
    remote_command = "cd #{shell_escape(workspace)} && #{command} < #{shell_escape(prompt_path)}"
    SSH.start_port(worker_host, remote_command, line: @port_line_bytes)
  end

  # -- Stream-json parsing --
  #
  # Claude Code's stream-json output emits one JSON object per line:
  #
  #   {"type":"system","subtype":"init","session_id":"...","tools":[...],"model":"..."}
  #   {"type":"stream_event","event":{"type":"content_block_delta","delta":{"text":"..."}}}
  #   {"type":"assistant","message":{...}}
  #   {"type":"result","subtype":"success","total_cost_usd":0.02,"usage":{...},...}
  #
  # We stream-parse each line, emit events for observability, and wait for the
  # final "result" event which signals turn completion.

  defp await_completion(port, on_message, metadata) do
    receive_loop(port, on_message, metadata, Config.settings!().claude.turn_timeout_ms, "")
  end

  defp receive_loop(port, on_message, metadata, timeout_ms, pending_line) do
    receive do
      {^port, {:data, {:eol, chunk}}} ->
        complete_line = pending_line <> to_string(chunk)
        handle_stream_line(port, on_message, metadata, complete_line, timeout_ms)

      {^port, {:data, {:noeol, chunk}}} ->
        receive_loop(port, on_message, metadata, timeout_ms, pending_line <> to_string(chunk))

      {^port, {:exit_status, 0}} ->
        Logger.warning("Claude process exited cleanly without emitting a result event")
        {:ok, :turn_completed}

      {^port, {:exit_status, status}} ->
        {:error, {:port_exit, status}}
    after
      timeout_ms ->
        stop_port(port)
        {:error, :turn_timeout}
    end
  end

  defp handle_stream_line(port, on_message, metadata, data, timeout_ms) do
    case Jason.decode(data) do
      {:ok, %{"type" => "result"} = payload} ->
        handle_result_event(port, on_message, metadata, payload, data)

      {:ok, %{"type" => "system", "subtype" => "init"} = payload} ->
        updated_metadata = maybe_set_usage(metadata, payload)

        emit_message(
          on_message,
          :session_initialized,
          %{
            payload: payload,
            raw: data,
            model: Map.get(payload, "model"),
            tools: Map.get(payload, "tools", [])
          },
          updated_metadata
        )

        receive_loop(port, on_message, updated_metadata, timeout_ms, "")

      {:ok, %{"type" => "assistant"} = payload} ->
        updated_metadata = maybe_set_usage(metadata, payload)

        emit_message(
          on_message,
          :assistant_message,
          %{payload: payload, raw: data},
          updated_metadata
        )

        receive_loop(port, on_message, updated_metadata, timeout_ms, "")

      {:ok, %{"type" => "stream_event"} = payload} ->
        emit_message(
          on_message,
          :stream_event,
          %{payload: payload, raw: data},
          metadata
        )

        receive_loop(port, on_message, metadata, timeout_ms, "")

      {:ok, payload} ->
        emit_message(
          on_message,
          :other_message,
          %{payload: payload, raw: data},
          metadata
        )

        receive_loop(port, on_message, metadata, timeout_ms, "")

      {:error, _reason} ->
        log_non_json_stream_line(data)

        emit_message(
          on_message,
          :malformed,
          %{payload: data, raw: data},
          metadata
        )

        receive_loop(port, on_message, metadata, timeout_ms, "")
    end
  end

  defp handle_result_event(_port, on_message, metadata, payload, raw) do
    is_error = Map.get(payload, "is_error", false)
    updated_metadata = maybe_set_usage(metadata, payload)

    cost_metadata =
      case Map.get(payload, "total_cost_usd") do
        cost when is_number(cost) -> Map.put(updated_metadata, :total_cost_usd, cost)
        _ -> updated_metadata
      end

    if is_error do
      emit_message(
        on_message,
        :turn_failed,
        %{
          payload: payload,
          raw: raw,
          details: %{
            subtype: Map.get(payload, "subtype"),
            result: Map.get(payload, "result")
          }
        },
        cost_metadata
      )

      {:error, {:turn_failed, Map.get(payload, "result", "unknown error")}}
    else
      emit_message(
        on_message,
        :turn_completed,
        %{
          payload: payload,
          raw: raw,
          details: %{
            subtype: Map.get(payload, "subtype"),
            result: Map.get(payload, "result"),
            duration_ms: Map.get(payload, "duration_ms"),
            num_turns: Map.get(payload, "num_turns"),
            session_id: Map.get(payload, "session_id")
          }
        },
        cost_metadata
      )

      {:ok, :turn_completed}
    end
  end

  # -- Workspace validation (preserved from original) --

  defp validate_workspace_cwd(workspace, nil) when is_binary(workspace) do
    expanded_workspace = Path.expand(workspace)
    expanded_root = Path.expand(Config.settings!().workspace.root)
    expanded_root_prefix = expanded_root <> "/"

    with {:ok, canonical_workspace} <- PathSafety.canonicalize(expanded_workspace),
         {:ok, canonical_root} <- PathSafety.canonicalize(expanded_root) do
      canonical_root_prefix = canonical_root <> "/"

      cond do
        canonical_workspace == canonical_root ->
          {:error, {:invalid_workspace_cwd, :workspace_root, canonical_workspace}}

        String.starts_with?(canonical_workspace <> "/", canonical_root_prefix) ->
          {:ok, canonical_workspace}

        String.starts_with?(expanded_workspace <> "/", expanded_root_prefix) ->
          {:error, {:invalid_workspace_cwd, :symlink_escape, expanded_workspace, canonical_root}}

        true ->
          {:error, {:invalid_workspace_cwd, :outside_workspace_root, canonical_workspace, canonical_root}}
      end
    else
      {:error, {:path_canonicalize_failed, path, reason}} ->
        {:error, {:invalid_workspace_cwd, :path_unreadable, path, reason}}
    end
  end

  defp validate_workspace_cwd(workspace, worker_host)
       when is_binary(workspace) and is_binary(worker_host) do
    cond do
      String.trim(workspace) == "" ->
        {:error, {:invalid_workspace_cwd, :empty_remote_workspace, worker_host}}

      String.contains?(workspace, ["\n", "\r", <<0>>]) ->
        {:error, {:invalid_workspace_cwd, :invalid_remote_workspace, worker_host, workspace}}

      true ->
        {:ok, workspace}
    end
  end

  # -- MCP config --

  defp write_mcp_config(_workspace, worker_host) when is_binary(worker_host) do
    # Remote workers don't get MCP config (Linear tool must be configured on the remote host)
    {:ok, nil}
  end

  defp write_mcp_config(workspace, nil) do
    McpConfig.write_config(workspace)
  end

  # -- Prompt file management --

  defp write_prompt_file(prompt) do
    path = Path.join(System.tmp_dir!(), "concerto_prompt_#{:erlang.unique_integer([:positive, :monotonic])}")

    case File.write(path, prompt) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:prompt_write_failed, reason}}
    end
  end

  defp cleanup_prompt_file(path) when is_binary(path), do: File.rm(path)
  defp cleanup_prompt_file(_path), do: :ok

  # -- Helpers --

  defp generate_session_id do
    <<a::32, b::16, c::16, d::16, e::48>> = :crypto.strong_rand_bytes(16)

    :io_lib.format("~8.16.0b-~4.16.0b-~4.16.0b-~4.16.0b-~12.16.0b", [a, b, c, d, e])
    |> IO.iodata_to_binary()
    |> String.downcase()
  end

  defp port_metadata(port, worker_host) when is_port(port) do
    base_metadata =
      case :erlang.port_info(port, :os_pid) do
        {:os_pid, os_pid} -> %{claude_pid: to_string(os_pid)}
        _ -> %{}
      end

    case worker_host do
      host when is_binary(host) -> Map.put(base_metadata, :worker_host, host)
      _ -> base_metadata
    end
  end

  defp maybe_set_usage(metadata, payload) when is_map(payload) do
    usage = Map.get(payload, "usage") || Map.get(payload, :usage)

    if is_map(usage) do
      Map.put(metadata, :usage, usage)
    else
      metadata
    end
  end

  defp maybe_set_usage(metadata, _payload), do: metadata

  defp stop_port(port) when is_port(port) do
    case :erlang.port_info(port) do
      :undefined ->
        :ok

      _ ->
        try do
          Port.close(port)
          :ok
        rescue
          ArgumentError -> :ok
        end
    end
  end

  defp emit_message(on_message, event, details, metadata) when is_function(on_message, 1) do
    message =
      metadata
      |> Map.merge(details)
      |> Map.put(:event, event)
      |> Map.put(:timestamp, DateTime.utc_now())

    on_message.(message)
  end

  defp log_non_json_stream_line(data) do
    text =
      data
      |> to_string()
      |> String.trim()
      |> String.slice(0, @max_stream_log_bytes)

    if text != "" do
      if String.match?(text, ~r/\b(error|warn|warning|failed|fatal|panic|exception)\b/i) do
        Logger.warning("Claude stream output: #{text}")
      else
        Logger.debug("Claude stream output: #{text}")
      end
    end
  end

  defp issue_context(%{id: issue_id, identifier: identifier}) do
    "issue_id=#{issue_id} issue_identifier=#{identifier}"
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end

  defp default_on_message(_message), do: :ok
end
