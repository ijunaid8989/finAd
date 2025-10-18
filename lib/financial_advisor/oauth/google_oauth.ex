defmodule FinancialAdvisor.OAuth.GoogleOAuth do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User

  @google_auth_url "https://accounts.google.com/o/oauth2/v2/auth"
  @google_token_url "https://oauth2.googleapis.com/token"
  @google_userinfo_url "https://www.googleapis.com/oauth2/v2/userinfo"

  @scopes [
    "https://www.googleapis.com/auth/gmail.modify",
    "https://www.googleapis.com/auth/calendar",
    "openid",
    "email",
    "profile"
  ]

  def config do
    %{
      client_id: System.get_env("GOOGLE_CLIENT_ID"),
      client_secret: System.get_env("GOOGLE_CLIENT_SECRET"),
      redirect_uri: System.get_env("GOOGLE_REDIRECT_URI")
    }
  end

  def auth_url(state) do
    params =
      URI.encode_query(%{
        client_id: config().client_id,
        redirect_uri: config().redirect_uri,
        response_type: "code",
        scope: Enum.join(@scopes, " "),
        state: state,
        access_type: "offline",
        prompt: "consent"
      })

    "#{@google_auth_url}?#{params}"
  end

  def get_token(code) do
    case HTTPoison.post(
           @google_token_url,
           encode_body(%{
             code: code,
             client_id: config().client_id,
             client_secret: config().client_secret,
             redirect_uri: config().redirect_uri,
             grant_type: "authorization_code"
           })
         ) do
      {:ok, response} ->
        response.body
        |> Jason.decode!()
        |> case do
          %{"error" => error} -> {:error, error}
          data -> {:ok, data}
        end

      {:error, reason} ->
        Logger.error("Google token exchange failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def refresh_token(refresh_token) do
    case HTTPoison.post(
           @google_token_url,
           encode_body(%{
             client_id: config().client_id,
             client_secret: config().client_secret,
             refresh_token: refresh_token,
             grant_type: "refresh_token"
           })
         ) do
      {:ok, response} ->
        response.body
        |> Jason.decode!()
        |> case do
          %{"error" => error} -> {:error, error}
          data -> {:ok, data}
        end

      {:error, reason} ->
        Logger.error("Google token refresh failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_user_info(access_token) do
    case HTTPoison.get(@google_userinfo_url, [{"Authorization", "Bearer #{access_token}"}]) do
      {:ok, response} ->
        response.body |> Jason.decode!() |> (&{:ok, &1}).()

      {:error, reason} ->
        Logger.error("Failed to fetch Google user info: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def upsert_user(google_data, access_token, refresh_token) do
    email = google_data["email"]

    case Repo.get_by(User, email: email) do
      nil ->
        %User{}
        |> User.changeset(%{email: email, google_id: google_data["id"]})
        |> User.google_oauth_changeset(%{
          google_access_token: encrypt_token(access_token),
          google_refresh_token: encrypt_token(refresh_token),
          google_id: google_data["id"]
        })
        |> Repo.insert()

      user ->
        user
        |> User.google_oauth_changeset(%{
          google_access_token: encrypt_token(access_token),
          google_refresh_token: encrypt_token(refresh_token),
          google_id: google_data["id"]
        })
        |> Repo.update()
    end
  end

  @doc """
  Makes a Google API request with automatic token refresh on 401.
  Returns {:ok, status_code, response_body} or {:error, reason}
  """
  def make_request(method, url, user, body \\ nil, headers \\ []) do
    headers = [
      {"Authorization", "Bearer #{user.google_access_token}"},
      {"Content-Type", "application/json"} | headers
    ]

    case do_request(method, url, body, headers) do
      {:ok, 200, response_body} ->
        {:ok, response_body}

      {:ok, 401, _} ->
        refresh_and_retry(method, url, user, body, headers)

      {:ok, status, response_body} ->
        Logger.error("Google API error: HTTP #{status}")
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        Logger.error("Google API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp refresh_and_retry(method, url, user, body, _headers) do
    with {:ok, token_data} <- refresh_token(user.google_refresh_token),
         new_access_token = token_data["access_token"],
         refresh_token = token_data["refresh_token"],
         {:ok, _} <- update_user_token(user, new_access_token, refresh_token),
         headers = [
           {"Authorization", "Bearer #{new_access_token}"},
           {"Content-Type", "application/json"}
         ],
         {:ok, 200, response_body} <- do_request(method, url, body, headers) do
      {:ok, response_body}
    else
      {:error, reason} ->
        Logger.error("Token refresh failed: #{inspect(reason)}")
        {:error, reason}

      {:ok, status, _} ->
        Logger.error("Google API error after refresh: HTTP #{status}")
        {:error, "HTTP #{status} after token refresh"}
    end
  end

  defp update_user_token(user, new_access_token, refresh_token) do
    user
    |> Ecto.Changeset.change(google_access_token: encrypt_token(new_access_token))
    |> Ecto.Changeset.change(google_refresh_token: encrypt_token(refresh_token))
    |> Repo.update()
  end

  defp do_request(:get, url, _body, headers) do
    case HTTPoison.get(url, headers) do
      {:ok, response} -> {:ok, response.status_code, response.body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_request(:post, url, body, headers) do
    case HTTPoison.post(url, body, headers) do
      {:ok, response} -> {:ok, response.status_code, response.body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_request(:patch, url, body, headers) do
    case HTTPoison.patch(url, body, headers) do
      {:ok, response} -> {:ok, response.status_code, response.body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp encrypt_token(token) do
    # TODO: Implement encryption/decryption with your key management service
    token
  end

  defp encode_body(params) do
    params
    |> Jason.encode!()
  end
end
