defmodule FinancialAdvisor.Repo.Migrations.CreateOAuthStates do
  use Ecto.Migration

  def change do
    create table(:oauth_states) do
      add :state, :string, null: false
      add :provider, :string, null: false
      add :user_id, references(:users)
      add :expires_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:oauth_states, [:state])
  end
end
