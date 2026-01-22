import Foundation
import CoreGraphics

enum Constants {
    enum App {
        static let version = "0.1.4"
        static let name = "Usage4AI"
    }

    enum Usage {
        static let criticalThreshold: Double = 90
        static let warningThreshold: Double = 80
        static let normalThreshold: Double = 50
    }

    enum RefreshInterval {
        static let options: [(value: Int, shortLabel: String, longLabel: String)] = [
            (30, "30s", "30 seconds"),
            (60, "1m", "1 minute"),
            (120, "2m", "2 minutes"),
            (300, "5m", "5 minutes"),
            (600, "10m", "10 minutes")
        ]
        static let defaultValue = 60
    }

    enum MenuBar {
        static let barWidth: CGFloat = 20
        static let barHeight: CGFloat = 5
        static let barSpacing: CGFloat = 2
        static let cornerRadius: CGFloat = 2
    }

    enum API {
        static let usageURL = "https://api.anthropic.com/api/oauth/usage"
        static let betaHeader = "oauth-2025-04-20"
    }

    enum TimeWindow {
        static let fiveHourSeconds = 5 * 3600
        static let sevenDaySeconds = 168 * 3600
    }
}
