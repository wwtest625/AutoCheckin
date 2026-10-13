import SwiftUI

struct AccountCardView: View {
    let account: AccountItem
    let onCheckin: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Avatar or Platform Icon
            if !account.avatarUrl.isEmpty, let url = URL(string: account.avatarUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(Circle())
                    default:
                        platformDefaultIcon
                    }
                }
            } else {
                platformDefaultIcon
            }
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(account.name)
                        .font(.headline)
                    
                    Text(account.platform.rawValue)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(account.platform == .trae ? Color.indigo.opacity(0.12) : Color.blue.opacity(0.12))
                        .foregroundStyle(account.platform == .trae ? Color.indigo : Color.blue)
                        .clipShape(Capsule())
                }
                
                HStack(spacing: 12) {
                    if !account.phone.isEmpty {
                        Label(account.phone, systemImage: "phone")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Label(account.uid, systemImage: "person.text.rectangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Label(account.credits, systemImage: "bitcoinsign.circle")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
                
                if !account.statusDetail.isEmpty {
                    Text(account.statusDetail)
                        .font(.caption2)
                        .foregroundStyle(statusColor)
                }
            }
            
            Spacer()
            
            // Status Badge & Action Button
            VStack(alignment: .trailing, spacing: 8) {
                statusBadge
                
                Button(action: onCheckin) {
                    if account.isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 72)
                    } else {
                        Text(buttonTitle)
                            .frame(width: 72)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .disabled(account.isLoading || account.status == .alreadyCheckedIn || account.status == .success || account.status == .expired)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
    
    private var platformDefaultIcon: some View {
        ZStack {
            Circle()
                .fill(account.platform == .trae ? Color.indigo.opacity(0.15) : Color.blue.opacity(0.15))
                .frame(width: 48, height: 48)
            
            Image(systemName: account.platform.iconName)
                .font(.title2)
                .foregroundStyle(account.platform == .trae ? Color.indigo : Color.blue)
        }
    }
    
    private var buttonTitle: String {
        switch account.status {
        case .alreadyCheckedIn, .success: return "已签到"
        case .expired: return "已过期"
        case .checking: return "签到中"
        default: return "立即签到"
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(account.status.rawValue)
                .font(.caption)
                .foregroundStyle(statusColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.1))
        .clipShape(Capsule())
    }
    
    private var statusColor: Color {
        switch account.status {
        case .alreadyCheckedIn, .success:
            return .green
        case .pending:
            return .blue
        case .checking:
            return .purple
        case .failed, .expired:
            return .red
        case .unknown:
            return .secondary
        }
    }
}
