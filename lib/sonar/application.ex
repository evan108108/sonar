defmodule Sonar.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    maybe_start_distribution()

    children =
      [
        SonarWeb.Telemetry,
        Sonar.Repo,
        {DNSCluster, query: Application.get_env(:sonar, :dns_cluster_query) || :ignore},
        {Phoenix.PubSub, name: Sonar.PubSub},
        Sonar.Identity,
        SonarWeb.Endpoint
      ] ++ discovery_children()

    opts = [strategy: :one_for_one, name: Sonar.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    SonarWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp discovery_enabled? do
    System.get_env("SONAR_DISCOVERY") == "true"
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
