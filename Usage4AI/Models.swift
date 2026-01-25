import Foundation

enum APIError: Error, LocalizedError {
    case unauthorized           // 401
    case rateLimited            // 429
    case serverError(Int)       // 5xx
    case networkError(Error)    // 網路錯誤
    case invalidResponse        // 無效回應
    case decodingError(Error)   // JSON 解析失敗

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Token 無效或已過期，請重新授權"
        case .rateLimited:
            return "請求過於頻繁，請稍後再試"
        case .serverError(let code):
            return "伺服器錯誤 (\(code))，請稍後再試"
        case .networkError(let error):
            if (error as NSError).code == NSURLErrorTimedOut {
                return "連線逾時，請檢查網路連線"
            } else if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                return "無網路連線"
            }
            return "網路錯誤：\(error.localizedDescription)"
        case .invalidResponse:
            return "伺服器回應無效"
        case .decodingError:
            return "資料格式錯誤"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .rateLimited, .serverError, .networkError:
            return true
        case .unauthorized, .invalidResponse, .decodingError:
            return false
        }
    }
}

struct UsageResponse: Codable {
    let fiveHour: UsageLimit?
    let sevenDay: UsageLimit?
    let sevenDayOpus: UsageLimit?
    let sevenDaySonnet: UsageLimit?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageLimit: Codable {
    /// API 回傳的 utilization 是百分比 (0-100)，不是小數
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    init(utilization: Double, resetsAt: String?) {
        self.utilization = min(max(utilization, 0), 100)
        self.resetsAt = resetsAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawUtilization = try container.decode(Double.self, forKey: .utilization)
        self.utilization = min(max(rawUtilization, 0), 100)
        self.resetsAt = try container.decodeIfPresent(String.self, forKey: .resetsAt)
    }
}

struct DisplayUsage {
    let name: String
    let icon: String
    let percentage: Int
    let remainingTime: String
    let status: UsageStatus
    let timeProgress: Double  // 0.0 = 剛開始, 1.0 = 即將重置

    init(name: String, icon: String, limit: UsageLimit) {
        self.name = name
        self.icon = icon
        self.percentage = Int(limit.utilization)
        if let resetsAt = limit.resetsAt {
            let (timeStr, progress) = DisplayUsage.parseResetTime(from: resetsAt, windowHours: name.contains("5-Hour") ? 5 : 168)
            self.remainingTime = timeStr
            self.timeProgress = progress
        } else {
            self.remainingTime = "--"
            self.timeProgress = 0.0
        }
        self.status = UsageStatus.from(percentage: limit.utilization)
    }

    private static func parseResetTime(from isoString: String, windowHours: Int) -> (String, Double) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var resetDate: Date?
        resetDate = formatter.date(from: isoString)

        if resetDate == nil {
            formatter.formatOptions = [.withInternetDateTime]
            resetDate = formatter.date(from: isoString)
        }

        guard let date = resetDate else { return ("--", 0.0) }

        let now = Date()
        let interval = date.timeIntervalSince(now)

        if interval <= 0 { return ("now", 1.0) }

        // 計算時間進度 (越接近重置時間，進度越高)
        let totalSeconds = Double(windowHours * 3600)
        let elapsedSeconds = totalSeconds - interval
        let progress = min(1.0, max(0.0, elapsedSeconds / totalSeconds))

        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600
        let minutes = (Int(interval) % 3600) / 60

        let timeStr: String
        if days > 0 {
            timeStr = "\(days)d \(hours)h"
        } else if hours > 0 {
            timeStr = "\(hours)h \(minutes)m"
        } else {
            timeStr = "\(minutes)m"
        }

        return (timeStr, progress)
    }
}

enum UsageStatus {
    case normal
    case warning
    case critical
    case exhausted

    static func from(percentage: Double) -> UsageStatus {
        if percentage >= 100 {
            return .exhausted
        } else if percentage > Constants.Usage.warningThreshold {
            return .critical
        } else if percentage >= Constants.Usage.normalThreshold {
            return .warning
        } else {
            return .normal
        }
    }

    var color: String {
        switch self {
        case .normal: return "green"
        case .warning: return "yellow"
        case .critical: return "red"
        case .exhausted: return "gray"
        }
    }
}
