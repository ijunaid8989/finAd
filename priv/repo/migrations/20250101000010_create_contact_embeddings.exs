defmodule FinancialAdvisor.Repo.Migrations.CreateContactEmbeddings do
  use Ecto.Migration

  def change do
    create table(:contact_embeddings) do
      add :contact_id, references(:hubspot_contacts), null: false
      add :embedding, :vector, size: 1536
      add :content_hash, :string

      timestamps()
    end

    create index(:contact_embeddings, [:contact_id])
  end
end
