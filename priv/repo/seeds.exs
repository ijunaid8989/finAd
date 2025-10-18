alias FinancialAdvisor.Repo

# Clear existing data
Repo.delete_all(FinancialAdvisor.User)

# Create test user if needed
test_user =
  Ecto.build_assoc(
    %FinancialAdvisor.User{},
    :emails,
    %FinancialAdvisor.Email{
      gmail_id: "test_123",
      from: "test@example.com",
      to: ["recipient@example.com"],
      subject: "Test Email",
      body: "This is a test email",
      received_at: DateTime.utc_now()
    }
  )

IO.puts("Seed data completed!")
