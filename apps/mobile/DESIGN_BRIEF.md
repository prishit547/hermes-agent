# Hermes — Mobile Design Brief

> **For the designer / design AI:** Design a complete, production-grade mobile app UI from this brief. Produce high-fidelity mockups for **every screen listed**, in **both light and dark themes**, for **both iOS and Android**, plus the shared component library. The result must feel like a first-party native app on each platform — not a cross-platform compromise. Aim for **modern, professional, premium**: restrained, confident, spacious, with a signature voice experience. When a detail isn't specified, choose the option a senior product designer at Apple or Linear would choose.

---

## 1. What the product is

**Hermes** is a personal AI assistant app. It's the phone client for a self-hosted AI agent ("Hermes Agent") that the user runs on their own machine and reaches privately over a secure tunnel (Tailscale). Unlike cloud chatbots, this is **the user's own agent** — private, always theirs, running local speech models.

The assistant does two things:
1. **Converses** — by text and by **voice** (speak to it, it speaks back), including a hands-free "call" mode.
2. **Manages the user's life** — calendar, events, reminders, tasks, daily briefings, and proactive notifications ("Leave in 15 min for your dentist appointment").

The emotional promise: *a calm, capable, trustworthy assistant that feels alive when you talk to it and quietly takes care of things when you don't.*

## 2. Who it's for

A technically-confident individual (developer, founder, power user) who self-hosts. They value **privacy, control, speed, and craft**. They will use this many times a day, often one-handed, often by voice, sometimes glancing at it for 2 seconds. The design must reward both deep use (long conversations) and glances (a reminder, a briefing).

## 3. Design principles

1. **Voice is the hero.** The voice experience is the app's signature moment — it should feel physical, responsive, and beautiful. Everything else is calm and recedes so voice can shine.
2. **Native, not neutral.** Respect each platform's conventions (navigation, gestures, typography, haptics, system sheets). A user should never feel they're in a web view.
3. **Calm surfaces, confident moments.** Most screens are quiet, generous whitespace, muted. Reserve color, motion, and depth for the moments that matter (speaking, a new reminder, task done).
4. **Glanceable.** Key information (next event, what to do now) is legible in under two seconds, from arm's length.
5. **Trust through clarity.** Show connection status, what the agent is doing, and where data lives. Never make the user guess whether it's working.
6. **Premium through restraint.** Few fonts, a tight palette, precise spacing, real depth. No visual noise, no gratuitous gradients, no stock-illustration clutter.

---

## 4. Visual identity

### Aesthetic direction
**"Quiet luxury, alive at the edges."** Think Linear × Things × Apple's own apps. Near-monochrome, deep and soft, with a single luminous accent that comes to life during voice and key actions. Surfaces have gentle, physical depth (soft shadows, subtle translucency/blur on floating layers), never flat-and-cheap, never heavy-and-skeuomorphic. **Dark theme is primary** (it's an assistant you talk to at night and on the go); light theme is a first-class equal.

### Color
Define both themes. Use these as the intended system (adjust hexes to taste, keep the relationships).

**Dark (primary)**
- Background `#0B0B0F` · Surface `#15151C` · Elevated surface `#1E1E28` · Hairline/border `#2A2A34`
- Primary/Accent (iris) `#7C83FF` · Accent-pressed `#6A72F0`
- Secondary accent (warm gold, sparingly for streaks/highlights) `#F5C97B`
- Text primary `#F4F4F7` · Text secondary `#A2A2AE` · Text tertiary `#6E6E7A`
- Success `#5EEAD4` · Warning `#F5C97B` · Danger `#FF6B6B`

**Light**
- Background `#F6F6FA` · Surface `#FFFFFF` · Elevated `#FFFFFF` (with shadow) · Hairline `#E7E7EE`
- Primary/Accent `#5B5BE6` · Text primary `#14141A` · Text secondary `#5C5C67` · Tertiary `#9A9AA6`

**Signature gradient** (voice orb, hero moments only): iris → violet → soft magenta, e.g. `#7C83FF → #9B7BF6 → #C77BE0`, animated slowly.

