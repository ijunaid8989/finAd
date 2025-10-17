defmodule FinancialAdvisor.Repo.Migrations.CreateEmails do
  use Ecto.Migration

  def change do
    create table(:emails) do
      add :user_id, references(:users), null: false
      add :gmail_id, :string, null: false
      add :from, :string, null: false
      add :to, {:array, :string}, null: false
      add :subject, :string
      add :body, :text
      add :html_body, :text
      add :received_at, :utc_datetime
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    create index(:emails, [:user_id])
    create unique_index(:emails, [:user_id, :gmail_id])
  end
end
