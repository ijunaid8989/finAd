defmodule FinancialAdvisor.Services.CalendarService do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User
  alias FinancialAdvisor.CalendarEvent

  @calendar_api_url "https://www.googleapis.com/calendar/v3/calendars"

  def get_access_token(user) do
    token = user.google_access_token
    # TODO: Check token expiry and refresh if needed
    {:ok, token}
  end

  def sync_events(user, time_min \\ nil) do
    time_min = time_min || DateTime.add(DateTime.utc_now(), -7 * 24 * 3600)

    with {:ok, access_token} <- get_access_token(user),
         calendar_id <- user.google_calendar_id || "primary" do
      case list_events(access_token, calendar_id, time_min) do
        {:ok, events} ->
          events
          |> Enum.map(&store_event(user, &1))
          |> Enum.count(&match?({:ok, _}, &1))

        {:error, reason} ->
          Logger.error("Failed to sync calendar events: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def list_events(access_token, calendar_id, time_min) do
    query =
      URI.encode_query(%{
        timeMin: DateTime.to_iso8601(time_min),
        maxResults: 250,
        singleEvents: true,
        orderBy: "startTime"
      })

    case HTTPoison.get(
           "#{@calendar_api_url}/#{calendar_id}/events?#{query}",
           [{"Authorization", "Bearer #{access_token}"}]
         ) do
      {:ok, response} ->
        response.body |> Jason.decode!() |> (&{:ok, Map.get(&1, "items", [])}).()

      {:error, reason} ->
        Logger.error("Failed to list events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp store_event(user, event_data) do
    parsed = parse_event(event_data)

    CalendarEvent.changeset(%CalendarEvent{}, Map.merge(parsed, %{user_id: user.id}))
    |> Repo.insert(on_conflict: :nothing)
  end

  defp parse_event(event) do
    start_time = parse_datetime(event["start"])
    end_time = parse_datetime(event["end"])

    attendees =
      (event["attendees"] || [])
      |> Enum.map(& &1["email"])

    %{
      google_event_id: event["id"],
      title: event["summary"] || "(no title)",
      description: event["description"],
      start_time: start_time,
      end_time: end_time,
      attendees: attendees,
      metadata: %{
        event_type: event["eventType"],
        status: event["status"]
      }
    }
  end

  defp parse_datetime(%{"dateTime" => dt}), do: DateTime.from_iso8601(dt) |> elem(1)
  defp parse_datetime(%{"date" => _date}), do: DateTime.utc_now()
  defp parse_datetime(_), do: DateTime.utc_now()

  def create_event(user, title, description, start_time, end_time, attendees) do
    with {:ok, access_token} <- get_access_token(user),
         calendar_id <- user.google_calendar_id || "primary" do
      body =
        Jason.encode!(%{
          summary: title,
          description: description,
          start: %{dateTime: DateTime.to_iso8601(start_time)},
          end: %{dateTime: DateTime.to_iso8601(end_time)},
          attendees: Enum.map(attendees, &%{email: &1}),
          reminders: %{
            useDefault: true
          }
        })

      case HTTPoison.post(
             "#{@calendar_api_url}/#{calendar_id}/events",
             body,
             [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]
           )
           |> IO.inspect() do
        {:ok, response} ->
          response.body |> Jason.decode!() |> (&{:ok, &1}).()

        {:error, reason} ->
          Logger.error("Failed to create calendar event: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  def update_event(user, event_id, updates) do
    with {:ok, access_token} <- get_access_token(user),
         calendar_id <- user.google_calendar_id || "primary" do
      body = Jason.encode!(updates)

      case HTTPoison.patch(
             "#{@calendar_api_url}/#{calendar_id}/events/#{event_id}",
             body,
             [
               {"Authorization", "Bearer #{access_token}"},
               {"Content-Type", "application/json"}
             ]
           ) do
        {:ok, response} ->
          response.body |> Jason.decode!() |> (&{:ok, &1}).()

        {:error, reason} ->
          Logger.error("Failed to update calendar event: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end
end
