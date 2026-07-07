defmodule Sonar.Repo.Migrations.AddFailureReasonToMessages do
  use Ecto.Migration

  def change do
    alter table(:messages) do
      add :failure_reason, :string
    end
  end
end
