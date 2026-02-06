import SwiftUI

enum PanelTab: String, CaseIterable {
    case sessions = "Sessions"
    case analytics = "Analytics"
    case prs = "PRs"

    var icon: String {
        switch self {
        case .sessions: return "rectangle.stack"
        case .analytics: return "chart.bar.xaxis"
        case .prs: return "arrow.triangle.merge"
        }
    }
}

struct PanelContainerView: View {
    @State private var selectedTab: PanelTab = .sessions
    @FocusState private var isFocused: Bool
    var sessionManager: SessionManager
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(PanelTab.allCases, id: \.self) { tab in
                    TabButton(
                        tab: tab,
                        isSelected: selectedTab == tab,
                        action: { selectedTab = tab }
                    )
                }
                Spacer()

                // Close button
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 12)
            }
            .padding(.top, 8)
            .padding(.bottom, 4)

            Divider()

            // Content
            switch selectedTab {
            case .sessions:
                SessionsContentView(sessionManager: sessionManager)
            case .analytics:
                AnalyticsContentView()
            case .prs:
                PRsContentView()
            }
        }
        .frame(width: 520, height: 720)
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onAppear {
            isFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .cycleTab)) { notification in
            if let forward = notification.object as? Bool {
                cycleTab(forward: forward)
            }
        }
        .onKeyPress(.escape) {
            onClose()
            return .handled
        }
    }

    private func cycleTab(forward: Bool) {
        let allTabs = PanelTab.allCases
        guard let currentIndex = allTabs.firstIndex(of: selectedTab) else { return }
        let nextIndex = forward
            ? (currentIndex + 1) % allTabs.count
            : (currentIndex - 1 + allTabs.count) % allTabs.count
        selectedTab = allTabs[nextIndex]
    }
}

// MARK: - Tab Button

struct TabButton: View {
    let tab: PanelTab
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: tab.icon)
                    .font(.system(size: 11))
                Text(tab.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular, design: .monospaced))
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Sessions Content (extracted from FloatingPanelView)

struct SessionsContentView: View {
    var sessionManager: SessionManager

    var body: some View {
        VStack(spacing: 0) {
            if sessionManager.sessions.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("No active sessions")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(sessionManager.sessions) { session in
                            SessionRowView(session: session)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Analytics Content (simplified wrapper)

struct AnalyticsContentView: View {
    @State private var usageSnapshots: [UsageSnapshot] = []
    @State private var paceData: [PaceSnapshot] = []

    private let dbClient = DatabaseClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Combined Usage & Pace Chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage & Pace")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                CombinedUsageChart(usageSnapshots: usageSnapshots, paceData: paceData)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadData()
        }
    }

    private func loadData() {
        usageSnapshots = dbClient.getUsageSnapshots(days: 7)
        paceData = dbClient.getPaceSnapshots(days: 7)
    }
}
