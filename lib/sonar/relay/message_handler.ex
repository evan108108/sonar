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
        # Reject only revoked peers explicitly. "offline" is a stale-liveness
        # marker (Discovery hasn't heard back in a while) — a message arriving
        # is itself proof of life. The previous whitelist of just paired /
        # discovered silently dropped Erlang-relay messages from offline peers
        # and logged them as "revoked", which was misleading and led to
        # confusing missing-message reports.
        if peer.connection_status == "revoked" do
          Logger.warning("Sonar Relay: message from revoked peer #{peer.name}, ignoring")
        else
          attrs =
            Map.merge(message_attrs, %{
              "id" => gen_id(),
              "peer_id" => peer.id,
              # Preserve the origin's id (mirrors the HTTP receive path) so the
              # id stays stable across the hop and acks correlate.
              "remote_message_id" => message_attrs["message_id"]
            })

          # Also apply passive liveness on the Erlang path — an inbound message
          # is proof the peer is alive right now. Mirrors the HTTP receive
          # controller's touch_peer_liveness.
          _ =
            Sonar.Peers.update(peer, %{
              "last_seen_at" => DateTime.utc_now(),
              "connection_status" =>
                if(peer.connection_status == "offline",
                  do: "discovered",
                  else: peer.connection_status
                )
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
        end
    end

    {:noreply, state}
  end

  # Incoming response to a message we sent
  def handle_cast({:sonar_response, from_instance_id, message_id, answer}, state) do
    Logger.info("Sonar Relay: received response for message #{message_id}")

    # Passive liveness — a response arriving is proof the peer is alive.
    # Mirrors the :sonar_message path and the HTTP receive controller.
    case Sonar.Peers.find_by_instance_id(from_instance_id) do
      nil -> :ok
      peer ->
        _ =
          Sonar.Peers.update(peer, %{
            "last_seen_at" => DateTime.utc_now(),
            "connection_status" =>
              if(peer.connection_status == "offline",
                do: "discovered",
                else: peer.connection_status
              )
          })
    end

    case Sonar.Messages.get(message_id) do
      nil ->
        Logger.warning("Sonar Relay: response for unknown message #{message_id}")

      message ->
        # `update_answer` (not `reply`) — the local audit gets the answer, but
        # DO NOT re-invoke `maybe_relay_response`, which would loop by casting
        # the same response back to the origin peer. Mirrors the HTTP path in
        # MessagesController.receive_response.
        case Sonar.Messages.update_answer(message.id, answer) do
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
