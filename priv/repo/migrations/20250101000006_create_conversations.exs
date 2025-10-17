defmodule FinancialAdvisor.Repo.Migrations.CreateConversations do
  use Ecto.Migration

  def change do
    create table(:conversations) do
      add :user_id, references(:users), null: false
      add :title, :string
      add :messages, {:array, :jsonb}, default: []
      add :context, :jsonb, default: "{}"

      timestamps()
    end

    create index(:conversations, [:user_id])
  end
end
