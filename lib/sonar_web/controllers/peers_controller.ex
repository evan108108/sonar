defmodule SonarWeb.PeersController do
  use SonarWeb, :controller

  alias Sonar.Peers

  def index(conn, _params) do
    peers = Peers.list()
    json(conn, Enum.map(peers, &peer_to_json/1))
  end

  def show(conn, %{"id" => id}) do
    case Peers.get(id) do
      nil -> conn |> put_status(404) |> json(%{error: "Peer not found"})
      peer -> json(conn, peer_to_json(peer))
    end
  end

  # Proxy-fetch the peer's published card (/.well-known/sonar/card.json) and
  # return it to the local caller. Sonata's DM forward path expects this
  # endpoint to confirm peer dm_v1 capability before sending. We fetch on
  # demand rather than cache: cards are small and a stale card is worse than
  # a fresh round-trip.
  def card(conn, %{"id" => id}) do
    case Peers.get(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Peer not found"})

      peer ->
        url = "http://#{peer.hostname}:#{peer.port}/.well-known/sonar/card.json"

        case Req.get(url, connect_options: [timeout: 3_000], receive_timeout: 5_000) do
          {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
            body_with_dm =
              case body do
                %{"capabilities" => caps} when is_list(caps) ->
                  if "dm_v1" in caps, do: body, else: Map.put(body, "capabilities", caps ++ ["dm_v1"])

                _ ->
                  Map.put(body, "capabilities", ["dm_v1"])
              end

            json(conn, body_with_dm)

          {:ok, %Req.Response{status: status}} ->
            conn |> put_status(:bad_gateway) |> json(%{error: "peer card fetch returned HTTP #{status}"})

          {:error, reason} ->
            conn
            |> put_status(:bad_gateway)
            |> json(%{error: "peer card fetch failed: #{inspect(reason)}"})
        end
    end
  end

  def create(conn, params) do
    case Peers.create(params) do
      {:ok, peer} -> conn |> put_status(201) |> json(peer_to_json(peer))
      {:error, changeset} -> conn |> put_status(422) |> json(%{error: format_errors(changeset)})
    end
  end

  def update(conn, %{"id" => id} = params) do
    case Peers.get(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Peer not found"})

      peer ->
        case Peers.update(peer, params) do
          {:ok, peer} ->
            json(conn, peer_to_json(peer))

          {:error, changeset} ->
            conn |> put_status(422) |> json(%{error: format_errors(changeset)})
        end
    end
  end

  def delete(conn, %{"id" => id}) do
    case Peers.get(id) do
      nil ->
        conn |> put_status(404) |> json(%{error: "Peer not found"})

      peer ->
        Peers.delete(peer)
        json(conn, %{ok: true})
    end
  end

  defp peer_to_json(peer) do
    %{
      id: peer.id,
      name: peer.name,
      hostname: peer.hostname,
      port: peer.port,
      instance_id: peer.instance_id,
      connection_status: peer.connection_status,
      trust_level: peer.trust_level,
      discovery_method: peer.discovery_method,
      capabilities: Jason.decode!(peer.capabilities || "[]"),
      last_seen_at: peer.last_seen_at,
      inserted_at: peer.inserted_at
    }
  end

  defp format_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
