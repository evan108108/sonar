defmodule Sonar.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    maybe_start_distribution()

    # Auto-migrate on startup (safe for SQLite, idempotent)
    # Skip Migrator in test — test_helper.exs handles migrations
    migrator =
      if Application.get_env(:sonar, :skip_migrator), do: [], else: [{Sonar.Migrator, []}]

    children =
      [
        SonarWeb.Telemetry,
        Sonar.Repo
      ] ++
        migrator ++
        [
          {DNSCluster, query: Application.get_env(:sonar, :dns_cluster_query) || :ignore},
          {Phoenix.PubSub, name: Sonar.PubSub},
          Sonar.Identity,
          SonarWeb.Endpoint,
          Sonar.PortFile
        ] ++ peer_health_children() ++ discovery_children()

    opts = [strategy: :one_for_one, name: Sonar.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SonarWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # Discovery is on by default; either env var set to exactly "false" opts out.
  # PluginManager injects SONAR_DISCOVERY_ENABLED; SONAR_DISCOVERY is the
  # legacy/manual name — honor both. `config :sonar, :discovery_enabled`
  # takes precedence for test env (Discovery hits DB and would crash
  # Ecto SQL Sandbox's :manual ownership without checkout).
  defp discovery_enabled? do
    case Application.get_env(:sonar, :discovery_enabled) do
      nil ->
        System.get_env("SONAR_DISCOVERY") != "false" and
          System.get_env("SONAR_DISCOVERY_ENABLED") != "false"

      configured ->
        configured == true
    end
  end

  # Peer liveness runs regardless of discovery: it is also what bootstraps
  # Erlang distribution to manual peers (Relay.connect_peer needs the node
  # name from /api/health). Off in test, where it would hit the DB outside
  # the SQL Sandbox.
  defp peer_health_children do
    if Application.get_env(:sonar, :peer_health_enabled, true), do: [Sonar.PeerHealth], else: []
  end

  defp discovery_children do
    if discovery_enabled?() do
      [
        Sonar.Relay.MessageHandler,
        Sonar.Relay,
        Sonar.Discovery
      ]
    else
      []
    end
  end

  defp maybe_start_distribution do
    if discovery_enabled?() and Node.alive?() == false do
      hostname = :inet.gethostname() |> elem(1) |> to_string()

      node_name =
        System.get_env("SONAR_NODE_NAME", "sonar@#{hostname}")
        |> String.to_atom()

      cookie = get_or_create_cookie()

      case Node.start(node_name) do
        {:ok, _} ->
          Node.set_cookie(cookie)
          require Logger
          Logger.info("Sonar: started distributed node #{node_name}")

        {:error, reason} ->
          require Logger
          Logger.warning("Sonar: could not start distributed node — #{inspect(reason)}")
      end
    end
  end

  defp get_or_create_cookie do
    cookie_path = Path.expand("~/.sonar/cookie")

    if File.exists?(cookie_path) do
      cookie_path |> File.read!() |> String.trim() |> String.to_atom()
    else
      cookie = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      File.mkdir_p!(Path.dirname(cookie_path))
      File.write!(cookie_path, cookie)
      File.chmod!(cookie_path, 0o600)
      String.to_atom(cookie)
    end
  end
end
