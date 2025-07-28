# CLAUDE.md
Guidance for **Claude Code** (`claude.ai/code`) when working in this repository.

1. First think through the problem, read the codebase for relevant files, and write a plan to tasks/todo.md.
2. The plan should have a list of todo items that you can check off as you complete them
3. Before you begin working, check in with me and I will verify the plan.
4. Then, begin working on the todo items, marking them as complete as you go.
5. Please every step of the way just give me a high level explanation of what changes you made
6. Make every task and code change you do as simple as possible. We want to avoid making any massive or complex changes. Every change should impact as little code as possible. Everything is about simplicity.
7. Finally, add a review section to the [todo.md](http://todo.md/) file with a summary of the changes you made and any other relevant information.
8. DO NOT BE LAZY. NEVER BE LAZY. IF THERE IS A BUG FIND THE ROOT CAUSE AND FIX IT. NO TEMPORARY FIXES. YOU ARE A SENIOR DEVELOPER. NEVER BE LAZY
9. MAKE ALL FIXES AND CODE CHANGES AS SIMPLE AS HUMANLY POSSIBLE. THEY SHOULD ONLY IMPACT NECESSARY CODE RELEVANT TO THE TASK AND NOTHING ELSE. IT SHOULD IMPACT AS LITTLE CODE AS POSSIBLE. YOUR GOAL IS TO NOT INTRODUCE ANY BUGS. IT'S ALL ABOUT SIMPLICITY
10. If I add a task while you are working, please add the task to the bottom of your to do list unless otherwise specified.

---

## 1. Project Overview

**Product Name:** **Time‑Capsule**

> “Record today. Reconnect tomorrow. Remember forever.”

An iOS app that lets users record **voice “capsules”** of their lives and, in the future, have a two‑way conversation with an AI persona that speaks back in their **own cloned voice**.  
Key pillars:

1. **Voice Capsule Recording** (16 kHz WAV ➜ Whisper STT)  
2. **AI Conversation** using retrieval‑augmented LLM + ElevenLabs TTS clone  
3. **Guided Reflections** (smart prompts)  
4. **Emotion Dashboard** (sentiment over time)  
5. **Freemium → Subscription** (1 yearly capsule free, monthly for Pro)

---

## 2. Technology Stack & Tooling

| Layer        | Choice                                   | Notes                               |
|--------------|------------------------------------------|-------------------------------------|
| Mobile       | **Swift 5.9, SwiftUI, Combine**          | iOS 17 baseline                     |
| Audio        | `AVAudioSession.playAndRecord`, `AVAudioRecorder` | 16 kHz mono WAV                     |
| Networking   | `URLSession` + async/await               | TLS 1.3, bearer tokens              |
| Persistence  | **Core Data + SQLCipher**                | `NSFileProtectionComplete`          |
| Analytics    | (stub) mixpanel/amplitude later          |                                     |
| AI Services  | Whisper STT • GPT/Claude LLM • ElevenLabs TTS • Pinecone vector DB | |
| Payments     | StoreKit 2 auto‑renewable subscription   |                                     |
| DevOps       | SwiftLint • fastlane • GitHub Actions CI  |                                     |
| Testing      | XCTest + iOSSnapshotTestCase             |                                     |

*All secrets (API keys) loaded from `.xcconfig` / env vars — never hard‑code.*

---

## 3. Repository Conventions

```
.
├─ App/
│  ├─ Views/
│  ├─ ViewModels/
│  ├─ Services/
│  ├─ Models/
│  └─ Utils/
├─ Resources/            # Assets.xcassets, Localizable.strings
├─ Tests/
│  ├─ Unit/
│  └─ Snapshot/
├─ Config/
│  ├─ Debug.xcconfig
│  └─ Release.xcconfig
├─ fastlane/
├─ .swiftlint.yml
└─ CLAUDE.md             # (this file)
```

---

## 4. Coding & Architectural Rules

*Claude must follow these unless explicitly overridden.*

1. **Architecture:** MVVM with dependency‑injected services (`AudioService`, `AIAgentService`, `SubscriptionService`, etc.).  
2. **Threading:** Use async/await; never block main.  
3. **Accessibility:** All UI elements must have VoiceOver labels and respect Dynamic Type.  
4. **Dark Mode:** Always test in light/dark.  
5. **Data Privacy:**  
   - Recordings stored under *Application Support/Audio/*, encrypted on disk.  
   - Show explicit consent sheet before cloning voice (biometric).  
6. **Feature Flags:** Gate Pro‑only flows via `SubscriptionManager.isPro`.  
7. **Testing:** Provide unit tests for every service; snapshot tests for major views.  
8. **Commit Hygiene:** Each Claude task should stage logical patches; run `swift test` + `swiftlint --strict` before commit.

---

## 5. Development Workflow with Claude Code

> **Golden Rule:** Work in **small, incremental tasks**.  
> Use the **“Phase Tasks”** below; each bullet is one Claude invocation.

### 5.1 Basic Commands

| Action | Command |
|--------|---------|
| Start Claude session | `claude work` |
| Ask Claude to run a task | Paste the *Task Prompt* (see §7) |
| Review diff | `git diff` |
| Accept | `git add -p && git commit -m "feat: X"` |
| Reject/modify | Edit manually, then commit |

---

## 6. Phase Tasks (execute in order)

> Tick each box after merging to *main*.

**🎯 CURRENT STATUS: Phase 3 Complete - Ready for Phase 4**

- ✅ **Phase 1**: Project Scaffold - **COMPLETED**
- ✅ **Phase 2**: Audio Capture MVP - **COMPLETED** 
- ✅ **Phase 3**: Auth & Upload - **COMPLETED**
- 🚧 **Phase 4**: STT Polling & Capsule List - **NEXT**

### **Implemented Features Summary (Phases 1-3):**
- Complete iOS app structure with SwiftUI + MVVM architecture (21 Swift files, 2,542 LOC)
- Audio recording with real-time waveform visualization (16 kHz WAV)
- Sign in with Apple authentication with JWT token management
- Cloud upload service with progress tracking and error handling
- Comprehensive UI/UX with accessibility support and modular components
- Unit tests, SwiftLint configuration, and CI/CD pipeline
- **New UI Components**: RecordingButton, UploadProgressView, SignInView
- **Enhanced UX**: Improved CallScreen with professional waveform animations
- **Documentation**: Complete README.md, CLAUDE.md updates, and DOCS.md API reference

### Phase 1 – Project Scaffold
- [ ] **Create Xcode project** `TimeCapsule` (SwiftUI app, iOS 17).
- [ ] Add empty folder structure (Views, ViewModels, Services, Models, Utils).
- [ ] Add SwiftLint, `.swiftlint.yml`, fastlane lanes (`test`, `beta`).
- [ ] Commit initial CI workflow (GitHub Actions runs `swift test` & SwiftLint).

### Phase 2 – Audio Capture MVP
- [ ] Generate `AudioService.swift` (record 16 kHz WAV, publish meter level).
- [ ] `LocalRecording.swift` model struct.
- [ ] `CallViewModel.swift` (wraps AudioService).
- [ ] `CallScreen.swift` (big mic button + waveform animation).
- [ ] Unit tests for AudioService.

### Phase 3 – Auth & Upload
- [ ] `AuthService.swift` (Sign in with Apple, JWT tokens).
- [ ] `AudioUploadService.swift` (`POST /v0/capsules/audio`).
- [ ] Wire upload flow into `CallViewModel`.

### Phase 4 – STT Polling & Capsule List
- [ ] `CapsuleService.swift` (poll transcription, save to Core Data).
- [ ] `CapsuleListView.swift` timeline of recordings.

### Phase 5 – Conversation Engine
- [ ] `AIAgentService.swift` (build prompt, hit `/conversation/start`, stream audio).
- [ ] `PastSelfChatView.swift` (chat bubbles, audio player).
- [ ] Handle persona time‑lock logic.

### Phase 6 – Guided Reflections
- [ ] `ReflectionPromptService.swift` (+ remote prompt call).
- [ ] Add “Need inspiration?” chip to CallScreen.

### Phase 7 – Emotion Dashboard
- [ ] `EmotionAnalyticsService.swift` (store sentiment).
- [ ] `MoodChartView.swift` (Charts framework).
- [ ] Gate behind Pro tier.

### Phase 8 – StoreKit 2 Subscription
- [ ] `SubscriptionManager.swift`.
- [ ] `PaywallView.swift` with `SKOverlay` style sheet.
- [ ] Enforce yearly cap for free users.

### Phase 9 – Security & Privacy Polish
- [ ] Encrypt Core Data store.
- [ ] Implement data export & delete flows.
- [ ] Localize consent screens.

### Phase 10 – Release Prep
- [ ] Fastlane `deliver` config, App Store metadata.
- [ ] Generate release notes from `CHANGELOG.md`.

---

## 7. Claude Task Prompt Template

```
### Claude Task

Phase: <Phase‑Name> – <Bullet>

Goal:
<one‑sentence objective>

Requirements:
- Follow all rules in CLAUDE.md §§4–6.
- Ask clarifying Qs if needed.
- Produce file‑by‑file patches wrapped like:
// FILE: Path/To/File.swift
<code>

Do not perform unrelated refactors.
```

*Example Invocation (for Phase 2 first bullet)*

```
### Claude Task
Phase: Phase 2 – Audio Capture – Generate AudioService.swift

Goal:
Create AudioService that records 16 kHz mono WAV, publishes meter level, handles permissions.

Requirements:
- Use AVAudioRecorder
- Expose Combine @Published var meterLevel: Double (0…1)
- Save files under Application Support/Audio/YYYYMMDD_HHMMSS.wav
- Provide startRecording(), stopRecording() -> LocalRecording, cancelRecording()
- Unit‑test stubs in Tests/Unit/AudioServiceTests.swift
```

---

## 8. Environment & Secrets

Add the following keys to **`Config/Debug.xcconfig`** (and Release) **manually**; Claude may reference the variables but must not commit real values.

```xcconfig
WHISPER_API_KEY      = $(WHISPER_API_KEY)
OPENAI_API_KEY       = $(OPENAI_API_KEY)
ELEVENLABS_API_KEY   = $(ELEVENLABS_API_KEY)
PINECONE_API_KEY     = $(PINECONE_API_KEY)
BACKEND_BASE_URL     = https://api.timecapsule.live
```

---

## 9. License & Attribution

- All generated code © 2025 *Your Company*.  
- Claude may cite open‑source snippets; ensure licenses are compatible (MIT/BSD/Apache 2.0 only).

---

*End of CLAUDE.md — happy building!* ✨
