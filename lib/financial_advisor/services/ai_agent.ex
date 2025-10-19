defmodule FinancialAdvisor.Services.AIAgent do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Conversation
  alias FinancialAdvisor.OngoingInstruction
  alias FinancialAdvisor.Email

  alias FinancialAdvisor.Task
  alias FinancialAdvisor.Services.{
    RAGService,
    GmailService,
    CalendarService,
    HubspotService,
    TaskProcessor
  }

  import Ecto.Query

  @claude_api_url "https://api.anthropic.com/v1/messages"
  @default_model "claude-sonnet-4-5-20250929"
  @max_iterations 5

  def config do
    %{
      api_key: System.get_env("CLAUDE_API_KEY"),
      model: System.get_env("CLAUDE_MODEL") || @default_model
    }
  end

  def available_tools do
    [
      %{
        name: "search_emails",
        description: "Search through user emails for specific information using semantic search",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "The search query to find relevant emails"
            }
          },
          required: ["query"]
        }
      },
      %{
        name: "search_contacts",
        description: "Search for contacts in HubSpot by name or email",
        input_schema: %{
          type: "object",
          properties: %{
            query: %{
              type: "string",
              description: "Name or email to search for"
            }
          },
          required: ["query"]
        }
      },
      %{
        name: "get_calendar_availability",
        description: "Get available time slots and existing events in the user's calendar",
        input_schema: %{
          type: "object",
          properties: %{
            days_ahead: %{
              type: "integer",
              description: "Number of days to check ahead (default: 7)"
            }
          },
          required: []
        }
      },
      %{
        name: "send_email",
        description: "Send an email to a recipient via Gmail",
        input_schema: %{
          type: "object",
          properties: %{
            to: %{
              type: "string",
              description: "Recipient email address"
            },
            subject: %{
              type: "string",
              description: "Email subject"
            },
            body: %{
              type: "string",
              description: "Email body content"
            }
          },
          required: ["to", "subject", "body"]
        }
      },
      %{
        name: "schedule_appointment",
        description:
          "Schedule an appointment with a contact. This will: 1) Look up the contact, 2) Send them an email with available times, 3) Create a task that waits for their response, 4) When they respond, automatically create the calendar event. Use this when the user wants to schedule a meeting but hasn't confirmed a specific time yet. If a specific time is already confirmed, use create_calendar_event instead. Be proactive - if the user doesn't specify a title, use a default like 'Meeting with [Contact Name]'. If they don't specify duration, default to 1 hour.",
        input_schema: %{
          type: "object",
          properties: %{
            contact_name: %{
              type: "string",
              description: "Name of the contact to schedule with (e.g., 'Sara Smith')"
            },
            contact_email: %{
              type: "string",
              description: "Email address of the contact (optional if contact_name is provided and contact can be found)"
            },
            title: %{
              type: "string",
              description: "Meeting/appointment title (if not provided, use 'Meeting with [Contact Name]')"
            },
            description: %{
              type: "string",
              description: "Meeting description or agenda (optional)"
            },
            duration_hours: %{
              type: "number",
              description: "Duration of the meeting in hours (default: 1 if not specified)"
            }
          },
          required: ["contact_name"]
        }
      },
      %{
        name: "create_calendar_event",
        description:
          "Create a calendar event immediately when a specific time is already confirmed. IMPORTANT: Use ISO8601 format for times. Examples: 2025-10-21T14:00:00Z (next Tuesday 2PM UTC), 2025-10-22T21:00:00Z (next Wednesday 9PM UTC). Use this when the user has already confirmed a specific date and time. If you need to coordinate with someone to find a time, use schedule_appointment instead.",
        input_schema: %{
          type: "object",
          properties: %{
            title: %{
              type: "string",
              description: "Event title"
            },
            description: %{
              type: "string",
              description: "Event description"
            },
            start_time: %{
              type: "string",
              description:
                "Start time in ISO8601 format (YYYY-MM-DDTHH:MM:SSZ). ALWAYS use current or future dates, never past dates."
            },
            end_time: %{
              type: "string",
              description:
                "End time in ISO8601 format (YYYY-MM-DDTHH:MM:SSZ). Must be after start_time."
            },
            attendees: %{
              type: "array",
              items: %{type: "string"},
              description: "List of attendee email addresses"
            }
          },
          required: ["title", "start_time", "end_time"]
        }
      },
      %{
        name: "update_calendar_event",
        description:
          "Update an existing calendar event. You can find the event by title (and optionally by date) or by event_id. You can update the title, description, start_time, end_time, or attendees.",
        input_schema: %{
          type: "object",
          properties: %{
            event_id: %{
              type: "string",
              description: "Google Calendar event ID (optional if title is provided)"
            },
            title: %{
              type: "string",
              description: "Event title to search for (optional if event_id is provided)"
            },
            date: %{
              type: "string",
              description:
                "Date in YYYY-MM-DD format to narrow down search (optional, only used with title)"
            },
            new_title: %{
              type: "string",
              description: "New event title (optional)"
            },
            description: %{
              type: "string",
              description: "New event description (optional)"
            },
            start_time: %{
              type: "string",
              description:
                "New start time in ISO8601 format (YYYY-MM-DDTHH:MM:SSZ) (optional)"
            },
            end_time: %{
              type: "string",
              description:
                "New end time in ISO8601 format (YYYY-MM-DDTHH:MM:SSZ) (optional)"
            },
            attendees: %{
              type: "array",
              items: %{type: "string"},
              description: "New list of attendee email addresses (optional)"
            }
          },
          required: []
        }
      },
      %{
        name: "create_hubspot_contact",
        description: "Create a new contact in HubSpot",
        input_schema: %{
          type: "object",
          properties: %{
            email: %{
              type: "string",
              description: "Contact email address"
            },
            first_name: %{
              type: "string",
              description: "First name"
            },
            last_name: %{
              type: "string",
              description: "Last name"
            },
            phone: %{
              type: "string",
              description: "Phone number (optional)"
            }
          },
          required: ["email", "first_name", "last_name"]
        }
      },
      %{
        name: "add_contact_note",
        description:
          "Add a note to a HubSpot contact. You can use either contact_id (HubSpot ID) or email address to identify the contact. If email is provided, the system will find the contact automatically.",
        input_schema: %{
          type: "object",
          properties: %{
            contact_id: %{
              type: "string",
              description: "HubSpot contact ID (optional if email is provided)"
            },
            email: %{
              type: "string",
              description: "Contact email address (optional if contact_id is provided)"
            },
            note: %{
              type: "string",
              description: "Note content to add to the contact"
            }
          },
          required: ["note"]
        }
      },
      %{
        name: "save_ongoing_instruction",
        description: "Save an ongoing instruction that the agent should remember",
        input_schema: %{
          type: "object",
          properties: %{
            instruction: %{
              type: "string",
              description: "The instruction to remember and execute"
            },
            trigger_type: %{
              type: "string",
              description:
                "When to trigger this instruction (e.g., 'email_received', 'contact_created', 'manual')"
            }
          },
          required: ["instruction", "trigger_type"]
        }
      },
      %{
        name: "get_ongoing_instructions",
        description: "Get all active ongoing instructions",
        input_schema: %{
          type: "object",
          properties: %{},
          required: []
        }
      },
      %{
        name: "get_contact_context",
        description:
          "Get detailed context about a contact including recent emails exchanged and HubSpot notes",
        input_schema: %{
          type: "object",
          properties: %{
            email: %{
              type: "string",
              description: "Email address of the contact"
            }
          },
          required: ["email"]
        }
      }
    ]
  end

  def chat(user, message, conversation_id \\ nil) do
    conversation = get_or_create_conversation(user, conversation_id)

    with {:ok, rag_context} <- RAGService.get_context_for_query(user.id, message),
         instructions <- get_active_instructions(user.id),
         messages <- build_message_history(conversation, message, rag_context, instructions) do
      # Main chat loop with tool calling support
      chat_with_tools(user, messages, conversation, 0)
    else
      {:error, reason} ->
        Logger.error("Failed to prepare chat: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Proactive agent - triggered by webhooks/events
  def handle_proactive_event(user, event_type, event_data, trigger_type \\ nil) do
    Logger.info("Proactive agent triggered: #{event_type} for user #{user.id}")

    # Get ongoing instructions for this trigger type
    trigger = trigger_type || map_event_type_to_trigger(event_type)
    instructions = get_active_instructions_by_trigger(user.id, trigger)

    # Build context for the event
    event_context = build_event_context(user, event_type, event_data)

    # Build proactive prompt
    proactive_prompt = build_proactive_prompt(event_type, event_data, event_context, instructions)

    # Create or get system conversation for proactive actions
    conversation = get_or_create_system_conversation(user)

    # Get RAG context if needed
    rag_context =
      case RAGService.get_context_for_query(user.id, event_context) do
        {:ok, context} -> context
        _ -> "No additional context found."
      end

    messages = build_proactive_message_history(conversation, proactive_prompt, rag_context, instructions)

    # Execute proactive action with tool calling
    case chat_with_tools(user, messages, conversation, 0) do
      {:ok, response} ->
        Logger.info("Proactive agent completed: #{response}")
        {:ok, response}

      {:error, reason} ->
        Logger.error("Proactive agent failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp map_event_type_to_trigger("email_received"), do: "email_received"
  defp map_event_type_to_trigger("contact_created"), do: "contact_created"
  defp map_event_type_to_trigger("event_created"), do: "calendar_event"
  defp map_event_type_to_trigger(_), do: "manual"

  defp get_active_instructions_by_trigger(user_id, trigger_type) do
    OngoingInstruction
    |> where([oi], oi.user_id == ^user_id and oi.status == "active")
    |> where([oi], oi.trigger_type == ^trigger_type or oi.trigger_type == "manual")
    |> Repo.all()
  end

  defp build_event_context(_user, "email_received", payload) do
    email_from = payload["from"] || payload["emailAddress"] || "unknown"
    email_subject = payload["subject"] || "No subject"
    email_body = payload["body"] || payload["snippet"] || ""

    """
    New email received:
    - From: #{email_from}
    - Subject: #{email_subject}
    - Body: #{String.slice(email_body, 0, 500)}
    """
  end

  defp build_event_context(user, "contact_created", payload) do
    contact_id = payload["objectId"] || payload["contact_id"] || "unknown"
    _portal_id = payload["portalId"] || user.hubspot_id

    case HubspotService.get_contact(user, contact_id) do
      {:ok, contact} ->
        props = contact["properties"] || %{}
        """
        New contact created in HubSpot:
        - Name: #{props["firstname"] || ""} #{props["lastname"] || ""}
        - Email: #{props["email"] || "No email"}
        - Contact ID: #{contact_id}
        """

      _ ->
        "New contact created in HubSpot (ID: #{contact_id})"
    end
  end

  defp build_event_context(_user, "event_created", payload) do
    event_title = payload["summary"] || payload["title"] || "Untitled Event"
    event_start = payload["start"] || payload["start_time"] || "Unknown time"

    """
    New calendar event created:
    - Title: #{event_title}
    - Start: #{event_start}
    """
  end

  defp build_event_context(_user, _event_type, _payload) do
    "Event occurred"
  end

  defp build_proactive_prompt(_event_type, _event_data, event_context, instructions) do
    instructions_text =
      if Enum.empty?(instructions) do
        "No specific ongoing instructions for this event type."
      else
        instructions
        |> Enum.map(&"- #{&1.instruction}")
        |> Enum.join("\n")
      end

    """
    An event has occurred that may require action:

    #{event_context}

    ## Active Ongoing Instructions:
    #{instructions_text}

    Review this event and determine if any action should be taken based on the ongoing instructions.
    Use the available tools to:
    - Create contacts if email is from someone not in HubSpot
    - Send emails if needed
    - Add notes to contacts
    - Schedule follow-ups
    - Take any other appropriate actions

    Be proactive but only take actions that are clearly warranted by the ongoing instructions or the event context.
    If no action is needed, simply acknowledge the event.
    """
  end

  defp build_proactive_message_history(_conversation, prompt, rag_context, instructions) do
    now = DateTime.utc_now()
    current_date = DateTime.to_date(now)

    system_prompt = """
    You are a proactive AI assistant for a Financial Advisor. You monitor events (emails, contacts, calendar) and take actions based on ongoing instructions.

    Current Date/Time: #{DateTime.to_iso8601(now)}
    Today: #{Calendar.strftime(current_date, "%B %d, %Y")}

    ## Relevant Context:
    #{rag_context}

    ## Active Ongoing Instructions:
    #{format_instructions(instructions)}

    When an event occurs, review it against the ongoing instructions and take appropriate action using the available tools.
    """

    [
      %{"role" => "user", "content" => system_prompt},
      %{"role" => "user", "content" => prompt}
    ]
  end

  defp get_or_create_system_conversation(user) do
    # Use a special conversation for proactive actions
    # Could also create a new one each time, but reusing is better for context
    case Repo.one(
           from(c in Conversation,
             where: c.user_id == ^user.id,
             where: fragment("?->>'role' = ?", c.context, "system"),
             limit: 1
           )
         ) do
      nil ->
        Conversation.changeset(%Conversation{}, %{
          user_id: user.id,
          messages: [],
          context: %{role: "system", type: "proactive"},
          title: "System Proactive Actions"
        })
        |> Repo.insert!()

      conversation ->
        conversation
    end
  end

  # Main chat loop that handles tool calling iteratively
  defp chat_with_tools(user, messages, conversation, iteration) when iteration < @max_iterations do
    case call_claude(user, messages) do
      {:ok, response_data} ->
        content = response_data["content"] || []
        {tool_calls, text_response} = process_content_blocks(content)

        # If there are tool calls, execute them and continue the conversation
        if tool_calls != [] do
          tool_results = execute_tools(user, tool_calls, conversation)

          # Add assistant message with tool calls to conversation
          assistant_message = build_assistant_message_with_tools(content)

          # Add tool results as user message (Claude expects this format)
          tool_results_message = build_tool_results_message(tool_calls, tool_results)

          # Continue the conversation with tool results
          updated_messages = messages ++ [assistant_message, tool_results_message]

          # Recursively call Claude again with tool results
          chat_with_tools(user, updated_messages, conversation, iteration + 1)
        else
          # No tool calls, final response
          final_response = text_response || "I'm here to help!"

          # Save final response to conversation
          save_message_to_conversation(conversation, "assistant", final_response)

          {:ok, final_response}
        end

      {:error, reason} ->
        Logger.error("Claude API error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp chat_with_tools(_user, _messages, _conversation, iteration) when iteration >= @max_iterations do
    Logger.warning("Max iterations reached in tool calling loop")
    {:error, "Maximum tool calling iterations reached"}
  end

  defp get_or_create_conversation(user, nil) do
    Conversation.changeset(%Conversation{}, %{user_id: user.id})
    |> Repo.insert!()
  end

  defp get_or_create_conversation(_user, conversation_id) do
    Repo.get!(Conversation, conversation_id)
  end

  defp build_message_history(conversation, user_message, rag_context, instructions) do
    now = DateTime.utc_now()
    current_date = DateTime.to_date(now)
    current_day_name = Calendar.strftime(now, "%A")
    dates_map = calculate_weekday_dates(current_date)

    system_prompt = """
    You are an AI assistant for a Financial Advisor. You have access to the user's emails, calendar, and HubSpot contacts.

    ⏰ **IMPORTANT TIME CONTEXT** (Use this for ALL date calculations):
    - Current Date/Time: #{DateTime.to_iso8601(now)}
    - Today: #{current_day_name}, #{Calendar.strftime(current_date, "%B %d, %Y")}

    **Next Occurrences of Each Day:**
    - Monday: #{Calendar.strftime(dates_map.monday, "%B %d, %Y")} (#{dates_map.monday})
    - Tuesday: #{Calendar.strftime(dates_map.tuesday, "%B %d, %Y")} (#{dates_map.tuesday})
    - Wednesday: #{Calendar.strftime(dates_map.wednesday, "%B %d, %Y")} (#{dates_map.wednesday})
    - Thursday: #{Calendar.strftime(dates_map.thursday, "%B %d, %Y")} (#{dates_map.thursday})
    - Friday: #{Calendar.strftime(dates_map.friday, "%B %d, %Y")} (#{dates_map.friday})
    - Saturday: #{Calendar.strftime(dates_map.saturday, "%B %d, %Y")} (#{dates_map.saturday})
    - Sunday: #{Calendar.strftime(dates_map.sunday, "%B %d, %Y")} (#{dates_map.sunday})

    Your responsibilities:
    1. Answer questions about clients by using information from emails and HubSpot
    2. Help schedule appointments and manage tasks
    3. Remember and execute ongoing instructions
    4. Use tool calling to interact with Gmail, Google Calendar, and HubSpot
    5. Be proactive in searching for context before taking actions
    6. When scheduling appointments, be proactive and use sensible defaults:
       - If user says "Schedule appointment with [Name]", use "Meeting with [Name]" as the title
       - Default duration is 1 hour unless specified
       - Don't ask for details unless absolutely necessary - proceed with defaults
       - Only ask for clarification if the request is truly ambiguous

    ## When Creating Calendar Events:
    - ALWAYS use ISO8601 format: YYYY-MM-DDTHH:MM:SSZ
    - NEVER use past dates - always use the dates provided above
    - When user says a day name (e.g., "Thursday"), use the date from the list above
    - When user says "tomorrow", use: #{Calendar.strftime(Date.add(current_date, 1), "%Y-%m-%d")}
    - When user says "next [day]", use the corresponding date from above
    - Always add timezone suffix: Z for UTC times

    **Time Format Examples:**
    - 9PM UTC: T21:00:00Z
    - 9:15PM UTC: T21:15:00Z
    - 2:30PM UTC: T14:30:00Z
    - Midnight UTC: T00:00:00Z

    **Calendar Event Examples:**
    - If user: "add event on thursday at 9PM", use: #{dates_map.thursday}T21:00:00Z
    - If user: "schedule for next monday at 2:30PM", use: #{dates_map.monday}T14:30:00Z
    - If user: "tomorrow at 10AM", use: #{Date.add(current_date, 1)}T10:00:00Z

    ## Relevant Context from RAG:
    #{rag_context}

    ## Active Ongoing Instructions:
    #{format_instructions(instructions)}

    Remember to use tool_use blocks to call functions when needed. Be helpful, professional, and thorough.
    """

    previous_messages =
      Enum.map(conversation.messages || [], fn msg ->
        %{
          "role" => msg["role"],
          "content" => normalize_message_content(msg["content"])
        }
      end)

    [
      %{"role" => "user", "content" => system_prompt}
      | previous_messages
    ] ++ [%{"role" => "user", "content" => user_message}]
  end

  defp normalize_message_content(content) when is_binary(content), do: content
  defp normalize_message_content(content) when is_list(content), do: content
  defp normalize_message_content(content) when is_map(content), do: content
  defp normalize_message_content(_), do: ""

  # Format message for API - ensure proper structure
  defp format_message_for_api(%{"role" => role, "content" => content}) do
    formatted_content =
      case content do
        content when is_binary(content) ->
          content
        content when is_list(content) ->
          # Ensure all list items are properly formatted maps
          Enum.map(content, fn
            item when is_map(item) -> item
            item when is_binary(item) -> %{"type" => "text", "text" => item}
            item -> %{"type" => "text", "text" => to_string(item)}
          end)
        content ->
          to_string(content)
      end

    %{
      "role" => role,
      "content" => formatted_content
    }
  end

  defp format_message_for_api(%{role: role, content: content}) do
    format_message_for_api(%{"role" => to_string(role), "content" => content})
  end

  defp format_message_for_api(message) do
    # Fallback for any other format
    %{
      "role" => Map.get(message, "role") || Map.get(message, :role) || "user",
      "content" => Map.get(message, "content") || Map.get(message, :content) || ""
    }
  end

  defp format_instructions(instructions) do
    if Enum.empty?(instructions) do
      "No active ongoing instructions."
    else
      instructions
      |> Enum.map(&"- #{&1.instruction} (Trigger: #{&1.trigger_type})")
      |> Enum.join("\n")
    end
  end

  defp calculate_weekday_dates(reference_date) do
    current_day = Date.day_of_week(reference_date)

    # Calculate days until next occurrence of each weekday
    days_until = fn target_day ->
      if current_day < target_day do
        target_day - current_day
      else
        7 - current_day + target_day
      end
    end

    %{
      monday: Date.add(reference_date, days_until.(1)),
      tuesday: Date.add(reference_date, days_until.(2)),
      wednesday: Date.add(reference_date, days_until.(3)),
      thursday: Date.add(reference_date, days_until.(4)),
      friday: Date.add(reference_date, days_until.(5)),
      saturday: Date.add(reference_date, days_until.(6)),
      sunday: Date.add(reference_date, days_until.(7))
    }
  end

  defp get_active_instructions(user_id) do
    OngoingInstruction
    |> where([oi], oi.user_id == ^user_id and oi.status == "active")
    |> Repo.all()
  end

  defp call_claude(_user, messages) do
    api_key = config().api_key

    unless api_key do
      Logger.error("CLAUDE_API_KEY not set")
      {:error, "API key not configured"}
    else
      model = config().model

      # Ensure all messages are properly formatted with string keys
      formatted_messages = Enum.map(messages, &format_message_for_api/1)

      body = %{
        "model" => model,
        "max_tokens" => 4096,
        "system" =>
          "You are a helpful AI assistant for financial advisors. Use the provided tools to help users manage their contacts and schedule. Pay attention to date/time context provided in the system message.",
        "messages" => formatted_messages,
        "tools" => available_tools()
      }

      case Req.post(@claude_api_url,
             json: body,
             headers: [
               {"x-api-key", api_key},
               {"anthropic-version", "2023-06-01"},
               {"content-type", "application/json"}
             ]
           ) do
        {:ok, %Req.Response{status: 200, body: response_body}} ->
          # Req automatically decodes JSON, so body is already a map
          {:ok, response_body}

        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("Claude API error: status=#{status}, model=#{model}, body=#{inspect(body)}")
          {:error, "API error: #{status} - Check if model '#{model}' is available in your API account"}

        {:error, reason} ->
          Logger.error("Claude API request failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp process_content_blocks(content) do
    Enum.reduce(content, {[], ""}, fn block, {tool_calls, text} ->
      case block do
        %{"type" => "text", "text" => text_content} ->
          {tool_calls, if(text == "", do: text_content, else: text <> "\n" <> text_content)}

        %{"type" => "tool_use", "name" => name, "input" => input, "id" => id} ->
          {tool_calls ++ [{name, input, id}], text}

        _ ->
          {tool_calls, text}
      end
    end)
  end

  defp build_assistant_message_with_tools(content) do
    %{
      "role" => "assistant",
      "content" => content
    }
  end

  defp build_tool_results_message(tool_calls, tool_results) do
    tool_result_blocks =
      Enum.zip(tool_calls, tool_results)
      |> Enum.map(fn {{_name, _input, tool_id}, {_result_id, result}} ->
        # Ensure result is a string
        content = if(is_binary(result), do: result, else: Jason.encode!(result))

        %{
          "type" => "tool_result",
          "tool_use_id" => tool_id,
          "content" => content
        }
      end)

    %{
      "role" => "user",
      "content" => tool_result_blocks
    }
  end

  defp execute_tools(user, tool_calls, conversation) do
    tool_calls
    |> Enum.map(fn {name, input, id} ->
      try do
        result = execute_tool(user, name, input, id, conversation)
        {id, result}
      rescue
        e ->
          Logger.error("Tool execution error: #{inspect(e)}")
          {id, "Error executing tool: #{Exception.message(e)}"}
      catch
        :exit, reason ->
          Logger.error("Tool execution exit: #{inspect(reason)}")
          {id, "Tool execution failed: #{inspect(reason)}"}
      end
    end)
  end

  defp execute_tool(user, "search_emails", %{"query" => query}, _id, _conversation) do
    case RAGService.search_emails(user.id, query) do
      {:ok, results} ->
        if Enum.empty?(results) do
          "No emails found matching your query."
        else
          results
          |> Enum.take(5)
          |> Enum.map(fn %{email: email, similarity: similarity} ->
            "From: #{email.from || "Unknown"}, Subject: #{email.subject || "No subject"}, Date: #{format_date(email.received_at)}, Relevance: #{Float.round(similarity * 100, 1)}%"
          end)
          |> Enum.join("\n")
        end

      {:error, reason} ->
        "Error searching emails: #{inspect(reason)}"
    end
  end

  defp execute_tool(user, "search_contacts", %{"query" => query}, _id, _conversation) do
    case HubspotService.search_contacts(user, query) do
      {:ok, results} ->
        if Enum.empty?(results) do
          "No contacts found matching your query."
        else
          results
          |> Enum.take(10)
          |> Enum.map(fn contact ->
            props = contact["properties"] || %{}
            name = "#{props["firstname"] || ""} #{props["lastname"] || ""}" |> String.trim()
            email = props["email"] || "No email"
            phone = props["phone"] || "No phone"
            "Name: #{name}, Email: #{email}, Phone: #{phone}"
          end)
          |> Enum.join("\n")
        end

      {:error, reason} ->
        "Error searching contacts: #{inspect(reason)}"
    end
  end

  defp execute_tool(user, "get_calendar_availability", params, _id, _conversation) do
    days = Map.get(params, "days_ahead", 7)

    case CalendarService.get_upcoming_events(user, days) do
      {:ok, events} ->
        if Enum.empty?(events) do
          "No calendar events found in the next #{days} days."
        else
          event_list =
            events
            |> Enum.take(10)
            |> Enum.map(fn event ->
              start_time = format_datetime(event.start_time)
              "Event: #{event.title || "Untitled"} on #{start_time}"
            end)
            |> Enum.join("\n")

          "Found #{length(events)} calendar events in the next #{days} days:\n#{event_list}"
        end

      {:error, reason} ->
        "Error getting calendar availability: #{inspect(reason)}"
    end
  end

  defp execute_tool(
         user,
         "send_email",
         %{"to" => to, "subject" => subject, "body" => body},
         _id,
         _conversation
       ) do
    case GmailService.send_email(user, to, subject, body) do
      {:ok, _} ->
        "Email sent successfully to #{to} with subject: #{subject}"

      {:error, reason} ->
        "Error sending email: #{inspect(reason)}"
    end
  end

  defp execute_tool(user, "schedule_appointment", params, _id, conversation) do
    # Extract parameters
    contact_name = params["contact_name"] || ""
    contact_email = params["contact_email"]
    # Use default title if not provided
    title = params["title"] || "Meeting with #{contact_name}"
    description = params["description"] || ""
    duration_hours = params["duration_hours"] || 1

    # Find contact if email not provided
    contact_email =
      if contact_email do
        contact_email
      else
        # Search for contact by name
        case HubspotService.search_contacts(user, contact_name) do
          {:ok, [contact | _]} ->
            contact["properties"]["email"] || contact["properties"]["Email"]

          _ ->
            nil
        end
      end

    if contact_email do
      # Create a task for scheduling appointment
      task_attrs = %{
        user_id: user.id,
        conversation_id: conversation && conversation.id,
        title: "Schedule appointment: #{title} with #{contact_name}",
        description: description,
        status: "pending",
        tool_calls: [
          %{
            "name" => "schedule_appointment",
            "input" => params
          }
        ],
        metadata: %{
          type: "schedule_appointment",
          contact_name: contact_name,
          contact_email: contact_email,
          title: title,
          description: description,
          duration_hours: duration_hours
        }
      }

      case Task.changeset(%Task{}, task_attrs) |> Repo.insert() do
        {:ok, _task} ->
          # Process the task immediately to send the email
          # This will trigger the workflow: send email → wait for response → create event
          TaskProcessor.process_pending_tasks()

          "Appointment scheduling task created. I've sent an email to #{contact_email} with available times. I'll create the calendar event once they respond with their preferred time."

        {:error, changeset} ->
          "Error creating scheduling task: #{inspect(changeset.errors)}"
      end
    else
      "Could not find contact '#{contact_name}'. Please provide an email address or ensure the contact exists in HubSpot."
    end
  end

  defp execute_tool(user, "create_calendar_event", params, _id, _conversation) do
    with {:ok, start_dt, _} <- DateTime.from_iso8601(params["start_time"]),
         {:ok, end_dt, _} <- DateTime.from_iso8601(params["end_time"]) do
      # Validate dates are in the future
      now = DateTime.utc_now()

      if DateTime.compare(start_dt, now) == :lt do
        "Error: Cannot create events in the past. Start time must be in the future."
      else
        case CalendarService.create_event(
               user,
               params["title"],
               Map.get(params, "description", ""),
               start_dt,
               end_dt,
               Map.get(params, "attendees", [])
             ) do
          {:ok, _event} ->
            "Calendar event created successfully: #{params["title"]} on #{params["start_time"]}"

          {:error, reason} ->
            "Error creating calendar event: #{inspect(reason)}"
        end
      end
    else
      {:error, reason} ->
        "Invalid datetime format: #{inspect(reason)}. Please use ISO8601 format (YYYY-MM-DDTHH:MM:SSZ)"
    end
  end

  defp execute_tool(user, "update_calendar_event", params, _id, _conversation) do
    # Find the event by event_id or title
    event_result =
      cond do
        params["event_id"] && params["event_id"] != "" ->
          CalendarService.find_event_by_google_id(user, params["event_id"])

        params["title"] && params["title"] != "" ->
          date =
            if params["date"] do
              case Date.from_iso8601(params["date"]) do
                {:ok, date} -> date
                _ -> nil
              end
            else
              nil
            end

          CalendarService.find_event_by_title(user, params["title"], date)

        true ->
          {:error, "Either event_id or title must be provided to update an event"}
      end

    case event_result do
      {:ok, event} ->
        # Build update payload
        updates = %{}

        updates =
          if params["new_title"] && params["new_title"] != "" do
            Map.put(updates, "summary", params["new_title"])
          else
            updates
          end

        updates =
          if params["description"] do
            Map.put(updates, "description", params["description"])
          else
            updates
          end

        updates =
          if params["start_time"] && params["start_time"] != "" do
            case DateTime.from_iso8601(params["start_time"]) do
              {:ok, start_dt, _} ->
                Map.put(updates, "start", %{"dateTime" => DateTime.to_iso8601(start_dt)})

              _ ->
                updates
            end
          else
            updates
          end

        updates =
          if params["end_time"] && params["end_time"] != "" do
            case DateTime.from_iso8601(params["end_time"]) do
              {:ok, end_dt, _} ->
                Map.put(updates, "end", %{"dateTime" => DateTime.to_iso8601(end_dt)})

              _ ->
                updates
            end
          else
            updates
          end

        updates =
          if params["attendees"] && is_list(params["attendees"]) do
            Map.put(updates, "attendees", Enum.map(params["attendees"], &%{"email" => &1}))
          else
            updates
          end

        if map_size(updates) == 0 do
          "No updates provided. Please specify at least one field to update (new_title, description, start_time, end_time, or attendees)."
        else
          case CalendarService.update_event(user, event.google_event_id, updates) do
            {:ok, updated_event} ->
              summary = updated_event["summary"] || event.title
              "Calendar event updated successfully: #{summary}"

            {:error, reason} ->
              "Error updating calendar event: #{inspect(reason)}"
          end
        end

      {:error, reason} ->
        "Error finding calendar event: #{inspect(reason)}"
    end
  end

  defp execute_tool(user, "create_hubspot_contact", params, _id, _conversation) do
    case HubspotService.create_contact(
           user,
           params["email"],
           params["first_name"],
           params["last_name"],
           Map.get(params, "phone")
         ) do
      {:ok, contact} ->
        contact_id = contact["id"] || "unknown"
        "Contact created successfully in HubSpot: #{params["first_name"]} #{params["last_name"]} (ID: #{contact_id})"

      {:error, reason} ->
        "Error creating HubSpot contact: #{inspect(reason)}"
    end
  end

  defp execute_tool(
         user,
         "add_contact_note",
         params,
         _id,
         _conversation
       ) do
    note = params["note"]
    contact_id = Map.get(params, "contact_id")
    email = Map.get(params, "email")

    cond do
      # If email is provided, use the email-based function
      email && email != "" ->
        case HubspotService.add_note_by_email(user, email, note) do
          {:ok, result} ->
            note_id = result["engagement"] && result["engagement"]["id"] || "unknown"
            "Note added successfully to contact with email #{email} (Note ID: #{note_id})"

          {:error, reason} ->
            "Error adding note to contact with email #{email}: #{inspect(reason)}"
        end

      # If contact_id is provided, use it directly
      contact_id && contact_id != "" ->
        case HubspotService.add_note_to_contact(user, contact_id, note) do
          {:ok, result} ->
            note_id = result["engagement"] && result["engagement"]["id"] || "unknown"
            "Note added successfully to contact #{contact_id} (Note ID: #{note_id})"

          {:error, reason} ->
            "Error adding note to contact #{contact_id}: #{inspect(reason)}"
        end

      # Neither provided
      true ->
        "Error: Either contact_id or email must be provided to add a note"
    end
  end

  defp execute_tool(user, "save_ongoing_instruction", params, _id, _conversation) do
    case OngoingInstruction.changeset(%OngoingInstruction{}, %{
           user_id: user.id,
           instruction: params["instruction"],
           trigger_type: Map.get(params, "trigger_type", "manual"),
           status: "active"
         })
         |> Repo.insert() do
      {:ok, _instruction} ->
        "Ongoing instruction saved successfully. I'll remember this for future interactions."

      {:error, changeset} ->
        "Error saving instruction: #{inspect(Ecto.Changeset.traverse_errors(changeset, & &1))}"
    end
  end

  defp execute_tool(user, "get_ongoing_instructions", _params, _id, _conversation) do
    instructions = get_active_instructions(user.id)

    if Enum.empty?(instructions) do
      "No active ongoing instructions."
    else
      instructions
      |> Enum.map(fn inst ->
        "- #{inst.instruction} (Trigger: #{inst.trigger_type})"
      end)
      |> Enum.join("\n")
    end
  end

  defp execute_tool(user, "get_contact_context", %{"email" => email}, _id, _conversation) do
    # Search for contact by email
    case HubspotService.search_contacts(user, email) do
      {:ok, []} ->
        "No contact found with email: #{email}"

      {:ok, [contact | _]} ->
        contact_id = contact["id"]
        props = contact["properties"] || %{}

        # Get recent emails with this contact
        recent_emails =
          from(e in Email,
            where: e.user_id == ^user.id,
            where: e.from == ^email or fragment("? = ANY(?)", ^email, e.to),
            order_by: [desc: e.received_at],
            limit: 5
          )
          |> Repo.all()

        # Build context string
        contact_info = """
        Contact Information:
        - Name: #{props["firstname"] || ""} #{props["lastname"] || ""}
        - Email: #{props["email"] || email}
        - Phone: #{props["phone"] || "Not provided"}
        - HubSpot ID: #{contact_id}
        """

        email_context =
          if Enum.empty?(recent_emails) do
            "\nNo recent emails found with this contact."
          else
            email_list =
              recent_emails
              |> Enum.map(fn e ->
                "  - #{e.subject || "No subject"} (#{format_date(e.received_at)})"
              end)
              |> Enum.join("\n")

            "\nRecent Emails (#{length(recent_emails)}):\n#{email_list}"
          end

        contact_info <> email_context

      {:error, reason} ->
        "Error getting contact context: #{inspect(reason)}"
    end
  end

  defp execute_tool(_user, tool_name, _params, _id, _conversation) do
    "Unknown tool: #{tool_name}. Available tools: #{available_tools() |> Enum.map(& &1.name) |> Enum.join(", ")}"
  end

  defp save_message_to_conversation(conversation, role, content) do
    updated_messages = (conversation.messages || []) ++ [%{"role" => role, "content" => content}]

    conversation
    |> Conversation.changeset(%{messages: updated_messages})
    |> Repo.update()
  end

  defp format_date(nil), do: "Unknown date"
  defp format_date(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_date(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_date(_), do: "Unknown date"

  defp format_datetime(%DateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  defp format_datetime(%NaiveDateTime{} = dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M")
  defp format_datetime(_), do: "Unknown time"
end
