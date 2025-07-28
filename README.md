# TimeCapsule

> "Record today. Reconnect tomorrow. Remember forever."

TimeCapsule is an innovative iOS app that lets users record voice capsules of their lives and, in the future, have two-way conversations with an AI persona that speaks back in their own cloned voice.

## Features

### ✅ Completed (Phases 1-3)

- **🎙️ Audio Recording**: High-quality 16 kHz mono WAV recording with real-time waveform visualization
- **🔐 Authentication**: Secure Sign in with Apple integration with JWT token management  
- **☁️ Cloud Upload**: Seamless audio upload with progress tracking and error handling
- **📱 Beautiful UI**: Modern SwiftUI interface with accessibility support and Dynamic Type
- **🔒 Security**: Keychain-based token storage and encrypted data transmission
- **🎨 UI Components**: Modular design with reusable components (RecordingButton, UploadProgressView, etc.)
- **♿ Accessibility**: Comprehensive VoiceOver support with accessibility identifiers

### 🚧 In Development (Future Phases)

- **📝 Speech-to-Text**: Automatic transcription using Whisper
- **🤖 AI Conversations**: Chat with your past self using LLM + voice cloning
- **💡 Guided Reflections**: Smart prompts for meaningful recordings
- **📊 Emotion Dashboard**: Sentiment analysis and mood tracking over time
- **💰 Subscription Model**: Freemium with Pro features

## Architecture

TimeCapsule follows a clean MVVM architecture with dependency injection:

```
TimeCapsule/
├── App/
│   ├── Views/           # SwiftUI views and components
│   ├── ViewModels/      # MVVM view models with Combine
│   ├── Services/        # Business logic and API layer
│   ├── Models/          # Data models and entities
│   └── Utils/           # Helpers and extensions
├── Resources/           # Assets and localization
├── Tests/
│   ├── Unit/           # Unit tests for services
│   └── Snapshot/       # UI snapshot tests
├── Config/             # Xcode configuration files
└── fastlane/           # Deployment automation
```

### Key Components

- **AudioService**: Handles recording with AVFoundation (291 LOC)
- **AuthService**: Manages Sign in with Apple and JWT tokens (243 LOC)
- **NetworkService**: Generic HTTP client with authentication (143 LOC)
- **AudioUploadService**: Multi-part file upload with progress (165 LOC)
- **CallViewModel**: Main recording interface logic (291 LOC)
- **CallScreen**: Primary recording UI with waveform visualization (461 LOC)
- **SignInView**: Sign in with Apple interface (127 LOC)

**Total Codebase**: ~2,542 lines of Swift code across 21 files

## Getting Started

### Prerequisites

- Xcode 15.0+
- iOS 17.0+ deployment target
- Apple Developer account (for Sign in with Apple)

### Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/your-username/timecapsule.git
   cd timecapsule
   ```

2. **Install dependencies**
   ```bash
   # Install SwiftLint (if not already installed)
   brew install swiftlint
   
   # Install fastlane (optional, for deployment)
   gem install fastlane
   ```

3. **Configure environment variables**
   
   Update `Config/Debug.xcconfig` and `Config/Release.xcconfig` with your API keys:
   ```
   WHISPER_API_KEY = your_whisper_key
   OPENAI_API_KEY = your_openai_key
   ELEVENLABS_API_KEY = your_elevenlabs_key
   PINECONE_API_KEY = your_pinecone_key
   BACKEND_BASE_URL = https://api.timecapsule.live
   ```

4. **Open in Xcode**
   ```bash
   open TimeCapsule.xcodeproj
   ```

5. **Build and run**
   - Select your target device/simulator
   - Press `Cmd+R` to build and run

## Development

### Build Commands

```bash
# Build the project
xcodebuild -project TimeCapsule.xcodeproj -scheme TimeCapsule build

# Run tests
xcodebuild test -project TimeCapsule.xcodeproj -scheme TimeCapsule -destination 'platform=iOS Simulator,name=iPhone 15'

# Lint code
swiftlint lint --strict

# Run fastlane tests
fastlane test
```

### Code Quality

- **SwiftLint**: Enforces Swift style guidelines
- **Unit Tests**: Services are fully unit tested
- **Accessibility**: Full VoiceOver support with proper labels
- **Security**: No hardcoded secrets, proper keychain usage

### Git Workflow

The project uses GitHub Actions for CI/CD:

- **Pull Requests**: Automatically run tests and linting
- **Main Branch**: Protected, requires PR reviews
- **Releases**: Automated via fastlane + TestFlight

## Technology Stack

| Layer | Technology | Purpose |
|-------|------------|---------|
| **UI** | SwiftUI, Combine | Reactive user interface |
| **Audio** | AVFoundation | Recording and playback |
| **Auth** | AuthenticationServices | Sign in with Apple |
| **Network** | URLSession | HTTP client with auth |
| **Storage** | Core Data, Keychain | Local data and security |
| **Testing** | XCTest | Unit and UI testing |
| **CI/CD** | GitHub Actions, fastlane | Automation |

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Make your changes and add tests
4. Ensure all tests pass: `xcodebuild test`
5. Run linting: `swiftlint lint --strict`
6. Commit your changes: `git commit -m 'Add amazing feature'`
7. Push to the branch: `git push origin feature/amazing-feature`
8. Open a Pull Request

## Privacy & Security

TimeCapsule takes privacy seriously:

- **Local First**: Audio files are processed locally when possible
- **Encrypted Storage**: All sensitive data is encrypted
- **Minimal Data**: Only necessary information is collected
- **User Control**: Users can delete their data at any time
- **Secure Transit**: All network requests use TLS 1.3

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Support

- **Issues**: [GitHub Issues](https://github.com/your-username/timecapsule/issues)
- **Discussions**: [GitHub Discussions](https://github.com/your-username/timecapsule/discussions)
- **Email**: support@timecapsule.app

---

**TimeCapsule** - Preserve your voice, preserve your story. 🎙️✨