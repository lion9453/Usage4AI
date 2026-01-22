import SwiftUI

struct UsageView: View {
    @ObservedObject var manager: UsageManager
    @State private var isRefreshing = false
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showSettings {
                // Settings view
                HStack {
                    Button(action: { showSettings = false }) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    Text("Settings")
                        .font(.headline)
                    Spacer()
                }
                .padding(.bottom, 4)

                Divider()

                SettingsView(manager: manager, inline: true)

                Divider()

                HStack {
                    Spacer()
                    Button("Back") { showSettings = false }
                        .buttonStyle(.borderless)
                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderless)
                }
            } else {
                // Usage view
                HStack(alignment: .center) {
                    Text("Usage4AI")
                        .font(.headline)
                    Spacer()
                    if manager.usage != nil {
                        Text("Max: \(manager.maxDisplayUsage.percentage)%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.bottom, 4)

                Divider()

                if manager.isLoading && manager.usage == nil {
                    HStack {
                        Spacer()
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                } else if let error = manager.lastError, manager.usage == nil {
                    ErrorView(error: error) {
                        Task {
                            await manager.fetchUsage()
                        }
                    }
                } else {
                    ForEach(manager.allDisplayUsages, id: \.name) { usage in
                        UsageLimitRow(usage: usage)
                    }
                }

                Divider()

                // 顯示錯誤（即使有舊資料）
                if let error = manager.lastError {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error.localizedDescription)
                            .foregroundColor(.orange)
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }

                HStack(alignment: .center) {
                    Text("Updated \(manager.lastUpdatedText)")
                        .font(.caption)
                        .foregroundColor(manager.lastError != nil ? .orange : .secondary)

                    Spacer()

                    Button(action: {
                        withAnimation(.linear(duration: 0.5).repeatCount(3, autoreverses: false)) {
                            isRefreshing = true
                        }
                        Task {
                            await manager.fetchUsage()
                            isRefreshing = false
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    }
                    .buttonStyle(.borderless)
                    .disabled(manager.isLoading)
                }

                Divider()

                HStack {
                    Text("Version: \(Constants.App.version)")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button("Settings") { showSettings = true }
                        .buttonStyle(.borderless)

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding()
        .frame(width: 280)
    }
}

struct ErrorView: View {
    let error: Error
    let onRetry: () -> Void

    private var apiError: APIError? {
        error as? APIError
    }

    private var errorIcon: String {
        guard let apiError = apiError else { return "exclamationmark.triangle" }
        switch apiError {
        case .unauthorized:
            return "key.slash"
        case .rateLimited:
            return "clock.badge.exclamationmark"
        case .serverError:
            return "server.rack"
        case .networkError:
            return "wifi.slash"
        case .invalidResponse, .decodingError:
            return "doc.questionmark"
        }
    }

    private var errorColor: Color {
        guard let apiError = apiError else { return .orange }
        switch apiError {
        case .unauthorized:
            return .red
        case .rateLimited:
            return .yellow
        case .serverError, .networkError:
            return .orange
        case .invalidResponse, .decodingError:
            return .purple
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: errorIcon)
                .font(.title2)
                .foregroundColor(errorColor)

            Text("Failed to load")
                .font(.caption)
                .fontWeight(.medium)

            Text(error.localizedDescription)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)

            if apiError?.isRetryable ?? true {
                Button(action: onRetry) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.clockwise")
                        Text("Retry")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

struct UsageLimitRow: View {
    let usage: DisplayUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Image(systemName: iconName)
                    .foregroundColor(.secondary)
                    .frame(width: 16, alignment: .center)
                Text(usage.name)
                    .font(.subheadline)
                Spacer()
                Text("\(usage.percentage)%")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(progressColor)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 8)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(progressColor)
                        .frame(width: geometry.size.width * CGFloat(usage.percentage) / 100, height: 8)
                }
            }
            .frame(height: 8)

            HStack(spacing: 0) {
                Text("Resets in: ")
                    .foregroundColor(.secondary)
                Text(usage.remainingTime)
                    .fontWeight(.semibold)
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch usage.icon {
        case "clock": return "clock"
        case "calendar": return "calendar"
        case "target": return "target"
        default: return "circle"
        }
    }

    private var progressColor: Color {
        switch usage.status {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .exhausted: return .gray
        }
    }
}

// Preview requires Xcode
// #Preview {
//     UsageView(manager: UsageManager())
// }
