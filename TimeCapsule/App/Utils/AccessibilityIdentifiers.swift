struct AccessibilityIdentifiers {
    struct CallScreen {
        static let recordButton = "call_screen_record_button"
        static let cancelButton = "call_screen_cancel_button"
        static let waveform = "call_screen_waveform"
        static let durationLabel = "call_screen_duration_label"
        static let statusLabel = "call_screen_status_label"
        static let permissionPrompt = "call_screen_permission_prompt"
        static let openSettingsButton = "call_screen_open_settings_button"
    }
    
    struct CapsuleList {
        static let list = "capsule_list"
        static let emptyState = "capsule_list_empty_state"
        static let loadingState = "capsule_list_loading"
        static let refreshControl = "capsule_list_refresh"
        static let deleteAlert = "capsule_delete_alert"
    }
    
    struct CapsuleRow {
        static let container = "capsule_row_container"
        static let statusIcon = "capsule_row_status_icon"
        static let transcription = "capsule_row_transcription"
        static let metadata = "capsule_row_metadata"
        static let actionButton = "capsule_row_action_button"
        static let retryButton = "capsule_row_retry_button"
        static let conversationButton = "capsule_row_conversation_button"
    }
    
    struct Chat {
        static let messageList = "chat_message_list"
        static let messageInput = "chat_message_input"
        static let sendButton = "chat_send_button"
        static let audioPlayButton = "chat_audio_play_button"
        static let typingIndicator = "chat_typing_indicator"
        static let timeLockBanner = "chat_time_lock_banner"
    }
    
    struct SignIn {
        static let container = "sign_in_container"
        static let appleSignInButton = "sign_in_apple_button"
        static let skipButton = "sign_in_skip_button"
        static let benefitsList = "sign_in_benefits_list"
    }
    
    struct Upload {
        static let progressView = "upload_progress_view"
        static let progressBar = "upload_progress_bar"
        static let progressLabel = "upload_progress_label"
    }
}

extension AccessibilityIdentifiers {
    static var allCallScreenIdentifiers: [String] {
        return [
            CallScreen.recordButton,
            CallScreen.cancelButton,
            CallScreen.waveform,
            CallScreen.durationLabel,
            CallScreen.statusLabel,
            CallScreen.permissionPrompt,
            CallScreen.openSettingsButton
        ]
    }
    
    static var allCapsuleListIdentifiers: [String] {
        return [
            CapsuleList.list,
            CapsuleList.emptyState,
            CapsuleList.loadingState,
            CapsuleList.refreshControl,
            CapsuleList.deleteAlert
        ]
    }
    
    static var allChatIdentifiers: [String] {
        return [
            Chat.messageList,
            Chat.messageInput,
            Chat.sendButton,
            Chat.audioPlayButton,
            Chat.typingIndicator,
            Chat.timeLockBanner
        ]
    }
    
    static var allIdentifiers: [String] {
        return allCallScreenIdentifiers + allCapsuleListIdentifiers + allChatIdentifiers + [
            SignIn.container,
            SignIn.appleSignInButton,
            SignIn.skipButton,
            SignIn.benefitsList,
            Upload.progressView,
            Upload.progressBar,
            Upload.progressLabel
        ]
    }
}