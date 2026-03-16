defmodule SymphonyElixir.Claude.McpConfig do
  @moduledoc """
  Generates temporary MCP configuration files for Claude Code sessions.
  """

  @spec write_config(Path.t()) :: {:ok, Path.t()} | {:error, term()}
  def write_config(workspace) do
    config = %{
      "mcpServers" => %{
        "linear" => %{
          "command" => "python3",
          "args" => [mcp_server_script()],
          "env" => mcp_env()
        }
      }
    }

    config_path = Path.join(workspace, ".concerto-mcp.json")

    case File.write(config_path, Jason.encode!(config)) do
      :ok -> {:ok, config_path}
      {:error, reason} -> {:error, {:mcp_config_write_failed, reason}}
    end
  end

  @spec cleanup(Path.t() | nil) :: :ok
  def cleanup(nil), do: :ok

  def cleanup(config_path) do
    File.rm(config_path)
    :ok
  end

  defp mcp_server_script do
    Path.join(:code.priv_dir(:symphony_elixir), "mcp/linear_graphql_server.py")
  end

  defp mcp_env do
    case System.get_env("LINEAR_API_KEY") do
      nil -> %{}
      key -> %{"LINEAR_API_KEY" => key}
    end
  end
end
