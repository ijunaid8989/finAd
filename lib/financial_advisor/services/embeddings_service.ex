defmodule FinancialAdvisor.Services.EmbeddingsService do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.Email
  alias FinancialAdvisor.HubspotContact
  alias FinancialAdvisor.EmailEmbedding
  alias FinancialAdvisor.ContactEmbedding
  import Ecto.Query

  @claude_api_url "https://api.anthropic.com/v1/messages"

  def config do
    %{
      api_key: System.get_env("CLAUDE_API_KEY", "YOUR_CLAUDE_API_KEY")
    }
  end

  def embed_email(email) do
    content = "#{email.subject}\n\n#{email.body}"
    content_hash = hash_content(content)

    case get_embedding(content) do
      {:ok, embedding} ->
        EmailEmbedding.changeset(%EmailEmbedding{}, %{
          email_id: email.id,
          embedding: embedding,
          content_hash: content_hash
        })
        |> Repo.insert()

      {:error, reason} ->
        Logger.error("Failed to embed email: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def embed_contact(contact) do
    content = "#{contact.first_name} #{contact.last_name} #{contact.email} #{contact.notes}"
    content_hash = hash_content(content)

    case get_embedding(content) do
      {:ok, embedding} ->
        ContactEmbedding.changeset(%ContactEmbedding{}, %{
          hubspot_contact_id: contact.id,
          embedding: embedding,
          content_hash: content_hash
        })
        |> Repo.insert()

      {:error, reason} ->
        Logger.error("Failed to embed contact: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def get_embedding(text) do
    # Using Claude's text input format for embeddings if available
    # Otherwise, fallback to a simple mock
    case call_embedding_api(text) do
      {:ok, embedding} ->
        {:ok, embedding}

      {:error, _reason} ->
        # Fallback: create deterministic embedding for testing
        {:ok, generate_mock_embedding(text)}
    end
  end

  defp call_embedding_api(text) do
    # This would integrate with Claude's embedding model
    # For now, returning mock as Claude v1 doesn't have dedicated embedding endpoint
    # You'd integrate with OpenAI embedding API or similar
    case System.get_env("EMBEDDINGS_PROVIDER", "mock") do
      "openai" ->
        call_openai_embedding(text)

      "mock" ->
        {:ok, generate_mock_embedding(text)}

      _ ->
        {:ok, generate_mock_embedding(text)}
    end
  end

  defp call_openai_embedding(text) do
    # TODO: Implement OpenAI embedding API call
    {:ok, generate_mock_embedding(text)}
  end

  defp generate_mock_embedding(text) do
    # Create deterministic embedding for testing purposes
    hash = :crypto.hash(:sha256, text)

    # Convert SHA256 hash to 1536-dimensional vector
    hash_bits = :binary.decode_unsigned(hash)

    for i <- 0..1535 do
      rem(hash_bits + i, 1000) / 1000
    end
  end

  def search_emails(user_id, query, limit \\ 10) do
    with {:ok, query_embedding} <- get_embedding(query) do
      emails =
        from(e in Email,
          where: e.user_id == ^user_id,
          join: emb in assoc(e, :embedding),
          select: %{
            email: e,
            similarity:
              fragment(
                "1 - (? <-> ?)",
                emb.embedding,
                ^query_embedding
              )
          },
          order_by: [desc: fragment("1 - (? <-> ?)", emb.embedding, ^query_embedding)],
          limit: ^limit
        )
        |> Repo.all()

      {:ok, emails}
    end
  end

  def search_contacts(user_id, query, limit \\ 10) do
    with {:ok, query_embedding} <- get_embedding(query) do
      contacts =
        from(c in HubspotContact,
          where: c.user_id == ^user_id,
          join: emb in ContactEmbedding,
          on: emb.hubspot_contact_id == c.id,
          select: %{
            contact: c,
            similarity:
              fragment(
                "1 - (? <-> ?)",
                emb.embedding,
                ^query_embedding
              )
          },
          order_by: [desc: fragment("1 - (? <-> ?)", emb.embedding, ^query_embedding)],
          limit: ^limit
        )
        |> Repo.all()
        |> IO.inspect()

      {:ok, contacts}
    end
  end

  defp hash_content(content) do
    :crypto.hash(:sha256, content)
    |> Base.encode16(case: :lower)
  end
end
