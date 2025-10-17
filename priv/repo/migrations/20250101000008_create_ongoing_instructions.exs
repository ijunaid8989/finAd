defmodule FinancialAdvisor.Repo.Migrations.CreateOngoingInstructions do
  use Ecto.Migration

  def change do
    create table(:ongoing_instructions) do
      add :user_id, references(:users), null: false
      add :instruction, :text, null: false
      add :status, :string, default: "active"
      add :trigger_type, :string
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    create index(:ongoing_instructions, [:user_id])
    create index(:ongoing_instructions, [:status])
  end
end
