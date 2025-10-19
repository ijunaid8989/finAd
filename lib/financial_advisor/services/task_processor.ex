defmodule FinancialAdvisor.Services.TaskProcessor do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Task
  alias FinancialAdvisor.User
  alias FinancialAdvisor.Services.{
    AIAgent,
    GmailService,
    CalendarService,
    EmailMonitorService
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
    User
    |> where([u], not is_nil(u.google_access_token))
    |> Repo.all()
    |> Enum.each(fn user ->
      EmailMonitorService.check_for_task_responses(user.id)
    end)
  end

  defp process_task(task) do
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
    _contact_name = get_in(task.metadata, ["contact_name"])
    contact_email = get_in(task.metadata, ["contact_email"])

    if contact_email do
      # Get available times from calendar
      case CalendarService.get_upcoming_events(user, 14) do
        {:ok, events} ->
          # Build available time slots (simplified - in production, calculate gaps)
          available_times = build_available_times(events)

          # Send email with available times
          subject = "Scheduling Request: #{task.title}"
          body = build_scheduling_email_body(task, available_times)

          case GmailService.send_email(user, contact_email, subject, body) do
            {:ok, _} ->
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

              {:ok, %{email_sent: true, waiting_for_response: true}, :waiting}

            {:error, reason} ->
              {:error, "Failed to send email: #{inspect(reason)}"}
          end

        {:error, reason} ->
          {:error, "Failed to get calendar: #{inspect(reason)}"}
      end
    else
      {:error, "Contact email not found in task metadata"}
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
