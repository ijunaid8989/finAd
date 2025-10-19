defmodule FinancialAdvisor.Services.WebhookProcessor do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.WebhookLog

  def process_webhook(user_id, provider, event_type, payload) do
    webhook_log =
      WebhookLog.changeset(%WebhookLog{}, %{
        user_id: user_id,
        provider: provider,
        event_type: event_type,
        payload: payload,
        processed: false
      })
      |> Repo.insert!()

    case process_event(user_id, provider, event_type, payload) do
      :ok ->
        webhook_log
        |> WebhookLog.changeset(%{processed: true})
        |> Repo.update()

      {:error, reason} ->
        Logger.error("Webhook processing failed: #{inspect(reason)}")

        webhook_log
        |> WebhookLog.changeset(%{error: inspect(reason)})
        |> Repo.update()
    end
  end

  defp process_event(_user_id, "gmail", "message_received", _payload) do
    # Handle incoming email - trigger ongoing instructions check
    Logger.info("New email received")
    :ok
  end

  defp process_event(_user_id, "hubspot", "contact_created", _payload) do
    # Handle contact creation - trigger ongoing instructions check
    Logger.info("New contact created in HubSpot")
    :ok
  end

  defp process_event(_user_id, "calendar", "event_created", _payload) do
    # Handle calendar event - trigger ongoing instructions check
    Logger.info("New calendar event created")
    :ok
  end

  defp process_event(_user_id, _provider, _event_type, _payload) do
    :ok
  end
end
