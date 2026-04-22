defmodule Sonar.Identity do
  @moduledoc """
  This agent's identity. Self-sovereign — the agent creates it, owns it, controls it.
  Persisted in SQLite, cached in an Agent process.
  """

  use Agent
  import Ecto.Query
  alias Sonar.Repo

  def start_link(_opts) do
    identity = load_or_create()
    Agent.start_link(fn -> identity end, name: __MODULE__)
  end

  def get do
    Agent.get(__MODULE__, & &1)
  end

  def update(changes) when is_map(changes) do
    Agent.update(__MODULE__, fn identity ->
      updated = Map.merge(identity, changes)
      persist(updated)
      updated
    end)
  end

  defp load_or_create do
    case Repo.one(from r in "identity", select: %{
      name: r.name,
      instance_id: r.instance_id,
      capabilities: r.capabilities,
      cert_fingerprint: r.cert_fingerprint
    }) do
      nil -> create_identity()
      row -> parse_identity(row)
    end
  end

  defp create_identity do
    hostname = :inet.gethostname() |> elem(1) |> to_string()
    name = System.get_env("SONAR_NAME", hostname)
    instance_id = generate_instance_id()
    now = DateTime.utc_now()

    Repo.insert_all("identity", [%{
      id: "singleton",
      name: name,
      instance_id: instance_id,
      capabilities: "[]",
      cert_fingerprint: nil,
      inserted_at: now,
      updated_at: now
    }])

    %{
      name: name,
      instance_id: instance_id,
      capabilities: [],
      version: app_version()
    }
  end

  defp parse_identity(row) do
    capabilities = case Jason.decode(row.capabilities || "[]") do
      {:ok, list} -> list
      _ -> []
    end

    %{
      name: row.name,
      instance_id: row.instance_id,
      capabilities: capabilities,
      version: app_version()
    }
  end

  defp persist(identity) do
    capabilities = Jason.encode!(identity[:capabilities] || [])
    now = DateTime.utc_now()

    Repo.update_all(
      from("identity", where: [id: "singleton"]),
      set: [
        name: identity.name,
        capabilities: capabilities,
        updated_at: now
      ]
    )
  end

  defp generate_instance_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp app_version do
    Application.spec(:sonar, :vsn) |> to_string()
  end
end
