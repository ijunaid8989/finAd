defmodule FinancialAdvisorWeb.SettingsLive do
  use FinancialAdvisorWeb, :live_view
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.OngoingInstruction
  import Ecto.Query

  def mount(_params, session, socket) do
    user = session["current_user"]

    unless user do
      {:ok, redirect(socket, to: ~p"/login")}
    else
      user = Repo.preload(user, :ongoing_instructions)

      {:ok,
       socket
       |> assign(
         user: user,
         instructions: user.ongoing_instructions,
         new_instruction: "",
         trigger_type: "manual"
       )}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex h-screen bg-gray-900">
      <!-- Sidebar -->
      <div class="w-64 bg-gray-800 border-r border-gray-700 p-4">
        <h1 class="text-xl font-bold text-white mb-6">Settings</h1>

        <nav class="space-y-2">
          <a href="/chat" class="block px-3 py-2 text-gray-300 hover:bg-gray-700 rounded">
            ← Back to Chat
          </a>
        </nav>
      </div>
      
    <!-- Main Content -->
      <div class="flex-1 overflow-y-auto p-8">
        <div class="max-w-2xl">
          <!-- Integrations -->
          <section class="mb-8">
            <h2 class="text-2xl font-bold text-white mb-6">Integrations</h2>

            <div class="space-y-4">
              <div class="bg-gray-800 p-4 rounded-lg">
                <div class="flex items-center justify-between">
                  <div>
                    <h3 class="font-semibold text-white">Google Account</h3>
                    <p class="text-sm text-gray-400">
                      <%= if @user.google_id do %>
                        Connected
                      <% else %>
                        Not connected
                      <% end %>
                    </p>
                  </div>

                  <%= if @user.google_id do %>
                    <button
                      phx-click="disconnect_google"
                      class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded text-sm"
                    >
                      Disconnect
                    </button>
                  <% else %>
                    <button
                      phx-click="connect_google"
                      class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded text-sm"
                    >
                      Connect
                    </button>
                  <% end %>
                </div>
              </div>

              <div class="bg-gray-800 p-4 rounded-lg">
                <div class="flex items-center justify-between">
                  <div>
                    <h3 class="font-semibold text-white">HubSpot Account</h3>
                    <p class="text-sm text-gray-400">
                      <%= if @user.hubspot_id do %>
                        Connected
                      <% else %>
                        Not connected
                      <% end %>
                    </p>
                  </div>

                  <%= if @user.hubspot_id do %>
                    <button
                      phx-click="disconnect_hubspot"
                      class="px-4 py-2 bg-red-600 hover:bg-red-700 text-white rounded text-sm"
                    >
                      Disconnect
                    </button>
                  <% else %>
                    <button
                      phx-click="connect_hubspot"
                      class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded text-sm"
                    >
                      Connect
                    </button>
                  <% end %>
                </div>
              </div>
            </div>
          </section>
          
    <!-- Ongoing Instructions -->
          <section>
            <h2 class="text-2xl font-bold text-white mb-6">Ongoing Instructions</h2>

            <div class="bg-gray-800 p-4 rounded-lg mb-6">
              <h3 class="font-semibold text-white mb-4">Add New Instruction</h3>

              <form phx-submit="add_instruction" class="space-y-4">
                <div>
                  <label class="block text-sm font-medium text-gray-300 mb-2">Instruction</label>
                  <textarea
                    name="instruction"
                    placeholder="e.g., When someone emails me that is not in HubSpot, create a contact..."
                    class="w-full px-3 py-2 bg-gray-700 text-white rounded border border-gray-600 focus:border-blue-500"
                    rows="3"
                  >
                  </textarea>
                </div>

                <div>
                  <label class="block text-sm font-medium text-gray-300 mb-2">Trigger Type</label>
                  <select
                    name="trigger_type"
                    class="w-full px-3 py-2 bg-gray-700 text-white rounded border border-gray-600 focus:border-blue-500"
                  >
                    <option value="email_received">Email Received</option>
                    <option value="contact_created">Contact Created</option>
                    <option value="calendar_event">Calendar Event</option>
                    <option value="manual">Manual</option>
                  </select>
                </div>

                <button
                  type="submit"
                  class="w-full px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded"
                >
                  Save Instruction
                </button>
              </form>
            </div>
            
    <!-- Instructions List -->
            <div class="space-y-4">
              <%= for instruction <- @instructions do %>
                <div class="bg-gray-800 p-4 rounded-lg">
                  <p class="text-white">{instruction.instruction}</p>
                  <p class="text-xs text-gray-400 mt-2">Trigger: {instruction.trigger_type}</p>

                  <button
                    phx-click="delete_instruction"
                    phx-value-id={instruction.id}
                    class="mt-3 text-sm text-red-400 hover:text-red-300"
                  >
                    Delete
                  </button>
                </div>
              <% end %>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  def handle_event("add_instruction", params, socket) do
    OngoingInstruction.changeset(%OngoingInstruction{}, %{
      user_id: socket.assigns.user.id,
      instruction: params["instruction"],
      trigger_type: params["trigger_type"]
    })
    |> Repo.insert()

    updated_instructions =
      OngoingInstruction
      |> where([oi], oi.user_id == ^socket.assigns.user.id)
      |> Repo.all()

    {:noreply, assign(socket, instructions: updated_instructions)}
  end

  def handle_event("delete_instruction", %{"id" => id}, socket) do
    Repo.get!(OngoingInstruction, id)
    |> Repo.delete()

    updated_instructions =
      OngoingInstruction
      |> where([oi], oi.user_id == ^socket.assigns.user.id)
      |> Repo.all()

    {:noreply, assign(socket, instructions: updated_instructions)}
  end

  def handle_event("connect_google", _params, socket) do
    url = google_auth_url()
    {:noreply, redirect(socket, external: url)}
  end

  def handle_event("connect_hubspot", _params, socket) do
    url = hubspot_auth_url()
    {:noreply, redirect(socket, external: url)}
  end

  def handle_event("disconnect_google", _params, socket) do
    user = socket.assigns.user

    user
    |> Ecto.Changeset.change(google_access_token: nil, google_refresh_token: nil, google_id: nil)
    |> Repo.update()

    {:noreply,
     socket |> put_flash(:info, "Google disconnected") |> assign(user: %{user | google_id: nil})}
  end

  def handle_event("disconnect_hubspot", _params, socket) do
    user = socket.assigns.user

    user
    |> Ecto.Changeset.change(hubspot_access_token: nil, hubspot_id: nil)
    |> Repo.update()

    {:noreply,
     socket |> put_flash(:info, "HubSpot disconnected") |> assign(user: %{user | hubspot_id: nil})}
  end

  defp google_auth_url do
    state = FinancialAdvisor.OAuth.StateManager.generate_state("google")
    FinancialAdvisor.OAuth.GoogleOAuth.auth_url(state)
  end

  defp hubspot_auth_url do
    state = FinancialAdvisor.OAuth.StateManager.generate_state("hubspot")
    FinancialAdvisor.OAuth.HubspotOAuth.auth_url(state)
  end
end
