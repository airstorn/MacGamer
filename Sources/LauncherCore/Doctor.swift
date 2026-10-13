import Foundation

public struct Doctor: Sendable {
    private let paths: AppPaths
    private let runtimeStore: RuntimeStore

    public init(paths: AppPaths = AppPaths()) {
        self.paths = paths
        self.runtimeStore = RuntimeStore(paths: paths)
    }

    public func report() -> DoctorReport {
        var issues: [String] = []
        let chip = Self.machineArchitecture()
        let macOSVersion = ProcessInfo.processInfo.operatingSystemVersionString
        let rosetta = Self.isRosettaInstalled()
        if chip == "arm64" && !rosetta {
            issues.append(MacGamerError.rosettaMissing.errorDescription ?? "Rosetta missing")
        }

        let installed = (try? runtimeStore.installedInfo()) != nil
        let info = try? runtimeStore.installedInfo()
        if !installed {
            issues.append(MacGamerError.runtimeNotInstalled.errorDescription ?? "Runtime missing")
        }

        let gptkImported = FileManager.default.fileExists(
            atPath: paths.gptkStore.appendingPathComponent("external/D3DMetal.framework").path
        )

        return DoctorReport(
            chip: chip,
            macOSVersion: macOSVersion,
            rosettaInstalled: rosetta,
            runtimeInstalled: installed,
            runtimeId: info?.id,
            gptkCapable: info?.gptkCapable ?? false,
            gptkImported: gptkImported,
            issues: issues
        )
    }

    public func formattedReport() -> String {
        let r = report()
        var lines = [
            "chip: \(r.chip)",
            "macos: \(r.macOSVersion)",
            "rosetta: \(r.rosettaInstalled ? "yes" : "no")",
            "runtime: \(r.runtimeInstalled ? (r.runtimeId ?? "yes") : "no")",
            "gptkCapable: \(r.gptkCapable ? "yes" : "no")",
            "gptkImported: \(r.gptkImported ? "yes" : "no")"
        ]
        if !r.issues.isEmpty {
            lines.append("issues:")
            lines.append(contentsOf: r.issues.map { "  - \($0)" })
        }
        return lines.joined(separator: "\n")
    }

    public static func machineArchitecture() -> String {
        var size = 0
        sysctlbyname("hw.machine", nil, &size, nil, 0)
        var machine = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.machine", &machine, &size, nil, 0)
        if let end = machine.firstIndex(of: 0) {
            machine = Array(machine[..<end])
        }
        return String(decoding: machine.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public static func isRosettaInstalled() -> Bool {
        let path = "/usr/libexec/rosetta/oahd"
        if FileManager.default.fileExists(atPath: path) {
            return true
        }
        let translated = "/Library/Apple/usr/libexec/oah/libRosettaRuntime"
        return FileManager.default.fileExists(atPath: translated)
    }
}
