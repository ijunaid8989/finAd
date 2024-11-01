defmodule FinancialAdvisorWeb.PageControllerTest do
  use FinancialAdvisorWeb.ConnCase

  test "GET / redirects to /login when not authenticated", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/login"
  end

  test "GET / redirects to /chat when authenticated", %{conn: conn} do
    # Create a test user and set session
    user = %FinancialAdvisor.User{id: 1, email: "test@example.com"}
    conn = conn |> put_session("current_user", user) |> get(~p"/")
    assert redirected_to(conn) == ~p"/chat"
  end
end
