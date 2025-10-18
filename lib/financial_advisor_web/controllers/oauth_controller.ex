defmodule FinancialAdvisorWeb.OAuthController do
  use FinancialAdvisorWeb, :controller
  require Logger
  alias FinancialAdvisor.OAuth.{GoogleOAuth, HubspotOAuth, StateManager}
  alias FinancialAdvisor.Services.{GmailService, CalendarService, HubspotService}
  alias FinancialAdvisor.Repo

  def google_callback(conn, %{"code" => code, "state" => state}) do
    case StateManager.verify_state(state, "google") do
      {:ok, oauth_state} ->
        StateManager.consume_state(state)

        with {:ok, token_data} <- GoogleOAuth.get_token(code),
             {:ok, user_info} <- GoogleOAuth.get_user_info(token_data["access_token"]),
             {:ok, user} <-
               GoogleOAuth.upsert_user(
                 user_info,
                 token_data["access_token"],
                 token_data["refresh_token"]
               ) do
          # Sync initial data
          Task.start_link(fn ->
            GmailService.sync_emails(user, 50)
            CalendarService.sync_events(user)
          end)

          conn
          |> put_session("current_user", user)
          |> redirect(to: ~p"/chat")
        else
          {:error, reason} ->
            Logger.error("Google OAuth failed: #{inspect(reason)}")

            conn
            |> put_flash(:error, "Google authentication failed")
            |> redirect(to: ~p"/login")
        end

      {:error, reason} ->
        Logger.error("OAuth state verification failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Invalid OAuth state")
        |> redirect(to: ~p"/login")
    end
  end

  def hubspot_callback(conn, %{"code" => code, "state" => state}) do
    case StateManager.verify_state(state, "hubspot") do
      {:ok, oauth_state} ->
        StateManager.consume_state(state)
        current_user = get_session(conn, "current_user")

        unless current_user do
          conn
          |> put_flash(:error, "Please authenticate with Google first")
          |> redirect(to: ~p"/login")
        else
          with {:ok, token_data} <- HubspotOAuth.get_token(code) |> IO.inspect(),
               access_token = token_data["access_token"],
               refresh_token = token_data["refresh_token"],
               portal_id = token_data["hub_id"] || "default_hub_id" do
            {:ok, user} =
              HubspotOAuth.upsert_user_hubspot(
                current_user,
                access_token,
                "#{portal_id}",
                refresh_token
              )

            # Sync initial contacts
            Task.start_link(fn ->
              HubspotService.sync_contacts(user, 100)
            end)

            conn
            |> put_session("current_user", user)
            |> put_flash(:info, "HubSpot connected successfully!")
            |> redirect(to: ~p"/chat")
          else
            {:error, reason} ->
              Logger.error("HubSpot OAuth failed: #{inspect(reason)}")

              conn
              |> put_flash(:error, "HubSpot authentication failed: #{inspect(reason)}")
              |> redirect(to: ~p"/settings")
          end
        end

      {:error, reason} ->
        Logger.error("OAuth state verification failed: #{inspect(reason)}")

        conn
        |> put_flash(:error, "Invalid OAuth state")
        |> redirect(to: ~p"/login")
    end
  end

  def google_disconnect(conn, _params) do
    user = get_session(conn, "current_user")

    user
    |> Ecto.Changeset.change(google_access_token: nil, google_refresh_token: nil, google_id: nil)
    |> FinancialAdvisor.Repo.update()

    conn
    |> put_session("current_user", nil)
    |> put_flash(:info, "Google disconnected")
    |> redirect(to: ~p"/settings")
  end

  def hubspot_disconnect(conn, _params) do
    user = get_session(conn, "current_user")

    user
    |> Ecto.Changeset.change(hubspot_access_token: nil, hubspot_id: nil)
    |> FinancialAdvisor.Repo.update()

    conn
    |> put_session("current_user", nil)
    |> put_flash(:info, "HubSpot disconnected")
    |> redirect(to: ~p"/settings")
  end
end