### Typography
- **One brand sans across both platforms for consistency: Inter** (or Geist). Use platform metrics so it still feels native.
- Alternatively, honor the OS: **SF Pro (iOS) / Roboto (Android)** — acceptable, but keep the type scale identical.
- Scale (pt): Display 34/40 bold · Title 24/30 semibold · Headline 20/26 semibold · Body 16/24 regular · Callout 15/22 · Subhead 13/18 medium · Caption 12/16. Tabular figures for times/dates.
- Generous line-height, tight letter-spacing on large sizes. Never justify.

### Iconography
- **Lightweight line icons, ~1.75px stroke, rounded caps.** SF Symbols on iOS where possible; a matching rounded line set (e.g. Lucide/Phosphor) on Android. Consistent weight everywhere.
- App icon & brand mark: reference the **caduceus ☤ / winged messenger** motif abstractly — a single elegant glyph, not literal. Works as a monochrome silhouette and as a gradient badge.

### Depth & material
- Cards: `20px` radius, soft shadow (large blur, low opacity), 1px hairline in dark mode for definition.
- Floating layers (nav bar, sheets, voice controls): subtle **translucency + background blur** (frosted), like native system chrome.
- Buttons: pill (full radius) for primary actions; `14px` radius for secondary. 44–52px tall touch targets.

### Motion
- **Spring physics, not linear.** Screen transitions use the platform default (iOS push/slide, Android shared-axis/container-transform).
- Micro-interactions everywhere: press-scale on tap, streaming text with a soft caret, list items settle in with slight stagger.
- **Haptics**: light tick on send, on record start/stop, on task complete; success haptic on reminder set.
- The **voice orb** is the motion centerpiece (see Voice screen).

---

## 5. Platform adaptivity (must-do)

Design each screen twice where the platform differs:
- **Navigation:** iOS large-title nav bars, swipe-back, bottom tab bar with SF Symbols. Android Material 3 top app bars, system back, Material bottom nav / navigation bar, ripple.
- **Controls:** iOS switches/segmented controls/action sheets/context menus; Android Material switches/chips/bottom sheets/FAB.
- **Sheets:** iOS uses native detented sheets (grabber, rounded top). Android uses Material bottom sheets.
- **Empty inputs, keyboards, date pickers:** native pickers on each OS.
- **Typography metrics & status bar** respect the platform. Respect safe areas, dynamic island, gesture insets.

---

## 6. Information architecture

**Primary navigation: a bottom tab bar with 5 destinations**, plus a persistent way into Voice and Settings.

```
Bottom tabs:
  1. Today      (home/dashboard)
  2. Chat       (conversation)
  3. ◉ Voice    (center — elevated/emphasized: hands-free mode)
  4. Calendar   (events + scheduling)
  5. Inbox      (unified notifications, tasks, agent activity)

Global:
  - Profile/avatar (top-left or top-right) → Settings stack
  - Connection status pill (in nav/app bar)
  - Voice is also reachable via a mic control on Chat and Today
```

Full screen inventory below. Mark: **[v1]** ship-now, **[v2]** roadmap — design all, but note priority.

---

## 7. Screens — detailed specifications

For each screen provide: light + dark, iOS + Android, and the empty / loading / error states noted.

### 7.1 Splash / launch **[v1]**
- Minimal: centered brand glyph on the app background, subtle breathing/scale animation, then dissolve into the app. No spinner unless load exceeds ~600ms.

### 7.2 Onboarding & connection **[v1]** (3–4 steps, swipeable, with progress dots)
1. **Welcome** — one strong line ("Your own AI. Private. Always yours."), the brand glyph, "Get started."
2. **Connect** — enter **Server URL** and **API key** (the gateway address + token). Big, friendly inputs. A **"Test connection"** button with a live result state (spinner → ✓ Connected / ✗ with a helpful reason). Helper text explains this is their Tailscale address + gateway port. Optional QR-scan affordance to import config.
3. **Notifications** — set the **ntfy server + topic** for reminders/briefings; request OS notification permission with a clear rationale card.
4. **Permissions & ready** — request microphone (rationale: voice mode), then a celebratory "You're connected" with a subtle animation → into Today.
- States: connection failure inline (never a dead-end), skip-for-now where possible.

