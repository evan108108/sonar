defmodule Sonar.Repo.Migrations.AddSessionIdsToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :target_session_id, :string
      add :from_session_id, :string
    end

    create index(:messages, [:target_session_id])
  end
end
