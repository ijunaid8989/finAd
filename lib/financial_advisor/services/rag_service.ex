defmodule FinancialAdvisor.Services.RAGService do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Email
  alias FinancialAdvisor.HubspotContact
  alias FinancialAdvisor.Services.EmbeddingsService
  import Ecto.Query

  def get_context_for_query(user_id, query, limit_emails \\ 5, limit_contacts \\ 3) do
    with {:ok, email_results} <- EmbeddingsService.search_emails(user_id, query, limit_emails),
         {:ok, contact_results} <-
           EmbeddingsService.search_contacts(user_id, query, limit_contacts) do
      email_context = format_email_results(email_results)
      contact_context = format_contact_results(contact_results)

      context = """
      Based on the user's emails and contacts, here is relevant context:

      ## Recent Emails:
      #{email_context}

      ## Relevant Contacts:
      #{contact_context}
      """

      {:ok, context}
    end
  end

  defp format_email_results(results) do
    results
    |> Enum.map(fn %{email: email, similarity: similarity} ->
      body = email.body || ""

      """
      - From: #{email.from}
        Subject: #{email.subject}
        Date: #{email.received_at}
        Relevance: #{Float.round(similarity * 100, 1)}%
        Body: #{String.slice(body, 0..500)}...
      """
    end)
    |> Enum.join("\n")
  end

  defp format_contact_results(results) do
    results
    |> Enum.map(fn %{contact: contact, similarity: similarity} ->
      """
      - #{contact.first_name} #{contact.last_name}
        Email: #{contact.email}
        Phone: #{contact.phone}
        Relevance: #{Float.round(similarity * 100, 1)}%
        Notes: #{contact.notes}
      """
    end)
    |> Enum.join("\n")
  end

  def get_all_emails_for_context(user_id) do
    Email
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.received_at)
    |> limit(100)
    |> Repo.all()
    |> Enum.map(fn email ->
      "From: #{email.from}\nSubject: #{email.subject}\nDate: #{email.received_at}\nBody: #{email.body}\n---"
    end)
    |> Enum.join("\n\n")
  end

  def get_all_contacts_for_context(user_id) do
    HubspotContact
    |> where([c], c.user_id == ^user_id)
    |> limit(50)
    |> Repo.all()
    |> Enum.map(fn contact ->
      "Name: #{contact.first_name} #{contact.last_name}\nEmail: #{contact.email}\nPhone: #{contact.phone}\nNotes: #{contact.notes}\n---"
    end)
    |> Enum.join("\n\n")
  end

  def search_emails(user_id, query) do
    EmbeddingsService.search_emails(user_id, query, 10)
  end

  def search_contacts(user_id, query) do
    EmbeddingsService.search_contacts(user_id, query, 5)
  end
end
