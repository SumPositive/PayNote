import Foundation
import OSLog

/// アプリ内の簡易ログレベル
enum AppLogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    /// ログ出力時に見分けやすい接頭辞を付ける
    var prefix: String {
        switch self {
        case .debug:
            return "(d)"
        case .info:
            return "(i)"
        case .warning:
            return "(W)"
        case .error:
            return "[ERROR]"
        }
    }

    static func < (lhs: AppLogLevel, rhs: AppLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// OSLog へ橋渡しするための種別
    var osLogType: OSLogType {
        switch self {
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        }
    }
}

#if DEBUG
private let currentLogLevel: AppLogLevel = .debug
#else
private let currentLogLevel: AppLogLevel = .error
#endif

private let appLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CreditMemo", category: "App")

/// 共通ログ出力
func appLog(
    _ level: AppLogLevel,
    _ message: String,
    file: String = #fileID,
    line: Int = #line,
    function: String = #function
) {
    // リリース時は error のみ残し、通常ログは抑える
    guard currentLogLevel <= level else { return }

    let fileName = (file as NSString).lastPathComponent
    let output = "\(fileName)(\(line)) \(function) \(level.prefix) \(message)"
    appLogger.log(level: level.osLogType, "\(output, privacy: .public)")
}
