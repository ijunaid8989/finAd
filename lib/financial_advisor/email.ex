defmodule FinancialAdvisor.Email do
  use Ecto.Schema
  import Ecto.Changeset

  schema "emails" do
    field :gmail_id, :string
    field :from, :string
    field :to, {:array, :string}
    field :subject, :string
    field :body, :string
    field :html_body, :string
    field :received_at, :utc_datetime
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisor.User
    has_one :embedding, FinancialAdvisor.EmailEmbedding

    timestamps()
  end

  def changeset(email, attrs) do
    email
    |> cast(attrs, [
      :gmail_id,
      :from,
      :to,
      :subject,
      :body,
      :html_body,
      :received_at,
      :metadata,
      :user_id
    ])
    |> validate_required([:gmail_id, :from, :to, :user_id])
    |> unique_constraint(:gmail_id, name: :emails_user_id_gmail_id_index)
  end
end
