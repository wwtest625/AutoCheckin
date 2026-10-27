import SwiftUI

struct ContentView: View {
    @Bindable var manager: CheckinManager

    private var doneCount: Int {
        manager.accounts.filter { $0.status == .alreadyCheckedIn || $0.status == .success }.count
    }

    private var pendingCount: Int {
        manager.accounts.filter { $0.status != .alreadyCheckedIn && $0.status != .success && $0.status != .expired }.count
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 216)

            Divider()
                .opacity(0.65)

            VStack(spacing: 0) {
                pageHeader

                Divider()
                    .opacity(0.5)

                Group {
                    switch manager.selectedTab {
                    case 0:
                        accountsListView
                    case 1:
                        CreditHistoryView(manager: manager)
                    case 2:
                        LogConsoleView(manager: manager) {
                            manager.logs.removeAll()
                        }
                        .padding(24)
                    case 3:
                        SettingsView(manager: manager)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(AppTheme.canvas)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.sidebar)
        .animation(.easeInOut(duration: 0.18), value: manager.selectedTab)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [AppTheme.accent, Color(red: 0.48, green: 0.35, blue: 0.90)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 38, height: 38)
                    .overlay {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: AppTheme.accent.opacity(0.24), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 1) {
                    Text("AutoCheckin")
                        .font(.system(size: 15, weight: .bold))
                    Text("日常，不必惦记")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 24)
            .padding(.bottom, 30)

            Text("工作台")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)

            VStack(spacing: 4) {
                sidebarButton(title: "今日签到", icon: "checkmark.circle", tab: 0, count: manager.accounts.count)
                sidebarButton(title: "积分趋势", icon: "chart.xyaxis.line", tab: 1)
                sidebarButton(title: "运行日志", icon: "text.alignleft", tab: 2, count: manager.logs.count)
                sidebarButton(title: "偏好设置", icon: "slider.horizontal.3", tab: 3)
            }
            .padding(.horizontal, 10)

            Spacer()

            Button {
                manager.selectedTab = 3
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: manager.autoCheckinEnabled ? "clock.badge.checkmark" : "clock")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(manager.autoCheckinEnabled ? AppTheme.success : .secondary)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(manager.autoCheckinEnabled ? "自动签到已开启" : "自动签到未开启")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                        Text(manager.autoCheckinEnabled
                             ? "每天 \(String(format: "%02d:%02d", manager.autoCheckinHour, manager.autoCheckinMinute))"
                             : "点这里设置执行时间")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(11)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)

            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                Text("凭证仅保存在这台 Mac")
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(AppTheme.sidebar)
    }

    private func sidebarButton(title: String, icon: String, tab: Int, count: Int? = nil) -> some View {
        let isSelected = manager.selectedTab == tab
        return Button {
            manager.selectedTab = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                Spacer()
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundStyle(isSelected ? AppTheme.accent : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(isSelected ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.05), in: Capsule())
                }
            }
            .foregroundStyle(isSelected ? AppTheme.accent : Color.primary.opacity(0.72))
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(isSelected ? AppTheme.accent.opacity(0.11) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var pageHeader: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(pageTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(pageSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            switch manager.selectedTab {
            case 0:
                accountActions
            case 1:
                creditActions
            default:
                EmptyView()
            }
        }
        .padding(.horizontal, 26)
        .frame(height: 82)
        .background(AppTheme.canvas)
    }

    private var pageTitle: String {
        switch manager.selectedTab {
        case 0: return "今日签到"
        case 1: return "积分趋势"
        case 2: return "运行日志"
        default: return "偏好设置"
        }
    }

    private var pageSubtitle: String {
        switch manager.selectedTab {
        case 0: return "把每天的重复操作，留给它来完成"
        case 1: return "近 14 天的积分变化与每日结余"
        case 2: return "扫描、查询与签到过程都在这里"
        default: return "自动化、安全与本地数据管理"
        }
    }

    private var accountActions: some View {
        HStack(spacing: 9) {
            Button {
                manager.scanAll()
            } label: {
                Group {
                    if manager.isScanning {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .frame(width: 15, height: 15)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("重新扫描本地账号")
            .disabled(manager.isScanning || manager.isCheckingAll)

            Button {
                Task { await manager.checkinAll() }
            } label: {
                HStack(spacing: 7) {
                    if manager.isCheckingAll {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(manager.isCheckingAll ? "正在签到" : "全部签到")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.accent)
            .disabled(manager.accounts.isEmpty || manager.isCheckingAll || manager.isScanning)
        }
    }

    private var creditActions: some View {
        HStack(spacing: 10) {
            Picker("统计对象", selection: $manager.selectedCreditAccountId) {
                Text("全部账号").tag(String?.none)
                Divider()
                ForEach(manager.accounts) { account in
                    Text("\(account.name) · \(account.platform.shortName)").tag(String?.some(account.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 170)

            Button {
                manager.refreshCreditSummary()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .help("刷新统计数据")
        }
    }

    private var accountsListView: some View {
        ScrollView {
            LazyVStack(spacing: 14, pinnedViews: []) {
                if manager.accounts.isEmpty {
                    emptyAccounts
                } else {
                    accountsOverview

                    HStack {
                        SectionHeading(title: "我的账号", subtitle: "选择账号可单独签到，右键可移除")
                        Spacer()
                        Text("\(manager.accounts.count) 个账号")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)

                    ForEach(manager.accounts) { account in
                        AccountCardView(account: account) {
                            Task { await manager.checkinAccount(id: account.id) }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                manager.deleteAccount(id: account.id)
                            } label: {
                                Label("删除此账号", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .padding(24)
            .padding(.bottom, 8)
        }
    }

    private var accountsOverview: some View {
        HStack(spacing: 24) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .stroke(AppTheme.accent.opacity(0.12), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: manager.accounts.isEmpty ? 0 : CGFloat(doneCount) / CGFloat(manager.accounts.count))
                        .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: doneCount == manager.accounts.count ? "checkmark" : "calendar")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(doneCount == manager.accounts.count ? "今天全部完成" : "今天已完成 \(doneCount) / \(manager.accounts.count)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    Text(doneCount == manager.accounts.count ? "做得很好，明天见" : "还有 \(pendingCount) 个账号等待签到")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            overviewMetric(value: "\(pendingCount)", label: "待签到", color: pendingCount == 0 ? AppTheme.success : AppTheme.warning)
            Divider().frame(height: 30)
            overviewMetric(value: "\(manager.accounts.count)", label: "账号总数", color: .primary)
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [AppTheme.accent.opacity(0.10), AppTheme.accent.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.10), lineWidth: 1)
        }
    }

    private func overviewMetric(value: String, label: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 56)
    }

    private var emptyAccounts: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.08))
                    .frame(width: 78, height: 78)
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 31, weight: .light))
                    .foregroundStyle(AppTheme.accent)
            }
            .padding(.bottom, 4)

            Text("先找到你的账号")
                .font(.system(size: 18, weight: .semibold))
            Text("在 Trae CN 或 WorkBuddy 客户端登录后，\n回到这里扫描即可开始自动签到。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Button {
                manager.scanAll()
            } label: {
                Label("扫描本地账号", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(AppTheme.accent)
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 110)
    }
}
