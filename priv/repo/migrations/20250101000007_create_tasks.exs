defmodule FinancialAdvisor.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks) do
      add :user_id, references(:users), null: false
      add :conversation_id, references(:conversations)
      add :title, :string, null: false
      add :description, :text
      add :status, :string, default: "pending"
      add :tool_calls, {:array, :jsonb}, default: []
      add :result, :jsonb
      add :metadata, :jsonb, default: "{}"
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:tasks, [:user_id])
    create index(:tasks, [:status])
  end
end
