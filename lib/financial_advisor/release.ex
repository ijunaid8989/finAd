defmodule FinancialAdvisor.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.
  """
  @app :financial_advisor

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, fn repo ->
        # Ensure pgvector extension exists before running migrations
        # The migration file will also create it, but this ensures it's available
        try do
          repo.query("CREATE EXTENSION IF NOT EXISTS vector", [])
        rescue
          _ -> :ok
        catch
          _, _ -> :ok
        end

        Ecto.Migrator.run(repo, :up, all: true)
      end)
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    # Many platforms require SSL when connecting to the database
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
  end
end
