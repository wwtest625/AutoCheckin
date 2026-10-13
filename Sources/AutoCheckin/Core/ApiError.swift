import Foundation

/// 接口调用失败时的错误描述。
///
/// 只用 `URLError(.badServerResponse)` 会让日志停在「服务器响应异常」，
/// 分不清是登录失效（401）、被频控（429）还是服务端故障（5xx）；
/// 这里把状态码与响应片段一并带出，直接落到运行控制台。
enum ApiError {

    static func httpFailure(response: URLResponse?, data: Data, context: String) -> NSError {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let hint: String
        switch status {
        case 401, 403: hint = "登录态可能已失效，请在客户端重新登录"
        case 429: hint = "请求过于频繁，已被限流"
        case 500...599: hint = "服务端异常"
        default: hint = "接口返回异常"
        }
        let snippet = String(data: data.prefix(160), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let detail = snippet.isEmpty ? hint : "\(hint)；响应: \(snippet)"
        return NSError(
            domain: "AutoCheckin.API",
            code: status,
            userInfo: [NSLocalizedDescriptionKey: "\(context) 失败，HTTP \(status)（\(detail)）"]
        )
    }
}
