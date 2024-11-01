defmodule FinancialAdvisorWeb.PageController do
  use FinancialAdvisorWeb, :controller

  def home(conn, _params) do
    user = get_session(conn, "current_user")

    if user do
      redirect(conn, to: ~p"/chat")
    else
      redirect(conn, to: ~p"/login")
    end
  end
end
