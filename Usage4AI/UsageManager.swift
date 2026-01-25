import Foundation
import SwiftUI
import Combine
import UserNotifications
import Network

@MainActor
class UsageManager: ObservableObject {
    @Published var usage: UsageResponse? {
        didSet {
            invalidateCache()
            checkUsageNotification()
        }
    }
    @Published var isLoading: Bool = false
    @Published var lastError: Error?
    @Published var lastUpdated: Date?
    @Published var isNetworkAvailable: Bool = true

    @AppStorage("refreshInterval") var refreshInterval: Int = 60
    @AppStorage("notificationsEnabled") var notificationsEnabled: Bool = true

    private var timer: Timer?
    private let apiURL = URL(string: Constants.API.usageURL)!
    private var appStateObservers: [Any] = []
    private var hasNotifiedCritical = false
    private var lastNotifiedPercentage: Int = 0

    // 快取
    private var cachedAllDisplayUsages: [DisplayUsage]?
    private var cachedMaxDisplayUsage: DisplayUsage?
    private var cachedToken: String?

    // 網路監控
    private let networkMonitor = NWPathMonitor()
    private let networkQueue = DispatchQueue(label: "NetworkMonitor")
    private var wasNetworkUnavailable = false

    // 重試機制
    private var retryCount = 0
    private let maxRetryCount = 3
    private var retryTask: Task<Void, Never>?

    init() {
        // 啟動時讀取一次 token，避免每次刷新都存取 Keychain
        do {
            cachedToken = try KeychainHelper.getOAuthToken()
        } catch {
            cachedToken = nil
        }
        setupAppStateObservers()
        setupNetworkMonitor()
        requestNotificationPermission()
        startTimer()
        Task {
            await fetchUsage()
        }
    }

    private func setupNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                let isAvailable = path.status == .satisfied
                let wasUnavailable = self.wasNetworkUnavailable

                self.isNetworkAvailable = isAvailable
                self.wasNetworkUnavailable = !isAvailable

