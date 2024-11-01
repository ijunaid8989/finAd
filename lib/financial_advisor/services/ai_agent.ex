defmodule FinancialAdvisor.Services.AIAgent do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Conversation
  alias FinancialAdvisor.OngoingInstruction
  alias FinancialAdvisor.Email
  alias FinancialAdvisor.HubspotContact

  alias FinancialAdvisor.Services.{
    RAGService,
    GmailService,
    CalendarService,
    HubspotService
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

  defp call_claude(user, messages) do
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
         %{"contact_id" => contact_id, "note" => note},
         _id,
         _conversation
       ) do
    case HubspotService.add_note_to_contact(user, contact_id, note) do
      {:ok, _} ->
        "Note added successfully to contact #{contact_id}"

      {:error, reason} ->
        "Error adding note to contact: #{inspect(reason)}"
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
