defmodule FinancialAdvisorWeb.WebhookController do
  use FinancialAdvisorWeb, :controller
  require Logger
  alias FinancialAdvisor.Services.WebhookProcessor
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User
  import Ecto.Query

  def gmail(conn, _params) do
    case verify_webhook_signature(conn, "gmail") do
      true ->
        payload = conn.body_params

        # Find user by Gmail ID
        user = Repo.get_by(User, google_id: payload["userId"])

        if user do
          WebhookProcessor.process_webhook(user.id, "gmail", "message_received", payload)
        end

        send_resp(conn, 200, "OK")

      false ->
        send_resp(conn, 401, "Unauthorized")
    end
  end

  def hubspot(conn, _params) do
    case verify_webhook_signature(conn, "hubspot") do
      true ->
        payload = conn.body_params

        # Hubspot webhooks include a portalId
        user = Repo.get_by(User, hubspot_id: payload["portalId"])

        if user do
          Enum.each(payload["events"] || [], fn event ->
            WebhookProcessor.process_webhook(
              user.id,
              "hubspot",
              event["subscriptionType"],
              event["objectId"]
            )
          end)
        end

        send_resp(conn, 200, "OK")

      false ->
        send_resp(conn, 401, "Unauthorized")
    end
  end

  def calendar(conn, _params) do
    case verify_webhook_signature(conn, "calendar") do
      true ->
        payload = conn.body_params
        user = Repo.get_by(User, google_id: payload["userId"])

        if user do
          WebhookProcessor.process_webhook(user.id, "calendar", "event_changed", payload)
        end

        send_resp(conn, 200, "OK")

      false ->
        send_resp(conn, 401, "Unauthorized")
    end
  end

  defp verify_webhook_signature(conn, provider) do
    # TODO: Implement webhook signature verification based on provider
    true
  end
end
