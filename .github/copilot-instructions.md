# Financial Advisor AI - Copilot Instructions

## Project Overview
This is a Phoenix 1.8 LiveView application that serves as an AI-powered financial advisor assistant. The app integrates with Google (Gmail/Calendar), HubSpot CRM, and Claude AI to provide intelligent email management, contact synchronization, and conversational assistance.

## Architecture & Key Components

### Core Service Architecture
- **AIAgent** (`lib/financial_advisor/services/ai_agent.ex`) - Central Claude AI integration with tool calling capabilities
- **RAGService** - Retrieval Augmented Generation using pgvector embeddings for contextual search
- **Integration Services** - Gmail, Calendar, HubSpot APIs with OAuth2 authentication
- **Webhook Processing** - Real-time event handling from external services

### Data Model Relationships
```
User -> Conversations, Emails, HubspotContacts, CalendarEvents, Tasks, OngoingInstructions
Conversations -> messages (JSON field storing chat history)
Emails/Contacts -> Embeddings (pgvector for semantic search)
```

### OAuth Integration Pattern
All OAuth tokens are stored as `:binary` fields with separate access/refresh tokens. Use dedicated changesets:
- `User.google_oauth_changeset/2` for Google tokens
- `User.hubspot_oauth_changeset/2` for HubSpot tokens

## Development Workflows

### Essential Commands
- `mix precommit` - Run before committing (compile with warnings as errors, format, test)
- `mix setup` - Initial project setup (deps, ecto, assets)
- `mix ecto.reset` - Reset database (useful for schema changes)
- `mix phx.server` - Start development server

### Testing Patterns
- Use `Phoenix.LiveViewTest` for LiveView testing with element IDs
- Database tests use `Ecto.Adapters.SQL.Sandbox.mode(:manual)`
- Test OAuth flows by mocking HTTP responses with `HTTPoison`

## Project-Specific Conventions

### HTTP Client
**Always use `:req` library, never `:httpoison`, `:tesla`, or `:httpc`.** The project includes Req by default.

### LiveView Patterns
- All LiveViews require user authentication via session checking in `mount/3`
- Use `Layouts.app` wrapper with `flash={@flash}` and `current_scope` assignments
- Chat interface uses streams for message history: `stream(socket, :messages, new_messages)`

### Service Integration
- All external API calls should include proper error handling and logging
- Use `with` statements for chaining API calls in services
- Store API responses in dedicated Ecto schemas (Email, HubspotContact, etc.)

### AI Agent Tool System
The `AIAgent` module implements a tool-calling pattern where Claude can execute:
- `search_emails` - Semantic search through user emails
- `search_contacts` - HubSpot contact search
- `send_email` - Gmail API integration
- `create_calendar_event` - Google Calendar integration
- `save_ongoing_instruction` - Persistent AI behavior rules

### Database & Embeddings
- Uses pgvector extension for semantic search
- Embeddings are generated for emails and contacts via `EmbeddingsService`
- RAG context is built by combining email and contact search results

### Configuration Management
Environment variables for API keys:
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`
- `HUBSPOT_CLIENT_ID`, `HUBSPOT_CLIENT_SECRET`  
- `CLAUDE_API_KEY`

## Critical Integration Points

### Webhook Processing
`WebhookController` handles real-time events from Gmail, HubSpot, and Calendar. All webhook payloads are logged to `WebhookLog` for debugging.

### Background Jobs
Uses Oban for async processing. Key jobs should be defined in `lib/financial_advisor/services/task_processor.ex`.

### Vector Search Implementation
RAG system uses cosine similarity search with embeddings stored in dedicated tables (`email_embeddings`, `contact_embeddings`). Search results include similarity scores for relevance ranking.

## Common Pitfalls

1. **OAuth Token Handling** - Always check token expiry and refresh as needed before API calls
2. **LiveView Memory** - Use streams for large collections, not regular assigns
3. **API Rate Limits** - Implement proper backoff for HubSpot/Gmail APIs
4. **Embedding Sync** - Ensure embeddings are created/updated when source data changes
5. **Error Boundary** - Wrap all external API calls in proper error handling to prevent process crashes

## File Structure Notes
- OAuth logic in `lib/financial_advisor/oauth/`
- Service modules follow naming: `lib/financial_advisor/services/{service_name}_service.ex`
- LiveViews in `lib/financial_advisor_web/live/` with corresponding templates
- Database schemas as separate modules in `lib/financial_advisor/`