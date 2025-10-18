defmodule FinancialAdvisor.OAuth.StateManager do
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.OAuthState
  require Logger

  def generate_state(provider, user_id \\ nil) do
    state = UUID.uuid4()

    OAuthState.changeset(%OAuthState{}, %{
      state: state,
      provider: provider,
      user_id: user_id,
      expires_at: DateTime.add(DateTime.utc_now(), 600)
    })
    |> Repo.insert!()

    state
  end

  def verify_state(state, provider) do
    case Repo.get_by(OAuthState, state: state, provider: provider) do
      nil ->
        {:error, :invalid_state}

      oauth_state ->
        if DateTime.compare(oauth_state.expires_at, DateTime.utc_now()) == :gt do
          {:ok, oauth_state}
        else
          {:error, :state_expired}
        end
    end
  end

  def consume_state(state) do
    case Repo.get_by(OAuthState, state: state) do
      nil -> :ok
      oauth_state -> Repo.delete(oauth_state)
    end
  end
end
