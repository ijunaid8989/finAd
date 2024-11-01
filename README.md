# Financial Advisor AI - Comprehensive Integration Platform

A sophisticated Elixir/Phoenix application that orchestrates Gmail, Google Calendar, and HubSpot to provide AI-powered financial advisor capabilities with automated workflows, real-time event processing, and intelligent contact management.

---

## 🎯 Core Features Implemented

### 1. **OAuth2 Authentication & Token Management**
   - Secure Google OAuth integration for Gmail and Google Calendar access
   - HubSpot OAuth integration for contact management
   - Automatic token refresh mechanisms with fallback retry logic
   - Encrypted token storage in database (binary fields)
   - State-based CSRF protection using `OAuthState` schema

### 2. **Gmail Integration & Email Management**
   - Sync emails from Gmail (past 7 days by default, configurable)
   - Full message parsing including headers, body, HTML body, and metadata
   - Automatic base64 decoding of Gmail message payloads
   - Email storage with unique constraints (user_id + gmail_id)
   - Vector embeddings for semantic email search using pgvector
   - Send emails directly through authenticated Gmail account

### 3. **Google Calendar Event Management**
   - Sync historical calendar events (7-day lookback by default)
   - Real-time polling system for newly created events (every 2 minutes)
   - Filter events to only process those created by the logged-in user
   - Attendee extraction and tracking
   - Event description and metadata preservation
   - Future events only for new event detection

### 4. **Automated Event Notification System**
   - **Event Detection**: Polls Google Calendar for new events created by user
   - **Email Invitations**: Automatically sends invitation emails to all attendees
   - **Smart Tracking**: Maintains `CalendarEventEmailLog` table to avoid duplicate emails
   - **Idempotent Design**: Safe to run repeatedly without resending emails
   - **Organizer Filtering**: Prevents emails to self
   - **Formatted Notifications**: Professional email templates with date/time formatting

### 5. **HubSpot Contact Management**
   - Sync contacts from HubSpot CRM
   - Webhook integration for real-time contact creation events
   - Automatic welcome emails when new contacts are added
   - Contact properties extraction (email, first_name, last_name, phone)
   - Notes and metadata storage
   - Portal ID mapping for multi-tenant support

### 6. **HubSpot Webhook Processing**
   - Listens for `contact.creation` events via webhooks
   - Automatic webhook setup during OAuth callback
   - Portal ID-based user routing
   - Async webhook processing to maintain fast response times
   - Welcome email automation for new contacts

### 7. **Vector Embeddings & Semantic Search**
   - pgvector integration for embedding storage (1536-dimensional vectors)
   - Email embeddings for semantic email search
   - Contact embeddings for semantic contact search
   - Content hashing to prevent duplicate embeddings
   - Similarity scoring using cosine distance (1 - L2 distance)

### 8. **RAG (Retrieval-Augmented Generation) System**
   - Semantic search across user's emails and contacts
   - Context extraction for AI agent queries
   - Relevance scoring with similarity percentages
   - Multi-source context aggregation (emails + contacts)

### 9. **Claude AI Integration**
   - Direct integration with Claude API (claude-3-5-sonnet model)
   - Tool-calling system for AI agent automation
   - Available tools:
     - `search_emails`: Semantic search through emails
     - `search_contacts`: Search HubSpot contacts
     - `get_calendar_availability`: Check calendar slots
     - `send_email`: Send emails via Gmail
     - `create_calendar_event`: Create new calendar events with ISO8601 datetime formatting
     - `create_hubspot_contact`: Create new HubSpot contacts
     - `add_contact_note`: Add notes to HubSpot contacts
     - `save_ongoing_instruction`: Store persistent instructions
     - `get_ongoing_instructions`: Retrieve active instructions
     - `get_contact_context`: Get detailed contact information with emails and notes
   - Automatic weekday date calculation for natural language scheduling
   - Conversation persistence with message history

### 10. **Ongoing Instructions System**
   - Store user-defined instructions in database
   - Trigger types: email_received, contact_created, calendar_event, manual
   - Status tracking (active/inactive)
   - Integration with AI agent for autonomous execution

### 11. **Conversation Management**
   - Persistent conversation storage
   - Message history with role tracking (user/assistant)
   - Context preservation across sessions
   - Task association with conversations

