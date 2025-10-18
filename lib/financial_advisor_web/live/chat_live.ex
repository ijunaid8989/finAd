defmodule FinancialAdvisorWeb.ChatLive do
  use FinancialAdvisorWeb, :live_view
  require Logger
  alias FinancialAdvisor.Services.AIAgent
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Conversation

  def mount(_params, session, socket) do
    user = session["current_user"]

    unless user do
      {:ok, redirect(socket, to: ~p"/login")}
    else
      conversation_id = session["conversation_id"]

      conversation =
        if conversation_id do
          Repo.get!(Conversation, conversation_id)
        else
          Conversation.changeset(%Conversation{}, %{user_id: user.id})
          |> Repo.insert!()
        end

      {:ok,
       socket
       |> assign(
         user: user,
         conversation: conversation,
         input: "",
         messages: conversation.messages || [],
         loading: false
       )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-900">
      <!-- Sidebar -->
      <div class="w-64 bg-gray-800 border-r border-gray-700 flex flex-col">
        <div class="p-4 border-b border-gray-700">
          <h1 class="text-xl font-bold text-white">Financial Advisor AI</h1>
          <p class="text-sm text-gray-400">{@user.email}</p>
        </div>

        <div class="flex-1 overflow-y-auto p-4">
          <button
            phx-click="new_conversation"
            class="w-full mb-4 px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-lg"
          >
            + New Conversation
          </button>

          <div class="space-y-2">
            <p class="text-xs font-semibold text-gray-400 uppercase">Quick Actions</p>
            <button
              phx-click="sync_emails"
              class="w-full text-left px-3 py-2 text-gray-300 hover:bg-gray-700 rounded text-sm"
            >
              📧 Sync Emails
            </button>
            <button
              phx-click="sync_calendar"
              class="w-full text-left px-3 py-2 text-gray-300 hover:bg-gray-700 rounded text-sm"
            >
              📅 Sync Calendar
            </button>
            <button
              phx-click="sync_contacts"
              class="w-full text-left px-3 py-2 text-gray-300 hover:bg-gray-700 rounded text-sm"
            >
              👥 Sync Contacts
            </button>
          </div>
        </div>

        <div class="p-4 border-t border-gray-700">
          <a href="/settings" class="text-gray-400 hover:text-white text-sm">⚙️ Settings</a>
        </div>
      </div>

    <!-- Main Chat Area -->
      <div class="flex-1 flex flex-col bg-gray-900">
        <!-- Messages -->
        <div class="flex-1 overflow-y-auto p-6 space-y-4" id="messages-container">
          <%= for {message, _idx} <- Enum.with_index(@messages) do %>
            <div class={[
              "flex gap-3",
              message["role"] == "user" && "flex-row-reverse"
            ]}>
              <div class={[
                "w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0",
                message["role"] == "user" && "bg-blue-600",
                message["role"] != "user" && "bg-gray-700"
              ]}>
                <span class="text-white text-sm">
                  {if message["role"] == "user", do: "👤", else: "🤖"}
                </span>
              </div>

              <div class={[
                "max-w-2xl px-4 py-2 rounded-lg",
                message["role"] == "user" && "bg-blue-600 text-white",
                message["role"] != "user" && "bg-gray-800 text-gray-100"
              ]}>
                <p class="text-sm">{message["content"]}</p>
              </div>
            </div>
          <% end %>

          <%= if @loading do %>
            <div class="flex gap-3">
              <div class="w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 bg-gray-700">
                <span class="text-white text-sm">🤖</span>
              </div>
              <div class="bg-gray-800 text-gray-100 px-4 py-2 rounded-lg">
                <div class="flex gap-2">
                  <div class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"></div>
                  <div
                    class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"
                    style="animation-delay: 0.1s"
                  >
                  </div>
                  <div
                    class="w-2 h-2 bg-gray-400 rounded-full animate-bounce"
                    style="animation-delay: 0.2s"
                  >
                  </div>
                </div>
              </div>
            </div>
          <% end %>
        </div>

    <!-- Input Area -->
        <div class="border-t border-gray-700 p-4">
          <form phx-submit="send_message">
            <div class="flex gap-3">
              <input
                type="text"
                name="message"
                value={@input}
                phx-change="update_input"
                placeholder="Ask me anything about your clients..."
                class="flex-1 px-4 py-3 bg-gray-800 text-white rounded-lg border border-gray-700 focus:border-blue-500 focus:outline-none"
              />
              <button
                type="submit"
                disabled={@loading or @input == ""}
                class={[
                  "px-6 py-3 rounded-lg font-medium transition-colors",
                  (@loading or @input == "") && "bg-gray-600 text-gray-400 cursor-not-allowed",
                  !(@loading or @input == "") && "bg-blue-600 hover:bg-blue-700 text-white"
                ]}
              >
                Send
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>

    <script>
      const container = document.getElementById('messages-container');
      if (container) container.scrollTop = container.scrollHeight;
    </script>
    """
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

  def handle_event("new_conversation", _params, socket) do
    conversation =
      Conversation.changeset(%Conversation{}, %{user_id: socket.assigns.user.id})
      |> Repo.insert!()

    {:noreply,
     socket
     |> assign(conversation: conversation, messages: [], input: "")
     |> redirect(to: ~p"/chat/#{conversation.id}")}
  end

  def handle_event("sync_emails", _params, socket) do
    user = socket.assigns.user
    Task.start_link(fn -> FinancialAdvisor.Services.GmailService.sync_emails(user, 100) end)
    {:noreply, socket |> put_flash(:info, "Syncing emails...")}
  end

  def handle_event("sync_calendar", _params, socket) do
    user = socket.assigns.user
    Task.start_link(fn -> FinancialAdvisor.Services.CalendarService.sync_events(user) end)
    {:noreply, socket |> put_flash(:info, "Syncing calendar...")}
  end

  def handle_event("sync_contacts", _params, socket) do
    user = socket.assigns.user
    Task.start_link(fn -> FinancialAdvisor.Services.HubspotService.sync_contacts(user, 100) end)
    {:noreply, socket |> put_flash(:info, "Syncing contacts...")}
  end

  defp stream_response(socket, user_message) do
    user = socket.assigns.user
    conversation = socket.assigns.conversation
    lv_pid = self()

    updated_messages =
      (socket.assigns.messages || []) ++
        [
          %{"role" => "user", "content" => user_message}
        ]

    socket = assign(socket, messages: updated_messages)

    Conversation.changeset(conversation, %{messages: updated_messages})
    |> Repo.update()

    Task.start_link(fn ->
      case AIAgent.chat(user, user_message, conversation.id) do
        {:ok, response, _tool_results} ->
          send(lv_pid, {:ai_response, response})

        {:ok, response} ->
          send(lv_pid, {:ai_response, response})

        {:error, reason} ->
          Logger.error("AI chat error: #{inspect(reason)}")
          send(lv_pid, {:ai_error, inspect(reason)})
      end
    end)

    socket
  end

  def handle_info({:ai_response, response}, socket) do
    updated_messages =
      (socket.assigns.messages || []) ++
        [
          %{"role" => "assistant", "content" => response}
        ]

    Conversation.changeset(socket.assigns.conversation, %{messages: updated_messages})
    |> Repo.update()

    {:noreply,
     socket
     |> assign(messages: updated_messages, loading: false)}
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
     |> assign(messages: updated_messages, loading: false)}
  end
end
