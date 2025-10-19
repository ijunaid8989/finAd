defmodule FinancialAdvisor.CalendarEventEmailLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "calendar_event_email_logs" do
    field :attendee_email, :string
    field :sent_at, :utc_datetime

    belongs_to :calendar_event, FinancialAdvisor.CalendarEvent

    timestamps()
  end

  def changeset(log, attrs) do
    log
    |> cast(attrs, [:calendar_event_id, :attendee_email, :sent_at])
    |> validate_required([:calendar_event_id, :attendee_email])
    |> unique_constraint(:attendee_email,
      name: :calendar_event_email_logs_calendar_event_id_attendee_email_index
    )
  end
end
