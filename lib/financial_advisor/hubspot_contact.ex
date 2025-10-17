defmodule FinancialAdvisor.HubspotContact do
  use Ecto.Schema
  import Ecto.Changeset

  schema "hubspot_contacts" do
    field :hubspot_contact_id, :string
    field :email, :string
    field :first_name, :string
    field :last_name, :string
    field :phone, :string
    field :properties, :map, default: %{}
    field :notes, :string
    field :synced_at, :utc_datetime

    belongs_to :user, FinancialAdvisor.User
    has_one :embedding, FinancialAdvisor.ContactEmbedding

    timestamps()
  end

  def changeset(contact, attrs) do
    contact
    |> cast(attrs, [
      :hubspot_contact_id,
      :email,
      :first_name,
      :last_name,
      :phone,
      :properties,
      :notes,
      :synced_at,
      :user_id
    ])
    |> validate_required([:hubspot_contact_id, :user_id])
    |> unique_constraint(:hubspot_contact_id,
      name: :hubspot_contacts_user_id_hubspot_contact_id_index
    )
  end
end