### 7.3 Today / Home dashboard **[v1 shell, v2 cards]**
The daily cockpit. Vertically scrolling cards on a calm background.
- **Header:** time-aware greeting ("Good evening, Rishit"), date, connection status pill, profile avatar → Settings. A large, tappable **"Ask Hermes"** affordance (tap = chat, hold mic = talk).
- **Daily briefing card** — a generated summary of the day (from the agent): weather line, "3 events, 2 tasks due," a one-paragraph brief. Tap to expand / hear it spoken (play button).
- **Up next** — the next 1–3 calendar events as compact rows (time, title, location, a colored calendar dot). Countdown to the next one.
- **Reminders & tasks due today** — checklist rows with swipe-to-complete.
- **Quick actions** — 3–4 chips/tiles: New reminder · Voice memo · Ask about my day · Add event.
- **Recent activity** — a peek at what the agent did lately (2 rows) → Inbox.
- States: first-run empty ("Nothing scheduled — ask me to set something up"), offline banner if the gateway is unreachable, skeleton loaders for cards.

### 7.4 Chat / Conversation **[v1]**
The core text+voice conversation.
- **Message list:** user bubbles (right, accent-tinted) and assistant messages (left, on surface). Assistant messages support **rich content**: markdown, code blocks (monospace, copyable), links, and **inline cards** when the agent returns structured results (an event it created, a task, a list). Streaming reply shows a soft animated caret. Timestamps on tap. Long-press → copy / share / "read aloud."
- **Tool activity inline:** when the agent is doing something (searching, checking calendar), show a compact, elegant "Hermes is checking your calendar…" chip that resolves into the result — makes the agent feel transparent and alive.
- **Input bar (floating, frosted):** expanding text field, **send** button, and a **mic button** that supports **hold-to-talk** (press-and-hold to record, release to send; slide-to-cancel). A **voice-reply toggle** (speaker on/off) so replies are spoken.
- **Top bar:** conversation title (auto-named), new-chat, history, and a segmented affordance to jump to full Voice mode.
- States: empty ("Ask me anything — or hold the mic"), listening (waveform in the input bar), transcribing ("…"), error (inline, retryable), offline.

### 7.5 Voice / Call mode **[v1 push-to-talk, v2 hands-free]** — the signature screen
A full-screen, immersive voice experience. This is where "premium" is won.
- **The orb:** a large, central, living **audio-reactive orb** (the signature gradient) that:
  - idles with a slow breathing motion,
  - **listens** — ripples/expands with the user's voice amplitude,
  - **thinks** — a gentle swirling/loading state,
  - **speaks** — pulses in sync with TTS output.
