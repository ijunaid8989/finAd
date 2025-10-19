defmodule FinancialAdvisor.Services.WebhookProcessor do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User
  alias FinancialAdvisor.WebhookLog
  alias FinancialAdvisor.Services.AIAgent

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

    # Process asynchronously to avoid blocking webhook response
    Task.start(fn ->
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
    end)

    # Return immediately to acknowledge webhook
    :ok
  end

  defp process_event(user_id, "gmail", "message_received", payload) do
    Logger.info("Processing email received webhook for user #{user_id}")

    case Repo.get(User, user_id) do
      nil ->
        Logger.error("User #{user_id} not found")
        {:error, "User not found"}

      user ->
        # Trigger proactive agent
        case AIAgent.handle_proactive_event(user, "email_received", payload, "email_received") do
          {:ok, _response} ->
            Logger.info("Proactive agent completed for email")
            :ok

          {:error, reason} ->
            Logger.error("Proactive agent failed for email: #{inspect(reason)}")
            # Don't fail the webhook, just log the error
            :ok
        end
    end
  end

  defp process_event(user_id, "hubspot", "contact_created", payload) do
    Logger.info("Processing contact created webhook for user #{user_id}")

    case Repo.get(User, user_id) do
      nil ->
        Logger.error("User #{user_id} not found")
        {:error, "User not found"}

      user ->
        # Trigger proactive agent
        case AIAgent.handle_proactive_event(user, "contact_created", payload, "contact_created") do
          {:ok, _response} ->
            Logger.info("Proactive agent completed for contact creation")
            :ok

          {:error, reason} ->
            Logger.error("Proactive agent failed for contact: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp process_event(user_id, "calendar", "event_created", payload) do
    Logger.info("Processing calendar event created webhook for user #{user_id}")

    case Repo.get(User, user_id) do
      nil ->
        Logger.error("User #{user_id} not found")
        {:error, "User not found"}

      user ->
        # Trigger proactive agent
        case AIAgent.handle_proactive_event(user, "event_created", payload, "calendar_event") do
          {:ok, _response} ->
            Logger.info("Proactive agent completed for calendar event")
            :ok

          {:error, reason} ->
            Logger.error("Proactive agent failed for calendar: #{inspect(reason)}")
            :ok
        end
    end
  end

  defp process_event(_user_id, _provider, _event_type, _payload) do
    :ok
  end
end
