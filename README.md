# 🛡️ InfoGuard AI

**AI-powered fact-checking for social media posts, in English and Tamil.**

InfoGuard AI lets you share an Instagram post or Reel straight from your phone and get back a verdict (`TRUE`, `FALSE` or `MISLEADING`), a plain-language explanation in **English and Tamil**, and a link to a supporting source. It combines speech transcription, visual analysis, live web search and an LLM fact-checker into a single pipeline.

---

## ✨ Features

- **Share-to-verify**: share a post from Instagram (or any app) into InfoGuard AI via Android's share sheet.
- **Multimodal analysis**: reads the caption, transcribes spoken audio, and describes on-screen visuals and text.
- **Live evidence retrieval (RAG)**: searches the web for corroborating or contradicting sources before judging the claim.
- **Bilingual output**: every explanation is returned in English and Tamil.
- **Verified proof links**: candidate source links are pinged to confirm they are live; social media, YouTube and Google links are filtered out.
- **Background verification**: runs as a foreground service and notifies you when the result is ready; tapping the notification opens the result screen.
- **Result caching**: previously verified URLs are served instantly from PostgreSQL.
- **Graceful degradation**: muted videos, photo posts and carousels are handled, and a failed audio or vision step does not abort the whole pipeline.

---

## 🧠 How It Works

```
 Share a post  ─►  Flutter app  ─►  POST /api/v1/verify  ─►  Spring Boot backend
                                                                    │
        ┌───────────────────────────────────────────────────────────┘
        ▼
 1. Cache lookup (PostgreSQL)            ── hit → return saved verdict
 2. Media extraction                     ── yt-dlp, falling back to Apify
 3. Split media                          ── ffmpeg: 3 keyframes + 16 kHz audio
 4. Parallel AI analysis (Groq)          ── Whisper (audio → English text)
                                            Vision model (frame description)
 5. Evidence retrieval                   ── Tavily web search
 6. Fact-check LLM (Groq)                ── JSON verdict + EN/TA explanation
 7. Proof-link validation                ── ping candidates, pick first live one
 8. Persist + cleanup                    ── save record, delete temp media
```

---

## 🧰 Tech Stack

