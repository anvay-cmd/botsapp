# BotsApp - WhatsApp Clone for AI Chatbots

A full-stack WhatsApp-style messaging app where you chat with AI bots instead of people. Each bot has its own persona, tools, and capabilities.

## Features

- **Google Sign-In** authentication with JWT tokens
- **Real-time chat** via WebSockets with token-by-token streaming
- **Voice calls** via WebRTC + Gemini Live Audio API
- **Custom bot creation** with persona, system prompt, and auto-generated avatars (Imagen 3)
- **7 integrations**: Web Search, Google Calendar, Gmail, Spotify, GitHub, Google Drive, News
- **Reminders**: bots can schedule reminders that text or call you
- **Push notifications** via GCP Pub/Sub + FCM
- **WhatsApp-style UI**: chat bubbles, read receipts, typing indicators, attachments

## Tech Stack

### Backend
- **FastAPI** + Uvicorn (async Python)
- **PostgreSQL** + SQLAlchemy (async) + Alembic
- **LangChain** + Gemini 2.0 Flash
- **WebSockets** for real-time messaging
- **WebRTC** signaling for voice calls
- **APScheduler** for reminders

### Frontend
- **Flutter** (Dart)
- **Riverpod** state management
- **GoRouter** navigation
- **flutter_webrtc** for voice calls

## Getting Started

### Prerequisites
- Python 3.11+
- PostgreSQL running locally
- Flutter SDK 3.x+
- A Google Cloud project with Gemini API enabled

### Backend Setup

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Configure environment
cp .env.example .env  # Edit with your values

# Create database
createdb botsapp

# Run migrations
alembic revision --autogenerate -m "initial"
alembic upgrade head

# Start server
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
```

### Frontend Setup

```bash
cd app
flutter pub get
flutter run
```

### Environment Variables

| Variable | Description |
|---|---|
| `GEMINI_API_KEY` | Google AI Studio API key |
| `DATABASE_URL` | PostgreSQL connection string |
| `JWT_SECRET` | Secret for JWT token signing |
| `GOOGLE_CLIENT_ID` | Google OAuth client ID |
| `GCP_PROJECT_ID` | GCP project for Pub/Sub |
| `PUBSUB_TOPIC` | Pub/Sub topic name |
| `GOOGLE_APPLICATION_CREDENTIALS` | Path to service account JSON |

## Push Notifications Setup (GCP Pub/Sub + FCM)

1. **Create GCP resources:**
   ```bash
   gcloud pubsub topics create botsapp-notifications
   ```

2. **Deploy Cloud Function:**
   ```bash
   gcloud functions deploy sendPushNotification \
     --trigger-topic=botsapp-notifications \
     --runtime=nodejs20
   ```

3. **Flutter setup:** Add `firebase_messaging` package, get FCM token on login, and POST to `/api/auth/fcm-token`

4. **Backend:** Set `GOOGLE_APPLICATION_CREDENTIALS` and `GCP_PROJECT_ID` in `.env`

## API Endpoints

| Method | Path | Description |
|---|---|---|
| POST | `/api/auth/google` | Google OAuth sign-in |
| GET | `/api/auth/me` | Get current user |
| PATCH | `/api/auth/me` | Update profile |
| GET | `/api/chats` | List all chats |
| POST | `/api/chats` | Create a chat |
| GET | `/api/chats/{id}/messages` | Get messages (paginated) |
| PATCH | `/api/chats/{id}/mute` | Mute/unmute chat |
| GET | `/api/bots` | List user's bots |
| POST | `/api/bots` | Create a bot |
| POST | `/api/bots/{id}/generate-image` | Generate avatar |
| GET | `/api/integrations` | List integrations |
| POST | `/api/integrations/{provider}/connect` | Connect integration |
| WS | `/ws?token=JWT` | Real-time chat |
| WS | `/ws/voice/{chatId}?token=JWT` | Voice call |

## Project Structure

```
botsapp/
├── app/                          # Flutter frontend
│   └── lib/
│       ├── config/               # Theme, routes, constants
│       ├── models/               # Data models
│       ├── providers/            # Riverpod state management
│       ├── services/             # API, WebSocket, WebRTC
│       ├── screens/              # All screens
│       └── widgets/              # Reusable widgets
├── backend/                      # FastAPI backend
│   ├── app/
│   │   ├── models/               # SQLAlchemy ORM models
│   │   ├── schemas/              # Pydantic schemas
│   │   ├── routers/              # API endpoints
│   │   ├── services/             # Business logic
│   │   ├── integrations/         # LangChain tools
│   │   └── utils/                # Auth, dependencies
│   └── alembic/                  # Database migrations
└── README.md
```
# botsapp
