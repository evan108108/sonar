defmodule Sonar.Relay.MessageHandler do
  @moduledoc """
  Receives messages from remote Sonar nodes via Erlang distribution.
  Registered globally so remote nodes can find it by name.
  """

  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{}}
  end

  # Incoming message from a remote peer
  def handle_cast({:sonar_message, from_instance_id, message_attrs}, state) do
    Logger.info("Sonar Relay: received message from #{from_instance_id}")

    case Sonar.Peers.find_by_instance_id(from_instance_id) do
      nil ->
        Logger.warning("Sonar Relay: message from unknown instance #{from_instance_id}, ignoring")

      peer ->
        if peer.connection_status in ["paired", "discovered"] do
          attrs =
            Map.merge(message_attrs, %{
              "id" => gen_id(),
              "peer_id" => peer.id,
              # Preserve the origin's id (mirrors the HTTP receive path) so the
              # id stays stable across the hop and acks correlate.
              "remote_message_id" => message_attrs["message_id"]
            })

          case Sonar.Messages.receive_message(attrs) do
            {:ok, msg} ->
              Logger.info("Sonar Relay: stored inbound message #{msg.id} from #{peer.name}")
              SonarWeb.Endpoint.broadcast(
                "messages:events",
                "new_message",
                Sonar.Messages.new_message_event(msg, peer, from_instance_id, message_attrs)
              )

            {:error, reason} ->
              Logger.error("Sonar Relay: failed to store message — #{inspect(reason)}")
          end
        else
          Logger.warning("Sonar Relay: message from revoked peer #{peer.name}, ignoring")
        end
    end

    {:noreply, state}
  end

  # Incoming response to a message we sent
  def handle_cast({:sonar_response, from_instance_id, message_id, answer}, state) do
    Logger.info("Sonar Relay: received response for message #{message_id}")

    case Sonar.Messages.get(message_id) do
      nil ->
        Logger.warning("Sonar Relay: response for unknown message #{message_id}")

      message ->
        case Sonar.Messages.reply(message, answer) do
          {:ok, _updated} ->
            SonarWeb.Endpoint.broadcast("messages:events", "reply_received", %{message_id: message_id, from_peer: from_instance_id, answer: answer})
          {:error, _} -> :ok
        end
    end

    {:noreply, state}
  end

  # Incoming DM acknowledgement forwarded from a peer — emit an `ack_forward`
  # plugin-webhook event to the local Sonata.
  def handle_cast({:sonar_ack, from_instance_id, ack_attrs}, state) do
    Logger.info("Sonar Relay: received ack_forward from #{from_instance_id}")

    SonarWeb.Endpoint.broadcast("messages:events", "ack_forward", %{
      message_id: ack_attrs["message_id"],
      acked_at_ms: ack_attrs["acked_at_ms"]
    })

    {:noreply, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  defp gen_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
