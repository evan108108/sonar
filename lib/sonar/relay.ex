defmodule Sonar.Relay do
  @moduledoc """
  Manages BEAM node connections to paired peers and relays messages
  via Erlang distribution for fast peer-to-peer communication.
  Only active when SONAR_DISCOVERY=true and the node is in distributed mode.
  """

  use GenServer
  require Logger

  defmodule State do
    defstruct connected_peers: %{}, monitors: %{}
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Send a message to a peer via Erlang distribution"
  def send_message(peer_id, message_attrs) do
    GenServer.call(__MODULE__, {:send_message, peer_id, message_attrs})
  end

  @doc """
  Send a RESPONSE to a peer via Erlang distribution. Casts a `:sonar_response`
  frame that the remote MessageHandler routes into `update_answer`, not
  `receive_message`. Prior to this, `maybe_relay_response` was calling
  `send_message` with a `%{"response_to", "answer"}` shape — arriving as a
  new inbound message with an `answer` but no `question`, so the changeset
  failed `validate_required([:id, :question])` and the reply was silently
  dropped. Only the HTTP fallback (`/api/messages/receive_response`) was
  routing responses correctly, so the bug hid whenever Erlang distribution
  wasn't connected between the two nodes.
  """
  def send_response(peer_id, message_id, answer) do
    GenServer.call(__MODULE__, {:send_response, peer_id, message_id, answer})
  end

  @doc "Forward a DM acknowledgement to a peer via Erlang distribution"
  def send_ack(peer_id, ack_attrs) do
    GenServer.call(__MODULE__, {:send_ack, peer_id, ack_attrs})
  end

  @doc "Check if a peer is connected via Erlang distribution"
  def connected?(peer_id) do
    GenServer.call(__MODULE__, {:connected?, peer_id})
  end

  @doc "Connect to a peer by node name"
  def connect_peer(peer_id, node_name) do
    GenServer.cast(__MODULE__, {:connect_peer, peer_id, node_name})
  end

  @doc "List connected peer node names"
  def connected_nodes do
    GenServer.call(__MODULE__, :connected_nodes)
  end

  # Callbacks

  def init(_opts) do
    # Monitor node connections/disconnections
    :net_kernel.monitor_nodes(true)
    {:ok, %State{}}
  end

  def handle_call({:send_message, peer_id, message_attrs}, _from, state) do
    case Map.get(state.connected_peers, peer_id) do
      nil ->
        {:reply, {:error, :not_connected}, state}

      node_name ->
        identity = Sonar.Identity.get()
        payload = {:sonar_message, identity.instance_id, message_attrs}

        try do
          GenServer.cast({Sonar.Relay.MessageHandler, node_name}, payload)
          {:reply, :ok, state}
        rescue
          e -> {:reply, {:error, e}, state}
        end
    end
  end

  def handle_call({:send_response, peer_id, message_id, answer}, _from, state) do
    case Map.get(state.connected_peers, peer_id) do
      nil ->
        {:reply, {:error, :not_connected}, state}

      node_name ->
        identity = Sonar.Identity.get()
        payload = {:sonar_response, identity.instance_id, message_id, answer}

        try do
          GenServer.cast({Sonar.Relay.MessageHandler, node_name}, payload)
          {:reply, :ok, state}
        rescue
          e -> {:reply, {:error, e}, state}
        end
    end
  end

  def handle_call({:send_ack, peer_id, ack_attrs}, _from, state) do
    case Map.get(state.connected_peers, peer_id) do
      nil ->
        {:reply, {:error, :not_connected}, state}

      node_name ->
        identity = Sonar.Identity.get()
        payload = {:sonar_ack, identity.instance_id, ack_attrs}

        try do
          GenServer.cast({Sonar.Relay.MessageHandler, node_name}, payload)
          {:reply, :ok, state}
        rescue
          e -> {:reply, {:error, e}, state}
        end
    end
  end

  def handle_call({:connected?, peer_id}, _from, state) do
    {:reply, Map.has_key?(state.connected_peers, peer_id), state}
  end

  def handle_call(:connected_nodes, _from, state) do
    {:reply, Map.values(state.connected_peers), state}
  end

  def handle_cast({:connect_peer, peer_id, node_name}, state) do
    node = String.to_atom(node_name)

    case Node.connect(node) do
      true ->
        ref = Node.monitor(node, true)
        Logger.info("Sonar Relay: connected to #{node_name}")

        state = %{
          state
          | connected_peers: Map.put(state.connected_peers, peer_id, node),
            monitors: Map.put(state.monitors, node, {peer_id, ref})
        }

        {:noreply, state}

      false ->
        Logger.warning("Sonar Relay: failed to connect to #{node_name}")
        {:noreply, state}

      :ignored ->
        Logger.warning("Sonar Relay: connection to #{node_name} ignored (node not alive)")
        {:noreply, state}
    end
  end

  def handle_info({:nodeup, node}, state) do
    Logger.info("Sonar Relay: node up — #{node}")
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.info("Sonar Relay: node down — #{node}")

    case Map.get(state.monitors, node) do
      {peer_id, _ref} ->
        # Update peer status to offline
        case Sonar.Peers.get(peer_id) do
          nil -> :ok
          peer -> Sonar.Peers.update(peer, %{"connection_status" => "offline"})
        end

        state = %{
          state
          | connected_peers: Map.delete(state.connected_peers, peer_id),
            monitors: Map.delete(state.monitors, node)
        }

        {:noreply, state}

      nil ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
