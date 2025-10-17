defmodule FinancialAdvisor.Repo.Migrations.CreateCalendarEvents do
  use Ecto.Migration

  def change do
    create table(:calendar_events) do
      add :user_id, references(:users), null: false
      add :google_event_id, :string, null: false
      add :title, :string, null: false
      add :description, :text
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime, null: false
      add :attendees, {:array, :string}, default: []
      add :metadata, :jsonb, default: "{}"

      timestamps()
    end

    create index(:calendar_events, [:user_id])
    create unique_index(:calendar_events, [:user_id, :google_event_id])
  end
end
