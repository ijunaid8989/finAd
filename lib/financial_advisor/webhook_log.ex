defmodule FinancialAdvisor.WebhookLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "webhook_logs" do
    field :provider, :string
    field :event_type, :string
    field :payload, :map
    field :processed, :boolean, default: false
    field :error, :string

    belongs_to :user, FinancialAdvisor.User

    timestamps()
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:provider, :event_type, :payload, :processed, :error, :user_id])
    |> validate_required([:user_id, :provider])
  end
end