### 12. **Task Management System**
   - Task creation from AI agent tool calls
   - Status tracking (pending, waiting_for_response, completed, failed)
   - Tool call recording and result storage
   - Metadata and error logging

### 13. **Webhook Logging & Monitoring**
   - Comprehensive webhook event logging
   - Provider tracking (gmail, hubspot, calendar)
   - Event type classification
   - Payload storage for debugging
   - Processing status and error messages

### 14. **Scheduled Sync Operations**
   - **Every 5 minutes**: Full data sync for Gmail, Calendar, and HubSpot
   - **Every 2 minutes**: Real-time event polling for new calendar events
   - **Parallel processing**: Multiple users synced concurrently
   - **Error handling**: Comprehensive logging and graceful degradation
   - **Embedding generation**: Automatic embedding creation for new emails and contacts

### 15. **LiveView Interface**
   - **Chat Interface**: Real-time AI conversations with message streaming
   - **Settings Page**: Integration connection management and instruction editor
   - **Authentication Page**: OAuth flow for Google and HubSpot
   - **Sidebar Navigation**: Quick sync actions, new conversations
   - **Flash Messages**: User feedback for operations

### 16. **Database Schema & Relationships**
   - `users`: Core user profile with OAuth tokens
   - `emails`: Gmail messages with metadata
   - `email_embeddings`: Vector embeddings for emails
   - `hubspot_contacts`: Synced contact records
   - `contact_embeddings`: Vector embeddings for contacts
   - `calendar_events`: Synced calendar events
   - `calendar_event_email_logs`: Tracking for sent invitation emails
   - `conversations`: Chat history
   - `tasks`: AI-generated tasks
   - `ongoing_instructions`: Persistent user instructions
   - `oauth_states`: CSRF protection tokens
   - `webhook_logs`: Webhook event tracking

---

## 🔄 Workflow Examples

### Example 1: New Contact Automation
```
1. Contact created in HubSpot
2. Webhook received at /api/webhooks/hubspot
3. Portal ID matched to user
4. Contact details fetched from HubSpot API
5. Welcome email automatically sent to contact
6. Event logged with timestamp
```

### Example 2: Calendar Event Notification
```
1. User creates event in Google Calendar with attendees
2. Polling detects new event (every 2 minutes)
3. Event stored in database
4. Invitation emails sent to all attendees (except organizer)
5. Email log entries created to prevent duplicates
6. If event modified later, only new attendees receive emails
```

### Example 3: AI-Powered Chat with Context
```
1. User asks AI agent: "Create a meeting with John"
2. RAG system fetches context:
   - Searches emails for "John" communications
   - Searches contacts for "John"
   - Gets calendar availability
3. AI uses tool to create calendar event
4. Sends invitation email via tool
5. Response streamed back to user in real-time
```

---

## 🚀 Technology Stack

- **Language**: Elixir 1.14+
- **Framework**: Phoenix 1.7+ with LiveView
- **Database**: PostgreSQL with pgvector extension install through this https://github.com/pgvector/pgvector
- **External APIs**: Google APIs (Gmail, Calendar), HubSpot, Claude AI
- **Authentication**: OAuth2
- **Background Jobs**: GenServer-based scheduling
- **HTTP Client**: HTTPoison (Note: Project guidelines recommend migrating to Req)
- **JSON**: Jason
- **Search**: Vector embeddings with cosine similarity

---

## 📋 Environment Variables Required

```env
# Google OAuth
GOOGLE_CLIENT_ID=your_client_id
GOOGLE_CLIENT_SECRET=your_client_secret
GOOGLE_REDIRECT_URI=http://localhost:4000/oauth/google/callback

# HubSpot OAuth
HUBSPOT_CLIENT_ID=your_client_id
HUBSPOT_CLIENT_SECRET=your_client_secret
HUBSPOT_REDIRECT_URI=http://localhost:4000/oauth/hubspot/callback

# Claude AI
CLAUDE_API_KEY=your_api_key

# Database
DATABASE_URL=postgresql://user:password@localhost/financial_advisor_dev

# Production
SECRET_KEY_BASE=generated_secret
PHX_HOST=yourdomain.com
```

---

## 🚀 Deployment to Render

