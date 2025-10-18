defmodule FinancialAdvisor.OAuthState do
  use Ecto.Schema
  import Ecto.Changeset

  schema "oauth_states" do
    field :state, :string
    field :provider, :string
    field :expires_at, :utc_datetime

    belongs_to :user, FinancialAdvisor.User

    timestamps()
  end

  def changeset(oauth_state, attrs) do
    oauth_state
    |> cast(attrs, [:state, :provider, :user_id, :expires_at])
    |> validate_required([:state, :provider, :expires_at])
    |> unique_constraint(:state)
  end
end
