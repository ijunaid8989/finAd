defmodule FinancialAdvisorWeb.AuthLive do
  use FinancialAdvisorWeb, :live_view
  alias FinancialAdvisor.OAuth.{GoogleOAuth, HubspotOAuth, StateManager}

  def mount(_params, session, socket) do
    user = session["current_user"]

    if user do
      {:ok, redirect(socket, to: ~p"/chat")}
    else
      {:ok, socket}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="flex items-center justify-center min-h-screen bg-gradient-to-br from-blue-600 to-blue-800">
      <div class="w-full max-w-md">
        <div class="bg-white rounded-lg shadow-lg p-8">
          <h1 class="text-3xl font-bold text-gray-900 mb-2">Financial Advisor AI</h1>
          <p class="text-gray-600 mb-6">Connect your accounts to get started</p>

          <div class="space-y-4">
            <a
              href={google_auth_url()}
              class="w-full flex items-center justify-center gap-2 px-4 py-3 bg-white text-gray-900 border border-gray-300 rounded-lg hover:bg-gray-50 font-medium transition"
            >
              <svg class="w-5 h-5" viewBox="0 0 24 24">
                <path
                  fill="currentColor"
                  d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
                />
                <path
                  fill="currentColor"
                  d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
                />
                <path
                  fill="currentColor"
                  d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
                />
                <path
                  fill="currentColor"
                  d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
                />
              </svg>
              Sign in with Google
            </a>

            <a
              href={hubspot_auth_url()}
              class="w-full flex items-center justify-center gap-2 px-4 py-3 bg-orange-500 text-white rounded-lg hover:bg-orange-600 font-medium transition"
            >
              <span>🔗</span> Connect HubSpot
            </a>
          </div>

          <div class="mt-6 pt-6 border-t border-gray-200">
            <p class="text-xs text-gray-500 text-center">
              We securely access your Gmail, Calendar, and HubSpot accounts to provide AI-powered assistance.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp google_auth_url do
    state = StateManager.generate_state("google")
    GoogleOAuth.auth_url(state)
  end

  defp hubspot_auth_url do
    state = StateManager.generate_state("hubspot")
    HubspotOAuth.auth_url(state)
  end
end
