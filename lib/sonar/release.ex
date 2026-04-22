defmodule Sonar.Release do
  @moduledoc """
  Release tasks — run migrations on startup.
  Called from application.ex to ensure the DB schema is current.
  """

  @app :sonar

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.ensure_all_started(:sonar)
  end
end
