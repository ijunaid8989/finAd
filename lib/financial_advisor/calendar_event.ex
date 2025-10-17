defmodule FinancialAdvisor.CalendarEvent do
  use Ecto.Schema
  import Ecto.Changeset

  schema "calendar_events" do
    field :google_event_id, :string
    field :title, :string
    field :description, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :attendees, {:array, :string}, default: []
    field :metadata, :map, default: %{}

    belongs_to :user, FinancialAdvisor.User

    timestamps()
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :google_event_id,
      :title,
      :description,
      :start_time,
      :end_time,
      :attendees,
      :metadata,
      :user_id
    ])
    |> validate_required([:google_event_id, :title, :start_time, :end_time, :user_id])
    |> unique_constraint(:google_event_id, name: :calendar_events_user_id_google_event_id_index)
  end
end
