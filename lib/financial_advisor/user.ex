defmodule FinancialAdvisor.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :google_id, :string
    field :hubspot_id, :string
    field :google_access_token, :binary
    field :google_refresh_token, :binary
    field :hubspot_access_token, :binary
    field :hubspot_refresh_token, :binary
    field :google_calendar_id, :string
    field :settings, :map, default: %{}

    has_many :conversations, FinancialAdvisor.Conversation
    has_many :emails, FinancialAdvisor.Email
    has_many :hubspot_contacts, FinancialAdvisor.HubspotContact
    has_many :calendar_events, FinancialAdvisor.CalendarEvent
    has_many :tasks, FinancialAdvisor.Task
    has_many :ongoing_instructions, FinancialAdvisor.OngoingInstruction

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :google_id, :hubspot_id, :google_calendar_id, :settings])
    |> validate_required([:email])
    |> unique_constraint(:email)
  end

  def google_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:google_access_token, :google_refresh_token, :google_id])
    |> validate_required([:google_id, :google_access_token])
  end

  def hubspot_oauth_changeset(user, attrs) do
    user
    |> cast(attrs, [:hubspot_access_token, :hubspot_id, :hubspot_refresh_token])
    |> validate_required([:hubspot_access_token, :hubspot_id, :hubspot_refresh_token])
  end
end
