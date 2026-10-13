import Foundation

public enum Diagnostics {
    public static func summarizeLog(at path: String, maxLines: Int = 40) throws -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            throw MacGamerError.io("лог не найден: \(path)")
        }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let tail = lines.suffix(maxLines)
        var summary: [String] = []
        if let backend = lines.first(where: { $0.hasPrefix("backend=") }) {
            summary.append(backend)
        }
        if let prefix = lines.first(where: { $0.hasPrefix("prefix=") }) {
            summary.append(prefix)
        }
        if let cmd = lines.first(where: { $0.hasPrefix("cmd=") }) {
            summary.append(cmd)
        }
        if let last = lines.last(where: { !$0.isEmpty }) {
            summary.append("last: \(last)")
        }
        summary.append("tail:")
        summary.append(contentsOf: tail)
        return summary.joined(separator: "\n")
    }

    public static func explain(_ error: Error) -> String {
        if let mac = error as? MacGamerError {
            return mac.errorDescription ?? String(describing: mac)
        }
        return error.localizedDescription
    }
}
