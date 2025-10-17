defmodule FinancialAdvisor.Repo.Migrations.CreateWebhookLogs do
  use Ecto.Migration

  def change do
    create table(:webhook_logs) do
      add :user_id, references(:users), null: false
      add :provider, :string
      add :event_type, :string
      add :payload, :jsonb
      add :processed, :boolean, default: false
      add :error, :text

      timestamps()
    end

    create index(:webhook_logs, [:user_id])
    create index(:webhook_logs, [:processed])
  end
end
