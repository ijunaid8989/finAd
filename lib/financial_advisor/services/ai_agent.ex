defmodule FinancialAdvisor.Services.AIAgent do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User
  alias FinancialAdvisor.Conversation
  alias FinancialAdvisor.Task
  alias FinancialAdvisor.OngoingInstruction

  alias FinancialAdvisor.Services.{
    RAGService,
    GmailService,
    CalendarService,
    HubspotService,
    SearchHelper,
    TaskManager
  }

  import Ecto.Query

  @claude_api_url "https://api.anthropic.com/v1/messages"
  @model "claude-3-5-sonnet-20241022"

  def config do
    %{
      api_key: System.get_env("CLAUDE_API_KEY")
    }
  end

  def available_tools do
    [
      %{
        name: "search_emails",
        description: "Search through user emails for specific information",
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
        description: "Get available time slots in the user's calendar",
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
        description: "Send an email to a recipient",
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
        name: "create_calendar_event",
        description:
          "Create a calendar event. IMPORTANT: Use ISO8601 format for times. Examples: 2025-10-21T14:00:00Z (next Tuesday 2PM UTC), 2025-10-22T21:00:00Z (next Wednesday 9PM UTC)",
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
        description: "Add a note to a HubSpot contact",
        input_schema: %{
          type: "object",
          properties: %{
            contact_id: %{
              type: "string",
              description: "HubSpot contact ID"
            },
            note: %{
              type: "string",
              description: "Note content"
            }
          },
          required: ["contact_id", "note"]
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
                "When to trigger this instruction (e.g., 'email_received', 'contact_created')"
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
        description: "Get detailed context about a contact including recent emails and notes",
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
      call_claude(user, messages, conversation)
    end
  end

  defp get_or_create_conversation(user, nil) do
    Conversation.changeset(%Conversation{}, %{user_id: user.id})
    |> Repo.insert!()
  end

  defp get_or_create_conversation(_user, conversation_id) do
    Repo.get!(Conversation, conversation_id)
  end

  defp build_message_history(conversation, user_message, rag_context, instructions) do
    # Get current date/time information for Claude
    now = DateTime.utc_now()
    current_date = DateTime.to_date(now)
    current_day_name = Calendar.strftime(now, "%A")

    # Calculate all weekdays for reference
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
          role: msg["role"],
          content: msg["content"]
        }
      end)

    (previous_messages ++
       [
         %{
           role: "user",
           content: user_message
         }
       ])
    |> (&([%{role: "user", content: system_prompt}] ++ &1)).()
  end

  defp format_instructions(instructions) do
    instructions
    |> Enum.map(&"- #{&1.instruction} (Trigger: #{&1.trigger_type})")
    |> Enum.join("\n")
  end

  defp calculate_weekday_dates(reference_date) do
    current_day = Date.day_of_week(reference_date)

    # Calculate days until each weekday (1=Monday, 7=Sunday)
    days_map = %{
      1 =>
        if(current_day > 1,
          do: 8 - current_day + 1,
          else: if(current_day == 1, do: 7, else: 1 - current_day)
        ),
      2 =>
        if(current_day > 2,
          do: 9 - current_day,
          else: if(current_day == 2, do: 7, else: 2 - current_day)
        ),
      3 =>
        if(current_day > 3,
          do: 10 - current_day,
          else: if(current_day == 3, do: 7, else: 3 - current_day)
        ),
      4 =>
        if(current_day > 4,
          do: 11 - current_day,
          else: if(current_day == 4, do: 7, else: 4 - current_day)
        ),
      5 =>
        if(current_day > 5,
          do: 12 - current_day,
          else: if(current_day == 5, do: 7, else: 5 - current_day)
        ),
      6 =>
        if(current_day > 6,
          do: 13 - current_day,
          else: if(current_day == 6, do: 7, else: 6 - current_day)
        ),
      7 =>
        if(current_day > 7,
          do: 14 - current_day,
          else: if(current_day == 7, do: 7, else: 7 - current_day)
        )
    }

    %{
      monday: Date.add(reference_date, Map.get(days_map, 1)),
      tuesday: Date.add(reference_date, Map.get(days_map, 2)),
      wednesday: Date.add(reference_date, Map.get(days_map, 3)),
      thursday: Date.add(reference_date, Map.get(days_map, 4)),
      friday: Date.add(reference_date, Map.get(days_map, 5)),
      saturday: Date.add(reference_date, Map.get(days_map, 6)),
      sunday: Date.add(reference_date, Map.get(days_map, 7))
    }
  end

  defp get_active_instructions(user_id) do
    OngoingInstruction
    |> where([oi], oi.user_id == ^user_id and oi.status == "active")
    |> Repo.all()
  end

  defp call_claude(user, messages, conversation) do
    headers = [
      {"Content-Type", "application/json"},
      {"x-api-key", config().api_key},
      {"anthropic-version", "2023-06-01"}
    ]

    body =
      Jason.encode!(%{
        model: @model,
        max_tokens: 2048,
        system:
          "You are a helpful AI assistant for financial advisors. Use the provided tools to help users manage their contacts and schedule. Pay attention to date/time context provided by the system.",
        messages: messages,
        tools: available_tools()
      })

    case HTTPoison.post(@claude_api_url, body, headers) do
      {:ok, response} ->
        handle_claude_response(user, response, conversation, messages)

      {:error, reason} ->
        Logger.error("Claude API error: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_claude_response(user, response, conversation, messages) do
    case Jason.decode(response.body) do
      {:ok, data} ->
        content = data["content"] || []

        {tool_calls, text_response} = process_content_blocks(content, user)

        # Store message in conversation
        updated_messages = [
          %{role: "assistant", content: text_response}
        ]

        conversation
        |> Conversation.changeset(%{
          messages: (conversation.messages || []) ++ updated_messages
        })
        |> Repo.update()

        # If there were tool calls, execute them
        if tool_calls != [] do
          results = execute_tools(user, tool_calls, conversation)
          {:ok, text_response, results}
        else
          {:ok, text_response}
        end

      {:error, reason} ->
        Logger.error("Failed to parse Claude response: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp process_content_blocks(content, user) do
    Enum.reduce(content, {[], ""}, fn block, {tool_calls, text} ->
      case block do
        %{"type" => "text", "text" => text_content} ->
          {tool_calls, text <> text_content}

        %{"type" => "tool_use", "name" => name, "input" => input, "id" => id} ->
          {tool_calls ++ [{name, input, id}], text}

        _ ->
          {tool_calls, text}
      end
    end)
  end

  defp execute_tools(user, tool_calls, conversation) do
    tool_calls
    |> Enum.map(fn {name, input, id} ->
      execute_tool(user, name, input, id, conversation)
    end)
  end

  defp execute_tool(user, "search_emails", %{"query" => query}, _id, _conversation) do
    case RAGService.search_emails(user.id, query) do
      {:ok, results} ->
        format_search_results(results)

      {:error, reason} ->
        "Error searching emails: #{inspect(reason)}"
    end
  end

  defp execute_tool(user, "search_contacts", %{"query" => query}, _id, _conversation) do
    case HubspotService.search_contacts(user, query) do
      {:ok, results} ->
        format_contact_results(results)

      {:error, reason} ->
        "Error searching contacts: #{inspect(reason)}"
    end
  end

  defp execute_tool(user, "get_contact_context", %{"email" => email}, _id, _conversation) do
    SearchHelper.get_contact_context(user.id, email)
  end

  defp execute_tool(user, "get_calendar_availability", params, _id, _conversation) do
    days = Map.get(params, "days_ahead", 7)

    case CalendarService.sync_events(user) do
      count when is_integer(count) ->
        "Found #{count} calendar events in the next #{days} days"

      {:error, reason} ->
        "Error getting calendar: #{inspect(reason)}"
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
        "Email sent successfully to #{to}"

      {:error, reason} ->
        "Error sending email: #{inspect(reason)}"
    end
  end

  defp execute_tool(user, "create_calendar_event", params, _id, _conversation) do
    with {:ok, start_dt, _} <- DateTime.from_iso8601(params["start_time"]),
         {:ok, end_dt, _} <- DateTime.from_iso8601(params["end_time"]) do
      case CalendarService.create_event(
             user,
             params["title"],
             Map.get(params, "description", ""),
             start_dt,
             end_dt,
             Map.get(params, "attendees", [])
           ) do
        {:ok, event} ->
          "Calendar event created: #{params["title"]} on #{params["start_time"]}"

        {:error, reason} ->
          "Error creating event: #{inspect(reason)}"
      end
    else
      {:error, reason} ->
        "Invalid datetime format: #{inspect(reason)}"
    end
  end

  defp execute_tool(user, "create_hubspot_contact", params, _id, _conversation) do
    case HubspotService.create_contact(
           user,
           params["email"],
           params["first_name"],
           params["last_name"],
           Map.get(params, "phone")
         )
         |> IO.inspect() do
      {:ok, contact} ->
        "Contact created in HubSpot: #{params["first_name"]} #{params["last_name"]}"

      {:error, reason} ->
        "Error creating contact: #{inspect(reason)}"
    end
  end

  defp execute_tool(
         user,
         "add_contact_note",
         %{"contact_id" => contact_id, "note" => note},
         _id,
         _conversation
       ) do
    case HubspotService.add_note_to_contact(user, contact_id, note) do
      {:ok, _} ->
        "Note added to contact"

      {:error, reason} ->
        "Error adding note: #{inspect(reason)}"
    end
  end

  defp execute_tool(user, "save_ongoing_instruction", params, _id, _conversation) do
    OngoingInstruction.changeset(%OngoingInstruction{}, %{
      user_id: user.id,
      instruction: params["instruction"],
      trigger_type: Map.get(params, "trigger_type", "manual")
    })
    |> Repo.insert()

    "Ongoing instruction saved. I'll remember this for future interactions."
  end

  defp execute_tool(user, "get_ongoing_instructions", _params, _id, _conversation) do
    instructions = get_active_instructions(user.id)

    instructions
    |> Enum.map(&"- #{&1.instruction} (#{&1.trigger_type})")
    |> Enum.join("\n")
  end

  defp execute_tool(_user, tool_name, _params, _id, _conversation) do
    "Unknown tool: #{tool_name}"
  end

  defp format_search_results(results) do
    results
    |> Enum.map(fn %{email: email, similarity: similarity} ->
      "From: #{email.from}, Subject: #{email.subject}, Relevance: #{Float.round(similarity * 100, 1)}%"
    end)
    |> Enum.join("\n")
  end

  defp format_contact_results(results) do
    results
    |> Enum.map(fn contact ->
      "#{contact["properties"]["firstname"]} #{contact["properties"]["lastname"]} (#{contact["properties"]["email"]})"
    end)
    |> Enum.join("\n")
  end
end
