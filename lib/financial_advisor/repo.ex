defmodule FinancialAdvisor.Repo do
  use Ecto.Repo,
    otp_app: :financial_advisor,
    adapter: Ecto.Adapters.Postgres
end
