import SwiftUI
import AppKit

@main
struct Usage4AIApp: App {
    @StateObject private var usageManager = UsageManager()

    var body: some Scene {
        MenuBarExtra {
            UsageView(manager: usageManager)
        } label: {
            MenuBarLabel(manager: usageManager)
                .contextMenu {
                    Button("Refresh") {
                        Task { await usageManager.fetchUsage() }
                    }
                    .keyboardShortcut("r")

                    Divider()

                    Button("Settings...") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                    .keyboardShortcut(",")

                    Button("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q")
                }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(manager: usageManager)
        }
        .commands {
            UsageCommands(manager: usageManager)
        }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var manager: UsageManager

    private var usagePercentage: Int {
        guard let usage = manager.usage, let fiveHour = usage.fiveHour else { return 0 }
        let util = fiveHour.utilization
        // < 90% round up, >= 90% round down
        if util < Constants.Usage.criticalThreshold {
            return Int(ceil(util))
        } else {
            return Int(floor(util))
        }
    }

    private var usageProgress: Double {
        min(1.0, Double(usagePercentage) / 100.0)
    }

    var body: some View {
        HStack(spacing: 5) {
            MenuBarProgressBars(
                usageProgress: usageProgress,
                timeProgress: manager.timeProgress,
                statusColor: manager.statusColor
            )

            Text("\(usagePercentage)%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .frame(width: 28, alignment: .trailing)
        }
    }
}

/// Separate view for progress bars with equatable conformance to prevent unnecessary redraws
struct MenuBarProgressBars: View, Equatable {
    let usageProgress: Double
    let timeProgress: Double
    let statusColor: Color

    static func == (lhs: MenuBarProgressBars, rhs: MenuBarProgressBars) -> Bool {
        // Only redraw when values actually change (with small tolerance for floating point)
        abs(lhs.usageProgress - rhs.usageProgress) < 0.001 &&
        abs(lhs.timeProgress - rhs.timeProgress) < 0.001 &&
        lhs.statusColor == rhs.statusColor
    }

    private var progressBarsImage: NSImage {
        let barWidth = Constants.MenuBar.barWidth
        let barHeight = Constants.MenuBar.barHeight
        let spacing = Constants.MenuBar.barSpacing
        let totalHeight = barHeight * 2 + spacing

        let image = NSImage(size: NSSize(width: barWidth, height: totalHeight), flipped: true) { _ in
            let cornerRadius = Constants.MenuBar.cornerRadius

            // Top bar background
            let topBgRect = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
            let topBgPath = NSBezierPath(roundedRect: topBgRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.setFill()
            topBgPath.fill()

            // Top bar progress
            if self.usageProgress > 0 {
                let progressWidth = max(barWidth * self.usageProgress, cornerRadius * 2)
                let topProgressRect = NSRect(x: 0, y: 0, width: progressWidth, height: barHeight)
                let topProgressPath = NSBezierPath(roundedRect: topProgressRect, xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor(self.statusColor).setFill()
                topProgressPath.fill()
            }

            // Bottom bar background
            let bottomY = barHeight + spacing
            let bottomBgRect = NSRect(x: 0, y: bottomY, width: barWidth, height: barHeight)
            let bottomBgPath = NSBezierPath(roundedRect: bottomBgRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.setFill()
            bottomBgPath.fill()

            // Bottom bar progress (time)
            if self.timeProgress > 0 {
                let timeProgressWidth = max(barWidth * self.timeProgress, cornerRadius * 2)
                let bottomProgressRect = NSRect(x: 0, y: bottomY, width: timeProgressWidth, height: barHeight)
                let bottomProgressPath = NSBezierPath(roundedRect: bottomProgressRect, xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor.cyan.setFill()
                bottomProgressPath.fill()
            }

            return true
        }

        image.isTemplate = false
        return image
    }

    var body: some View {
        Image(nsImage: progressBarsImage)
    }
}

struct UsageCommands: Commands {
    let manager: UsageManager

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Refresh Usage") {
                Task {
                    await manager.fetchUsage()
                }
            }
            .keyboardShortcut("u", modifiers: [.command, .option])

            Divider()
        }
    }
}
