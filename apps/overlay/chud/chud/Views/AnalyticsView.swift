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
    @State private var usageSnapshots: [UsageSnapshot] = []
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

            // Combined Usage & Pace Chart
            VStack(alignment: .leading, spacing: 8) {
                Text("Usage & Pace")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                CombinedUsageChart(usageSnapshots: usageSnapshots, paceData: paceData)
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
        usageSnapshots = dbClient.getUsageSnapshots(days: days)
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

// MARK: - View Mode Toggle

enum ChartViewMode: String, CaseIterable {
    case today = "Today"
    case week = "Week"
}

// MARK: - Combined Usage & Pace Chart

struct CombinedUsageChart: View {
    let usageSnapshots: [UsageSnapshot]
    let paceData: [PaceSnapshot]

    @State private var viewMode: ChartViewMode = .today

    // MARK: - Today View Data

    private var todayUsageSnapshots: [UsageSnapshot] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let startOfDayMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        return usageSnapshots.filter { $0.timestamp >= startOfDayMs }
    }

    private var todayPaceData: [PaceSnapshot] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let startOfDayMs = Int64(startOfDay.timeIntervalSince1970 * 1000)
        return paceData.filter { $0.timestamp >= startOfDayMs }
    }

    // MARK: - Week View Data (grouped by day)

    private struct DayData: Identifiable {
        let id: String  // "YYYY-MM-DD"
        let date: Date
        let daysAgo: Int
        let usageSnapshots: [UsageSnapshot]
        let paceSnapshots: [PaceSnapshot]

        // Each day gets a unique color from the palette
        var color: Color {
            Self.dayColors[min(daysAgo, Self.dayColors.count - 1)]
        }

        // 7-day color palette - distinct colors for each day
        static let dayColors: [Color] = [
            Color(hue: 0.35, saturation: 0.8, brightness: 0.9),  // Today - bright green
            Color(hue: 0.55, saturation: 0.7, brightness: 0.85), // Yesterday - teal
            Color(hue: 0.60, saturation: 0.6, brightness: 0.8),  // 2 days - blue
            Color(hue: 0.70, saturation: 0.5, brightness: 0.75), // 3 days - indigo
            Color(hue: 0.80, saturation: 0.4, brightness: 0.7),  // 4 days - purple
            Color(hue: 0.90, saturation: 0.35, brightness: 0.65),// 5 days - magenta
            Color(hue: 0.95, saturation: 0.3, brightness: 0.6),  // 6 days - pink/gray
        ]

        var dayLabel: String {
            if daysAgo == 0 { return "Today" }
            if daysAgo == 1 { return "Yesterday" }
            let formatter = DateFormatter()
            formatter.dateFormat = "EEE"
            return formatter.string(from: date)
        }
    }

    private var weekData: [DayData] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        var days: [DayData] = []

        for daysAgo in 0..<7 {
            guard let dayStart = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { continue }
            let dayStartMs = Int64(dayStart.timeIntervalSince1970 * 1000)
            let dayEndMs = dayStartMs + 24 * 60 * 60 * 1000

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            let dayId = formatter.string(from: dayStart)

            let dayUsage = usageSnapshots.filter { $0.timestamp >= dayStartMs && $0.timestamp < dayEndMs }
            let dayPace = paceData.filter { $0.timestamp >= dayStartMs && $0.timestamp < dayEndMs }

            // Only include days with data
            if !dayUsage.isEmpty || !dayPace.isEmpty {
                days.append(DayData(
                    id: dayId,
                    date: dayStart,
                    daysAgo: daysAgo,
                    usageSnapshots: dayUsage,
                    paceSnapshots: dayPace
                ))
            }
        }

        return days.reversed()  // Oldest first for drawing order
    }

    // MARK: - Y-Axis Calculations (shared)

    private var activeUsageSnapshots: [UsageSnapshot] {
        viewMode == .today ? todayUsageSnapshots : usageSnapshots.filter { snapshot in
            let sevenDaysAgo = Int64(Date().timeIntervalSince1970 * 1000) - 7 * 24 * 60 * 60 * 1000
            return snapshot.timestamp >= sevenDaysAgo
        }
    }

    private var activePaceData: [PaceSnapshot] {
        viewMode == .today ? todayPaceData : paceData.filter { snapshot in
            let sevenDaysAgo = Int64(Date().timeIntervalSince1970 * 1000) - 7 * 24 * 60 * 60 * 1000
            return snapshot.timestamp >= sevenDaysAgo
        }
    }

    private var maxCost: Double {
        activeUsageSnapshots.map(\.cost).max() ?? 1
    }

    private var minCost: Double {
        activeUsageSnapshots.map(\.cost).min() ?? 0
    }

    private var latestCost: Double {
        todayUsageSnapshots.last?.cost ?? 0
    }

    private var maxPace: Double {
        activePaceData.map(\.pace).max() ?? 1
    }

    private var minPace: Double {
        activePaceData.map(\.pace).min() ?? 0
    }

    private var avgPace: Double {
        guard !todayPaceData.isEmpty else { return 0 }
        return todayPaceData.reduce(0) { $0 + $1.pace } / Double(todayPaceData.count)
    }

    private var combinedMin: Double {
        min(minCost, minPace)
    }

    private var combinedMax: Double {
        max(maxCost, maxPace)
    }

    private var niceYRange: (min: Double, max: Double) {
        let niceMin = floor(combinedMin / 10) * 10
        let niceMax = ceil(combinedMax / 10) * 10
        return (niceMin, niceMax)
    }

    private var yAxisTicks: [Double] {
        let range = niceYRange
        guard range.max > range.min else { return [range.min] }
        var ticks: [Double] = []
        var current = range.min
        while current <= range.max {
            ticks.append(current)
            current += 10
        }
        return ticks
    }

    // MARK: - Today View Time Range

    private var timeRange: (start: Int64, end: Int64)? {
        let allTimestamps = todayUsageSnapshots.map(\.timestamp) + todayPaceData.map(\.timestamp)
        guard let minTs = allTimestamps.min(), let maxTs = allTimestamps.max() else {
            return nil
        }
        return (minTs, maxTs)
    }

    private var hourlyTicks: [Int64] {
        guard let range = timeRange else { return [] }

        let calendar = Calendar.current
        let hourMs: Int64 = 3600 * 1000

        let startDate = Date(timeIntervalSince1970: Double(range.start) / 1000.0)
        let startHour = calendar.dateInterval(of: .hour, for: startDate)?.start ?? startDate
        let startHourMs = Int64(startHour.timeIntervalSince1970 * 1000)

        let endDate = Date(timeIntervalSince1970: Double(range.end) / 1000.0)
        let endHourStart = calendar.dateInterval(of: .hour, for: endDate)?.start ?? endDate
        let endHourMs = Int64(endHourStart.timeIntervalSince1970 * 1000)
        let roundedEndMs = endHourMs < range.end ? endHourMs + hourMs : endHourMs

        var ticks: [Int64] = []
        var currentMs = startHourMs

        while currentMs <= roundedEndMs {
            ticks.append(currentMs)
            currentMs += hourMs
        }

        return ticks
    }

    private var extendedTimeRange: (start: Int64, end: Int64)? {
        guard !hourlyTicks.isEmpty else { return timeRange }
        return (hourlyTicks.first!, hourlyTicks.last!)
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // View mode toggle and legend
            HStack(spacing: 16) {
                // View mode picker
                Picker("View", selection: $viewMode) {
                    ForEach(ChartViewMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 120)

                Spacer()

                // Today's stats (using today's color)
                HStack(spacing: 4) {
                    Circle()
                        .fill(todayColor)
                        .frame(width: 8, height: 8)
                    Text("$\(String(format: "%.0f", latestCost)) • $\(String(format: "%.0f", avgPace))/hr")
                        .font(.system(size: 10, design: .monospaced))
                }
            }

            if viewMode == .today {
                todayChartView
            } else {
                weekChartView
            }
        }
    }

    // MARK: - Today Chart View

    // Get color for today (consistent between views)
    private var todayColor: Color {
        DayData.dayColors[0]  // Today is daysAgo = 0
    }

    @ViewBuilder
    private var todayChartView: some View {
        if todayUsageSnapshots.isEmpty && todayPaceData.isEmpty {
            Text("No data yet today")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        } else {
            HStack(alignment: .top, spacing: 0) {
                yAxisView

                GeometryReader { geometry in
                    let height = geometry.size.height
                    let width = geometry.size.width
                    let yRange = niceYRange
                    let effectiveRange = yRange.max - yRange.min
                    let rangeVal = effectiveRange > 0 ? effectiveRange : 1

                    ZStack {
                        gridLines(width: width, height: height)

                        if todayUsageSnapshots.count > 1, let range = extendedTimeRange {
                            let timeSpan = Double(range.end - range.start)
                            costAreaPath(snapshots: todayUsageSnapshots, range: range, timeSpan: timeSpan, yRange: yRange, rangeVal: rangeVal, width: width, height: height, color: todayColor)
                            costLinePath(snapshots: todayUsageSnapshots, range: range, timeSpan: timeSpan, yRange: yRange, rangeVal: rangeVal, width: width, height: height, color: todayColor)
                        }

                        if todayPaceData.count > 1, let range = extendedTimeRange {
                            let timeSpan = Double(range.end - range.start)
                            paceLinePath(snapshots: todayPaceData, range: range, timeSpan: timeSpan, yRange: yRange, rangeVal: rangeVal, width: width, height: height, color: todayColor)
                        }

                        xAxisTicks(width: width, height: height)
                    }
                }
                .frame(height: 400)
            }

            xAxisLabels
        }
    }

    // MARK: - Week Chart View

    @ViewBuilder
    private var weekChartView: some View {
        if weekData.isEmpty {
            Text("No data this week")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        } else {
            // Day legend
            HStack(spacing: 8) {
                ForEach(weekData.reversed().prefix(7)) { day in
                    HStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(day.color)
                            .frame(width: 12, height: 3)
                        Text(day.dayLabel)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)

            HStack(alignment: .top, spacing: 0) {
                yAxisView

                GeometryReader { geometry in
                    let height = geometry.size.height
                    let width = geometry.size.width
                    let yRange = niceYRange
                    let effectiveRange = yRange.max - yRange.min
                    let rangeVal = effectiveRange > 0 ? effectiveRange : 1

                    ZStack {
                        gridLines(width: width, height: height)

                        // Draw each day's lines (oldest first so newest is on top)
                        ForEach(weekData) { day in
                            let dayStartMs = Int64(day.date.timeIntervalSince1970 * 1000)
                            let dayEndMs = dayStartMs + 24 * 60 * 60 * 1000
                            let timeSpan = Double(dayEndMs - dayStartMs)

                            // Cost line for this day
                            if day.usageSnapshots.count > 1 {
                                costLinePath(
                                    snapshots: day.usageSnapshots,
                                    range: (dayStartMs, dayEndMs),
                                    timeSpan: timeSpan,
                                    yRange: yRange,
                                    rangeVal: rangeVal,
                                    width: width,
                                    height: height,
                                    color: day.color
                                )
                            }

                            // Pace line for this day
                            if day.paceSnapshots.count > 1 {
                                paceLinePath(
                                    snapshots: day.paceSnapshots,
                                    range: (dayStartMs, dayEndMs),
                                    timeSpan: timeSpan,
                                    yRange: yRange,
                                    rangeVal: rangeVal,
                                    width: width,
                                    height: height,
                                    color: day.color
                                )
                            }
                        }

                        // Hourly tick marks (0-24)
                        weekXAxisTicks(width: width, height: height)
                    }
                }
                .frame(height: 400)
            }

            weekXAxisLabels
        }
    }

    // MARK: - Shared Components

    @ViewBuilder
    private var yAxisView: some View {
        HStack(spacing: 2) {
            VStack(alignment: .trailing, spacing: 0) {
                ForEach(Array(yAxisTicks.reversed().enumerated()), id: \.offset) { _, tick in
                    Text("$\(String(format: "%.0f", tick))")
                        .font(.system(size: 7, design: .monospaced))
                        .foregroundColor(.secondary)
                    if tick != yAxisTicks.first {
                        Spacer()
                    }
                }
            }
            .frame(width: 32, height: 400)

            VStack(spacing: 0) {
                ForEach(Array(yAxisTicks.reversed().enumerated()), id: \.offset) { _, tick in
                    Rectangle().fill(Color.gray.opacity(0.5)).frame(width: 4, height: 1)
                    if tick != yAxisTicks.first {
                        Spacer()
                    }
                }
            }
            .frame(width: 4, height: 400)
        }
    }

    @ViewBuilder
    private func gridLines(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: height / 2))
            path.addLine(to: CGPoint(x: width, y: height / 2))
        }
        .stroke(Color.gray.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
    }

    @ViewBuilder
    private func costAreaPath(snapshots: [UsageSnapshot], range: (start: Int64, end: Int64), timeSpan: Double, yRange: (min: Double, max: Double), rangeVal: Double, width: CGFloat, height: CGFloat, color: Color) -> some View {
        Path { path in
            path.move(to: CGPoint(x: 0, y: height))

            for snapshot in snapshots {
                let x = timeSpan > 0
                    ? CGFloat(Double(snapshot.timestamp - range.start) / timeSpan) * width
                    : width / 2
                let normalizedCost = (snapshot.cost - yRange.min) / rangeVal
                let y = height - (CGFloat(normalizedCost) * height)
                path.addLine(to: CGPoint(x: x, y: y))
            }

            path.addLine(to: CGPoint(x: width, y: height))
            path.closeSubpath()
        }
        .fill(color.opacity(0.15))
    }

    @ViewBuilder
    private func costLinePath(snapshots: [UsageSnapshot], range: (start: Int64, end: Int64), timeSpan: Double, yRange: (min: Double, max: Double), rangeVal: Double, width: CGFloat, height: CGFloat, color: Color) -> some View {
        Path { path in
            for (index, snapshot) in snapshots.enumerated() {
                let x = timeSpan > 0
                    ? CGFloat(Double(snapshot.timestamp - range.start) / timeSpan) * width
                    : width / 2
                let normalizedCost = (snapshot.cost - yRange.min) / rangeVal
                let y = height - (CGFloat(normalizedCost) * height)

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder
    private func paceLinePath(snapshots: [PaceSnapshot], range: (start: Int64, end: Int64), timeSpan: Double, yRange: (min: Double, max: Double), rangeVal: Double, width: CGFloat, height: CGFloat, color: Color) -> some View {
        Path { path in
            for (index, snapshot) in snapshots.enumerated() {
                let x = timeSpan > 0
                    ? CGFloat(Double(snapshot.timestamp - range.start) / timeSpan) * width
                    : width / 2
                let normalizedPace = (snapshot.pace - yRange.min) / rangeVal
                let y = height - (CGFloat(normalizedPace) * height)

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(color.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
    }

    @ViewBuilder
    private func xAxisTicks(width: CGFloat, height: CGFloat) -> some View {
        if let range = extendedTimeRange {
            let timeSpan = Double(range.end - range.start)
            ForEach(hourlyTicks, id: \.self) { tickMs in
                if timeSpan > 0 {
                    let x = CGFloat(Double(tickMs - range.start) / timeSpan) * width
                    Path { path in
                        path.move(to: CGPoint(x: x, y: height - 4))
                        path.addLine(to: CGPoint(x: x, y: height))
                    }
                    .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func weekXAxisTicks(width: CGFloat, height: CGFloat) -> some View {
        // Show ticks every 4 hours (0, 4, 8, 12, 16, 20, 24)
        ForEach([0, 4, 8, 12, 16, 20, 24], id: \.self) { hour in
            let x = CGFloat(hour) / 24.0 * width
            Path { path in
                path.move(to: CGPoint(x: x, y: height - 4))
                path.addLine(to: CGPoint(x: x, y: height))
            }
            .stroke(Color.gray.opacity(0.5), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var xAxisLabels: some View {
        if let range = extendedTimeRange {
            GeometryReader { geometry in
                let width = geometry.size.width
                let timeSpan = Double(range.end - range.start)

                ZStack(alignment: .leading) {
                    ForEach(hourlyTicks, id: \.self) { tickMs in
                        if timeSpan > 0 {
                            let x = CGFloat(Double(tickMs - range.start) / timeSpan) * width
                            Text(formatHourShort(tickMs))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                                .position(x: x, y: 6)
                        }
                    }
                }
            }
            .frame(height: 16)
            .padding(.leading, 36)
        }
    }

    @ViewBuilder
    private var weekXAxisLabels: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                ForEach([0, 4, 8, 12, 16, 20, 24], id: \.self) { hour in
                    let x = CGFloat(hour) / 24.0 * width
                    Text(hour == 24 ? "12a" : (hour == 0 ? "12a" : (hour == 12 ? "12p" : "\(hour % 12)\(hour < 12 ? "a" : "p")")))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .position(x: x, y: 6)
                }
            }
        }
        .frame(height: 16)
        .padding(.leading, 36)
    }

    // MARK: - Helpers

    private func formatHourShort(_ timestamp: Int64) -> String {
        let date = Date(timeIntervalSince1970: Double(timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }
}
