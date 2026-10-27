import SwiftUI

struct AccountCardView: View {
    let account: AccountItem
    var todayDelta: Double? = nil
    let onCheckin: () -> Void

    private var platformColor: Color {
        account.platform == .trae ? AppTheme.accent : Color(red: 0.10, green: 0.60, blue: 0.70)
    }

    var body: some View {
        HStack(spacing: 18) {
            // MARK: - 1. 左栏：账号身份信息
            HStack(spacing: 12) {
                avatar

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(account.name)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)

                        Text(account.platform.shortName)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(platformColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(platformColor.opacity(0.10), in: Capsule())
                    }

                    if !account.uid.isEmpty {
                        Text(account.uid)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else if !account.phone.isEmpty {
                        Text(account.phone)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: 215, alignment: .leading)

            Divider()
                .frame(height: 38)
                .opacity(0.55)

            // MARK: - 2. 中栏：状态与变动铺开展示（充分利用空间）
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    // 状态胶囊徽标
                    HStack(spacing: 5) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 6, height: 6)
                        Text(account.status.rawValue)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(statusColor)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(statusColor.opacity(0.10), in: Capsule())

                    // 上次打卡时间
                    if let timeText = formattedCheckinTime {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 10))
                            Text(timeText)
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(.secondary)
                    }

                    // 今日积分收益变动（若有时序记录）
                    if let delta = todayDelta, abs(delta) > 0.001 {
                        HStack(spacing: 3) {
                            Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                                .font(.system(size: 9, weight: .bold))
                            Text(delta > 0 ? "+\(formatDelta(delta))" : "\(formatDelta(delta))")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                        }
                        .foregroundStyle(delta > 0 ? AppTheme.success : .red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background((delta > 0 ? AppTheme.success : Color.red).opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
                    }
                }

                // 诊断/详细说明（若有错误或特别提示）
                if !account.statusDetail.isEmpty && account.statusDetail != account.status.rawValue {
                    Text(account.statusDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(account.status == .failed || account.status == .expired ? .red : .secondary)
                        .lineLimit(1)
                } else {
                    Text(account.platform == .trae ? "字节跳动 AI IDE 开发者每日权益" : "腾讯云 WorkBuddy 编码模型额度")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
                .frame(height: 38)
                .opacity(0.55)

            // MARK: - 3. 右栏：可用积分与动作按钮
            HStack(spacing: 16) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(account.credits.replacingOccurrences(of: " 积分", with: ""))
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("可用总积分")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(minWidth: 85, alignment: .trailing)

                if isCompleted {
                    Button(action: onCheckin) {
                        buttonLabel
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    .disabled(true)
                } else {
                    Button(action: onCheckin) {
                        buttonLabel
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    .controlSize(.regular)
                    .disabled(account.isLoading || account.status == .expired)
                }
            }
        }
        .cardStyle(padding: 16)
    }

    private var buttonLabel: some View {
        Group {
            if account.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Text(buttonTitle)
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .frame(width: 66, height: 20)
    }

    private var avatar: some View {
        ZStack {
            if !account.avatarUrl.isEmpty, let url = URL(string: account.avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        platformDefaultIcon
                    }
                }
            } else {
                platformDefaultIcon
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(platformColor.opacity(0.12), lineWidth: 1)
        }
    }

    private var platformDefaultIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(platformColor.opacity(0.10))
            Image(systemName: account.platform.iconName)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(platformColor)
        }
    }

    private var isCompleted: Bool {
        account.status == .alreadyCheckedIn || account.status == .success
    }

    private var buttonTitle: String {
        switch account.status {
        case .alreadyCheckedIn, .success: return "已完成"
        case .expired: return "已过期"
        case .checking: return "签到中"
        default: return "立即签到"
        }
    }

    private var statusColor: Color {
        switch account.status {
        case .alreadyCheckedIn, .success: return AppTheme.success
        case .pending: return AppTheme.warning
        case .checking: return AppTheme.accent
        case .failed, .expired: return .red
        case .unknown: return .secondary
        }
    }

    private var formattedCheckinTime: String? {
        guard let date = account.lastCheckinTime else { return nil }
        let calendar = Calendar.current
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let timeString = timeFormatter.string(from: date)
        
        if calendar.isDateInToday(date) {
            return "今日 \(timeString) 打卡"
        } else if calendar.isDateInYesterday(date) {
            return "昨日 \(timeString)"
        } else {
            let df = DateFormatter()
            df.dateFormat = "MM/dd HH:mm"
            return df.string(from: date)
        }
    }

    private func formatDelta(_ num: Double) -> String {
        if num.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(num))"
        } else {
            return String(format: "%.1f", num)
        }
    }
}
