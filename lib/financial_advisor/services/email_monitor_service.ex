defmodule FinancialAdvisor.Services.EmailMonitorService do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Task
  alias FinancialAdvisor.Email
  alias FinancialAdvisor.Services.AIAgent
  import Ecto.Query

  # Monitor emails for task responses
  def check_for_task_responses(user_id) do
    # Get all tasks waiting for email responses
    waiting_tasks =
      Task
      |> where([t], t.user_id == ^user_id)
      |> where([t], t.status == "waiting_for_response")
      |> Repo.all()

    # Get recent emails
    recent_emails =
      Email
      |> where([e], e.user_id == ^user_id)
      |> where([e], e.received_at >= ago(1, "hour"))
      |> order_by([e], desc: e.received_at)
      |> Repo.all()

    # Check each waiting task for matching emails
    Enum.each(waiting_tasks, fn task ->
      check_task_for_responses(task, recent_emails)
    end)
  end

  defp check_task_for_responses(task, recent_emails) do
    # Extract expected email info from task metadata
    expected_from = get_in(task.metadata, ["expected_from"])
    expected_subject_keywords = get_in(task.metadata, ["expected_subject_keywords"]) || []

    # Find matching emails
    matching_emails =
      recent_emails
      |> Enum.filter(fn email ->
        matches_task?(email, expected_from, expected_subject_keywords)
      end)

    if Enum.any?(matching_emails) do
      Logger.info("Found response email for task #{task.id}")
      process_task_response(task, List.first(matching_emails))
    end
  end

  defp matches_task?(email, expected_from, expected_subject_keywords) do
    from_match =
      if expected_from do
        String.contains?(String.downcase(email.from || ""), String.downcase(expected_from))
      else
        true
      end

    subject_match =
      if Enum.any?(expected_subject_keywords) do
        email_subject = String.downcase(email.subject || "")
        Enum.any?(expected_subject_keywords, fn keyword ->
          String.contains?(email_subject, String.downcase(keyword))
        end)
      else
        true
      end

    from_match && subject_match
  end

  defp process_task_response(task, email) do
    user = Repo.preload(task, :user).user

    # Update task status
    task
    |> Task.changeset(%{
      status: "processing_response",
      metadata: Map.merge(task.metadata || %{}, %{
        response_email_id: email.id,
        response_received_at: DateTime.utc_now()
      })
    })
    |> Repo.update()

    # Use AI agent to process the response
    continue_task_with_response(user, task, email)
  end

  defp continue_task_with_response(user, task, email) do
    # Build context for AI to process the response
    context = """
    A response has been received for task: #{task.title}

    Task Description: #{task.description || "N/A"}
    Original Task: #{inspect(task.tool_calls)}

    Response Email:
    - From: #{email.from}
    - Subject: #{email.subject}
    - Body: #{String.slice(email.body || "", 0, 1000)}
    """

    # Create a prompt for the AI to continue the task
    prompt = """
    A response has been received for the task. Please:
    1. Parse the email response
    2. Determine what action to take (accept, decline, request new times, etc.)
    3. Use the appropriate tools to complete the task
    4. Update any relevant contacts or calendar events
    5. Send any necessary follow-up emails

    Task Context:
    #{context}
    """

    # Get conversation
    conversation = Repo.preload(task, :conversation).conversation

    # Use AI agent to continue the task
    case AIAgent.chat(user, prompt, conversation && conversation.id) do
      {:ok, response} ->
        # Mark task as completed
        task
        |> Task.changeset(%{
          status: "completed",
          result: Map.merge(task.result || %{}, %{
            final_response: response,
            completed_at: DateTime.utc_now()
          })
        })
        |> Repo.update()

        Logger.info("Task #{task.id} completed after processing response")

      {:error, reason} ->
        Logger.error("Failed to continue task #{task.id}: #{inspect(reason)}")
        # Mark as failed or keep waiting
        task
        |> Task.changeset(%{status: "waiting_for_response"})
        |> Repo.update()
    end
  end

  # Helper to create a task that waits for email response
  def create_waiting_task(user, conversation, title, description, tool_calls, expected_from, expected_subject_keywords \\ []) do
    Task.changeset(%Task{}, %{
      user_id: user.id,
      conversation_id: conversation && conversation.id,
      title: title,
      description: description,
      status: "waiting_for_response",
      tool_calls: tool_calls,
      metadata: %{
        expected_from: expected_from,
        expected_subject_keywords: expected_subject_keywords,
        created_at: DateTime.utc_now()
      }
    })
    |> Repo.insert()
  end
end
