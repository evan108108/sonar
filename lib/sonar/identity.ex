defmodule Sonar.Identity do
  @moduledoc """
  This agent's identity. Self-sovereign — the agent creates it, owns it, controls it.
  """

  use Agent

  def start_link(_opts) do
    hostname = :inet.gethostname() |> elem(1) |> to_string()

    identity = %{
      name: System.get_env("SONAR_NAME", hostname),
      instance_id: generate_instance_id(),
      capabilities: [],
      version: Application.spec(:sonar, :vsn) |> to_string()
    }

    Agent.start_link(fn -> identity end, name: __MODULE__)
  end

  def get do
    Agent.get(__MODULE__, & &1)
  end

  def update(changes) when is_map(changes) do
    Agent.update(__MODULE__, fn identity -> Map.merge(identity, changes) end)
  end

  defp generate_instance_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
