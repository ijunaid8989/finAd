defmodule FinancialAdvisorWeb.WebhookController do
  use FinancialAdvisorWeb, :controller
  require Logger
  alias FinancialAdvisor.Services.WebhookProcessor
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User

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
        events = conn.body_params["_json"] || []

        Enum.each(events, fn event ->
          if event["subscriptionType"] == "object.creation" && event["changeFlag"] == "CREATED" do
            portal_id = event["portalId"]
            contact_id = event["objectId"]

            # Process asynchronously so we return 200 quickly
            Task.start_link(fn ->
              FinancialAdvisor.Services.HubspotContactWebhookHandler.handle_contact_creation(
                portal_id,
                contact_id
              )
            end)
          end
        end)

        # Always return 200 OK to acknowledge receipt
        send_resp(conn, 200, "OK")

      false ->
        send_resp(conn, 401, "Unauthorized")
    end
  end

  defp verify_webhook_signature(_conn, _provider) do
    # TODO: Implement webhook signature verification
    # For production, verify the X-HubSpot-Request-Signature header
    # using your webhook signing secret
    true
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

  defp verify_webhook_signature(_conn, _provider) do
    # TODO: Implement webhook signature verification based on provider
    true
  end
end
