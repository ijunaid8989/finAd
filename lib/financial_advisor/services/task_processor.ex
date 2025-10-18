defmodule FinancialAdvisor.Services.TaskProcessor do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Task
  import Ecto.Query

  def process_pending_tasks do
    pending_tasks =
      Task
      |> where([t], t.status == "pending")
      |> Repo.all()

    Enum.each(pending_tasks, &process_task/1)
  end

  defp process_task(task) do
    Logger.info("Processing task: #{task.id}")

    case execute_task(task) do
      {:ok, result} ->
        task
        |> Task.changeset(%{
          status: "waiting_for_response",
          result: result,
          completed_at: DateTime.utc_now()
        })
        |> Repo.update()

      {:error, reason} ->
        Logger.error("Task #{task.id} failed: #{inspect(reason)}")

        task
        |> Task.changeset(%{
          status: "failed",
          metadata: %{error: reason}
        })
        |> Repo.update()
    end
  end

  defp execute_task(task) do
    # Execute based on task metadata and stored tool calls
    {:ok, %{status: "completed"}}
  end
end
