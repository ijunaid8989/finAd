defmodule FinancialAdvisor.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :email, :string, null: false
      add :google_id, :string
      add :hubspot_id, :string
      add :google_access_token, :binary
      add :google_refresh_token, :binary
      add :hubspot_access_token, :binary
      add :google_calendar_id, :string
      add :settings, :jsonb, default: "{}"

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:google_id])
  end
end
