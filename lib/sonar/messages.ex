defmodule Sonar.Messages do
  @moduledoc """
  Context module for message operations.
  """

  import Ecto.Query
  alias Sonar.Repo
  alias Sonar.Schema.Message

  def inbox(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)

    query =
      from(m in Message,
        where: m.direction == "inbound",
        order_by: [desc: m.inserted_at],
        limit: ^limit
      )

    query = if status, do: where(query, [m], m.status == ^status), else: query
    Repo.all(query)
  end

  def get(id) do
    Repo.get(Message, id)
  end

  def send_message(attrs) do
    id = gen_id()

    result =
      %Message{}
      |> Message.changeset(
        Map.merge(attrs, %{"id" => id, "direction" => "outbound", "status" => "pending"})
      )
      |> Repo.insert()

    # Attempt delivery via Erlang distribution if peer is connected
    case result do
      {:ok, message} ->
        maybe_relay_message(message)
        {:ok, message}

      error ->
        error
    end
  end

  def reply(message, answer) do
    result =
      message
      |> Message.changeset(%{
        "answer" => answer,
        "status" => "answered",
        "answered_at" => DateTime.utc_now()
      })
      |> Repo.update()

    # Push response back to peer if connected
    case result do
      {:ok, updated} ->
        maybe_relay_response(updated)
        SonarWeb.Endpoint.broadcast("messages:events", "reply_sent", %{message_id: updated.id, answer: answer})
        {:ok, updated}

      error ->
        error
    end
  end

  def update_answer(message_id, answer) do
    case get(message_id) do
      nil -> {:error, :not_found}
      message ->
        message
        |> Message.changeset(%{"answer" => answer, "status" => "answered", "answered_at" => DateTime.utc_now()})
        |> Repo.update()
    end
  end

  def receive_message(attrs) do
    %Message{}
    |> Message.changeset(Map.merge(attrs, %{"direction" => "inbound", "status" => "pending"}))
    |> Repo.insert()
  end

  defp maybe_relay_message(message) do
    if message.peer_id != nil do
      payload = %{
        "question" => message.question,
        "context" => message.context,
        "message_id" => message.id,
        "expires_at" => message.expires_at
      }

      # Try Erlang distribution first, fall back to HTTP
      relayed =
        if relay_available?() do
          case Sonar.Relay.send_message(message.peer_id, payload) do
            :ok -> true
            _ -> false
          end
        else
          false
        end

      unless relayed, do: http_relay_message(message.peer_id, payload)
    end
  end

  defp maybe_relay_response(message) do
    if message.peer_id != nil && message.answer != nil do
      # Use remote_message_id if available (the sender's original message ID)
      response_to = message.remote_message_id || message.id
      payload = %{
        "response_to" => response_to,
        "answer" => message.answer
      }

      relayed =
        if relay_available?() do
          case Sonar.Relay.send_message(message.peer_id, payload) do
            :ok -> true
            _ -> false
          end
        else
          false
        end

      unless relayed, do: http_relay_response(message.peer_id, response_to, message.answer)
    end
  end

  defp relay_available? do
    Process.whereis(Sonar.Relay) != nil
  end

  # HTTP fallback for message delivery when Erlang distribution isn't connected
  defp http_relay_message(peer_id, payload) do
    case Sonar.Peers.get(peer_id) do
      nil -> {:error, :peer_not_found}
      peer ->
        identity = Sonar.Identity.get()
        url = "http://#{peer.hostname}:#{peer.port}/api/messages/receive"
        body = Jason.encode!(%{from_instance_id: identity.instance_id, message: payload})
        http_post(url, body)
    end
  end

  defp http_relay_response(peer_id, message_id, answer) do
    case Sonar.Peers.get(peer_id) do
      nil -> {:error, :peer_not_found}
      peer ->
        identity = Sonar.Identity.get()
        url = "http://#{peer.hostname}:#{peer.port}/api/messages/receive_response"
        body = Jason.encode!(%{from_instance_id: identity.instance_id, message_id: message_id, answer: answer})
        http_post(url, body)
    end
  end

  defp http_post(url, body) do
    uri = URI.parse(url)
    host = String.to_charlist(uri.host || "127.0.0.1")
    port = uri.port || 80
    path = uri.path || "/"

    case :gen_tcp.connect(host, port, [:binary, active: false], 5_000) do
      {:ok, socket} ->
        request = "POST #{path} HTTP/1.1\r\nHost: #{uri.host}:#{port}\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\nConnection: close\r\n\r\n#{body}"
        :gen_tcp.send(socket, request)
        result = :gen_tcp.recv(socket, 0, 10_000)
        :gen_tcp.close(socket)
        case result do
          {:ok, response} ->
            if String.contains?(response, "200") or String.contains?(response, "201"), do: :ok, else: {:error, response}
          error -> error
        end
      error -> error
    end
  end

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
