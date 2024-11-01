defmodule FinancialAdvisor.Services.CalendarService do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User
  alias FinancialAdvisor.CalendarEvent
  alias FinancialAdvisor.CalendarEventEmailLog
  alias FinancialAdvisor.OAuth.GoogleOAuth
  alias FinancialAdvisor.Services.GmailService
  import Ecto.Query

  @calendar_api_url "https://www.googleapis.com/calendar/v3/calendars"

  def sync_events(user, time_min \\ nil) do
    time_min = time_min || DateTime.add(DateTime.utc_now(), -7 * 24 * 3600)
    calendar_id = user.google_calendar_id || "primary"

    case list_events(user, calendar_id, time_min) do
      {:ok, events} ->
        events
        |> Enum.map(&store_event(user, &1))
        |> Enum.count(&match?({:ok, _}, &1))

      {:error, reason} ->
        Logger.error("Failed to sync calendar events: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def poll_new_events do
    User
    |> where([u], not is_nil(u.google_access_token))
    |> Repo.all()
    |> Enum.each(&poll_user_events/1)
  end

  defp poll_user_events(user) do
    Logger.info("Polling new calendar events for user: #{user.email}")
    calendar_id = user.google_calendar_id || "primary"

    time_min = DateTime.utc_now()

    case list_events(user, calendar_id, time_min) do
      {:ok, events} ->
        Logger.info("Found #{Enum.count(events)} new events for #{user.email}")

        events
        |> Enum.filter(&created_by_user?/1)
        |> Enum.each(&process_new_event(user, &1))

      {:error, reason} ->
        Logger.error("Failed to poll events for #{user.email}: #{inspect(reason)}")
    end
  end

  defp created_by_user?(%{
         "creator" => %{"email" => creator_email},
         "organizer" => %{"email" => organizer_email}
       }) do
    creator_email == organizer_email
  end

  defp created_by_user?(_), do: false

  defp process_new_event(user, event_data) do
    event_id = event_data["id"]
    title = event_data["summary"] || "(no title)"

    case Repo.get_by(CalendarEvent, user_id: user.id, google_event_id: event_id) do
      nil ->
        Logger.info("New event detected: #{title} (#{event_id})")
        store_event_and_notify(user, event_data)

      existing_event ->
        Logger.debug("Event already exists: #{title}")
        check_and_send_pending_emails(user, existing_event, event_data)
    end
  end

  defp store_event_and_notify(user, event_data) do
    parsed = parse_event(event_data)

    with {:ok, event} <-
           CalendarEvent.changeset(%CalendarEvent{}, Map.merge(parsed, %{user_id: user.id}))
           |> Repo.insert() do
      send_emails_to_attendees(user, event, parsed[:attendees])
      {:ok, event}
    else
      {:error, reason} ->
        Logger.error("Failed to store event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp check_and_send_pending_emails(user, event, event_data) do
    attendees = parse_event(event_data)[:attendees]

    pending_attendees =
      attendees
      |> Enum.reject(fn email ->
        Repo.exists?(
          from(l in CalendarEventEmailLog,
            where: l.calendar_event_id == ^event.id and l.attendee_email == ^email
          )
        )
      end)

    if Enum.any?(pending_attendees) do
      Logger.info(
        "Found #{Enum.count(pending_attendees)} pending attendees for event #{event.id}"
      )

      send_emails_to_attendees(user, event, pending_attendees)
    end
  end

  defp send_emails_to_attendees(user, event, attendees) do
    Enum.each(attendees, fn attendee_email ->
      send_event_email(user, event, attendee_email)
    end)
  end

  defp send_event_email(user, event, attendee_email) do
    if attendee_email == user.email do
      Logger.debug("Skipping email to organizer: #{attendee_email}")
      mark_email_sent(event.id, attendee_email)
      :ok
    else
      subject = "Invitation: #{event.title}"

      body = """
      Hi there,

      You've been invited to: #{event.title}

      Date & Time: #{format_datetime(event.start_time)} - #{format_datetime(event.end_time)}
      #{if event.description, do: "\nDescription:\n#{event.description}", else: ""}

      Please update your calendar accordingly.

      Best regards,
      #{user.email}
      """

      case GmailService.send_email(user, attendee_email, subject, body) do
        {:ok, _} ->
          Logger.info("Event email sent to #{attendee_email} for event #{event.id}")
          mark_email_sent(event.id, attendee_email)
          :ok

        {:error, reason} ->
          Logger.error("Failed to send event email to #{attendee_email}: #{inspect(reason)}")
          :error
      end
    end
  end

  defp mark_email_sent(calendar_event_id, attendee_email) do
    CalendarEventEmailLog.changeset(%CalendarEventEmailLog{}, %{
      calendar_event_id: calendar_event_id,
      attendee_email: attendee_email,
      sent_at: DateTime.utc_now()
    })
    |> Repo.insert(on_conflict: :nothing)
  end

  def list_events(user, calendar_id, time_min) do
    query =
      URI.encode_query(%{
        timeMin: DateTime.to_iso8601(time_min),
        maxResults: 250,
        singleEvents: true,
        orderBy: "startTime"
      })

    case GoogleOAuth.make_request(
           :get,
           "#{@calendar_api_url}/#{calendar_id}/events?#{query}",
           user
         ) do
      {:ok, response_body} ->
        response_body |> Jason.decode!() |> (&{:ok, Map.get(&1, "items", [])}).()

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
      |> Enum.filter(&(&1 != nil))

    %{
      google_event_id: event["id"],
      title: event["summary"] || "(no title)",
      description: event["description"],
      start_time: start_time,
      end_time: end_time,
      attendees: attendees,
      metadata: %{
        event_type: event["eventType"],
        status: event["status"],
        creator_email: get_in(event, ["creator", "email"])
      }
    }
  end

  defp parse_datetime(%{"dateTime" => dt}), do: DateTime.from_iso8601(dt) |> elem(1)
  defp parse_datetime(%{"date" => _date}), do: DateTime.utc_now()
  defp parse_datetime(_), do: DateTime.utc_now()

  defp format_datetime(datetime) when is_struct(datetime, DateTime) do
    datetime
    |> DateTime.shift_zone!("Etc/UTC")
    |> Calendar.strftime("%B %d, %Y at %I:%M %p %Z")
  end

  defp format_datetime(_), do: "N/A"

  def create_event(user, title, description, start_time, end_time, attendees) do
    calendar_id = user.google_calendar_id || "primary"

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

    case GoogleOAuth.make_request(
           :post,
           "#{@calendar_api_url}/#{calendar_id}/events",
           user,
           body
         ) do
      {:ok, response_body} ->
        response_body |> Jason.decode!() |> (&{:ok, &1}).()

      {:error, reason} ->
        Logger.error("Failed to create calendar event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def update_event(user, event_id, updates) do
    calendar_id = user.google_calendar_id || "primary"
    body = Jason.encode!(updates)

    case GoogleOAuth.make_request(
           :patch,
           "#{@calendar_api_url}/#{calendar_id}/events/#{event_id}",
           user,
           body
         ) do
      {:ok, response_body} ->
        response_body |> Jason.decode!() |> (&{:ok, &1}).()

      {:error, reason} ->
        Logger.error("Failed to update calendar event: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_upcoming_events(user, days_ahead \\ 7) do
    time_min = DateTime.utc_now()
    time_max = DateTime.add(time_min, days_ahead * 24 * 3600)

    events =
      from(e in CalendarEvent,
        where: e.user_id == ^user.id,
        where: e.start_time >= ^time_min,
        where: e.start_time <= ^time_max,
        order_by: [asc: e.start_time]
      )
      |> Repo.all()

    {:ok, events}
  end

  # Find event by title and optional date
  def find_event_by_title(user, title, date \\ nil) do
    query =
      from(e in CalendarEvent,
        where: e.user_id == ^user.id,
        where: ilike(e.title, ^"%#{title}%"),
        order_by: [desc: e.start_time],
        limit: 10
      )

    query =
      if date do
        date_start = DateTime.new!(date, ~T[00:00:00], "Etc/UTC")
        date_end = DateTime.add(date_start, 1, :day)

        query
        |> where([e], e.start_time >= ^date_start and e.start_time < ^date_end)
      else
        query
      end

    events = Repo.all(query)

    case events do
      [] -> {:error, "No event found with title containing '#{title}'"}
      [event] -> {:ok, event}
      events -> {:ok, List.first(events)}
    end
  end

  # Find event by Google event ID
  def find_event_by_google_id(user, google_event_id) do
    case Repo.get_by(CalendarEvent, user_id: user.id, google_event_id: google_event_id) do
      nil -> {:error, "Event not found with ID: #{google_event_id}"}
      event -> {:ok, event}
    end
  end
end
