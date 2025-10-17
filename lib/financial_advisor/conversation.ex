defmodule FinancialAdvisor.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  schema "conversations" do
    field :title, :string
    field :messages, {:array, :map}, default: []
    field :context, :map, default: %{}

    belongs_to :user, FinancialAdvisor.User
    has_many :tasks, FinancialAdvisor.Task

    timestamps()
  end

  def changeset(conv, attrs) do
    conv
    |> cast(attrs, [:title, :messages, :context, :user_id])
    |> validate_required([:user_id])
  end
end
