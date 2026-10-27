import SwiftUI
import Charts

struct CreditHistoryView: View {
    @Bindable var manager: CheckinManager

    private var summary: CreditSummary { manager.creditSummary }
    private var hasAnyRecord: Bool { summary.points.contains(where: \.hasRecord) }
    private var todaySubtitle: String {
        if summary.todayDaysSincePrevious > 1 {
            return "相较 \(summary.todayDaysSincePrevious) 天前有效记录"
        }
        return "相较上一有效快照"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                kpiStatsRow
                chartCardView
                detailHistoryTable
            }
            .padding(24)
        }
        .background(AppTheme.canvas)
        .onAppear { manager.refreshCreditSummary() }
    }

    private var kpiStatsRow: some View {
        HStack(spacing: 12) {
            kpiCard(
                title: "今日净变动",
                value: formatDelta(summary.todayDelta),
                footnote: todaySubtitle,
                color: deltaColor(summary.todayDelta)
            )
            kpiCard(
                title: "近 14 天净变动",
                value: formatDelta(summary.fourteenDayDelta),
                footnote: "期间获得与消耗之和",
                color: deltaColor(summary.fourteenDayDelta)
            )
            kpiCard(
                title: "当前可用积分",
                value: formatNumber(summary.currentTotal),
                footnote: manager.selectedCreditAccountId == nil ? "全部账号合计" : "当前账号结余",
                color: .primary
            )
        }
    }

    private func kpiCard(title: String, value: String, footnote: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(footnote)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle(padding: 17)
    }

    private var chartCardView: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeading(title: "每日净增减", subtitle: "向上为增加，向下为消耗")
                Spacer()
                HStack(spacing: 14) {
                    legend(color: AppTheme.success, title: "增加")
                    legend(color: .red.opacity(0.8), title: "减少")
                }
            }

            if !hasAnyRecord {
                VStack(spacing: 12) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("还没有积分快照")
                        .font(.system(size: 13, weight: .medium))
                    Text("完成一次状态查询或签到后，趋势会出现在这里")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            } else {
                Chart(summary.points) { point in
                    BarMark(
                        x: .value("日期", point.displayDate),
                        y: .value("净变动", point.netDelta),
                        width: .fixed(14)
                    )
                    .foregroundStyle(barColor(point.netDelta))
                    .cornerRadius(3)

                    if point.netDelta != 0 {
                        PointMark(
                            x: .value("日期", point.displayDate),
                            y: .value("净变动", point.netDelta)
                        )
                        .foregroundStyle(.clear)
                        .annotation(position: point.netDelta > 0 ? .top : .bottom, spacing: 4) {
                            Text(formatAnnotation(point.netDelta))
                                .font(.system(size: 8, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 4]))
                            .foregroundStyle(Color.secondary.opacity(0.20))
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(formatNumber(number))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let date = value.as(String.self) {
                                Text(date)
                                    .font(.system(size: 9))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(height: 224)
            }
        }
        .cardStyle(padding: 19)
    }

    private var detailHistoryTable: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                SectionHeading(title: "逐日明细")
                Spacer()
                Text("最近 14 天")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    tableHeader("日期", width: 112)
                    tableHeader("当日结余", width: 110)
                    tableHeader("净增减", width: 100)
                    tableHeader("记录状态", width: nil)
                }
                .padding(.horizontal, 4)
                .padding(.bottom, 9)

                Divider()

                ForEach(summary.points.reversed()) { point in
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Text(point.dateString)
                                .font(.system(size: 11, design: .monospaced))
                            if Calendar.current.isDateInToday(point.date) {
                                Text("今")
                                    .font(.system(size: 8, weight: .semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 17, height: 17)
                                    .background(AppTheme.accent.opacity(0.09), in: Circle())
                            }
                        }
                        .frame(width: 112, alignment: .leading)

                        Text(formatNumber(point.closingBalance))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .frame(width: 110, alignment: .leading)

                        Text(formatSignedNumber(point.netDelta))
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(deltaColor(point.netDelta))
                            .frame(width: 100, alignment: .leading)

                        HStack(spacing: 5) {
                            Circle()
                                .fill(recordStatusColor(point))
                                .frame(width: 5, height: 5)
                            Text(recordStatusText(point))
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 10)

                    if point.id != summary.points.first?.id {
                        Divider().opacity(0.5)
                    }
                }
            }
        }
        .cardStyle(padding: 19)
    }

    private func recordStatusText(_ point: DailyCreditPoint) -> String {
        guard point.hasRecord else { return "无快照" }
        return point.isConsecutive ? "已记录" : "跨 \(point.daysSincePrevious) 天累计"
    }

    private func recordStatusColor(_ point: DailyCreditPoint) -> Color {
        guard point.hasRecord else { return Color.secondary.opacity(0.35) }
        return point.isConsecutive ? AppTheme.success : AppTheme.warning
    }

    @ViewBuilder
    private func tableHeader(_ title: String, width: CGFloat?) -> some View {
        let label = Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
        if let width {
            label.frame(width: width, alignment: .leading)
        } else {
            label.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func legend(color: Color, title: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func barColor(_ delta: Double) -> Color {
        if delta > 0.001 { return AppTheme.success }
        if delta < -0.001 { return .red.opacity(0.78) }
        return Color.secondary.opacity(0.16)
    }

    private func deltaColor(_ delta: Double) -> Color {
        if delta > 0.001 { return AppTheme.success }
        if delta < -0.001 { return .red }
        return .secondary
    }

    private func formatDelta(_ delta: Double) -> String {
        "\(formatSignedNumber(delta)) 积分"
    }

    private func formatSignedNumber(_ number: Double) -> String {
        number > 0.001 ? "+\(formatNumber(number))" : formatNumber(number)
    }

    private func formatAnnotation(_ delta: Double) -> String {
        formatSignedNumber(delta)
    }

    private func formatNumber(_ number: Double) -> String {
        if abs(number) < 0.001 { return "0" }
        if number.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(number))"
        }
        return String(format: "%.1f", number)
    }
}
