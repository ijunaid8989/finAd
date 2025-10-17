defmodule FinancialAdvisor.Task do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tasks" do
    field :title, :string
    field :description, :string
    field :status, :string, default: "pending"
    field :tool_calls, {:array, :map}, default: []
    field :result, :map
    field :metadata, :map, default: %{}
    field :completed_at, :utc_datetime

    belongs_to :user, FinancialAdvisor.User
    belongs_to :conversation, FinancialAdvisor.Conversation

    timestamps()
  end

  def changeset(task, attrs) do
    task
    |> cast(attrs, [
      :title,
      :description,
      :status,
      :tool_calls,
      :result,
      :metadata,
      :completed_at,
      :user_id,
      :conversation_id
    ])
    |> validate_required([:title, :user_id])
  end
end
