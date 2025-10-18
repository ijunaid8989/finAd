defmodule FinancialAdvisor.Repo.Migrations.AddHubspotRefreshTokenToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :hubspot_refresh_token, :binary
    end
  end
end
