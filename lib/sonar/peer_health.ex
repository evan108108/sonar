defmodule Sonar.PeerHealth do
  @moduledoc """
  Periodic liveness checks for manually registered peers.

  Split out of `Sonar.Discovery` so peer liveness — and the Erlang
  distribution bootstrap it triggers (`Sonar.Relay.connect_peer/2` needs the
  node name from the peer's /api/health) — keeps running when mDNS is off or
  broken. Before the split, `discovery=false` silently stopped both.

  Each check also repairs two kinds of drift:

    * **Moved port.** When `hostname:port` stops answering, probe the shared
      port range on that host for a card.json and follow it: one carrying the
      row's instance_id, or, for a row that has none, any sonar but
      ourselves. Port changes are expected now that the plugin falls back
      through `SONAR_PORT_RANGE` at boot.
    * **Unbound row.** A reachable peer whose row has no instance_id gets it
      from its card. If another row already holds that instance_id (the old
      LAN row from before a move), the two are merged into the row that holds
      the id, which keeps its name, history and tokens and takes the
      reachable address.
  """

  use GenServer
  require Logger

  import Ecto.Query

  alias Sonar.Peers
  alias Sonar.Repo
  alias Sonar.Schema.Peer

  @first_check_ms 3_000
  @interval_ms 60_000
  @health_timeout_ms 5_000
  @probe_timeout_ms 2_000

  # Passive-liveness grace window — a peer whose last_seen_at is fresher than
  # this is considered "still alive" even when an active probe fails.
  @passive_liveness_grace_seconds 180

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Process.send_after(self(), :check, @first_check_ms)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:check, state) do
    check_all()
    Process.send_after(self(), :check, @interval_ms)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @doc "Checks every manual peer once."
  def check_all(opts \\ []) do
    Repo.all(
      from(p in Peer,
        where: p.connection_status in ["discovered", "paired", "offline"],
        where: p.discovery_method == "manual"
      )
    )
    |> Enum.each(&check_peer(&1, opts))
  end

  @doc """
  Checks one peer. Returns `{:ok, peer}` (possibly the merged/moved row) or
  `{:error, peer}`.

  Options (for tests): `:get` — `fn url, timeout_ms -> {:ok, body} | {:error, _}`;
  `:range` — the port range to probe; `:connect` — whether to bootstrap the relay.
  """
  def check_peer(%Peer{} = peer, opts \\ []) do
    get = Keyword.get(opts, :get, &http_get/2)
    range = Keyword.get(opts, :range, Application.get_env(:sonar, :peer_port_range))

    case get.(health_url(peer.hostname, peer.port), @health_timeout_ms) do
      {:ok, body} ->
        alive(peer, body, get, opts)

      {:error, _} ->
        case find_moved_port(peer, range, get) do
          {:ok, port} ->
            Logger.info("Sonar PeerHealth: #{peer.name} moved #{peer.port} → #{port}")
            {:ok, moved} = Peers.update(peer, %{"port" => port})

            case get.(health_url(moved.hostname, port), @health_timeout_ms) do
              {:ok, body} -> alive(moved, body, get, opts)
              {:error, _} -> unreachable(moved)
            end

          :error ->
            unreachable(peer)
        end
    end
  end

  defp alive(peer, health_body, get, opts) do
    {:ok, peer} =
      Peers.update(peer, %{
        "last_seen_at" => DateTime.utc_now(),
        "connection_status" =>
          if(peer.connection_status == "offline", do: "discovered", else: peer.connection_status)
      })

    peer = bind_identity(peer, get)

    if Keyword.get(opts, :connect, true) and Process.whereis(Sonar.Relay) != nil and
         not Sonar.Relay.connected?(peer.id) do
      Sonar.Relay.connect_peer(peer.id, derive_node_name(peer, health_body))
    end

    {:ok, peer}
  end

  defp unreachable(peer) do
    # Only clobber to offline if we ALSO haven't seen the peer via
    # passive-liveness (an inbound message on any transport) recently.
    # An active probe can fail transiently — BEAM :httpc has been observed
    # returning :ehostunreach against hosts that curl reaches fine, likely due
    # to source-address selection differences after Erlang distribution comes
    # up. Passive-liveness from receive_message / receive_response /
    # :sonar_message / :sonar_response is authoritative: if a message arrived
    # recently, the peer IS reachable in the direction that matters.
    if not_recently_seen?(peer) do
      {:ok, offline} = Peers.update(peer, %{"connection_status" => "offline"})
      {:error, offline}
    else
      {:error, peer}
    end
  end

  # A row with no instance_id learns it from the peer's card. When an older
  # row already holds that id, merge into it.
  defp bind_identity(%Peer{instance_id: id} = peer, _get) when is_binary(id) and id != "",
    do: peer

  defp bind_identity(peer, get) do
    with {:ok, card_id} <- card_instance_id(peer.hostname, peer.port, get, @health_timeout_ms),
         false <- card_id == Sonar.Identity.get().instance_id do
      case Peers.find_by_instance_id(card_id) do
        nil ->
          {:ok, bound} = Peers.update(peer, %{"instance_id" => card_id})
          Logger.info("Sonar PeerHealth: bound #{peer.name} to instance #{card_id}")
          bound

        %Peer{} = holder ->
          {:ok, merged} = Peers.merge(holder, peer)

          Logger.info(
            "Sonar PeerHealth: merged #{peer.name} into #{holder.name} " <>
              "(#{merged.hostname}:#{merged.port}, instance #{card_id})"
          )

          merged
      end
    else
      _ -> peer
    end
  end

  # Probe the range on the peer's host for its card. A row with an
  # instance_id only follows a card carrying that id. A row without one has
  # nothing but its hostname to go on, so the sonar answering on that host
  # (other than ourselves) is it; bind_identity then binds or merges it by
  # the card's id. That is how an id-less Tailscale row (Scout's
  # "evan-laptop", still on :4000) finds us after we move to 4001.
  defp find_moved_port(_peer, nil, _get), do: :error

  # Probes run concurrently, so a dead host (an old LAN row) costs one probe
  # timeout per pass, not one per port in the range.
  defp find_moved_port(peer, range, get) do
    me = Sonar.Identity.get().instance_id

    accepts? =
      if peer.instance_id in [nil, ""],
        do: fn id -> id != me end,
        else: fn id -> id == peer.instance_id end

    range
    |> Enum.reject(&(&1 == peer.port))
    |> Task.async_stream(
      fn port -> {port, card_instance_id(peer.hostname, port, get, @probe_timeout_ms)} end,
      max_concurrency: 20,
      timeout: @probe_timeout_ms + 1_000,
      on_timeout: :kill_task
    )
    |> Enum.find_value(:error, fn
      {:ok, {port, {:ok, id}}} -> if accepts?.(id), do: {:ok, port}
      _ -> nil
    end)
  end

  defp card_instance_id(hostname, port, get, timeout) do
    with {:ok, body} <- get.("http://#{hostname}:#{port}/.well-known/sonar/card.json", timeout),
         {:ok, %{"agent" => %{"instance_id" => id}}} when is_binary(id) and id != "" <-
           Jason.decode(body) do
      {:ok, id}
    else
      _ -> :error
    end
  end

  defp not_recently_seen?(peer) do
    case peer.last_seen_at do
      nil ->
        true

      %DateTime{} = seen ->
        DateTime.diff(DateTime.utc_now(), seen, :second) > @passive_liveness_grace_seconds
    end
  end

  defp health_url(hostname, port), do: "http://#{hostname}:#{port}/api/health"

  @doc false
  def http_get(url, timeout) do
    uri = URI.parse(url)
    target = ~c"http://#{uri.host}:#{uri.port || 80}#{uri.path || "/"}"

    case :httpc.request(:get, {target, []}, [timeout: timeout, connect_timeout: timeout], []) do
      {:ok, {{_, 200, _}, _, body}} -> {:ok, to_string(body)}
      _ -> {:error, :unhealthy}
    end
  rescue
    _ -> {:error, :unreachable}
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
end