- **Live transcript:** the user's words and the assistant's reply stream as elegant captions beneath the orb (large, readable, auto-scrolling).
- **Controls (frosted bar):** mute, end, keyboard (drop to text), and a **mode switch**: **push-to-talk** vs **hands-free** (continuous, with barge-in — you can interrupt while it's speaking). Show which mode is active.
- **State clarity:** always show, in one word + the orb's behavior, whether it's *Listening / Thinking / Speaking / Idle*.
- Design the **hands-free "call" variant** (like a phone call: timer, big end button, backgroundable) and the **push-to-talk variant**.
- States: permission-needed, connecting, poor-connection, interrupted (barge-in).

### 7.6 Voice memo capture **[v2]**
Quick capture that the agent transcribes and files.
- Big record button, live waveform + timer, pause/stop. On stop: shows the transcript, lets the user send it as a note / task / calendar item, or into chat. "Saved" confirmation.

### 7.7 Calendar **[v2]**
- **Views:** an **Agenda/schedule list** (default, grouped by day) and a **Month** view with event dots; segmented control to switch. Today is anchored and quickly reachable.
- Event rows: time, title, location, calendar color, attendee avatars.
- **FAB / add:** create event — and a prominent **"Add with a sentence"** natural-language field ("Lunch with Sam tomorrow 1pm") that the agent parses.
- States: empty day, loading, not-connected-to-Google (a gentle "Connect Google Calendar" card).

### 7.8 Event detail / create-edit **[v2]**
- Detail: title, time, location (with map thumbnail), notes, attendees, calendar, reminders; actions: edit, delete, "ask Hermes about this."
- Create/Edit: native date/time pickers, all-day toggle, calendar picker, reminder offsets, attendees. Plus the natural-language quick-add at top.

### 7.9 Tasks / To-do **[v2]**
- Sectioned list (Today / Upcoming / Someday / Done), swipe-to-complete with a satisfying check animation + haptic, drag to reorder, due dates, priority accent. Add via input or voice. Empty state that invites voice capture.

### 7.10 Reminders **[v2]**
- Simple, time/location-based reminders list. Create flow with natural-language and native pickers. Ties into notifications.

### 7.11 Inbox / Activity (unified) **[v1 shell, v2 rich]**
A single feed that unifies: **proactive notifications, actionable items, and the agent's activity log**.
- Grouped by time (Today / Earlier). Item types with distinct but consistent styling:
  - **Notification** (a reminder/briefing that was pushed),
  - **Actionable** — has inline buttons ("Snooze," "Done," "Reschedule," "Reply"),
  - **Activity** — "Hermes ran your morning briefing," "Created event 'Dentist'."
- Unread indicators, swipe actions, filter chips (All / Actionable / Activity).
- States: empty ("You're all caught up"), loading skeleton.

### 7.12 Notification / actionable detail **[v2]**
- Full context of a pushed item with primary/secondary actions, and a "continue in chat" affordance.

### 7.13 Conversation history & search **[v1 list, v2 search]**
- **History:** list of past conversations (auto-titled, last message preview, timestamp), swipe to delete/rename, pinned favorites.
- **Search:** global search across conversations and messages, with recent + suggested queries; results grouped by conversation.

### 7.14 Settings (stack) **[v1]**
Root list (grouped, native inset style) → detail pages:
- **Connection** — server URL, API key (masked, reveal), test/health status, disconnect.
- **Voice** — STT engine, TTS voice (with **preview/play** per voice), auto-speak default, hands-free & **wake-word** toggle (v2), speaking rate.
- **Notifications** — ntfy server/topic, per-type toggles (briefings, reminders, activity), quiet hours.
- **Assistant** — model/provider info (read-only, from the gateway), memory/personalization hints.
- **Integrations** — Google Calendar connect/disconnect status.
- **Appearance** — theme (System / Light / Dark), accent color, text size.
- **About** — version, links, privacy note ("your data lives on your machine"), diagnostics/logs.
- Include the **profile/account** header (avatar, the connected server name) at the top of settings root.

### 7.15 Global states & system **[v1]**
Design these reusable states:
- **Offline / gateway unreachable** — a non-alarming top banner + a full-screen variant with retry.
- **Loading** — skeletons (never spinners for content), shimmer.
- **Empty** — friendly, with a clear primary action, often nudging voice.
- **Error** — inline, human-readable, retryable; never a raw stack trace.
- **Permission prompts** — pre-permission rationale cards before the OS dialog (mic, notifications).
- **Toasts/snackbars & haptics** for confirmations.

---

## 8. Component library (design as a system)
Deliver a components sheet: bottom tab bar (incl. the emphasized center Voice control), top/nav bars (iOS large title + Android app bar), buttons (primary pill, secondary, tertiary/text, destructive), input field & the floating chat composer, chips, list rows (with leading icon/avatar, trailing chevron/switch/value), cards (briefing, event, task, notification), the **voice orb** in all states, waveform, message bubbles + inline result cards, segmented control, sheets (iOS detented + Android), dialogs, snackbars/toasts, connection-status pill, avatars, skeletons, badges, the FAB (Android). Show light + dark for each.

## 9. Accessibility & quality bar
- WCAG AA contrast in both themes. Full Dynamic Type / font-scaling support (test at largest sizes). VoiceOver/TalkBack labels for all controls, especially the voice orb states. Minimum 44×44 targets. Reduced-motion variants for the orb and transitions. Never rely on color alone (pair with icon/label). RTL-safe layouts.

## 10. Deliverables
1. High-fidelity mockups for **every screen in §7**, in **light + dark**, for **iOS + Android** (call out where they diverge).
2. The **§8 component library** sheet.
3. The **voice orb** state study (idle/listening/thinking/speaking) with motion notes.
4. A one-page **style tile**: color, type scale, iconography, elevation, motion tokens.
5. Note **[v1] vs [v2]** on each screen so build can sequence.

**North star:** when someone opens this app, the first reaction should be *"this is beautiful, and it feels like it was made just for my phone."* When they hold the mic and it answers, it should feel *alive*.
