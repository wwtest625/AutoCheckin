import SwiftUI

struct AccountCardView: View {
    let account: AccountItem
    let onCheckin: () -> Void

    private var platformColor: Color {
        account.platform == .trae ? AppTheme.accent : Color(red: 0.10, green: 0.60, blue: 0.70)
    }

    var body: some View {
        HStack(spacing: 15) {
            avatar

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Text(account.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(account.platform.shortName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(platformColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(platformColor.opacity(0.09), in: Capsule())
                }

                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(account.status.rawValue)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor)
                    if !account.uid.isEmpty {
                        Text("·")
                            .foregroundStyle(.quaternary)
                        Text(account.uid)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                if !account.statusDetail.isEmpty && account.statusDetail != account.status.rawValue {
                    Text(account.statusDetail)
                        .font(.system(size: 10))
                        .foregroundStyle(account.status == .failed || account.status == .expired ? .red : .secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: 2) {
                Text(account.credits.replacingOccurrences(of: " 积分", with: ""))
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Text("可用积分")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 86, alignment: .trailing)

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
        .cardStyle(padding: 17)
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
                .stroke(platformColor.opacity(0.10), lineWidth: 1)
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
        default: return "签到"
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
}