| Layer | Technology |
|-------|------------|
| Mobile app | Flutter (Dart), Material 3 |
| Backend | Java 17, Spring Boot 4.1.1, Spring Web / WebFlux, Spring Data JPA, Lombok |
| Database | PostgreSQL |
| Media tooling | `yt-dlp`, `ffmpeg` |
| AI / APIs | [Groq](https://groq.com) (Whisper speech translation, vision model, fact-check LLM), [Tavily](https://tavily.com) (web search), [Apify](https://apify.com) (Instagram scraper fallback) |

---

## 📁 Project Structure

```
InfoGuard-AI/
├── backend/                         # Spring Boot REST API
│   ├── pom.xml
│   └── src/main/
│       ├── java/com/project/verifier/
│       │   ├── VerifierApplication.java
│       │   ├── controller/VerificationController.java
│       │   ├── dto/                 # VerificationRequest / VerificationResponse
│       │   ├── entity/              # VerificationRecord (JPA)
│       │   ├── repository/          # VerificationRepository
│       │   └── service/
│       │       ├── VerificationService.java      # Pipeline orchestration
│       │       ├── MediaExtractionService.java   # yt-dlp / Apify / ffmpeg
│       │       ├── LlmService.java               # Whisper + vision calls
│       │       ├── TavilySearchService.java      # Web evidence retrieval
│       │       └── GroqVerificationService.java  # Final fact-check LLM
│       └── resources/application.properties
└── frontend/                        # Flutter mobile app
    ├── pubspec.yaml
    └── lib/
        ├── main.dart                # App, share intent, foreground service, notifications
        ├── models/verification_response.dart
        ├── services/backend_api_service.dart
        └── screens/result_screen.dart
```

---

## 🚀 Getting Started

### Prerequisites

- **Java 17+** and Maven (the Maven wrapper is included)
- **PostgreSQL** running locally
- **yt-dlp** and **ffmpeg** available on your `PATH`
- **Flutter SDK** (Dart `^3.13.4`) and an Android device or emulator
- API keys for **Groq**, **Tavily** and **Apify**

### 1. Clone the repository

```bash
git clone https://github.com/Manovishal-og/InfoGuard-AI.git
cd InfoGuard-AI
```

### 2. Set up the backend

**Create the database**

```sql
CREATE DATABASE verifier_db;
```

**Configure credentials** in `backend/src/main/resources/application.properties`:

```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/verifier_db
spring.datasource.username=<your-db-user>
spring.datasource.password=<your-db-password>
```

> ⚠️ Use your own database credentials and avoid committing real passwords. Prefer environment variables or an untracked local properties file.

**Export your API keys**

```bash
export GROQ_API_KEY=your_groq_key
export TAVILY_API_KEY=your_tavily_key
export APIFY_API_KEY=your_apify_key
```

**Run the server**

```bash
cd backend
./mvnw spring-boot:run
```

The API starts on `http://localhost:8080`. Tables are created automatically (`spring.jpa.hibernate.ddl-auto=update`).

### 3. Set up the mobile app

Point the app at your backend by editing `baseUrl` in `frontend/lib/services/backend_api_service.dart`:

```dart
static const String baseUrl = 'https://your-backend-url';
```

To reach a local backend from a physical phone, expose it with a tunnel such as [ngrok](https://ngrok.com) (`ngrok http 8080`) or use your machine's LAN address.

Then run the app:

```bash
cd frontend
flutter pub get
flutter run
```

### 4. Use it

1. Open Instagram and find a post or Reel you want to check.
2. Tap **Share** and choose **InfoGuard AI** (or paste the link into the app).
3. Wait for the notification, then open it to see the verdict, bilingual explanation and proof link.

---

## 📡 API Reference

### `POST /api/v1/verify`

**Request**

```json
{
  "url": "https://www.instagram.com/reel/XXXXXXXXXXX/",
  "caption": "optional caption override"
}
```

`url` is required. If `caption` is omitted, the caption is extracted from the post.

**Response**

```json
{
  "verdict": "FALSE",
  "category": "Health/Nutrition/Politics/General",
  "explanationEn": "Clear explanation in English.",
  "explanationTa": "தமிழில் தெளிவான விளக்கம்.",
  "proofLink": "https://example.com/supporting-article"
}
```

| Field | Description |
|-------|-------------|
| `verdict` | `TRUE`, `FALSE` or `MISLEADING` |
| `category` | Topic of the claim (e.g. Health, Nutrition, Politics, General) |
| `explanationEn` / `explanationTa` | Explanation in English and Tamil |
| `proofLink` | Validated link to a supporting source |

---

## ⚙️ Configuration

| Property / Variable | Purpose | Default |
|---------------------|---------|---------|
| `server.port` | Backend port | `8080` |
| `GROQ_API_KEY` → `app.groq.api-key` | Groq API access | required |
| `TAVILY_API_KEY` → `app.tavily.api-key` | Tavily search access | required |
| `APIFY_API_KEY` → `app.apify.token` | Apify scraper fallback | required |
| `app.groq.model` | LLM used for the final fact-check | see `application.properties` |
| `app.media.temp-dir` | Scratch directory for downloaded media | `/tmp/verifier_media` |

---

## 📝 Notes & Limitations

- The pipeline is built around **Instagram** posts and Reels; other platforms depend on `yt-dlp` support.
- Verdicts are AI-generated from retrieved web evidence and should be treated as a **starting point, not a final authority**. Always review the proof link.
- Public Instagram content only: private posts cannot be extracted.
- The Flutter app has a `mockMode` flag in `backend_api_service.dart` for UI development without a running backend.
- The Android share-intent and foreground-service features are the primary target platform.

---

## 🤝 Contributing

Contributions, issues and feature requests are welcome. Fork the repo, create a feature branch, and open a pull request.

## 📄 License

No license file is currently included in this repository. Add one (for example MIT) to define how others may use the project.
