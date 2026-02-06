import SwiftUI

enum TimeRange: Int, CaseIterable {
    case week = 7
    case month = 28
    case quarter = 90

    var label: String {
        switch self {
        case .week: return "7 days"
        case .month: return "28 days"
        case .quarter: return "90 days"
        }
    }
}

struct AnalyticsView: View {
    @State private var timeRange: TimeRange = .month
    @State private var heatmapData: [HeatmapCell] = []
    @State private var projectData: [ProjectTime] = []
    @State private var usageData: [DailyUsage] = []
    @State private var paceData: [PaceSnapshot] = []

    private let dbClient = DatabaseClient()
    private let days = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with time range picker
            HStack {
                Text("Analytics")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Spacer()
                Picker("Time Range", selection: $timeRange) {
                    ForEach(TimeRange.allCases, id: \.self) { range in
                        Text(range.label).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            Divider()

            // Usage Cost Chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Daily Cost")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                UsageCostChart(data: usageData)
            }

            Divider()

            // Pace Chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Pace ($/hr)")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                PaceChart(data: paceData)
            }

            Divider()

            // Activity Heatmap
            VStack(alignment: .leading, spacing: 8) {
                Text("Activity")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                HeatmapGrid(data: heatmapData, days: days)
            }

            Divider()

            // Project Breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("Projects")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                ProjectBreakdownChart(data: Array(projectData.prefix(8)))
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 400, height: 650)
        .onChange(of: timeRange) { _, newValue in
            loadData(days: newValue.rawValue)
        }
        .onAppear {
            loadData(days: timeRange.rawValue)
        }
    }

    private func loadData(days: Int) {
        heatmapData = dbClient.getActivityHeatmap(days: days)
        projectData = dbClient.getProjectBreakdown(days: days)
        usageData = dbClient.getDailyUsage(days: days)
        paceData = dbClient.getPaceSnapshots(days: days)
    }
}

// MARK: - Heatmap Grid

struct HeatmapGrid: View {
    let data: [HeatmapCell]
    let days: [String]

    private let cellSize: CGFloat = 14
    private let spacing: CGFloat = 2

    // Build a 2D grid: [hour][dayOfWeek] -> count
    private var grid: [[Int]] {
        var result = Array(repeating: Array(repeating: 0, count: 7), count: 24)
        for cell in data {
            if cell.hour >= 0 && cell.hour < 24 && cell.dayOfWeek >= 0 && cell.dayOfWeek < 7 {
                result[cell.hour][cell.dayOfWeek] = cell.count
            }
        }
        return result
    }

    private var maxCount: Int {
        data.map(\.count).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            // Hour labels row
            HStack(spacing: spacing) {
                Text("")  // Spacer for day labels
                    .frame(width: 20, height: cellSize)
                ForEach(0..<24, id: \.self) { hour in
                    if hour % 6 == 0 {
                        Text(String(format: "%02d", hour))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: cellSize, height: cellSize)
                    } else {
                        Text("")
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }

            // Grid rows (one per day)
            ForEach(0..<7, id: \.self) { dayIndex in
                HStack(spacing: spacing) {
                    // Day label
                    Text(days[dayIndex])
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: cellSize)

                    // Hour cells
                    ForEach(0..<24, id: \.self) { hour in
                        let count = grid[hour][dayIndex]
                        let intensity = maxCount > 0 ? Double(count) / Double(maxCount) : 0

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue.opacity(0.1 + intensity * 0.9))
                            .frame(width: cellSize, height: cellSize)
                    }
                }
            }
        }
    }
}

// MARK: - Project Breakdown Chart

struct ProjectBreakdownChart: View {
    let data: [ProjectTime]

    private var maxMinutes: Int {
        data.map(\.totalMinutes).max() ?? 1
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if data.isEmpty {
                Text("No data")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                ForEach(data, id: \.cwd) { project in
                    HStack(spacing: 8) {
                        // Project name (abbreviated)
                        Text(abbreviatePath(project.cwd))
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .frame(width: 140, alignment: .leading)

                        // Bar
                        GeometryReader { geometry in
                            let barWidth = maxMinutes > 0
                                ? CGFloat(project.totalMinutes) / CGFloat(maxMinutes) * geometry.size.width
                                : 0

                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.blue.opacity(0.7))
                                .frame(width: barWidth, height: 12)
                        }
                        .frame(height: 12)

                        // Time label
                        Text(formatTime(project.totalMinutes))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }
        }
    }

