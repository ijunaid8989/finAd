defmodule FinancialAdvisor.OngoingInstruction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ongoing_instructions" do
    field :instruction, :string
    field :status, :string, default: "active"
    field :trigger_type, :string
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisor.User

    timestamps()
  end

  def changeset(instr, attrs) do
    instr
    |> cast(attrs, [:instruction, :status, :trigger_type, :metadata, :user_id])
    |> validate_required([:instruction, :user_id])
  end
end
