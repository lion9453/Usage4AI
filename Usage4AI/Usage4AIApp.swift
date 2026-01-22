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
        guard let usage = manager.usage else { return 0 }
        let util = usage.fiveHour.utilization
        // < 90% 無條件進位，>= 90% 無條件捨去
        if util < Constants.Usage.criticalThreshold {
            return Int(ceil(util))
        } else {
            return Int(floor(util))
        }
    }

    private var usageProgress: Double {
        min(1.0, Double(usagePercentage) / 100.0)
    }

    private var progressBarsImage: NSImage {
        let barWidth = Constants.MenuBar.barWidth
        let barHeight = Constants.MenuBar.barHeight
        let spacing = Constants.MenuBar.barSpacing
        let totalHeight = barHeight * 2 + spacing

        let image = NSImage(size: NSSize(width: barWidth, height: totalHeight), flipped: true) { rect in
            let cornerRadius = Constants.MenuBar.cornerRadius

            // 上層背景
            let topBgRect = NSRect(x: 0, y: 0, width: barWidth, height: barHeight)
            let topBgPath = NSBezierPath(roundedRect: topBgRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.setFill()
            topBgPath.fill()

            // 上層進度
            if self.usageProgress > 0 {
                let progressWidth = max(barWidth * self.usageProgress, cornerRadius * 2)
                let topProgressRect = NSRect(x: 0, y: 0, width: progressWidth, height: barHeight)
                let topProgressPath = NSBezierPath(roundedRect: topProgressRect, xRadius: cornerRadius, yRadius: cornerRadius)
                NSColor(self.manager.statusColor).setFill()
                topProgressPath.fill()
            }

            // 下層背景
            let bottomY = barHeight + spacing
            let bottomBgRect = NSRect(x: 0, y: bottomY, width: barWidth, height: barHeight)
            let bottomBgPath = NSBezierPath(roundedRect: bottomBgRect, xRadius: cornerRadius, yRadius: cornerRadius)
            NSColor.white.setFill()
            bottomBgPath.fill()

            // 下層進度（時間）
            if self.manager.timeProgress > 0 {
                let timeProgressWidth = max(barWidth * self.manager.timeProgress, cornerRadius * 2)
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
        HStack(spacing: 5) {
            Image(nsImage: progressBarsImage)

            Text("\(usagePercentage)%")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .frame(width: 28, alignment: .trailing)
        }
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
