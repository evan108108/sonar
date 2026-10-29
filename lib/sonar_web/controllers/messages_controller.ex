defmodule SonarWeb.MessagesController do
  use SonarWeb, :controller

  alias Sonar.Messages

  def inbox(conn, params) do
    opts =
      [
        limit: parse_int(params["limit"]) || 50,
        status: params["status"]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    messages = Messages.inbox(opts)
    json(conn, Enum.map(messages, &message_to_json/1))
  end

  def show(conn, %{"id" => id}) do
    case Messages.get(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Message not found"})
      message -> json(conn, message_to_json(message))
    end
  end

  def send_message(conn, %{"peer_id" => peer_id, "question" => question} = params) do
    attrs = %{
      "peer_id" => peer_id,
      "question" => question,
      "context" => params["context"],
      "expires_at" => parse_datetime(params["expires_at"]),
      "callback_url" => params["callback_url"],
      "target_session_id" => params["target_session_id"],
      "from_session_id" => params["from_session_id"],
      # Honor the origin's message id so it stays stable across the whole hop
      # (origin audit row -> wire -> receiver event -> ack). Falls back to a
      # generated id when absent (see Messages.send_message).
      "message_id" => params["message_id"],
      # Pass-through extras — forwarded verbatim on the wire, not persisted.
      "in_reply_to" => params["in_reply_to"],
      "sender_display" => params["sender_display"]
    }

    case Messages.send_message(attrs) do
      {:ok, message} ->
        # 202 kept for wire compat; `status` now reflects the actual relay
        # outcome ("relayed" | "failed" | "pending"), not a hardcoded value.
        conn
        |> put_status(202)
        |> json(%{
          message_id: message.id,
          status: message.status,
          failure_reason: message.failure_reason,
          poll_url: "/api/messages/#{message.id}"
        })

      {:error, changeset} ->
        conn |> put_status(422) |> json(%{error: format_errors(changeset)})
    end
  end

  def send_message(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing required fields: peer_id, question"})
  end

  def reply(conn, %{"id" => id, "answer" => answer}) do
    case Messages.get(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Message not found"})

      message ->
        case Messages.reply(message, answer) do
          {:ok, message} ->
            json(conn, message_to_json(message))

          {:error, changeset} ->
            conn |> put_status(422) |> json(%{error: format_errors(changeset)})
        end
    end
  end

  # HTTP peer-to-peer message delivery (same as Erlang relay but via HTTP)
  def receive_message(conn, %{"from_instance_id" => from_instance_id, "message" => message_attrs} = params) do
    case Sonar.Peers.find_by_instance_id(from_instance_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Unknown sender instance"})

      peer ->
        touch_peer_liveness(peer, params["from_port"])

        attrs =
          message_attrs
          |> Map.merge(%{
            "id" => gen_id(),
            "peer_id" => peer.id,
            "remote_message_id" => message_attrs["message_id"]
          })

        case Messages.receive_message(attrs) do
          {:ok, msg} ->
            SonarWeb.Endpoint.broadcast(
              "messages:events",
              "new_message",
              Messages.new_message_event(msg, peer, from_instance_id, message_attrs)
            )
            conn |> put_status(201) |> json(%{ok: true, message_id: msg.id})

          {:error, changeset} ->
            conn |> put_status(422) |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def receive_message(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing required fields: from_instance_id, message"})
  end

  # HTTP peer-to-peer response delivery
  # Uses update_answer directly (not reply/2) to avoid re-relaying the response back
  def receive_response(conn, %{"from_instance_id" => from_instance_id, "message_id" => message_id, "answer" => answer} = params) do
    # Passive liveness — same guard as receive_message/receive_ack. A response
    # arriving is proof of life. Unknown senders do NOT nudge state (spoof
    # guard); we still proceed to look up the local message row since the
    # audit key is `message_id` on our side.
    case Sonar.Peers.find_by_instance_id(from_instance_id) do
      nil -> :ok
      peer -> touch_peer_liveness(peer, params["from_port"])
    end

    case Messages.get(message_id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Message not found"})

      _message ->
        case Messages.update_answer(message_id, answer) do
          {:ok, _updated} ->
            SonarWeb.Endpoint.broadcast("messages:events", "reply_received", %{message_id: message_id, answer: answer})
            json(conn, %{ok: true})

          {:error, reason} ->
            conn |> put_status(422) |> json(%{error: inspect(reason)})
        end
    end
  end

  def receive_response(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing required fields: from_instance_id, message_id, answer"})
  end

  # Local endpoint — Sonata's dm_ack handler POSTs here to forward a DM
  # acknowledgement to the origin peer. Sonar transports it over the relay
  # (Erlang distribution, HTTP fallback) to that peer.
  def ack_forward(conn, %{"peer_id" => peer_id, "message_id" => message_id} = params) do
    acked_at_ms = params["acked_at_ms"] || System.os_time(:millisecond)
    Messages.send_ack_forward(peer_id, message_id, acked_at_ms)
    json(conn, %{ok: true, message_id: message_id})
  end

  def ack_forward(conn, _params) do
    conn |> put_status(400) |> json(%{error: "missing peer_id or message_id"})
  end

  # Peer-to-peer HTTP endpoint — the origin peer receives a forwarded ack and
  # emits an `ack_forward` plugin-webhook event to its local Sonata.
  def receive_ack(conn, %{"from_instance_id" => from_instance_id, "message" => %{"message_id" => message_id} = ack} = params) do
    # Passive liveness — only when the sender matches a known peer. Unknown
    # instance ids must not nudge peer state (spoof guard).
    case Sonar.Peers.find_by_instance_id(from_instance_id) do
      nil -> :ok
      peer -> touch_peer_liveness(peer, params["from_port"])
    end

    SonarWeb.Endpoint.broadcast("messages:events", "ack_forward", %{
      message_id: message_id,
      acked_at_ms: ack["acked_at_ms"]
    })
    json(conn, %{ok: true})
  end

  def receive_ack(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing required fields: from_instance_id, message.message_id"})
  end

  # Passive liveness: a successfully-matched inbound peer request proves the
  # peer is reachable right now, even when Discovery isn't running. Refresh
  # last_seen_at and un-stick a stale "offline" status. `from_port` is the
  # sender's currently bound port: following it is how a peer that moved
  # ports (SONAR_PORT_RANGE fallback) heals on its next message.
  defp touch_peer_liveness(peer, from_port) do
    {:ok, peer} = Sonar.Peers.follow_port(peer, from_port)
    attrs = %{"last_seen_at" => DateTime.utc_now()}

    attrs =
      if peer.connection_status == "offline",
        do: Map.put(attrs, "connection_status", "discovered"),
        else: attrs

    Sonar.Peers.update(peer, attrs)
  end

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)

  defp message_to_json(message) do
    %{
      id: message.id,
      peer_id: message.peer_id,
      direction: message.direction,
      question: message.question,
      context: message.context,
      answer: message.answer,
      status: message.status,
      failure_reason: message.failure_reason,
      expires_at: message.expires_at,
      remote_message_id: message.remote_message_id,
      answered_at: message.answered_at,
      target_session_id: message.target_session_id,
      from_session_id: message.from_session_id,
      inserted_at: message.inserted_at
    }
  end

  defp parse_int(nil), do: nil
  defp parse_int(s) when is_binary(s), do: String.to_integer(s)
  defp parse_int(i) when is_integer(i), do: i

  defp parse_datetime(nil), do: nil
  defp parse_datetime(ms) when is_integer(ms), do: DateTime.from_unix!(ms, :millisecond)
  defp parse_datetime(s) when is_binary(s), do: parse_datetime(String.to_integer(s))

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _opts} -> msg end)
  end
end
