defmodule Sonar.Repo.Migrations.AddRemoteMessageId do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :remote_message_id, :string
    end
  end
end
