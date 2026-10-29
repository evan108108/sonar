defmodule Sonar.PortFile do
  @moduledoc """
  Publishes the port the endpoint actually bound.

  Sonata's PluginManager reads `$SONATA_PLUGIN_DATA_DIR/sonar.port` after
  spawn to learn where to reach us; the same value goes out in /api/health,
  card.json and outbound peer requests (`from_port`) so remote peers can
  follow a port change.

  Runs once, after `SonarWeb.Endpoint` in the supervision tree, so the
  listener is up before the file appears.
  """

  use Task, restart: :temporary
  require Logger

  @file_name "sonar.port"

  def start_link(_opts), do: Task.start_link(&write/0)

  @doc "The bound HTTP port, or the configured one when the server isn't running (tests)."
  def bound_port do
    case safe_server_info() do
      {:ok, {_ip, port}} when is_integer(port) -> port
      _ -> configured_port()
    end
  end

  @doc false
  def write do
    case System.get_env("SONATA_PLUGIN_DATA_DIR") do
      nil -> :ok
      dir -> write(dir, bound_port())
    end
  end

  @doc "Writes `port` to `<dir>/sonar.port` atomically (tmp + rename)."
  def write(dir, port) do
    path = Path.join(dir, @file_name)
    tmp = path <> ".tmp"

    with :ok <- File.write(tmp, Integer.to_string(port)),
         :ok <- File.rename(tmp, path) do
      Logger.info("Sonar: listening on port #{port} (#{path})")
      :ok
    else
      {:error, reason} ->
        Logger.warning("Sonar: could not write #{path}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp configured_port do
    Application.get_env(:sonar, SonarWeb.Endpoint)[:http][:port] || 4000
  end

  defp safe_server_info do
    SonarWeb.Endpoint.server_info(:http)
  rescue
    _ -> :error
  catch
    :exit, _ -> :error
  end
end
