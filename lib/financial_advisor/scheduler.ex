defmodule FinancialAdvisor.Scheduler do
  use GenServer
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User

  alias FinancialAdvisor.Services.{
    GmailService,
    CalendarService,
    HubspotService,
    EmbeddingsService,
    WebhookProcessor,
    TaskProcessor
  }

  import Ecto.Query

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_work()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sync_data, state) do
    Logger.info("Starting scheduled data sync...")

    User
    |> where([u], not is_nil(u.google_access_token) or not is_nil(u.hubspot_access_token))
    |> Repo.all()
    |> Enum.each(&sync_user_data/1)

    schedule_work()
    {:noreply, state}
  end

  defp sync_user_data(user) do
    Logger.info("Syncing data for user: #{user.email}")

    # Sync Gmail
    if user.google_access_token do
      case GmailService.sync_emails(user, 100) do
        count when is_integer(count) ->
          Logger.info("Synced #{count} emails for #{user.email}")

        {:error, reason} ->
          Logger.error("Failed to sync emails for #{user.email}: #{inspect(reason)}")
      end

      # Embed new emails
      sync_email_embeddings(user)
    end

    # Sync Calendar
    if user.google_access_token do
      case CalendarService.sync_events(user) do
        count when is_integer(count) ->
          Logger.info("Synced #{count} calendar events for #{user.email}")

        {:error, reason} ->
          Logger.error("Failed to sync calendar for #{user.email}: #{inspect(reason)}")
      end
    end

    # Sync HubSpot
    if user.hubspot_access_token do
      case HubspotService.sync_contacts(user, 100) do
        count when is_integer(count) ->
          Logger.info("Synced #{count} HubSpot contacts for #{user.email}")

        {:error, reason} ->
          Logger.error("Failed to sync HubSpot for #{user.email}: #{inspect(reason)}")
      end

      # Embed new contacts
      sync_contact_embeddings(user)
    end

    # Process pending tasks
    TaskProcessor.process_pending_tasks()
  end

  defp sync_email_embeddings(user) do
    query =
      from(e in FinancialAdvisor.Email,
        where: e.user_id == ^user.id,
        left_join: emb in FinancialAdvisor.EmailEmbedding,
        on: emb.email_id == e.id,
        where: is_nil(emb.id),
        select: e
      )

    Repo.all(query)
    |> Enum.each(&EmbeddingsService.embed_email/1)
  end

  defp sync_contact_embeddings(user) do
    query =
      from(c in FinancialAdvisor.HubspotContact,
        where: c.user_id == ^user.id,
        left_join: emb in FinancialAdvisor.ContactEmbedding,
        on: emb.hubspot_contact_id == c.id,
        where: is_nil(emb.id),
        select: c
      )

    Repo.all(query)
    |> Enum.each(&EmbeddingsService.embed_contact/1)
  end

  defp schedule_work do
    Process.send_after(self(), :sync_data, 5 * 60 * 1000)
  end
end
