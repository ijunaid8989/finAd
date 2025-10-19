defmodule FinancialAdvisor.Repo.Migrations.CreateCalendarEventEmailLogs do
  use Ecto.Migration

  def change do
    create table(:calendar_event_email_logs) do
      add :calendar_event_id, references(:calendar_events), null: false
      add :attendee_email, :string, null: false
      add :sent_at, :utc_datetime

      timestamps()
    end

    create index(:calendar_event_email_logs, [:calendar_event_id])

    create unique_index(
             :calendar_event_email_logs,
             [:calendar_event_id, :attendee_email],
             name: :calendar_event_email_logs_calendar_event_id_attendee_email_index
           )
  end
end