                // 網路恢復時自動重新整理
                if isAvailable && wasUnavailable {
                    self.retryCount = 0  // 重置重試計數
                    await self.fetchUsage()
                }
            }
        }
        networkMonitor.start(queue: networkQueue)
    }

    deinit {
        timer?.invalidate()
        timer = nil
        retryTask?.cancel()
        retryTask = nil
        networkMonitor.cancel()
        for observer in appStateObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupAppStateObservers() {
        let activateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.startTimer()
                await self?.fetchUsage()
            }
        }

        let resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.stopTimer()
            }
        }

        appStateObservers = [activateObserver, resignObserver]
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func invalidateCache() {
        cachedAllDisplayUsages = nil
        cachedMaxDisplayUsage = nil
    }

    func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.fetchUsage()
            }
        }
    }

    func updateRefreshInterval(_ interval: Int) {
        refreshInterval = interval
        startTimer()
    }

    func fetchUsage() async {
        // 取消任何正在進行的重試
        retryTask?.cancel()
        retryTask = nil

        await performFetch()
    }

    private func performFetch(isRetry: Bool = false) async {
        isLoading = true
        defer { isLoading = false }

        do {
            // 使用快取的 token，如果沒有則嘗試從 Keychain 讀取
            if cachedToken == nil {
                refreshToken()
            }

            guard let token = cachedToken else {
                throw APIError.unauthorized
            }

            var request = URLRequest(url: apiURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue(Constants.API.betaHeader, forHTTPHeaderField: "anthropic-beta")
            request.setValue("\(Constants.App.name)/\(Constants.App.version)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 30

            let data: Data
            let response: URLResponse

            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw APIError.networkError(error)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            switch httpResponse.statusCode {
            case 200:
                break
            case 401:
                // Token 失效，清除快取
                cachedToken = nil
                KeychainHelper.clearCachedToken()

                // 如果不是重試，嘗試從 Claude Code Keychain 重新讀取 token 並重試一次
                if !isRetry {
                    refreshToken()
                    if cachedToken != nil {
                        await performFetch(isRetry: true)
                        return
                    }
                }
                throw APIError.unauthorized
            case 429:
                throw APIError.rateLimited
            case 500...599:
                throw APIError.serverError(httpResponse.statusCode)
            default:
                throw APIError.invalidResponse
            }

            do {
                let decoder = JSONDecoder()
                usage = try decoder.decode(UsageResponse.self, from: data)
            } catch {
                throw APIError.decodingError(error)
            }

            lastUpdated = Date()
            lastError = nil
            retryCount = 0  // 成功後重置重試計數
        } catch let error as APIError {
            lastError = error
            scheduleRetryIfNeeded(for: error)
        } catch {
            let apiError = APIError.networkError(error)
            lastError = apiError
            scheduleRetryIfNeeded(for: apiError)
        }
    }

    private func scheduleRetryIfNeeded(for error: APIError) {
        guard error.isRetryable else { return }
        guard retryCount < maxRetryCount else {
            retryCount = 0  // 達到最大重試次數後重置
            return
        }

        retryCount += 1

        // 指數退避：2^retryCount 秒 (2s, 4s, 8s)
        let delay = pow(2.0, Double(retryCount))

        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self?.performFetch()
            } catch {
                // Task 被取消
            }
        }
    }

    /// 手動刷新 token（需要時才呼叫）
    func refreshToken() {
        do {
            cachedToken = try KeychainHelper.getOAuthToken()
        } catch {
            cachedToken = nil
        }
    }

    var timeProgress: Double {
        guard let usage = usage, let fiveHour = usage.fiveHour else { return 0.0 }
        let fiveHourUsage = DisplayUsage(name: "5-Hour Session", icon: "clock", limit: fiveHour)
        return fiveHourUsage.timeProgress
    }

    var maxDisplayUsage: DisplayUsage {
        if let cached = cachedMaxDisplayUsage {
            return cached
        }

        guard usage != nil else {
            return DisplayUsage(name: "Unknown", icon: "?", limit: UsageLimit(utilization: 0, resetsAt: ""))
        }

        let allUsages = allDisplayUsages
        let result = allUsages.max(by: { $0.percentage < $1.percentage }) ?? allUsages.first!
        cachedMaxDisplayUsage = result
        return result
    }

    var usageStatus: UsageStatus {
        guard let usage = usage, let fiveHour = usage.fiveHour else { return .normal }
        let fiveHourUsage = DisplayUsage(name: "5-Hour Session", icon: "clock", limit: fiveHour)
        return fiveHourUsage.status
    }

    var statusColor: Color {
        switch usageStatus {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        case .exhausted: return .gray
        }
    }

    var allDisplayUsages: [DisplayUsage] {
        if let cached = cachedAllDisplayUsages {
            return cached
        }

        guard let usage = usage else { return [] }

        var usages: [DisplayUsage] = []

        if let fiveHour = usage.fiveHour {
            usages.append(DisplayUsage(name: "5-Hour Session", icon: "clock", limit: fiveHour))
        }

        if let sevenDay = usage.sevenDay {
            usages.append(DisplayUsage(name: "Weekly Limit", icon: "calendar", limit: sevenDay))
        }

        if let opus = usage.sevenDayOpus {
            usages.append(DisplayUsage(name: "Opus Only", icon: "target", limit: opus))
        }

        if let sonnet = usage.sevenDaySonnet {
            usages.append(DisplayUsage(name: "Sonnet Only", icon: "bolt", limit: sonnet))
        }

        cachedAllDisplayUsages = usages
        return usages
    }

    var lastUpdatedText: String {
        guard let lastUpdated = lastUpdated else { return "Never" }

        let interval = Date().timeIntervalSince(lastUpdated)

        if interval < 60 {
            return "\(Int(interval))s ago"
        } else {
            return "\(Int(interval / 60))m ago"
        }
    }

    // MARK: - 通知

    func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func checkUsageNotification() {
        guard notificationsEnabled else { return }
        guard usage != nil else { return }

        let maxUsage = maxDisplayUsage
        guard maxUsage.percentage >= Int(Constants.Usage.criticalThreshold) else {
            hasNotifiedCritical = false
            lastNotifiedPercentage = maxUsage.percentage
            return
        }

        // 只在首次達到 90% 或每增加 5% 時通知
        let shouldNotify = !hasNotifiedCritical ||
            (maxUsage.percentage >= lastNotifiedPercentage + 5)

        guard shouldNotify else { return }

        hasNotifiedCritical = true
        lastNotifiedPercentage = maxUsage.percentage

        sendNotification(for: maxUsage)
    }

    private func sendNotification(for usage: DisplayUsage) {
        let content = UNMutableNotificationContent()
        content.title = "⚠️ Claude 用量警告"
        content.body = "\(usage.name) 已使用 \(usage.percentage)%，將在 \(usage.remainingTime) 後重置"
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "usage-warning-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }
}
