defmodule Sonar.MCPServer do
  @moduledoc """
  MCP server over stdio. Reads JSON-RPC from stdin, executes actions
  via ActionRegistry, writes responses to stdout. Same actions as the
  HTTP API — one definition, two surfaces.

  Start standalone:
    elixir --no-halt -S mix run -e "Sonar.MCPServer.start_link([])"

  Or launch via Mix task:
    mix sonar.mcp
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Read stdin asynchronously
    spawn_link(fn -> read_loop() end)
    {:ok, %{buffer: ""}}
  end

  defp read_loop do
    case IO.read(:stdio, :line) do
      :eof -> :ok
      {:error, _} -> :ok
      data ->
        GenServer.cast(__MODULE__, {:data, data})
        read_loop()
    end
  end

  def handle_cast({:data, data}, state) do
    buffer = state.buffer <> data
    {messages, remaining} = extract_messages(buffer)

    for msg <- messages do
      handle_jsonrpc(msg)
    end

    {:noreply, %{state | buffer: remaining}}
  end

  defp extract_messages(buffer) do
    extract_messages(buffer, [])
  end

  defp extract_messages(buffer, acc) do
    case Regex.run(~r/Content-Length:\s*(\d+)\r?\n\r?\n/i, buffer, return: :index) do
      [{header_start, header_len}, {num_start, num_len}] ->
        content_length = buffer |> binary_part(num_start, num_len) |> String.to_integer()
        body_start = header_start + header_len

        if byte_size(buffer) >= body_start + content_length do
          body = binary_part(buffer, body_start, content_length)
          remaining = binary_part(buffer, body_start + content_length, byte_size(buffer) - body_start - content_length)

          case Jason.decode(body) do
            {:ok, msg} -> extract_messages(remaining, [msg | acc])
            _ -> extract_messages(remaining, acc)
          end
        else
          {Enum.reverse(acc), buffer}
        end

      _ ->
        {Enum.reverse(acc), buffer}
    end
  end

  defp handle_jsonrpc(%{"method" => "initialize", "id" => id}) do
    respond(id, %{
      protocolVersion: "2024-11-05",
      capabilities: %{tools: %{}},
      serverInfo: %{name: "sonar", version: "0.1.0"}
    })
  end

  defp handle_jsonrpc(%{"method" => "notifications/initialized"}) do
    # No response needed
    :ok
  end

  defp handle_jsonrpc(%{"method" => "tools/list", "id" => id}) do
    tools = Sonar.ActionRegistry.mcp_tool_schemas()
    respond(id, %{tools: tools})
  end

  defp handle_jsonrpc(%{"method" => "tools/call", "id" => id, "params" => params}) do
    name = params["name"]
    args = params["arguments"] || %{}

    case Sonar.ActionRegistry.execute(name, args) do
      {:ok, result} ->
        respond(id, %{
          content: [%{type: "text", text: Jason.encode!(result, pretty: true)}]
        })

      {:error, :not_found} ->
        respond(id, %{
          content: [%{type: "text", text: "Not found"}],
          isError: true
        })

      {:error, reason} ->
        respond(id, %{
          content: [%{type: "text", text: "Error: #{inspect(reason)}"}],
          isError: true
        })
    end
  end

  defp handle_jsonrpc(%{"method" => "ping", "id" => id}) do
    respond(id, %{})
  end

  defp handle_jsonrpc(_msg), do: :ok

  defp respond(id, result) do
    msg = Jason.encode!(%{jsonrpc: "2.0", id: id, result: result})
    header = "Content-Length: #{byte_size(msg)}\r\n\r\n"
    IO.write(:stdio, header <> msg)
  end
end
