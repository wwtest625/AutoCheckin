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
    
    private var countTotal: Int { manager.logs.count }
    private var countSuccess: Int { manager.logs.filter { $0.level == .success }.count }
    private var countWarning: Int { manager.logs.filter { $0.level == .warning }.count }
    private var countError: Int { manager.logs.filter { $0.level == .error }.count }
    
    var body: some View {
        VStack(spacing: 0) {
            // 顶部工具栏
            topToolbar
            
            Divider()
            
            // 筛选栏与搜索栏
            filterAndSearchBar
            
            Divider()
            
            // 日志主列表
            logListView
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - 顶部工具栏
    private var topToolbar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)
                
                Text("运行控制台")
                    .font(.system(size: 13, weight: .semibold))
                
                Text("\(countTotal) 条记录")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // 自动触底开关
            Button {
                manager.logAutoScroll.toggle()
            } label: {
                Label(
                    manager.logAutoScroll ? "自动滚动 (开)" : "自动滚动 (关)",
                    systemImage: manager.logAutoScroll ? "arrow.down.to.line.compact" : "pause.circle"
                )
                .font(.caption)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(manager.logAutoScroll ? .blue : .secondary)
            .help(manager.logAutoScroll ? "新日志产生时自动滚至底部" : "暂停自动触底")
            
            // 复制全部日志
            Button {
                copyAllLogs()
            } label: {
                Label("复制日志", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(manager.logs.isEmpty)
            .foregroundStyle(.secondary)
            .help("将当前全部日志复制到系统剪贴板")
            
            // 清空日志
            Button(role: .destructive, action: onClear) {
                Label("清空", systemImage: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .disabled(manager.logs.isEmpty)
            .help("清空所有日志输出")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
    }
    
    // MARK: - 筛选栏与搜索栏
    private var filterAndSearchBar: some View {
        HStack(spacing: 10) {
            // 分类筛选 Pills
            HStack(spacing: 6) {
                filterChip(title: "全部", count: countTotal, level: nil, color: .primary)
                filterChip(title: "成功", count: countSuccess, level: .success, color: .green)
                filterChip(title: "警告", count: countWarning, level: .warning, color: .orange)
                filterChip(title: "错误", count: countError, level: .error, color: .red)
            }
            
            Spacer()
            
            // 搜索框
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                
                TextField("搜索账号、UID 或日志内容...", text: $manager.logSearchText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                
                if !manager.logSearchText.isEmpty {
                    Button {
                        manager.logSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(width: 220)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.8)
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.25))
    }
    
    @ViewBuilder
    private func filterChip(title: String, count: Int, level: LogLevel?, color: Color) -> some View {
        let isSelected = manager.logFilterLevel == level
        Button {
            manager.logFilterLevel = level
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(
                            Capsule()
                                .fill(isSelected ? (level?.color ?? .secondary) : Color.secondary.opacity(0.18))
                        )
                        .foregroundStyle(isSelected ? Color.white : Color.secondary)
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? color.opacity(0.15) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? color.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .foregroundStyle(isSelected ? color : .secondary)
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - 日志滚动列表
    private var logListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if filteredLogs.isEmpty {
                    emptyStateView
                } else {
                    LazyVStack(spacing: 3) {
                        ForEach(filteredLogs) { log in
                            logRowView(log)
                                .id(log.id)
                        }
                    }
                    .padding(.vertical, 6)
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.4))
            .onChange(of: manager.logs.count) {
                if manager.logAutoScroll, let last = filteredLogs.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }
    
    // MARK: - 单行渲染
    @ViewBuilder
    private func logRowView(_ log: LogMessage) -> some View {
        HStack(alignment: .center, spacing: 10) {
            // 1. 时间戳
            Text(log.formattedTime)
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 58, alignment: .leading)
            
            // 2. 状态徽章 Badge
            HStack(spacing: 3) {
                Image(systemName: log.level.icon)
                    .font(.system(size: 9))
                Text(log.level.rawValue)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(log.level.color.opacity(0.14))
            .foregroundStyle(log.level.color)
            .clipShape(Capsule())
            
            // 3. 业务 Tag
            if let tag = log.tag {
                Text(tag)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(tagBadgeColor(tag).opacity(0.12))
                    .foregroundStyle(tagBadgeColor(tag))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            
            // 4. 清晰正文
            Text(log.cleanMessage)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(logMessageColor(log.level))
                .lineLimit(2)
                .textSelection(.enabled)
            
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.clear)
        )
        .padding(.horizontal, 6)
        .contextMenu {
            Button("复制消息正文") {
                copySingleLog(log.cleanMessage)
            }
            Button("复制整条日志 (含时间与标签)") {
                copySingleLog("[\(log.formattedTime)] [\(log.level.rawValue)] \(log.content)")
            }
        }
    }
    
    // MARK: - 空状态
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: manager.logs.isEmpty ? "doc.text.magnifyingglass" : "line.3.horizontal.decrease.circle")
                .font(.system(size: 38))
                .foregroundStyle(.tertiary)
            
            Text(manager.logs.isEmpty ? "暂无运行日志" : "未找到匹配的日志")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
            
            Text(manager.logs.isEmpty ? "点击顶部「一键签到」或「刷新扫描」，将在此展示详细执行过程。" : "尝试更改筛选分类或清除搜索关键词。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            
            if !manager.logs.isEmpty && (manager.logFilterLevel != nil || !manager.logSearchText.isEmpty) {
                Button("重置筛选条件") {
                    manager.logFilterLevel = nil
                    manager.logSearchText = ""
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(30)
    }
    
    // MARK: - Helpers
    private func logMessageColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .success: return .primary
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    private func tagBadgeColor(_ tag: String) -> Color {
        if tag.contains("Trae") {
            return .blue
        } else if tag.contains("WorkBuddy") {
            return .purple
        } else if tag.contains("定时") {
            return .teal
        } else if tag.contains("扫描") {
            return .indigo
        } else {
            return .secondary
        }
    }
    
    private func copyAllLogs() {
        let text = filteredLogs.map { log in
            "[\(log.formattedTime)] [\(log.level.rawValue)] \(log.content)"
        }.joined(separator: "\n")
        
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func copySingleLog(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
