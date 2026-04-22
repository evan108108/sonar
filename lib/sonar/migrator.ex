defmodule Sonar.Migrator do
  @moduledoc """
  Runs Ecto migrations on startup. Ensures the DB schema is current
  before any other process tries to query it. Safe to run repeatedly.
  """

  use Task, restart: :transient

  def start_link(_opts) do
    Task.start_link(__MODULE__, :migrate, [])
  end

  def migrate do
    Ecto.Migrator.run(Sonar.Repo, :up, all: true)
  end
end