    private func abbreviatePath(_ path: String) -> String {
        let components = path.split(separator: "/")
        if components.count >= 2 {
            return components.suffix(2).joined(separator: "/")
        } else if let last = components.last {
            return String(last)
        }
        return path
    }

    private func formatTime(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return "\(hours)h \(mins)m"
        }
        return "\(mins)m"
    }
}

// MARK: - Usage Cost Chart

struct UsageCostChart: View {
    let data: [DailyUsage]

    private var maxCost: Double {
        data.map(\.cost).max() ?? 1
    }

    private var totalCost: Double {
        data.reduce(0) { $0 + $1.cost }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if data.isEmpty {
                Text("No usage data yet")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                // Summary line
                HStack {
                    Text("Total: $\(String(format: "%.2f", totalCost))")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer()
                    Text("Avg: $\(String(format: "%.2f", totalCost / Double(data.count)))/day")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                // Bar chart
                GeometryReader { geometry in
                    let barWidth = max(4, (geometry.size.width - CGFloat(data.count - 1) * 2) / CGFloat(data.count))

                    HStack(alignment: .bottom, spacing: 2) {
                        ForEach(Array(data.enumerated()), id: \.offset) { _, usage in
                            let height = maxCost > 0
                                ? CGFloat(usage.cost) / CGFloat(maxCost) * geometry.size.height
                                : 0

                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.green.opacity(0.8))
                                    .frame(width: barWidth, height: max(2, height))
                            }
                        }
                    }
                }
                .frame(height: 60)

                // X-axis labels (first and last date)
                if let first = data.first, let last = data.last {
                    HStack {
                        Text(abbreviateDate(first.date))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(abbreviateDate(last.date))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func abbreviateDate(_ dateStr: String) -> String {
        // Convert "2026-02-06" to "Feb 6"
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else {
            return dateStr
        }
        let months = ["", "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(months[month]) \(day)"
    }
}

// MARK: - Pace Chart

struct PaceChart: View {
    let data: [PaceSnapshot]

    private var maxPace: Double {
        data.map(\.pace).max() ?? 1
    }

    private var avgPace: Double {
        guard !data.isEmpty else { return 0 }
        return data.reduce(0) { $0 + $1.pace } / Double(data.count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if data.isEmpty {
                Text("No pace data yet")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            } else {
                // Summary line
                HStack {
                    Text("Avg: $\(String(format: "%.2f", avgPace))/hr")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                    Spacer()
                    if let latest = data.last {
                        Text("Latest: $\(String(format: "%.2f", latest.pace))/hr")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

                // Line chart using Path
                GeometryReader { geometry in
                    if data.count > 1 {
                        Path { path in
                            let xStep = geometry.size.width / CGFloat(data.count - 1)

                            for (index, snapshot) in data.enumerated() {
                                let x = CGFloat(index) * xStep
                                let y = maxPace > 0
                                    ? geometry.size.height - (CGFloat(snapshot.pace) / CGFloat(maxPace) * geometry.size.height)
                                    : geometry.size.height

                                if index == 0 {
                                    path.move(to: CGPoint(x: x, y: y))
                                } else {
                                    path.addLine(to: CGPoint(x: x, y: y))
                                }
                            }
                        }
                        .stroke(Color.cyan, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                        // Filled area under the line
                        Path { path in
                            let xStep = geometry.size.width / CGFloat(data.count - 1)

                            path.move(to: CGPoint(x: 0, y: geometry.size.height))

                            for (index, snapshot) in data.enumerated() {
                                let x = CGFloat(index) * xStep
                                let y = maxPace > 0
                                    ? geometry.size.height - (CGFloat(snapshot.pace) / CGFloat(maxPace) * geometry.size.height)
                                    : geometry.size.height
                                path.addLine(to: CGPoint(x: x, y: y))
                            }

                            path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                            path.closeSubpath()
                        }
                        .fill(Color.cyan.opacity(0.2))
                    } else if data.count == 1 {
                        // Single point
                        let y = maxPace > 0
                            ? geometry.size.height - (CGFloat(data[0].pace) / CGFloat(maxPace) * geometry.size.height)
                            : geometry.size.height / 2
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 6, height: 6)
                            .position(x: geometry.size.width / 2, y: y)
                    }
                }
                .frame(height: 60)

                // Time range labels
                if let first = data.first, let last = data.last {
                    HStack {
                        Text(formatTimestamp(first.timestamp))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatTimestamp(last.timestamp))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func formatTimestamp(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}
