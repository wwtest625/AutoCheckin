import SwiftUI
import AppKit

struct LogConsoleView: View {
    @Bindable var manager: CheckinManager
    let onClear: () -> Void

    private var filteredLogs: [LogMessage] {
        manager.logs.filter { item in
            let matchesLevel = manager.logFilterLevel == nil || item.level == manager.logFilterLevel
            let matchesSearch = manager.logSearchText.isEmpty ||
                item.content.localizedCaseInsensitiveContains(manager.logSearchText) ||
                (item.tag?.localizedCaseInsensitiveContains(manager.logSearchText) ?? false) ||
                item.formattedTime.contains(manager.logSearchText)
            return matchesLevel && matchesSearch
        }
    }

    private func count(_ level: LogLevel) -> Int {
        manager.logs.filter { $0.level == level }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.6)
            logListView
        }
        .background(AppTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 7) {
                filterChip(title: "全部", count: manager.logs.count, level: nil)
                filterChip(title: "成功", count: count(.success), level: .success)
                filterChip(title: "警告", count: count(.warning), level: .warning)
                filterChip(title: "错误", count: count(.error), level: .error)

                Spacer()

                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("搜索日志", text: $manager.logSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                    if !manager.logSearchText.isEmpty {
                        Button {
                            manager.logSearchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .frame(width: 210)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
            }

            HStack(spacing: 13) {
                Text("显示 \(filteredLogs.count) / \(manager.logs.count) 条")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    manager.logAutoScroll.toggle()
                } label: {
                    Label("跟随最新", systemImage: manager.logAutoScroll ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(manager.logAutoScroll ? AppTheme.accent : .secondary)
                }
                .buttonStyle(.plain)
                Button {
                    copyAllLogs()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .disabled(filteredLogs.isEmpty)
                Button(role: .destructive, action: onClear) {
                    Label("清空", systemImage: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(manager.logs.isEmpty)
            }
        }
        .padding(14)
    }

    private func filterChip(title: String, count: Int, level: LogLevel?) -> some View {
        let selected = manager.logFilterLevel == level
        return Button {
            manager.logFilterLevel = level
        } label: {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)")
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 10, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? AppTheme.accent : .secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(selected ? AppTheme.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var logListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if filteredLogs.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredLogs) { log in
                            logRowView(log)
                                .id(log.id)
                        }
                    }
                    .padding(.vertical, 7)
                }
            }
            .onChange(of: manager.logs.count) {
                if manager.logAutoScroll, let last = filteredLogs.last {
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logRowView(_ log: LogMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(log.formattedTime)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 56, alignment: .leading)
                .padding(.top, 2)

            Image(systemName: log.level.icon)
                .font(.system(size: 10))
                .foregroundStyle(log.level.color)
                .frame(width: 13)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                if let tag = log.tag {
                    Text(tag)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(log.cleanMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(log.level == .error ? .red : .primary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("复制消息正文") { copySingleLog(log.cleanMessage) }
            Button("复制整条日志") {
                copySingleLog("[\(log.formattedTime)] [\(log.level.rawValue)] \(log.content)")
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: manager.logs.isEmpty ? "text.alignleft" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(.tertiary)
            Text(manager.logs.isEmpty ? "这里还很安静" : "没有匹配的日志")
                .font(.system(size: 13, weight: .medium))
            Text(manager.logs.isEmpty ? "扫描或签到后，执行过程会记录在这里" : "尝试更换分类或清除搜索关键词")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !manager.logs.isEmpty && (manager.logFilterLevel != nil || !manager.logSearchText.isEmpty) {
                Button("重置筛选") {
                    manager.logFilterLevel = nil
                    manager.logSearchText = ""
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300)
        .padding(30)
    }

    private func copyAllLogs() {
        let text = filteredLogs.map { log in
            "[\(log.formattedTime)] [\(log.level.rawValue)] \(log.content)"
        }.joined(separator: "\n")
        copySingleLog(text)
    }

    private func copySingleLog(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
