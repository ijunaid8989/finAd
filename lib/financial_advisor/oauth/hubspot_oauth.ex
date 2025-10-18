defmodule FinancialAdvisor.OAuth.HubspotOAuth do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User

  @hubspot_auth_url "https://app.hubspot.com/oauth/authorize"
  @hubspot_token_url "https://api.hubapi.com/oauth/v1/token"
  @hubspot_userinfo_url "https://api.hubapi.com/crm/v3/objects/contacts/me"

  def config do
    %{
      client_id: System.get_env("HUBSPOT_CLIENT_ID", "8d697191-a8e4-4d03-bc1e-662d4eb27559"),
      client_secret:
        System.get_env("HUBSPOT_CLIENT_SECRET", "e6de7ae9-02c3-4316-9eeb-2527fdfac0ea"),
      redirect_uri:
        System.get_env("HUBSPOT_REDIRECT_URI", "http://localhost:4000/oauth/hubspot/callback")
    }
  end

  def auth_url(state) do
    params =
      URI.encode_query(%{
        client_id: config().client_id,
        redirect_uri: config().redirect_uri,
        scope: "crm.objects.contacts.read crm.objects.contacts.write",
        state: state
      })

    "#{@hubspot_auth_url}?#{params}"
  end

  def get_token(code) do
    body =
      URI.encode_query(%{
        grant_type: "authorization_code",
        client_id: config().client_id,
        client_secret: config().client_secret,
        redirect_uri: config().redirect_uri,
        code: code
      })

    case HTTPoison.post(@hubspot_token_url, body, [
           {"Content-Type", "application/x-www-form-urlencoded"}
         ]) do
      {:ok, response} ->
        response.body
        |> Jason.decode!()
        |> case do
          %{"error" => error} -> {:error, error}
          data -> {:ok, data}
        end

      {:error, reason} ->
        Logger.error("HubSpot token exchange failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def refresh_token(refresh_token) do
    body =
      URI.encode_query(%{
        grant_type: "refresh_token",
        client_id: config().client_id,
        client_secret: config().client_secret,
        refresh_token: refresh_token
      })

    case HTTPoison.post(@hubspot_token_url, body, [
           {"Content-Type", "application/x-www-form-urlencoded"}
         ]) do
      {:ok, response} ->
        response.body
        |> Jason.decode!()
        |> case do
          %{"error" => error} -> {:error, error}
          data -> {:ok, data}
        end

      {:error, reason} ->
        Logger.error("HubSpot token refresh failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_user_portal_id(access_token) do
    case HTTPoison.get(@hubspot_userinfo_url, [
           {"Authorization", "Bearer #{access_token}"},
           {"Content-Type", "application/json"}
         ]) do
      {:ok, response} ->
        response.body |> Jason.decode!() |> (&{:ok, &1}).()

      {:error, reason} ->
        Logger.error("Failed to fetch HubSpot user info: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def upsert_user_hubspot(user, access_token, hubspot_id) do
    user
    |> User.hubspot_oauth_changeset(%{
      hubspot_access_token: encrypt_token(access_token),
      hubspot_id: hubspot_id
    })
    |> Repo.update()
  end

  defp encrypt_token(token) do
    # TODO: Implement encryption/decryption with your key management service
    token
  end
end
