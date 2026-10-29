defmodule Sonar.Discovery do
  @moduledoc """
  mDNS/DNS-SD discovery for finding Sonar peers on the local network.
  Advertises this instance as `_sonar._tcp` and browses for other instances.
  Peer liveness checks live in `Sonar.PeerHealth`, which runs without mDNS.
  """

  use GenServer
  require Logger

  # handle_peer_lost/1 will be wired up once mDNS :removed events are re-enabled;
  # suppress the unused-function warning until then without deleting the code.
  @compile {:nowarn_unused_function, handle_peer_lost: 1}

  @service_type "_sonar._tcp.local"
  @query_interval 15_000
  @client_restart_min_ms 1_000
  @client_restart_max_ms 300_000

  defmodule State do
    # client_ref monitors Mdns.Client. It's nil while the client is down or
    # has no socket, and queries are skipped until a restart succeeds.
    defstruct [:identity, :port, :client_ref, started: false, restart_ms: 1_000]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    identity = Sonar.Identity.get()
    port = Sonar.PortFile.bound_port()

    # Start advertising and browsing
    send(self(), :start_mdns)

    {:ok, %State{identity: identity, port: port}}
  end

  def handle_info(:start_mdns, state) do
    # Start the mdns server for advertising
    Mdns.Server.start()
    Mdns.Server.set_ip(get_local_ip())

    Mdns.Server.add_service(%Mdns.Server.Service{
      domain: @service_type,
      data: "sonar-#{state.identity.name}.#{@service_type}",
      ttl: 120,
      type: :ptr
    })

    # Subscribe to discovery events (registers this process to receive mDNS messages)
    Mdns.EventManager.add_handler()

    state = start_client(%{state | started: true})

    # Start periodic queries
    send(self(), :query_peers)

    Logger.info(
      "Sonar Discovery: advertising as sonar-#{state.identity.name} on #{@service_type}"
    )

    {:noreply, state}
  end

  def handle_info(:query_peers, state) do
    # Mdns.Client.query/1 is a cast that crashes the client when its socket
    # is nil, so only query while the monitored client has one.
    if state.started and state.client_ref != nil do
      Mdns.Client.query(@service_type)
    end

    if state.started, do: Process.send_after(self(), :query_peers, @query_interval)
    {:noreply, state}
  end

  # Mdns.Client went down. Its supervisor restarts it with an empty state
  # (udp: nil), and nothing calls start/1 again — before this, every later
  # query crashed it again, every 15s, indefinitely. Re-open the socket
  # after a backoff.
  def handle_info({:DOWN, ref, :process, _pid, reason}, %State{client_ref: ref} = state) do
    Logger.warning(
      "Sonar Discovery: mDNS client down (#{inspect(reason)}); restarting in #{state.restart_ms}ms"
    )

    Process.send_after(self(), :restart_client, state.restart_ms)
    {:noreply, %{state | client_ref: nil}}
  end

  def handle_info(:restart_client, state) do
    {:noreply, start_client(state)}
  end

  # mDNS discovery event — {service_type, device}
  def handle_info({@service_type, device}, state) do
    handle_peer_discovered(device, state.identity)
    {:noreply, state}
  end

  # Catch-all for other mDNS namespaces or unknown messages
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Opens the client's socket and monitors it. On failure, retries with
  # exponential backoff (capped) instead of letting queries crash it.
  defp start_client(state) do
    with pid when is_pid(pid) <- Process.whereis(Mdns.Client),
         :ok <- safe_client_start() do
      %{state | client_ref: Process.monitor(pid), restart_ms: @client_restart_min_ms}
    else
      failure ->
        Logger.warning(
          "Sonar Discovery: mDNS client start failed (#{inspect(failure)}); retrying in #{state.restart_ms}ms"
        )

        Process.send_after(self(), :restart_client, state.restart_ms)
        %{state | client_ref: nil, restart_ms: min(state.restart_ms * 2, @client_restart_max_ms)}
    end
  end

  defp safe_client_start do
    Mdns.Client.start()
  catch
    :exit, reason -> {:error, reason}
  end

  defp handle_peer_discovered(device, my_identity) do
    # Don't discover ourselves
    hostname = to_string(device.domain || device.ip |> :inet.ntoa() |> to_string())

    if hostname != "" do
      instance_id = device.payload["id"]
      port = parse_port(device.payload["port"]) || device.port || 4001

      # Skip if this is our own instance
      if instance_id != my_identity.instance_id do
        case Sonar.Peers.find_by_instance_id(instance_id) do
          nil ->
            name = device.payload["name"] || hostname

            Sonar.Peers.create(%{
              "name" => name,
              "hostname" => hostname,
              "port" => port,
              "instance_id" => instance_id,
              "discovery_method" => "mdns",
              "connection_status" => "discovered"
            })

            Logger.info("Sonar Discovery: new peer found — #{name} at #{hostname}:#{port}")

          peer ->
            Sonar.Peers.update(peer, %{
              "hostname" => hostname,
              "port" => port,
              "last_seen_at" => DateTime.utc_now(),
              "connection_status" =>
                if(peer.connection_status == "offline",
                  do: "discovered",
                  else: peer.connection_status
                )
            })
        end
      end
    end
  end

  @doc false
  def handle_peer_lost(device) do
    hostname = to_string(device.domain || device.ip |> :inet.ntoa() |> to_string())

    case Sonar.Peers.find_by_hostname(hostname) do
      nil ->
        :ok

      peer ->
        Sonar.Peers.update(peer, %{"connection_status" => "offline"})
        Logger.info("Sonar Discovery: peer lost — #{peer.name}")
    end
  end

  defp get_local_ip do
    case :inet.getif() do
      {:ok, addrs} ->
        addrs
        |> Enum.map(fn {ip, _, _} -> ip end)
        |> Enum.reject(fn ip -> ip == {127, 0, 0, 1} end)
        |> List.first() || {0, 0, 0, 0}

      _ ->
        {0, 0, 0, 0}
    end
  end

  defp parse_port(nil), do: nil
  defp parse_port(p) when is_integer(p), do: p
  defp parse_port(p) when is_binary(p), do: String.to_integer(p)
end
