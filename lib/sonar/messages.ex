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
    # Honor a caller-provided message id (Sonata sends M_origin as a UUID) so the
    # id is stable end-to-end; generate one only when absent.
    id = attrs["message_id"] || gen_id()

    # Pass-through fields that ride the wire but are not persisted (no column).
    extras = %{
      "in_reply_to" => attrs["in_reply_to"],
      "sender_display" => attrs["sender_display"]
    }

    result =
      %Message{}
      |> Message.changeset(
        Map.merge(attrs, %{"id" => id, "direction" => "outbound", "status" => "pending"})
      )
      |> Repo.insert()

    # Attempt delivery (Erlang distribution, HTTP fallback) and persist the
    # outcome — "relayed" or "failed" — instead of leaving the row "pending".
    case result do
      {:ok, message} ->
        case maybe_relay_message(message, extras) do
          :relayed -> {:ok, mark_relay_outcome(message, "relayed", nil)}
          {:error, reason} -> {:ok, mark_relay_outcome(message, "failed", reason)}
          :no_peer -> {:ok, message}
        end

      error ->
        error
    end
  end

  # Persist the relay outcome on the message row. Returns the updated message,
  # or the original if the update itself fails (outcome reporting must not
  # turn a delivered/attempted send into a 422).
  defp mark_relay_outcome(message, status, reason) do
    attrs = %{"status" => status, "failure_reason" => format_reason(reason)}

    case message |> Message.changeset(attrs) |> Repo.update() do
      {:ok, updated} -> updated
      {:error, _} -> message
    end
  end

  defp format_reason(nil), do: nil
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

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

  @doc """
  Builds the `new_message` plugin-webhook payload broadcast to Sonata for an
  inbound peer DM.

  `msg` is the persisted `Sonar.Schema.Message`, `peer` the sending
  `Sonar.Schema.Peer`, `from_instance_id` the sender's instance id, and
  `raw_attrs` the raw inbound wire payload (used to forward pass-through fields
  that Sonar does not persist).

  Fields `in_reply_to` and `sender_display` are forwarded verbatim from the
  wire payload — they are not columns on the messages table (persisting them
  would require a migration). They are `nil` for initiating DMs.
  """
  def new_message_event(msg, peer, from_instance_id, raw_attrs \\ %{}) do
    %{
      # The origin's id (stored as remote_message_id on receive) so acks
      # correlate back to the sender's audit row; falls back to local id.
      message_id: msg.remote_message_id || msg.id,
      from_peer: from_instance_id,
      from_peer_id: peer && peer.id,
      from_peer_name: peer && peer.name,
      sender_display: raw_attrs["sender_display"],
      in_reply_to: raw_attrs["in_reply_to"],
      direction: "inbound",
      status: msg.status,
      # `body` is the renamed field; `question` is kept for backcompat.
      body: msg.question,
      question: msg.question,
      context: msg.context,
      target_session_id: msg.target_session_id,
      from_session_id: msg.from_session_id
    }
  end

  @doc """
  Forwards a cross-peer DM acknowledgement to the origin peer (`peer_id`).

  Tries the Erlang relay first, falling back to HTTP. The origin peer's Sonar
  then emits an `ack_forward` plugin-webhook event to its local Sonata.
  """
  def send_ack_forward(peer_id, message_id, acked_at_ms) do
    payload = %{"message_id" => message_id, "acked_at_ms" => acked_at_ms}

    relayed =
      if relay_available?() do
        case Sonar.Relay.send_ack(peer_id, payload) do
          :ok -> true
          _ -> false
        end
      else
        false
      end

    unless relayed, do: http_relay_ack(peer_id, payload)
    :ok
  end

  # Returns :relayed when either transport delivered, {:error, reason} when
  # both failed, or :no_peer for peer-less messages (nothing to relay).
  defp maybe_relay_message(message, extras) do
    if message.peer_id != nil do
      payload = %{
        "question" => message.question,
        "context" => message.context,
        "message_id" => message.id,
        "expires_at" => message.expires_at,
        "target_session_id" => message.target_session_id,
        "from_session_id" => message.from_session_id,
        # Forwarded verbatim; nil for initiating DMs. Not persisted locally.
        "in_reply_to" => extras["in_reply_to"],
        "sender_display" => extras["sender_display"]
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

      if relayed do
        :relayed
      else
        case http_relay_message(message.peer_id, payload) do
          :ok -> :relayed
          {:error, reason} -> {:error, reason}
        end
      end
    else
      :no_peer
    end
  end

  defp maybe_relay_response(message) do
    if message.peer_id != nil && message.answer != nil do
      # Use remote_message_id if available (the sender's original message ID)
      response_to = message.remote_message_id || message.id

      relayed =
        if relay_available?() do
          # Route as a `:sonar_response` frame — NOT `send_message`. The old
          # code was casting a `%{"response_to", "answer"}` map through the
          # `:sonar_message` handler, which then failed the changeset's
          # `validate_required([:id, :question])` and silently discarded the
          # reply. See Sonar.Relay.send_response docstring.
          case Sonar.Relay.send_response(message.peer_id, response_to, message.answer) do
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
    if Application.get_env(:sonar, :skip_http_relay, false) do
      :ok
    else
      case Sonar.Peers.get(peer_id) do
        nil -> {:error, :peer_not_found}
        peer ->
          identity = Sonar.Identity.get()
          url = "http://#{peer.hostname}:#{peer.port}/api/messages/receive"
          body = Jason.encode!(%{from_instance_id: identity.instance_id, from_port: Sonar.PortFile.bound_port(), message: payload})
          http_post(url, body)
      end
    end
  end

  defp http_relay_response(peer_id, message_id, answer) do
    if Application.get_env(:sonar, :skip_http_relay, false) do
      :ok
    else
      case Sonar.Peers.get(peer_id) do
        nil -> {:error, :peer_not_found}
        peer ->
          identity = Sonar.Identity.get()
          url = "http://#{peer.hostname}:#{peer.port}/api/messages/receive_response"
          body = Jason.encode!(%{from_instance_id: identity.instance_id, from_port: Sonar.PortFile.bound_port(), message_id: message_id, answer: answer})
          http_post(url, body)
      end
    end
  end

  defp http_relay_ack(peer_id, payload) do
    if Application.get_env(:sonar, :skip_http_relay, false) do
      :ok
    else
      case Sonar.Peers.get(peer_id) do
        nil ->
          {:error, :peer_not_found}

        peer ->
          identity = Sonar.Identity.get()
          url = "http://#{peer.hostname}:#{peer.port}/api/messages/receive_ack"
          body = Jason.encode!(%{from_instance_id: identity.instance_id, from_port: Sonar.PortFile.bound_port(), message: payload})
          http_post(url, body)
      end
    end
  end

  defp http_post(url, body) do
    case System.cmd("curl", ["-s", "--max-time", "10", "-X", "POST", "-H", "Content-Type: application/json", "-d", body, "-w", "\n%{http_code}", url], stderr_to_stdout: true) do
      {output, 0} ->
        status = output |> String.trim() |> String.split("\n") |> List.last()
        if status in ["200", "201"], do: :ok, else: {:error, output}
      {output, code} ->
        {:error, "curl exit #{code}: #{output}"}
    end
  end

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
