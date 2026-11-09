defmodule SonarWeb.Events do
  @moduledoc """
  The one door for `messages:events`, the feed this node's Sonata reads over
  the channel socket.

  Always node-local. Sonar.Relay joins paired peers into one Erlang cluster,
  and `SonarWeb.Endpoint.broadcast/3` fans out to every node in it, so a
  peer's `new_message` used to reach this node's Sonata as well as its own.
  The sender then materialised its own outbound DM as an inbound one and gave
  it to a local worker (message 6f4406fe, 2026-11-09). Cross-node delivery
  belongs to the relay (`GenServer.cast` to the peer's MessageHandler), never
  to PubSub.
  """

  @topic "messages:events"

  def topic, do: @topic

  def emit(event, payload) when is_binary(event) do
    SonarWeb.Endpoint.local_broadcast(@topic, event, payload)
  end
end
