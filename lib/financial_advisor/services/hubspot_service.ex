defmodule FinancialAdvisor.Services.HubspotService do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.HubspotContact
  alias FinancialAdvisor.OAuth.HubspotOAuth

  @hubspot_api_url "https://api.hubapi.com"

  def sync_contacts(user, limit \\ 100) do
    case list_contacts(user, limit) do
      {:ok, contacts} ->
        contacts
        |> Enum.map(&store_contact(user, &1))
        |> Enum.count(&match?({:ok, _}, &1))

      {:error, reason} ->
        Logger.error("Failed to sync HubSpot contacts: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def list_contacts(user, limit \\ 100, after_token \\ nil) do
    query_params = %{limit: limit, properties: "firstname,lastname,email,phone"}

    query_params =
      if after_token, do: Map.put(query_params, :after, after_token), else: query_params

    query = URI.encode_query(query_params)

    case make_request(:get, "#{@hubspot_api_url}/crm/v3/objects/contacts?#{query}", user, nil) do
      {:ok, response_body} ->
        decoded = Jason.decode!(response_body)
        {:ok, decoded["results"] || []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_contact(user, contact_id) do
    query = URI.encode_query(%{properties: "firstname,lastname,email,phone"})

    case make_request(
           :get,
           "#{@hubspot_api_url}/crm/v3/objects/contacts/#{contact_id}?#{query}",
           user,
           nil
         ) do
      {:ok, response_body} ->
        {:ok, Jason.decode!(response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def search_contacts(user, query_text) do
    body = Jason.encode!(%{query: query_text, limit: 10})

    case make_request(:post, "#{@hubspot_api_url}/crm/v3/objects/contacts/search", user, body) do
      {:ok, response_body} ->
        decoded = Jason.decode!(response_body)
        {:ok, decoded["results"] || []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def create_contact(user, email, first_name, last_name, phone \\ nil) do
    body =
      Jason.encode!(%{
        properties: %{
          email: email,
          firstname: first_name,
          lastname: last_name,
          phone: phone
        }
      })

    case make_request(:post, "#{@hubspot_api_url}/crm/v3/objects/contacts", user, body) do
      {:ok, response_body} ->
        {:ok, Jason.decode!(response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def update_contact(user, contact_id, properties) do
    body = Jason.encode!(%{properties: properties})

    case make_request(
           :patch,
           "#{@hubspot_api_url}/crm/v3/objects/contacts/#{contact_id}",
           user,
           body
         ) do
      {:ok, response_body} ->
        {:ok, Jason.decode!(response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def add_note_to_contact(user, contact_id, note_text) do
    body =
      Jason.encode!(%{
        engagement: %{active: true, type: "NOTE"},
        associations: %{contactIds: [contact_id]},
        attachments: [],
        metadata: %{body: note_text}
      })

    case make_request(:post, "#{@hubspot_api_url}/crm/v3/objects/notes", user, body) do
      {:ok, response_body} ->
        {:ok, Jason.decode!(response_body)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp make_request(method, url, user, body) do
    headers = [
      {"Authorization", "Bearer #{user.hubspot_access_token}"},
      {"Content-Type", "application/json"}
    ]

    case do_request(method, url, body, headers) do
      {:ok, 200, response_body} ->
        {:ok, response_body}

      {:ok, 401, _} ->
        refresh_and_retry(method, url, user, body)

      {:ok, status, _} ->
        {:error, "HTTP #{status}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp refresh_and_retry(method, url, user, body) do
    IO.inspect(user)

    with {:ok, token_data} <- HubspotOAuth.refresh_token(user.hubspot_refresh_token),
         new_token = token_data["access_token"],
         {:ok, _} <- update_user_token(user, new_token),
         headers = [
           {"Authorization", "Bearer #{new_token}"},
           {"Content-Type", "application/json"}
         ],
         {:ok, 200, response_body} <- do_request(method, url, body, headers) do
      {:ok, response_body}
    else
      {:error, reason} ->
        Logger.error("Token refresh failed: #{inspect(reason)}")
        {:error, reason}

      {:ok, status, _} ->
        {:error, "HTTP #{status} after refresh"}
    end
  end

  defp update_user_token(user, new_token) do
    user
    |> Ecto.Changeset.change(hubspot_access_token: new_token)
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

  defp store_contact(user, contact_data) do
    parsed = parse_contact(contact_data)

    HubspotContact.changeset(%HubspotContact{}, Map.merge(parsed, %{user_id: user.id}))
    |> Repo.insert(on_conflict: :nothing)
  end

  defp parse_contact(contact) do
    props = contact["properties"] || %{}

    %{
      hubspot_contact_id: contact["id"],
      email: props["email"],
      first_name: props["firstname"],
      last_name: props["lastname"],
      phone: props["phone"],
      properties: props,
      synced_at: DateTime.utc_now()
    }
  end
end
