defmodule FinancialAdvisorWeb.Router do
  use FinancialAdvisorWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {FinancialAdvisorWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FinancialAdvisorWeb do
    pipe_through :browser

    get "/", PageController, :home
    live "/login", AuthLive
    live "/chat", ChatLive
    live "/chat/:id", ChatLive
    live "/settings", SettingsLive

    get "/oauth/google/callback", OAuthController, :google_callback
    get "/oauth/hubspot/callback", OAuthController, :hubspot_callback
    delete "/oauth/google/disconnect", OAuthController, :google_disconnect
    delete "/oauth/hubspot/disconnect", OAuthController, :hubspot_disconnect
  end

  scope "/api", FinancialAdvisorWeb do
    pipe_through :api

    post "/webhooks/gmail", WebhookController, :gmail
    post "/webhooks/hubspot", WebhookController, :hubspot
    post "/webhooks/calendar", WebhookController, :calendar
  end

  # Other scopes may use custom stacks.
  # scope "/api", FinancialAdvisorWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:financial_advisor, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: FinancialAdvisorWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
