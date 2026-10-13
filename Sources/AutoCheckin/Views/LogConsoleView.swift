import SwiftUI

struct LogConsoleView: View {
    let logs: [LogMessage]
    let onClear: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Label("运行日志 (\(logs.count))", systemImage: "terminal.fill")
                    .font(.headline)
                
                Spacer()
                
                Button(action: onClear) {
                    Label("清空日志", systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(logs.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
            
            Divider()
            
            // Console text area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if logs.isEmpty {
                            Text("暂无日志输出，点击「扫描并检测」或「一键签到」开始。")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .padding(16)
                        } else {
                            ForEach(logs) { log in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("[\(log.formattedTime)]")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                    
                                    Text(log.content)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(logColor(log.level))
                                        .textSelection(.enabled)
                                }
                                .id(log.id)
                            }
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor).opacity(0.6))
                .onChange(of: logs.count) {
                    if let last = logs.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }
    
    private func logColor(_ level: LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
