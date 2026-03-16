defmodule SymphonyElixir.Claude.McpConfigTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Claude.McpConfig

  test "write_config creates a valid MCP config file with linear server" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-mcp-config-write-#{System.unique_integer([:positive])}"
      )

    try do
      File.mkdir_p!(test_root)

      assert {:ok, config_path} = McpConfig.write_config(test_root)
      assert String.ends_with?(config_path, ".concerto-mcp.json")
      assert File.exists?(config_path)

      config = config_path |> File.read!() |> Jason.decode!()
      assert %{"mcpServers" => %{"linear" => server}} = config
      assert server["command"] == "python3"
      assert is_list(server["args"])
      assert length(server["args"]) == 1
      assert String.ends_with?(hd(server["args"]), "linear_graphql_server.py")
    after
      File.rm_rf(test_root)
    end
  end

  test "cleanup removes the MCP config file" do
    test_root =
      Path.join(
        System.tmp_dir!(),
        "symphony-elixir-mcp-config-cleanup-#{System.unique_integer([:positive])}"
      )

    try do
      File.mkdir_p!(test_root)

      {:ok, config_path} = McpConfig.write_config(test_root)
      assert File.exists?(config_path)

      assert :ok = McpConfig.cleanup(config_path)
      refute File.exists?(config_path)
    after
      File.rm_rf(test_root)
    end
  end

  test "cleanup with nil path is a no-op" do
    assert :ok = McpConfig.cleanup(nil)
  end

  # --------------------------------------------------------------------------
  # Skipped: DynamicTool execution tests
  #
  # The following tests verified the old DynamicTool.execute/2,3 and
  # DynamicTool.tool_specs/0 functions that handled linear_graphql tool calls
  # inline within the Codex JSON-RPC protocol. In the Claude Code protocol,
  # tool execution is handled by an external MCP server
  # (priv/mcp/linear_graphql_server.py), so these tests no longer apply to
  # McpConfig which only writes/cleans config files.
  # --------------------------------------------------------------------------

  @tag :skip
  # TODO: Tool execution moved to MCP server (priv/mcp/linear_graphql_server.py)
  test "tool_specs advertises the linear_graphql input contract" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "unsupported tools return a failure payload with the supported tool list" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql returns successful GraphQL responses as tool text" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql accepts a raw GraphQL query string" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql ignores legacy operationName arguments" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql passes multi-operation documents through unchanged" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql rejects blank raw query strings even when using the default client" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql marks GraphQL error responses as failures while preserving the body" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql marks atom-key GraphQL error responses as failures" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql validates required arguments before calling Linear" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql rejects invalid argument types" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql rejects invalid variables" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql formats transport and auth failures" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql formats unexpected failures from the client" do
  end

  @tag :skip
  # TODO: Tool execution moved to MCP server
  test "linear_graphql falls back to inspect for non-JSON payloads" do
  end
end
