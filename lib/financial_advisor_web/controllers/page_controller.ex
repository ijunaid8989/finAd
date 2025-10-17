defmodule FinancialAdvisorWeb.PageController do
  use FinancialAdvisorWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
