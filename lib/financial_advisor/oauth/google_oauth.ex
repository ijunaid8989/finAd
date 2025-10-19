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
    # Google OAuth token endpoint expects form-encoded data, not JSON
    body =
      URI.encode_query(%{
        code: code,
        client_id: config().client_id,
        client_secret: config().client_secret,
        redirect_uri: config().redirect_uri,
        grant_type: "authorization_code"
      })

    headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

    case HTTPoison.post(@google_token_url, body, headers) do
      {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
        case Jason.decode(response_body) do
          {:ok, %{"error" => error, "error_description" => description}} ->
            Logger.error("Google token exchange error: #{error} - #{description}")
            {:error, "#{error}: #{description}"}

          {:ok, data} ->
            {:ok, data}

          {:error, reason} ->
            Logger.error("Failed to decode token response: #{inspect(reason)}")
            {:error, "Invalid response format"}
        end

      {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
        Logger.error("Google token exchange failed: HTTP #{status}, #{response_body}")
        case Jason.decode(response_body) do
          {:ok, %{"error" => error, "error_description" => description}} ->
            {:error, "#{error}: #{description}"}

          _ ->
            {:error, "HTTP #{status}"}
        end

      {:error, reason} ->
        Logger.error("Google token exchange request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def refresh_token(refresh_token) do
    unless refresh_token do
      Logger.error("Refresh token is nil")
      {:error, "No refresh token available"}
    else
      # Google OAuth token endpoint expects form-encoded data, not JSON
      body =
        URI.encode_query(%{
          client_id: config().client_id,
          client_secret: config().client_secret,
          refresh_token: refresh_token,
          grant_type: "refresh_token"
        })

      headers = [{"Content-Type", "application/x-www-form-urlencoded"}]

      case HTTPoison.post(@google_token_url, body, headers) do
        {:ok, %HTTPoison.Response{status_code: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"error" => error, "error_description" => description}} ->
              Logger.error("Google token refresh error: #{error} - #{description}")
              {:error, "#{error}: #{description}"}

            {:ok, data} ->
              {:ok, data}

            {:error, reason} ->
              Logger.error("Failed to decode refresh token response: #{inspect(reason)}")
              {:error, "Invalid response format"}
          end

        {:ok, %HTTPoison.Response{status_code: status, body: response_body}} ->
          Logger.error("Google token refresh failed: HTTP #{status}, #{response_body}")
          case Jason.decode(response_body) do
            {:ok, %{"error" => error, "error_description" => description}} ->
              {:error, "#{error}: #{description}"}

            _ ->
              {:error, "HTTP #{status}"}
          end

        {:error, reason} ->
          Logger.error("Google token refresh request failed: #{inspect(reason)}")
          {:error, reason}
      end
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
    # Decrypt the access token before using it
    access_token = decrypt_token(user.google_access_token)

    headers = [
      {"Authorization", "Bearer #{access_token}"},
      {"Content-Type", "application/json"} | headers
    ]

    case do_request(method, url, body, headers) do
      {:ok, 200, response_body} ->
        {:ok, response_body}

      {:ok, 401, _} ->
        refresh_and_retry(method, url, user, body, headers)

      {:ok, status, response_body} ->
        Logger.error("Google API error: HTTP #{status}")
        {:error, "HTTP #{status}, #{inspect(response_body)}"}

      {:error, reason} ->
        Logger.error("Google API request failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp refresh_and_retry(method, url, user, body, _headers) do
    # Decrypt the refresh token before using it
    decrypted_refresh_token = decrypt_token(user.google_refresh_token)

    with {:ok, token_data} <- refresh_token(decrypted_refresh_token),
         new_access_token = token_data["access_token"],
         # Google may not return a new refresh_token if the old one is still valid
         new_refresh_token = token_data["refresh_token"] || decrypted_refresh_token,
         {:ok, _} <- update_user_token(user, new_access_token, new_refresh_token),
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

  defp encrypt_token(token) when is_binary(token) do
    # TODO: Implement encryption/decryption with your key management service
    # For now, tokens are stored as-is (no encryption)
    token
  end

  defp encrypt_token(nil), do: nil

  defp decrypt_token(token) when is_binary(token) do
    # TODO: Implement decryption with your key management service
    # For now, tokens are stored as-is (no decryption needed)
    token
  end

  defp decrypt_token(nil), do: nil

end
