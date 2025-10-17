defmodule FinancialAdvisor.EmailEmbedding do
  use Ecto.Schema
  import Ecto.Changeset

  schema "email_embeddings" do
    field :embedding, Pgvector.Ecto.Vector
    field :content_hash, :string

    belongs_to :email, FinancialAdvisor.Email

    timestamps()
  end

  def changeset(emb, attrs) do
    emb
    |> cast(attrs, [:embedding, :content_hash, :email_id])
    |> validate_required([:embedding, :email_id])
  end
end
