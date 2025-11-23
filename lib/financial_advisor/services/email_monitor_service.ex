defmodule FinancialAdvisor.Services.EmailMonitorService do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Task
  alias FinancialAdvisor.Email
  alias FinancialAdvisor.User
  alias FinancialAdvisor.Services.AIAgent
  import Ecto.Query

  # Monitor emails for task responses
  # This function syncs emails first, then checks for responses
  def check_for_task_responses(user_id) do
    user = Repo.get(User, user_id)

    if user && user.google_access_token do
      # Get all tasks waiting for email responses
      waiting_tasks =
        Task
        |> where([t], t.user_id == ^user_id)
        |> where([t], t.status == "waiting_for_response")
        |> Repo.all()

      if Enum.empty?(waiting_tasks) do
        Logger.debug("No waiting tasks for user #{user_id}")
        :ok
      else
        Logger.info("Checking for responses to #{length(waiting_tasks)} waiting tasks for user #{user_id}")

        # IMPORTANT: Sync emails first to get the latest responses
        Logger.info("Syncing emails for user #{user_id} before checking task responses...")
        case FinancialAdvisor.Services.GmailService.sync_emails(user, 50) do
          count when is_integer(count) ->
            Logger.info("Synced #{count} emails for user #{user_id}")

          {:error, reason} ->
            Logger.error("Failed to sync emails for user #{user_id}: #{inspect(reason)}")
            # Continue anyway with existing emails
        end

        # Get recent emails (check last 24 hours to catch any missed emails)
        recent_emails =
          Email
          |> where([e], e.user_id == ^user_id)
          |> where([e], e.received_at >= ago(24, "hour"))
          |> order_by([e], desc: e.received_at)
          |> Repo.all()

        Logger.info("Found #{length(recent_emails)} recent emails to check")

        # Check each waiting task for matching emails
        Enum.each(waiting_tasks, fn task ->
          check_task_for_responses(task, recent_emails)
        end)

        :ok
      end
    else
      Logger.warning("User #{user_id} not found or no Google access token")
      :ok
    end
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
    # Match by sender email (case-insensitive, partial match)
    from_match =
      if expected_from do
        email_from = String.downcase(email.from || "")
        expected_from_lower = String.downcase(expected_from)
        # Check if email is from the expected sender or contains the expected email
        String.contains?(email_from, expected_from_lower) ||
          String.contains?(expected_from_lower, email_from)
      else
        true
      end

    # Match by subject keywords (more flexible - any keyword match is enough)
    subject_match =
      if Enum.any?(expected_subject_keywords) do
        email_subject = String.downcase(email.subject || "")
        # Check if subject contains any of the keywords
        Enum.any?(expected_subject_keywords, fn keyword ->
          keyword_lower = String.downcase(keyword)
          String.contains?(email_subject, keyword_lower)
        end)
      else
        # If no keywords specified, match any email from the expected sender
        true
      end

    # Also check email body for scheduling-related keywords if subject doesn't match
    # Look for date/time patterns, confirmation words, etc.
    body_match =
      if not subject_match do
        email_body = String.downcase(email.body || "")

        # Check for date/time patterns
        date_time_patterns = [
          "wednesday", "thursday", "friday", "monday", "tuesday", "saturday", "sunday",
          "november", "december", "january", "february", "march", "april", "may",
          "june", "july", "august", "september", "october",
          "work", "would", "that", "works", "good", "fine", "ok", "okay", "yes",
          "26th", "27th", "28th", "29th", "30th", "31st", "1st", "2nd", "3rd",
          "am", "pm", "morning", "afternoon", "evening"
        ]

        # If it's from the expected sender, be more lenient with body matching
        if from_match do
          # Any date/time keyword is enough if from the right sender
          Enum.any?(date_time_patterns, fn keyword ->
            String.contains?(email_body, keyword)
          end)
        else
          true # If sender doesn't match, don't use body matching
        end
      else
        true
      end

    result = from_match && (subject_match || body_match)

    if result do
      Logger.info("Email matches task: from=#{email.from}, subject=#{email.subject}")
    end

    result
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
