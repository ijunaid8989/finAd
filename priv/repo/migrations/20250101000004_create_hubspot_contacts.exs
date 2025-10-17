defmodule FinancialAdvisor.Repo.Migrations.CreateHubspotContacts do
  use Ecto.Migration

  def change do
    create table(:hubspot_contacts) do
      add :user_id, references(:users), null: false
      add :hubspot_contact_id, :string, null: false
      add :email, :string
      add :first_name, :string
      add :last_name, :string
      add :phone, :string
      add :properties, :jsonb, default: "{}"
      add :notes, :text
      add :synced_at, :utc_datetime

      timestamps()
    end

    create index(:hubspot_contacts, [:user_id])
    create unique_index(:hubspot_contacts, [:user_id, :hubspot_contact_id])
  end
end
