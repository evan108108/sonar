defmodule Sonar.Discovery do
  @moduledoc """
  mDNS/DNS-SD discovery for finding Sonar peers on the local network.
  Advertises this instance as `_sonar._tcp` and browses for other instances.
  Only starts when SONAR_DISCOVERY=true.
  """

  use GenServer
  require Logger

  # handle_peer_lost/1 will be wired up once mDNS :removed events are re-enabled;
  # suppress the unused-function warning until then without deleting the code.
  @compile {:nowarn_unused_function, handle_peer_lost: 1}

  @service_type "_sonar._tcp.local"
  @query_interval 15_000
  @health_interval 60_000

  defmodule State do
    defstruct [:identity, :port, started: false]
  end

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    identity = Sonar.Identity.get()
    port = Application.get_env(:sonar, SonarWeb.Endpoint)[:http][:port] || 4000

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

    # Start the mdns client for browsing
    Mdns.Client.start()

    # Subscribe to discovery events (registers this process to receive mDNS messages)
    Mdns.EventManager.add_handler()

    # Start periodic queries
    send(self(), :query_peers)
    # Run first health check quickly (3s) to auto-connect known peers
    Process.send_after(self(), :health_check, 3_000)

    Logger.info(
      "Sonar Discovery: advertising as sonar-#{state.identity.name} on #{@service_type}"
    )

    {:noreply, %{state | started: true}}
  end

  def handle_info(:query_peers, state) do
    if state.started do
      Mdns.Client.query(@service_type)
      Process.send_after(self(), :query_peers, @query_interval)
    end

    {:noreply, state}
  end

  def handle_info(:health_check, state) do
    check_peer_health()
    schedule_health_check()
    {:noreply, state}
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

  defp handle_peer_discovered(device, my_identity) do
    # Don't discover ourselves
    hostname = to_string(device.domain || device.ip |> :inet.ntoa() |> to_string())

    if hostname != "" do
      instance_id = device.payload["id"]
      port = parse_port(device.payload["port"]) || device.port || 8400

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

  defp check_peer_health do
    import Ecto.Query

    peers =
      Sonar.Repo.all(
        from(p in Sonar.Schema.Peer,
          where: p.connection_status in ["discovered", "paired"],
          where: p.discovery_method == "manual"
        )
      )

    for peer <- peers do
      url = "http://#{peer.hostname}:#{peer.port}/api/health"

      case http_get(url) do
        {:ok, body} ->
          Sonar.Peers.update(peer, %{"last_seen_at" => DateTime.utc_now()})
          # Auto-connect via Erlang distribution if relay is running and not already connected
          if Process.whereis(Sonar.Relay) != nil and not Sonar.Relay.connected?(peer.id) do
            node_name = derive_node_name(peer, body)
            if node_name, do: Sonar.Relay.connect_peer(peer.id, node_name)
          end

        {:error, _} ->
          Sonar.Peers.update(peer, %{"connection_status" => "offline"})
      end
    end
  end

  defp http_get(url) do
    try do
      uri = URI.parse(url)
      host = to_charlist(uri.host)
      port = uri.port || 80
      path = to_charlist(uri.path || "/")

      case :httpc.request(:get, {~c"http://#{host}:#{port}#{path}", []}, [timeout: 5000], []) do
        {:ok, {{_, 200, _}, _, body}} -> {:ok, to_string(body)}
        _ -> {:error, :unhealthy}
      end
    rescue
      _ -> {:error, :unreachable}
    end
  end

  # Derive the Erlang node name from a peer's health response or hostname.
  # The health endpoint returns {"node": "sonar@Mac", ...} — use that directly.
  # Falls back to "sonar@<hostname>" if node isn't in the response.
  defp derive_node_name(peer, health_body) do
    case Jason.decode(health_body) do
      {:ok, %{"node" => node}} when is_binary(node) and node != "nonode@nohost" -> node
      _ -> "sonar@#{peer.hostname}"
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

  defp schedule_health_check do
    Process.send_after(self(), :health_check, @health_interval)
  end

  defp parse_port(nil), do: nil
  defp parse_port(p) when is_integer(p), do: p
  defp parse_port(p) when is_binary(p), do: String.to_integer(p)
end
