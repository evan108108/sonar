defmodule Sonar.Sessions do
  @moduledoc """
  Session discovery for Sonar DMs.

  v0 acts as a thin window onto Sonata's DM registry. The local listing is
  fetched over loopback HTTP from Sonata (`http://127.0.0.1:3211/api/dm/registry`).
  Remote listings are fetched from a paired peer's Sonar (`/api/sessions/local`)
  — paired-trust only, no HMAC in v0 (per ratified plan §11.2).

  Both functions are degrade-graceful: a failed local lookup returns an empty
  list with `queried_at` set, and logs a warning. A failed remote lookup
  returns an `{:error, atom}` tuple so the caller can render an error response.
  """

  require Logger

  @sonata_registry_url "http://127.0.0.1:3211/api/dm/registry"
  @local_timeout_ms 2_000
  @remote_timeout_ms 5_000

  @doc """
  Lists DM sessions registered locally on this host (via the loopback Sonata).

  Returns `{:ok, %{sessions: list, queried_at: ms}}`. On transport failure,
  returns `{:ok, %{sessions: [], queried_at: ms}}` and logs a warning.
  """
  def list_local do
    case http_get(@sonata_registry_url, @local_timeout_ms) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"entries" => entries} = decoded} ->
            sessions = Enum.map(entries, &normalize_entry/1)
            queried_at = decoded["generatedAt"] || now_ms()
            {:ok, %{sessions: sessions, queried_at: queried_at}}

          {:ok, %{"sessions" => sessions} = decoded} ->
            queried_at = decoded["queried_at"] || decoded["queriedAt"] || now_ms()
            {:ok, %{sessions: Enum.map(sessions, &normalize_entry/1), queried_at: queried_at}}

          {:ok, _} ->
            Logger.warning("Sonar.Sessions: unexpected Sonata registry shape; returning empty list")
            {:ok, %{sessions: [], queried_at: now_ms()}}

          {:error, reason} ->
            Logger.warning(
              "Sonar.Sessions: failed to decode Sonata registry response — #{inspect(reason)}"
            )
            {:ok, %{sessions: [], queried_at: now_ms()}}
        end

      {:error, reason} ->
        Logger.warning(
          "Sonar.Sessions: Sonata loopback unreachable (#{inspect(reason)}); returning empty list"
        )
        {:ok, %{sessions: [], queried_at: now_ms()}}
    end
  end

  @doc """
  Lists DM sessions on a remote peer.

  Peer must be in `paired` connection_status. Returns:
    * `{:ok, %{sessions: list, queried_at: ms}}` on success
    * `{:error, :peer_not_found}` if the peer id doesn't resolve
    * `{:error, :peer_not_paired}` if the peer is not paired
    * `{:error, :sonata_unreachable}` on HTTP transport failure
  """
  def list_remote(peer_id) when is_binary(peer_id) do
    case Sonar.Peers.get(peer_id) do
      nil ->
        {:error, :peer_not_found}

      peer ->
        if peer.connection_status == "paired" do
          url = "http://#{peer.hostname}:#{peer.port}/api/sessions/local"

          case http_get(url, @remote_timeout_ms) do
            {:ok, body} ->
              case Jason.decode(body) do
                {:ok, %{"sessions" => sessions} = decoded} ->
                  queried_at = decoded["queried_at"] || decoded["queriedAt"] || now_ms()
                  {:ok, %{sessions: Enum.map(sessions, &normalize_entry/1), queried_at: queried_at}}

                _ ->
                  {:error, :sonata_unreachable}
              end

            {:error, _reason} ->
              {:error, :sonata_unreachable}
          end
        else
          {:error, :peer_not_paired}
        end
    end
  end

  # ---- internal ----

  defp normalize_entry(entry) when is_map(entry) do
    %{
      session_id: entry["session_id"] || entry["sessionId"],
      session_label: entry["session_label"] || entry["sessionLabel"],
      role: entry["role"],
      registered_at: entry["registered_at"] || entry["registeredAt"]
    }
  end

  defp normalize_entry(other), do: other

  defp now_ms, do: System.system_time(:millisecond)

  defp http_get(url, timeout_ms) do
    timeout_s =
      timeout_ms
      |> div(1000)
      |> max(1)
      |> Integer.to_string()

    case System.cmd("curl", ["-s", "--max-time", timeout_s, "-w", "\n%{http_code}", url],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        case String.split(output, "\n", trim: false) |> Enum.reverse() do
          [status_code | rest] ->
            body = rest |> Enum.reverse() |> Enum.join("\n")

            if status_code in ["200", "201"] do
              {:ok, body}
            else
              {:error, "http #{status_code}: #{body}"}
            end

          _ ->
            {:error, "no_output"}
        end

      {output, code} ->
        {:error, "curl exit #{code}: #{output}"}
    end
  end
end
