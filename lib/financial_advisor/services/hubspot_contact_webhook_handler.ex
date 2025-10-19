defmodule FinancialAdvisor.Services.HubspotContactWebhookHandler do
  require Logger
  alias FinancialAdvisor.Repo
  alias FinancialAdvisor.User
  alias FinancialAdvisor.Services.HubspotService
  alias FinancialAdvisor.Services.GmailService

  def handle_contact_creation(portal_id, contact_id) do
    Logger.info(
      "Processing HubSpot contact creation: contactId=#{contact_id}, portalId=#{portal_id}"
    )

    with {:ok, user} <- get_user_by_portal_id(portal_id),
         {:ok, contact} <- HubspotService.get_contact(user, contact_id),
         {:ok, contact_info} <- parse_contact_response(contact) do
      send_welcome_email(user, contact_info)
    else
      {:error, reason} ->
        Logger.error("Failed to process contact creation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_user_by_portal_id(portal_id) do
    case Repo.get_by(User, hubspot_id: "#{portal_id}") do
      nil ->
        {:error, "User not found"}

      user ->
        {:ok, user}
    end
  end

  defp parse_contact_response(response_body) when is_binary(response_body) do
    case Jason.decode(response_body) do
      {:ok, data} -> parse_contact_response(data)
      {:error, reason} -> {:error, reason}
    end
  end

  defp parse_contact_response(%{"properties" => properties, "id" => contact_id}) do
    # Extract properties from the HubSpot response format
    email = get_property(properties, "email")
    first_name = get_property(properties, "firstname")
    last_name = get_property(properties, "lastname")

    if email do
      {:ok,
       %{
         contact_id: contact_id,
         email: email,
         first_name: first_name,
         last_name: last_name
       }}
    else
      {:error, "Contact has no email address"}
    end
  end

  defp parse_contact_response(_), do: {:error, "Invalid response format"}

  defp get_property(properties, key) when is_list(properties) do
    # If properties is a list of maps with "name" and "value"
    Enum.find_value(properties, fn
      %{"name" => ^key, "value" => value} -> value
      _ -> nil
    end)
  end

  defp get_property(properties, key) when is_map(properties) do
    # If properties is a map with direct key access
    case properties[key] do
      nil -> nil
      %{"value" => value} -> value
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp send_welcome_email(user, contact_info) do
    email = contact_info.email
    name = get_contact_name(contact_info)

    subject = "Welcome! Thank you for being a client"

    body = """
    Hi #{name},

    Welcome to our financial advisory platform! We're excited to have you as a client.

    Thank you for choosing to work with us. We're committed to helping you achieve your financial goals.

    If you have any questions or need assistance, please don't hesitate to reach out.

    Best regards,
    Financial Advisor Team
    """

    case GmailService.send_email(user, email, subject, body) do
      {:ok, result} ->
        Logger.info("Welcome email sent to #{email}: #{inspect(result)}")
        {:ok, result}

      {:error, reason} ->
        Logger.error("Failed to send welcome email to #{email}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_contact_name(%{first_name: first_name, last_name: last_name})
       when is_binary(first_name) and is_binary(last_name) do
    "#{first_name} #{last_name}"
  end

  defp get_contact_name(%{first_name: first_name}) when is_binary(first_name) do
    first_name
  end

  defp get_contact_name(%{email: email}) do
    email
  end

  defp get_contact_name(_), do: "Valued Client"
end
