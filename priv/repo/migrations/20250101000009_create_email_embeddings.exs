defmodule FinancialAdvisor.Repo.Migrations.CreateEmailEmbeddings do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS vector"

    create table(:email_embeddings) do
      add :email_id, references(:emails), null: false
      add :embedding, :vector, size: 1536
      add :content_hash, :string

      timestamps()
    end

    create index(:email_embeddings, [:email_id])
  end
end