### Prerequisites
- [Render Account](https://render.com) - Sign up for free
- GitHub/GitLab repository with your code
- PostgreSQL database with pgvector extension (Render supports this)

### Quick Start (Using render.yaml)

1. **Connect Repository to Render:**
   - Go to [Render Dashboard](https://dashboard.render.com)
   - Click "New +" → "Blueprint"
   - Connect your GitHub/GitLab repository
   - Render will automatically detect `render.yaml` and create all services

2. **Set Environment Variables:**
   - Go to your web service settings → "Environment"
   - Add the following (see full list below):
     - `SECRET_KEY_BASE` - Generate with: `mix phx.gen.secret`
     - `PHX_HOST` - Your Render URL (e.g., `financial-advisor.onrender.com`)
     - `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`, `GOOGLE_REDIRECT_URI`
     - `HUBSPOT_CLIENT_ID`, `HUBSPOT_CLIENT_SECRET`, `HUBSPOT_REDIRECT_URI`
     - `CLAUDE_API_KEY`

3. **Enable pgvector Extension:**
   - Go to your database service → "Connect" → "Connect via psql"
   - Run: `CREATE EXTENSION IF NOT EXISTS vector;`

4. **Deploy:**
   - Render automatically deploys on git push
   - Or manually trigger from dashboard

### Manual Setup

1. **Create PostgreSQL Database:**
   - Render Dashboard → "New +" → "PostgreSQL"
   - Name: `financial-advisor-db`
   - PostgreSQL Version: 15
   - Enable pgvector: `CREATE EXTENSION IF NOT EXISTS vector;`

2. **Create Web Service:**
   - Render Dashboard → "New +" → "Web Service"
   - Connect repository
   - Environment: `Docker`
   - Dockerfile Path: `Dockerfile`
   - Link the database (auto-sets `DATABASE_URL`)

3. **Set Environment Variables:**
   - `PHX_SERVER=true`
   - `PORT=8080`
   - `MIX_ENV=prod`
   - Plus all OAuth and API keys (see full list in DEPLOYMENT.md)

4. **Run Migrations:**
   - After first deploy, go to web service → "Shell"
   - Run: `./bin/migrate`

### Required Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `SECRET_KEY_BASE` | Phoenix secret | Generate: `mix phx.gen.secret` |
| `PHX_HOST` | Your app hostname | `financial-advisor.onrender.com` |
| `DATABASE_URL` | PostgreSQL URL | Auto-set when linking database |
| `GOOGLE_CLIENT_ID` | Google OAuth ID | From Google Cloud Console |
| `GOOGLE_CLIENT_SECRET` | Google OAuth secret | From Google Cloud Console |
| `GOOGLE_REDIRECT_URI` | Google redirect | `https://your-app.onrender.com/oauth/google/callback` |
| `HUBSPOT_CLIENT_ID` | HubSpot OAuth ID | From HubSpot Developer Portal |
| `HUBSPOT_CLIENT_SECRET` | HubSpot OAuth secret | From HubSpot Developer Portal |
| `HUBSPOT_REDIRECT_URI` | HubSpot redirect | `https://your-app.onrender.com/oauth/hubspot/callback` |
| `CLAUDE_API_KEY` | Claude AI API key | From Anthropic |

### Post-Deployment

1. **Update OAuth Redirect URIs:**
   - Google: `https://your-app.onrender.com/oauth/google/callback`
   - HubSpot: `https://your-app.onrender.com/oauth/hubspot/callback`

2. **Verify Deployment:**
   - Visit your Render URL
   - Check logs in Render dashboard
   - Verify pgvector: Connect to DB and run `\dx`

### Troubleshooting

- **Check Logs:** Render Dashboard → Your Service → "Logs"
- **Database Connection:** Verify `DATABASE_URL` is set
- **pgvector Issues:** Run `CREATE EXTENSION IF NOT EXISTS vector;` in database shell
- **Build Failures:** Check Dockerfile and build logs

For detailed deployment instructions, see [DEPLOYMENT.md](./DEPLOYMENT.md).

---

## 🔧 Setup & Installation

### Prerequisites
- Elixir 1.14+
- PostgreSQL 13+
- pgvector extension

### Installation Steps

```bash
# 1. Clone and install dependencies
mix ecto.create
mix ecto.migrate

# 2. Create OAuth applications
# - Google: https://console.cloud.google.com
# - HubSpot: https://app.hubspot.com/l/developer

# 3. Configure environment variables
cp .env.example .env
# Edit .env with your credentials

# 4. Start the server
mix phx.server

# 5. Visit http://localhost:4000
```

---

## 📊 Data Flow Architecture

```
User Login
  ↓
  ├─→ Google OAuth → Gmail + Calendar Access
  │    ├─→ Sync Emails (7-day lookback)
  │    ├─→ Sync Calendar Events (7-day lookback)
  │    └─→ Store with Embeddings
  │
  └─→ HubSpot OAuth → Contact Access
       ├─→ Sync Contacts
       ├─→ Setup Contact Creation Webhook
       └─→ Store with Embeddings

Scheduled Tasks (every 2-5 min)
  ├─→ Poll new calendar events
  │    ├─→ Filter by creator (current user)
  │    ├─→ Send invitation emails
  │    └─→ Log sent emails
  │
  ├─→ Listen for HubSpot webhooks
  │    ├─→ Extract contact ID from event
  │    ├─→ Fetch contact details
  │    └─→ Send welcome email
  │
  └─→ Full sync cycle
       ├─→ Refresh all emails
       ├─→ Refresh all contacts
       └─→ Generate embeddings

AI Chat Flow
  ├─→ User message received
  ├─→ RAG retrieves context (emails + contacts)
  ├─→ Claude processes with available tools
  ├─→ Tools execute (send email, create event, etc)
  ├─→ Results stored in database
  └─→ Response streamed to UI
```

---

## 🎯 Key Improvements Made

1. ✅ **Fixed Chat Persistence**: URL params now properly capture conversation_id on refresh
2. ✅ **HubSpot Contact Webhooks**: Automatic welcome emails on new contact creation
3. ✅ **Google Calendar Polling**: Real-time detection of new events with attendee notifications
4. ✅ **Email Tracking**: Prevents duplicate invitation emails using `CalendarEventEmailLog`
5. ✅ **Idempotent Operations**: Safe to retry without side effects
6. ✅ **Async Processing**: Webhooks return 200 immediately, process in background
7. ✅ **Vector Search**: Semantic search across emails and contacts
8. ✅ **AI Agent Tools**: 10+ tools for autonomous decision making
9. ✅ **OAuth Token Refresh**: Automatic refresh with fallback retry
10. ✅ **Comprehensive Logging**: Full observability of all operations

---

## 🔐 Security Features

- OAuth2 CSRF protection with state tokens
- Encrypted binary token storage
- Token refresh before expiration
- Webhook signature verification placeholders
- User isolation (scoped queries)
- Secure session management

---

## 📈 Performance Optimizations

- **Batch operations**: Sync 100+ emails/contacts in single operations
- **Vector indexing**: Fast similarity search on embeddings
- **Connection pooling**: 10 pool connections per environment
- **Async webhooks**: Non-blocking webhook processing
- **Smart polling**: Only processes future events
- **Unique constraints**: Prevents duplicate database entries

---

## 🚦 Monitoring & Observability

- Comprehensive logging in all services
- Webhook event tracking with status
- Task result storage for audit trails
- Email log tracking with timestamps
- Error logging with stack traces
- Phoenix telemetry metrics integration

---

## 🔮 Future Enhancements

1. Multiple calendar support (personal + team calendars)
2. Advanced scheduling with timezone support
3. Contact enrichment with external data sources
4. Bulk email campaign management
5. Meeting analytics and attendance tracking
6. Natural language task scheduling
7. Email template management
8. Multi-user team collaboration features
9. Advanced analytics dashboard
10. SMS notifications integration

---

## 📝 License

This project is part of the Financial Advisor AI platform.

---

## 👥 Contributing

For development contributions, follow the existing patterns:
- Use explicit `{:ok, result}` and `{:error, reason}` patterns
- Write comprehensive tests with factories
- Document complex logic with comments
- Keep services focused on single responsibilities
- Use Ecto.Multi for transactional operations

---

**Last Updated**: October 2025
**Status**: Production Ready
**Version**: 1.0.0
