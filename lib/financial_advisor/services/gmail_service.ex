defmodule FinancialAdvisor.Services.GmailService do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User
  alias FinancialAdvisor.Email
  alias FinancialAdvisor.OAuth.GoogleOAuth
  alias FinancialAdvisor.Services.EmbeddingsService

  @gmail_api_url "https://www.googleapis.com/gmail/v1/users/me"

  def sync_emails(user, limit \\ 100) do
    case list_messages(user, limit) do
      {:ok, messages} ->
        messages
        |> Enum.map(&fetch_and_store_message(user, &1))
        |> Enum.count(&match?({:ok, _}, &1))

      {:error, reason} ->
        Logger.error("Failed to list Gmail messages: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def list_messages(user, limit \\ 100) do
    query =
      URI.encode_query(%{
        q: "newer_than:7d",
        maxResults: limit
      })

    case GoogleOAuth.make_request(:get, "#{@gmail_api_url}/messages?#{query}", user) do
      {:ok, response_body} ->
        response_body |> Jason.decode!() |> (&{:ok, Map.get(&1, "messages", [])}).()

      {:error, reason} ->
        Logger.error("Failed to list messages: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_message(user, message_id) do
    case GoogleOAuth.make_request(
           :get,
           "#{@gmail_api_url}/messages/#{message_id}?format=full",
           user
         ) do
      {:ok, response_body} ->
        response_body |> Jason.decode!() |> (&{:ok, &1}).()

      {:error, reason} ->
        Logger.error("Failed to fetch message: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp fetch_and_store_message(user, message_ref) do
    with {:ok, full_message} <- get_message(user, message_ref["id"]) do
      parsed = parse_message(full_message)

      case Email.changeset(%Email{}, Map.merge(parsed, %{user_id: user.id}))
           |> Repo.insert(
             on_conflict: :nothing,
             conflict_target: [:user_id, :gmail_id],
             returning: true
           ) do
        {:ok, email} ->
          create_embeddings(email)
          {:ok, email}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp create_embeddings(%{id: nil}), do: :noop

  defp create_embeddings(email) do
    EmbeddingsService.embed_email(email)
  end

  defp parse_message(message) do
    headers = message["payload"]["headers"] || []
    subject = find_header(headers, "Subject") || "(no subject)"
    from = find_header(headers, "From") || "unknown"
    to = find_header(headers, "To", true)

    body_text = get_body_text(message["payload"])
    received_at = parse_timestamp(find_header(headers, "Date"))

    %{
      gmail_id: message["id"],
      subject: subject,
      from: from,
      to: to,
      body: body_text,
      received_at: received_at,
      metadata: %{
        thread_id: message["threadId"],
        labels: message["labelIds"] || []
      }
    }
  end

  defp find_header(headers, name, as_list \\ false) do
    case Enum.find(headers, &(&1["name"] == name)) do
      nil ->
        nil

      header ->
        value = header["value"]
        if as_list, do: String.split(value, ",") |> Enum.map(&String.trim/1), else: value
    end
  end

  defp get_body_text(payload) do
    case payload["parts"] do
      nil ->
        payload["body"]["data"]
        |> decode_gmail_base64()
        |> String.slice(0..1000)

      parts ->
        part = Enum.find(parts, &(&1["mimeType"] == "text/plain"))

        if part && part["body"]["data"] do
          part["body"]["data"]
          |> decode_gmail_base64()
          |> String.slice(0..1000)
        else
          ""
        end
    end
  end

  defp decode_gmail_base64(data) do
    data
    |> String.replace("-", "+")
    |> String.replace("_", "/")
    |> Base.decode64!(padding: false)
  rescue
    _ -> ""
  end

  defp parse_timestamp(date_str) when is_binary(date_str) do
    date_str = String.trim(date_str)

    case DateTime.from_iso8601(date_str) do
      {:ok, datetime, _} ->
        datetime

      :error ->
        DateTime.utc_now()
    end
  rescue
    _ ->
      DateTime.utc_now()
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()
  defp parse_timestamp(_), do: DateTime.utc_now()

  def send_email(user, to, subject, body) do
    raw_message = create_raw_message(user.email, to, subject, body)
    send_raw_message(user, raw_message)
  end

  defp create_raw_message(from, to, subject, body) do
    message = """
    From: #{from}
    To: #{to}
    Subject: #{subject}

    #{body}
    """

    message
    |> Base.encode64()
    |> String.replace("+", "-")
    |> String.replace("/", "_")
    |> String.trim("=")
  end

  defp send_raw_message(user, raw_message) do
    body = Jason.encode!(%{raw: raw_message})

    case GoogleOAuth.make_request(
           :post,
           "#{@gmail_api_url}/messages/send",
           user,
           body
         ) do
      {:ok, response_body} ->
        response_body |> Jason.decode!() |> (&{:ok, &1}).()

      {:error, reason} ->
        Logger.error("Failed to send email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def watch_emails(user) do
    body =
      Jason.encode!(%{
        topicName: "projects/YOUR_PROJECT_ID/topics/gmail-events"
      })

    case GoogleOAuth.make_request(:post, "#{@gmail_api_url}/watch", user, body) do
      {:ok, response_body} ->
        response_body |> Jason.decode!() |> (&{:ok, &1}).()

      {:error, reason} ->
        Logger.error("Failed to setup Gmail watch: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
