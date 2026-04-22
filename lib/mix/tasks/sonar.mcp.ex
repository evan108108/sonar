defmodule Mix.Tasks.Sonar.Mcp do
  @moduledoc """
  Starts the Sonar MCP server over stdio.

  Usage in Claude Code MCP config:
    "sonar": { "command": "mix", "args": ["sonar.mcp"], "cwd": "/path/to/sonar" }

  Or with elixir directly:
    cd /path/to/sonar && mix sonar.mcp
  """

  use Mix.Task

  @shortdoc "Start the Sonar MCP server (stdio JSON-RPC)"

  @impl Mix.Task
  def run(_args) do
    # Start the full application (Repo, Identity, etc.)
    Mix.Task.run("app.start")

    # Start the MCP server
    {:ok, _pid} = Sonar.MCPServer.start_link([])

    # Keep the process alive
    Process.sleep(:infinity)
  end
end
