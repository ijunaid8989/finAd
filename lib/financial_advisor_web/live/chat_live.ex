defmodule FinancialAdvisorWeb.ChatLive do
  use FinancialAdvisorWeb, :live_view
  require Logger
  alias FinancialAdvisor.Services.AIAgent
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Conversation
  alias FinancialAdvisorWeb.Layouts
  import Ecto.Query

  def mount(params, session, socket) do
    user = session["current_user"]

    unless user do
      {:ok, redirect(socket, to: ~p"/login")}
    else
      conversation_id = params["id"] || session["conversation_id"]

      conversation =
        if conversation_id do
          Repo.get(Conversation, conversation_id) ||
            Conversation.changeset(%Conversation{}, %{user_id: user.id})
            |> Repo.insert!()
        else
          Conversation.changeset(%Conversation{}, %{user_id: user.id})
          |> Repo.insert!()
        end

      # If we created a new conversation and we're not already on its URL, redirect
      socket =
        if is_nil(conversation_id) or params["id"] != "#{conversation.id}" do
          redirect(socket, to: ~p"/chat/#{conversation.id}")
        else
          socket
        end

      # Get all conversations for history tab
      conversations =
        from(c in Conversation,
          where: c.user_id == ^user.id,
          order_by: [desc: c.updated_at],
          limit: 20
        )
        |> Repo.all()

      {:ok,
       socket
       |> assign(
         user: user,
         conversation: conversation,
         conversations: conversations,
         input: "",
         messages: conversation.messages || [],
         loading: false,
         chat_task: nil,
         active_tab: "chat"
       )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-white">
        <!-- Mobile-First Header -->
        <div class="flex items-center justify-between p-4 border-b border-gray-200 bg-white">
          <h1 class="text-lg font-semibold text-gray-900">Ask Anything</h1>
          <div class="flex items-center gap-2">
            <button
              phx-click="new_conversation"
              class="px-3 py-1.5 text-sm font-medium text-blue-600 hover:bg-blue-50 rounded-lg"
            >
              + New thread
            </button>
            <a href="/settings" class="p-2 text-gray-400 hover:text-gray-600">
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
              </svg>
            </a>
          </div>
        </div>

        <!-- Tabs -->
        <div class="flex border-b border-gray-200 bg-white">
          <button
            phx-click="switch_tab"
            phx-value-tab="chat"
            class={[
              "flex-1 px-4 py-3 text-sm font-medium border-b-2 transition-colors",
              @active_tab == "chat" && "border-blue-600 text-blue-600",
              @active_tab != "chat" && "border-transparent text-gray-500 hover:text-gray-700"
            ]}
          >
            Chat
          </button>
          <button
            phx-click="switch_tab"
            phx-value-tab="history"
            class={[
              "flex-1 px-4 py-3 text-sm font-medium border-b-2 transition-colors",
              @active_tab == "history" && "border-blue-600 text-blue-600",
              @active_tab != "history" && "border-transparent text-gray-500 hover:text-gray-700"
            ]}
          >
            History
          </button>
        </div>

        <!-- Context Indicator -->
        <%= if @active_tab == "chat" do %>
          <div class="px-4 py-2 bg-gray-50 border-b border-gray-200">
            <p class="text-xs text-gray-500">
              Context set to all meetings • <%= format_context_time() %>
            </p>
          </div>
        <% end %>

        <!-- Content Area -->
        <div class="flex-1 overflow-y-auto bg-white">
          <%= if @active_tab == "chat" do %>
            <!-- Chat View -->
            <div class="p-4 space-y-4" id="messages-container">
              <%= for {message, idx} <- Enum.with_index(@messages) do %>
                <div class={[
                  "flex gap-3",
                  message["role"] == "user" && "flex-row-reverse"
                ]}>
                  <!-- Avatar -->
                  <div class={[
                    "w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 text-sm font-medium text-white",
                    message["role"] == "user" && "bg-blue-600",
                    message["role"] != "user" && "bg-gray-400"
                  ]}>
                    <%= if message["role"] == "user", do: get_user_initials(@user.email), else: "AI" %>
                  </div>

                  <!-- Message Content -->
                  <div class={[
                    "flex-1 max-w-[85%]",
                    message["role"] == "user" && "flex flex-col items-end"
                  ]}>
                    <div class={[
                      "px-4 py-2 rounded-2xl",
                      message["role"] == "user" && "bg-blue-600 text-white",
                      message["role"] != "user" && "bg-gray-100 text-gray-900"
                    ]}>
                      <%= render_message_content(message["content"]) %>
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if @loading do %>
                <div class="flex gap-3">
                  <div class="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 bg-gray-400 text-white text-sm font-medium">
                    AI
                  </div>
                  <div class="bg-gray-100 px-4 py-2 rounded-2xl">
                    <div class="flex gap-1">
                      <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"></div>
                      <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.1s"></div>
                      <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce" style="animation-delay: 0.2s"></div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>
          <% else %>
            <!-- History View -->
            <div class="p-4 space-y-2">
              <%= if Enum.empty?(@conversations) do %>
                <div class="text-center py-12">
                  <p class="text-gray-500">No conversation history yet</p>
                  <button
                    phx-click="new_conversation"
                    class="mt-4 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700"
                  >
                    Start a conversation
                  </button>
                </div>
              <% else %>
                <%= for conversation <- @conversations do %>
                  <button
                    phx-click="select_conversation"
                    phx-value-conversation-id={conversation.id}
                    class="w-full text-left block p-3 rounded-lg hover:bg-gray-50 border border-gray-200 transition-colors"
                  >
                    <div class="flex items-center justify-between">
                      <div class="flex-1 min-w-0">
                        <p class="text-sm font-medium text-gray-900 truncate">
                          <%= conversation.title || "Untitled Conversation" %>
                        </p>
                        <%= if List.first(conversation.messages || []) do %>
                          <p class="text-xs text-gray-500 truncate mt-1">
                            <%= List.first(conversation.messages)["content"] |> String.slice(0, 60) %>
                          </p>
                        <% end %>
                      </div>
                      <p class="text-xs text-gray-400 ml-2">
                        <%= format_relative_time(conversation.updated_at) %>
                      </p>
                    </div>
                  </button>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>

        <!-- Input Area -->
        <%= if @active_tab == "chat" do %>
          <div class="border-t border-gray-200 bg-white p-4">
            <form phx-submit="send_message" class="flex gap-2">
              <input
                type="text"
                name="message"
                value={@input}
                phx-change="update_input"
                placeholder="Ask anything about your meetings..."
                disabled={@loading}
                class="flex-1 px-4 py-3 bg-gray-50 border border-gray-200 rounded-full text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:opacity-50"
              />
              <button
                type="submit"
                disabled={@loading or @input == ""}
                class={[
                  "px-4 py-3 rounded-full font-medium transition-colors disabled:opacity-50",
                  (@loading or @input == "") && "bg-gray-200 text-gray-400 cursor-not-allowed",
                  !(@loading or @input == "") && "bg-blue-600 hover:bg-blue-700 text-white"
                ]}
              >
                <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 19l9 2-9-18-9 18 9-2zm0 0v-8" />
                </svg>
              </button>
            </form>
            <div class="flex items-center justify-between mt-2 px-2">
              <div class="flex items-center gap-2 text-xs text-gray-500">
                <span>All meetings</span>
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" />
                </svg>
              </div>
              <div class="flex items-center gap-2">
                <button class="p-1.5 text-gray-400 hover:text-gray-600">
                  <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                    <path d="M10 12a2 2 0 100-4 2 2 0 000 4z" />
                  </svg>
                </button>
                <button class="p-1.5 text-gray-400 hover:text-gray-600">
                  <svg class="w-4 h-4" fill="currentColor" viewBox="0 0 20 20">
                    <path fill-rule="evenodd" d="M7 4a3 3 0 016 0v4a3 3 0 11-6 0V4zm4 10.93A7.001 7.001 0 0017 8a1 1 0 10-2 0A5 5 0 015 8a1 1 0 00-2 0 7.001 7.001 0 006 6.93V17H6a1 1 0 100 2h8a1 1 0 100-2h-3v-2.07z" clip-rule="evenodd" />
                  </svg>
                </button>
              </div>
            </div>
          </div>
        <% end %>
    </div>

    <script>
      const container = document.getElementById('messages-container');
      if (container) container.scrollTop = container.scrollHeight;
    </script>

    <Layouts.flash_group flash={@flash} />
    """
  end

  # Helper to render message content (with meeting cards if detected)
  defp render_message_content(content) when is_binary(content) do
    # Check if content mentions meetings/events and render cards
    if String.contains?(String.downcase(content), "meeting") or
         String.contains?(String.downcase(content), "event") or
         String.contains?(String.downcase(content), "calendar") do
      # Try to extract meeting info and render cards
      render_with_meeting_cards(content)
    else
      content
    end
  end

  defp render_message_content(content), do: to_string(content)

  defp render_with_meeting_cards(content) do
    # Simple implementation - in production, parse content more intelligently
    # For now, just render the content
    content
  end

  # Get user initials for avatar
  defp get_user_initials(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.slice(0, 2)
    |> String.upcase()
  end

  # Format context time
  defp format_context_time do
    now = DateTime.utc_now()
    Calendar.strftime(now, "%I:%M%p - %B %d, %Y")
  end

  # Format relative time
  defp format_relative_time(%DateTime{} = datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    format_diff(diff_seconds, datetime)
  end

  defp format_relative_time(%NaiveDateTime{} = naive_datetime) do
    # Convert NaiveDateTime to DateTime (assuming UTC)
    datetime = DateTime.from_naive!(naive_datetime, "Etc/UTC")
    format_relative_time(datetime)
  end

  defp format_relative_time(_), do: "Unknown"

  defp format_diff(diff_seconds, datetime) do

    cond do
      diff_seconds < 60 -> "Just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604800 -> "#{div(diff_seconds, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d, %Y")
    end
  end

  def handle_event("send_message", %{"message" => message}, socket) do
    input = String.trim(message)

    if input == "" or socket.assigns.loading do
      {:noreply, socket}
    else
      {:noreply,
       socket
       |> assign(input: "", loading: true)
       |> stream_response(input)}
    end
  end

  def handle_event("update_input", %{"message" => message}, socket) do
    {:noreply, assign(socket, input: message)}
  end

  def handle_event("update_input", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    # Refresh conversations when switching to history
    conversations =
      if tab == "history" do
        from(c in Conversation,
          where: c.user_id == ^socket.assigns.user.id,
          order_by: [desc: c.updated_at],
          limit: 20
        )
        |> Repo.all()
      else
        socket.assigns.conversations || []
      end

    {:noreply, assign(socket, active_tab: tab, conversations: conversations)}
  end

  def handle_event("select_conversation", %{"conversation-id" => conversation_id}, socket) do
    conversation = Repo.get(Conversation, conversation_id)

    if conversation && conversation.user_id == socket.assigns.user.id do
      {:noreply,
       socket
       |> assign(
         conversation: conversation,
         messages: conversation.messages || [],
         active_tab: "chat"
       )
       |> push_navigate(to: ~p"/chat/#{conversation.id}")}
    else
      {:noreply, socket |> put_flash(:error, "Conversation not found")}
    end
  end

  def handle_event("new_conversation", _params, socket) do
    conversation =
      Conversation.changeset(%Conversation{}, %{user_id: socket.assigns.user.id})
      |> Repo.insert!()

    # Refresh conversations list
    conversations =
      from(c in Conversation,
        where: c.user_id == ^socket.assigns.user.id,
        order_by: [desc: c.updated_at],
        limit: 20
      )
      |> Repo.all()

    {:noreply,
     socket
     |> assign(conversation: conversation, messages: [], input: "", conversations: conversations, active_tab: "chat")
     |> push_navigate(to: ~p"/chat/#{conversation.id}")}
  end

  def handle_event("sync_emails", _params, socket) do
    user = socket.assigns.user

    if user.google_access_token do
      Task.async(fn ->
        case FinancialAdvisor.Services.GmailService.sync_emails(user, 100) do
          count when is_integer(count) ->
            # After syncing emails, check for task responses
            FinancialAdvisor.Services.EmailMonitorService.check_for_task_responses(user.id)
            send(self(), {:sync_complete, :emails, {:ok, "Synced #{count} emails and checked for task responses"}})

          {:error, reason} ->
            send(self(), {:sync_complete, :emails, {:error, "Failed to sync: #{inspect(reason)}"}})
        end
      end)

      {:noreply, socket |> put_flash(:info, "Syncing emails...")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please connect your Google account in Settings first")}
    end
  end

  def handle_event("sync_calendar", _params, socket) do
    user = socket.assigns.user

    if user.google_access_token do
      Task.async(fn ->
        case FinancialAdvisor.Services.CalendarService.sync_events(user) do
          count when is_integer(count) ->
            send(self(), {:sync_complete, :calendar, {:ok, "Synced #{count} calendar events"}})

          {:error, reason} ->
            send(self(), {:sync_complete, :calendar, {:error, "Failed to sync: #{inspect(reason)}"}})
        end
      end)

      {:noreply, socket |> put_flash(:info, "Syncing calendar...")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please connect your Google account in Settings first")}
    end
  end

  def handle_event("sync_contacts", _params, socket) do
    user = socket.assigns.user

    if user.hubspot_access_token do
      Task.async(fn ->
        case FinancialAdvisor.Services.HubspotService.sync_contacts(user, 100) do
          count when is_integer(count) ->
            send(self(), {:sync_complete, :contacts, {:ok, "Synced #{count} contacts"}})

          {:error, reason} ->
            send(self(), {:sync_complete, :contacts, {:error, "Failed to sync: #{inspect(reason)}"}})
        end
      end)

      {:noreply, socket |> put_flash(:info, "Syncing contacts...")}
    else
      {:noreply,
       socket
       |> put_flash(:error, "Please connect your HubSpot account in Settings first")}
    end
  end

  defp stream_response(socket, user_message) do
    user = socket.assigns.user
    conversation = socket.assigns.conversation

    updated_messages =
      (socket.assigns.messages || []) ++
        [
          %{"role" => "user", "content" => user_message}
        ]

    socket = assign(socket, messages: updated_messages)

    Conversation.changeset(conversation, %{messages: updated_messages})
    |> Repo.update()

    # Use Task.async instead of Task.start_link to avoid crashing LiveView
    task =
      Task.async(fn ->
        try do
          case AIAgent.chat(user, user_message, conversation.id) do
            {:ok, response, tool_results} ->
              {:ok, response, tool_results}

            {:ok, response} ->
              {:ok, response, []}

            {:error, reason} ->
              Logger.error("AI chat error: #{inspect(reason)}")
              {:error, inspect(reason)}
          end
        rescue
          e ->
            Logger.error("AI chat exception: #{inspect(e)}")
            {:error, Exception.message(e)}
        catch
          :exit, reason ->
            Logger.error("AI chat exit: #{inspect(reason)}")
            {:error, "Task exited: #{inspect(reason)}"}
        end
      end)

    socket
    |> assign(chat_task: task.ref)
  end

  # Handle sync completion messages
  def handle_info({:sync_complete, :emails, {:ok, message}}, socket) do
    {:noreply, socket |> put_flash(:info, message)}
  end

  def handle_info({:sync_complete, :emails, {:error, message}}, socket) do
    {:noreply, socket |> put_flash(:error, message)}
  end

  def handle_info({:sync_complete, :calendar, {:ok, message}}, socket) do
    {:noreply, socket |> put_flash(:info, message)}
  end

  def handle_info({:sync_complete, :calendar, {:error, message}}, socket) do
    {:noreply, socket |> put_flash(:error, message)}
  end

  def handle_info({:sync_complete, :contacts, {:ok, message}}, socket) do
    {:noreply, socket |> put_flash(:info, message)}
  end

  def handle_info({:sync_complete, :contacts, {:error, message}}, socket) do
    {:noreply, socket |> put_flash(:error, message)}
  end

  def handle_info({ref, result}, socket) when is_reference(ref) do
    # Task completed - only handle if it's our chat task
    if socket.assigns[:chat_task] == ref do
      case result do
        {:ok, response, tool_results} ->
          handle_info({:ai_response, response, tool_results}, socket |> assign(:chat_task, nil))

        {:error, error} ->
          handle_info({:ai_error, error}, socket |> assign(:chat_task, nil))
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, socket) do
    # Task crashed or exited
    if socket.assigns[:chat_task] == ref do
      error_message = "The AI service encountered an error. Please try again."
      Logger.error("Chat task crashed: #{inspect(reason)}")

      updated_messages =
        (socket.assigns.messages || []) ++
          [
            %{"role" => "assistant", "content" => error_message}
          ]

      {:noreply,
       socket
       |> assign(messages: updated_messages, loading: false)
       |> assign(:chat_task, nil)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:ai_response, response, tool_results}, socket) do
    tool_results_text =
      tool_results
      |> Enum.map(fn result -> "Tool result: #{result}" end)
      |> Enum.join("\n\n")

    full_response =
      if tool_results_text != "" do
        "#{response}\n\n#{tool_results_text}"
      else
        response
      end

    updated_messages =
      (socket.assigns.messages || []) ++
        [
          %{"role" => "assistant", "content" => full_response}
        ]

    Conversation.changeset(socket.assigns.conversation, %{messages: updated_messages})
    |> Repo.update()

    {:noreply,
     socket
     |> assign(messages: updated_messages, loading: false, chat_task: nil)}
  end

  def handle_info({:ai_error, error}, socket) do
    error_message = "Sorry, there was an error: #{error}"

    updated_messages =
      (socket.assigns.messages || []) ++
        [
          %{"role" => "assistant", "content" => error_message}
        ]

    {:noreply,
     socket
     |> assign(messages: updated_messages, loading: false, chat_task: nil)}
  end
end
