defmodule FinancialAdvisor.Services.TaskProcessor do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Task
  alias FinancialAdvisor.User
  alias FinancialAdvisor.Services.{
    AIAgent,
    GmailService,
    CalendarService,
    EmailMonitorService,
    HubspotService
  }
  import Ecto.Query

  def process_pending_tasks do
    pending_tasks =
      Task
      |> where([t], t.status == "pending")
      |> Repo.all()

    Enum.each(pending_tasks, &process_task/1)
  end

  def process_waiting_tasks do
    # Check for email responses to waiting tasks
    # This is called frequently to check if responses have arrived
    User
    |> where([u], not is_nil(u.google_access_token))
    |> Repo.all()
    |> Enum.each(fn user ->
      # Check if this user has any waiting tasks before syncing
      waiting_count =
        Task
        |> where([t], t.user_id == ^user.id)
        |> where([t], t.status == "waiting_for_response")
        |> Repo.aggregate(:count, :id)

      if waiting_count > 0 do
        Logger.info("User #{user.email} has #{waiting_count} waiting task(s), checking for responses...")
        EmailMonitorService.check_for_task_responses(user.id)
      end
    end)
  end

  # Process a specific task (public function for immediate processing)
  def process_task(task) do
    Logger.info("Processing task: #{task.id} - #{task.title}")

    user = Repo.preload(task, :user).user

    case execute_task(user, task) do
      {:ok, result, :waiting} ->
        # Task requires waiting for response
        task
        |> Task.changeset(%{
          status: "waiting_for_response",
          result: result
        })
        |> Repo.update()

      {:ok, result} ->
        # Task completed immediately
        task
        |> Task.changeset(%{
          status: "completed",
          result: result,
          completed_at: DateTime.utc_now()
        })
        |> Repo.update()

      {:error, reason} ->
        Logger.error("Task #{task.id} failed: #{inspect(reason)}")

        task
        |> Task.changeset(%{
          status: "failed",
          metadata: Map.merge(task.metadata || %{}, %{error: inspect(reason)})
        })
        |> Repo.update()
    end
  end

  defp execute_task(user, task) do
    # Execute based on task type and tool calls
    task_type = get_in(task.metadata, ["type"]) || infer_task_type(task)

    case task_type do
      "schedule_appointment" ->
        execute_schedule_appointment(user, task)

      "send_email" ->
        execute_send_email(user, task)

      _ ->
        # Generic task execution using AI agent
        execute_with_ai(user, task)
    end
  end

  defp infer_task_type(task) do
    title_lower = String.downcase(task.title || "")
    desc_lower = String.downcase(task.description || "")

    cond do
      String.contains?(title_lower, "schedule") or String.contains?(title_lower, "appointment") ->
        "schedule_appointment"

      String.contains?(title_lower, "email") or String.contains?(desc_lower, "email") ->
        "send_email"

      true ->
        "generic"
    end
  end

  defp execute_schedule_appointment(user, task) do
    # Extract contact info from task metadata
    # Try both string and atom keys for compatibility
    metadata = task.metadata || %{}
    contact_name = get_in(metadata, ["contact_name"]) || get_in(metadata, [:contact_name]) || ""
    contact_email = get_in(metadata, ["contact_email"]) || get_in(metadata, [:contact_email])

    Logger.info("Executing schedule appointment task: contact=#{contact_name}, email=#{contact_email}")
    Logger.info("Task metadata: #{inspect(metadata)}")

    # If contact_email is missing, try to extract from tool_calls
    contact_email =
      if contact_email do
        contact_email
      else
        # Try to get from tool_calls input
        case task.tool_calls do
          [%{"name" => "schedule_appointment", "input" => input} | _] ->
            input["contact_email"] || input[:contact_email]

          _ ->
            nil
        end
      end

    # If contact_name is missing but we have email, try to find the contact
    contact_name =
      if contact_name && contact_name != "" do
        contact_name
      else
        # Try to get from tool_calls
        case task.tool_calls do
          [%{"name" => "schedule_appointment", "input" => input} | _] ->
            input["contact_name"] || input[:contact_name] || ""

          _ ->
            ""
        end
      end

    # If we still don't have contact_email, try to find it by contact_name
    contact_email =
      if is_nil(contact_email) && contact_name && contact_name != "" do
        Logger.info("Contact email not in metadata, searching for contact: #{contact_name}")
        case HubspotService.search_contacts(user, contact_name) do
          {:ok, [contact | _]} ->
            props = contact["properties"] || %{}
            found_email = props["email"] || props["Email"]
            Logger.info("Found contact email: #{found_email}")
            found_email

          _ ->
            nil
        end
      else
        contact_email
      end

    if contact_email do
      # Get available times from calendar
      case CalendarService.get_upcoming_events(user, 14) do
        {:ok, events} ->
          # Build available time slots (simplified - in production, calculate gaps)
          available_times = build_available_times(events)

          # Send email with available times
          subject = "Scheduling Request: #{task.title}"
          body = build_scheduling_email_body(task, available_times)

          Logger.info("Sending scheduling email to #{contact_email}")

          case GmailService.send_email(user, contact_email, subject, body) do
            {:ok, result} ->
              Logger.info("Email sent successfully to #{contact_email}: #{inspect(result)}")

              # Create waiting task for response
              conversation = Repo.preload(task, :conversation).conversation

              EmailMonitorService.create_waiting_task(
                user,
                conversation,
                task.title,
                task.description,
                task.tool_calls,
                contact_email,
                ["Re:", "Schedule", "Appointment", "Time"]
              )

              {:ok, %{email_sent: true, waiting_for_response: true, email_to: contact_email}, :waiting}

            {:error, reason} ->
              Logger.error("Failed to send email to #{contact_email}: #{inspect(reason)}")
              {:error, "Failed to send email to #{contact_email}: #{inspect(reason)}"}
          end

        {:error, reason} ->
          Logger.error("Failed to get calendar events: #{inspect(reason)}")
          {:error, "Failed to get calendar: #{inspect(reason)}"}
      end
    else
      error_msg = "Contact email not found in task metadata"
      error_msg = if contact_name && contact_name != "", do: "#{error_msg} for contact: #{contact_name}", else: error_msg
      Logger.error("#{error_msg}. Task ID: #{task.id}, Metadata: #{inspect(task.metadata)}, Tool calls: #{inspect(task.tool_calls)}")
      {:error, error_msg}
    end
  end

  defp build_available_times(_events) do
    # Simplified - in production, calculate actual free time slots
    # For now, return some example times
    [
      "Tomorrow at 10:00 AM",
      "Tomorrow at 2:00 PM",
      "Thursday at 10:00 AM",
      "Thursday at 2:00 PM",
      "Friday at 10:00 AM"
    ]
  end

  defp build_scheduling_email_body(task, available_times) do
    """
    Hi,

    #{task.description || "I'd like to schedule a meeting with you."}

    Here are some available times:
    #{Enum.map(available_times, &"- #{&1}") |> Enum.join("\n")}

    Please let me know which time works best for you, or suggest an alternative time.

    Best regards
    """
  end

  defp execute_send_email(user, task) do
    # Extract email details from tool calls
    email_params = extract_email_params(task.tool_calls)

    case GmailService.send_email(
           user,
           email_params["to"],
           email_params["subject"],
           email_params["body"]
         ) do
      {:ok, _} ->
        {:ok, %{email_sent: true}}

      {:error, reason} ->
        {:error, "Failed to send email: #{inspect(reason)}"}
    end
  end

  defp extract_email_params(tool_calls) do
    # Find send_email tool call
    email_call =
      Enum.find(tool_calls || [], fn call ->
        call["name"] == "send_email" || (is_map(call) && Map.get(call, "name") == "send_email")
      end)

    case email_call do
      %{"input" => input} when is_map(input) -> input
      %{input: input} when is_map(input) -> input
      _ -> %{}
    end
  end

  defp execute_with_ai(user, task) do
    # Use AI agent to execute the task
    conversation = Repo.preload(task, :conversation).conversation

    prompt = """
    Please execute the following task:
    Title: #{task.title}
    Description: #{task.description || "N/A"}

    Tool calls to execute:
    #{inspect(task.tool_calls)}

    Use the appropriate tools to complete this task.
    """

    case AIAgent.chat(user, prompt, conversation && conversation.id) do
      {:ok, response} ->
        {:ok, %{ai_response: response}}

      {:error, reason} ->
        {:error, "AI execution failed: #{inspect(reason)}"}
    end
  end
end
