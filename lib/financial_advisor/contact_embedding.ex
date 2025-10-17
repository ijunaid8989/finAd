defmodule FinancialAdvisor.ContactEmbedding do
  use Ecto.Schema
  import Ecto.Changeset

  schema "contact_embeddings" do
    field :embedding, Pgvector.Ecto.Vector
    field :content_hash, :string

    belongs_to :contact, FinancialAdvisor.HubspotContact

    timestamps()
  end

  def changeset(emb, attrs) do
    emb
    |> cast(attrs, [:embedding, :content_hash, :contact_id])
    |> validate_required([:embedding, :contact_id])
  end
end
