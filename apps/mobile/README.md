# Hermes Mobile

A Flutter companion app for [Hermes Agent](../../README.md) — chat and voice with
your agent from iOS/Android over [Tailscale](https://tailscale.com).

It talks to a **single endpoint**: the OpenAI-compatible `api_server` that runs
in-process inside the Hermes gateway (default port `8642`). No separate service.

## Backend prerequisites

Enable the API server on the machine running Hermes (e.g. your Mac):

```bash
# ~/.hermes/.env
API_SERVER_ENABLED=true
API_SERVER_KEY=<a-long-random-secret>       # the app's bearer token
API_SERVER_HOST=<your-tailscale-ip>         # e.g. 100.x.y.z — NOT 0.0.0.0
```

Local speech models (already supported by Hermes):

```yaml
# ~/.hermes/config.yaml
stt:
  provider: parakeet          # or "local" for faster-whisper
  parakeet:
    model: mlx-community/parakeet-tdt-0.6b-v2
tts:
  provider: piper
  piper:
    voice: /Volumes/X31/Models/piper/en_US-lessac-medium.onnx
```

Make sure the phone and Mac are on the same tailnet, then run `hermes gateway run`.

## App configuration

On first launch the app shows an onboarding screen. Enter:

- **Server URL** — `http://<tailscale-ip>:8642`
- **API key** — the `API_SERVER_KEY` above

Tap **Test** to probe `/health`, then **Save**.

## Features (MVP)

- **Text chat** — streamed token-by-token from `/v1/chat/completions` (SSE), with a
  stable `X-Hermes-Session-Id` so the gateway threads one transcript.
- **Push-to-talk** — hold the mic button to record; audio is transcribed via
  `/v1/audio/transcriptions` (Parakeet / faster-whisper) and sent as a turn.
- **Voice replies** — toggle the speaker icon to have replies spoken back via
  `/v1/audio/speech` (Piper).
- **Proactive push** — subscribes to the gateway's ntfy topic and raises OS
  notifications for reminders/briefings (set the ntfy server + topic in Settings
  to match `NTFY_SERVER_URL` / `NTFY_HOME_CHANNEL`).

## Architecture

Layered MVVM (see the [Flutter app architecture guide](https://docs.flutter.dev/app-architecture)):

```
lib/
├── data/
│   ├── services/       # HermesApiClient (HTTP/SSE), AudioService, SettingsService
│   └── repositories/   # ChatRepository, SettingsRepository (single source of truth)
├── domain/models/      # ConnectionSettings, Message
└── ui/
    ├── core/           # theme
    └── features/
        ├── chat/       # ChatViewModel + ChatScreen
        └── settings/   # SettingsViewModel + SettingsScreen
```

## Develop

```bash
flutter pub get
flutter analyze
flutter test
flutter run          # with a device/simulator attached
```

## Roadmap

- Hands-free / continuous voice with VAD + barge-in (backend: `/v1/voice/stream` WS).
- Push notifications (NTFY → FCM) for proactive reminders.
- Personal-management surfaces: calendar, reminders, daily briefing.
