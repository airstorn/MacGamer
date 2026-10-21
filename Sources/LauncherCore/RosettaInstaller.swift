import Foundation

public enum RosettaInstaller {
    public static func install() throws {
        if Doctor.isRosettaInstalled() {
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/softwareupdate")
        process.arguments = ["--install-rosetta", "--agree-to-license"]
        let err = Pipe()
        process.standardError = err
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MacGamerError.processFailed(
                detail.isEmpty
                    ? "не удалось установить Rosetta. Выполните: softwareupdate --install-rosetta --agree-to-license"
                    : detail
            )
        }
        if !Doctor.isRosettaInstalled() {
            throw MacGamerError.rosettaMissing
        }
    }
}
