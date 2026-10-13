import Foundation
import XCTest
@testable import LauncherCore

final class LauncherCoreTests: XCTestCase {
    func testManifestLoads() throws {
        let manifest = try RuntimeStore(paths: temporaryPaths()).loadManifest()
        XCTAssertEqual(manifest.id, "winecx-26.2")
        XCTAssertEqual(manifest.components.dxmt.version, "0.80")
        XCTAssertTrue(manifest.gptkCapable)
    }

    func testDoctorReportsChip() {
        let report = Doctor(paths: temporaryPaths()).report()
        XCTAssertFalse(report.chip.isEmpty)
        XCTAssertFalse(report.macOSVersion.isEmpty)
    }

    func testAppManifestReadyAndInstalling() throws {
        let readyURL = try fixtureURL("appmanifest_570.acf")
        let installingURL = try fixtureURL("appmanifest_440_installing.acf")
        let ready = try XCTUnwrap(SteamVDF.parseAppManifest(at: readyURL))
        let installing = try XCTUnwrap(SteamVDF.parseAppManifest(at: installingURL))
        XCTAssertEqual(ready.appId, 570)
        XCTAssertEqual(SteamVDF.installState(for: ready.stateFlags), .ready)
        XCTAssertEqual(installing.appId, 440)
        XCTAssertEqual(SteamVDF.installState(for: installing.stateFlags), .updating)
    }

    func testSteamSyncAddsGamesFromFixtures() throws {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        try seedRuntime(paths: paths)
        let bottleStore = BottleStore(paths: paths, runtimeStore: RuntimeStore(paths: paths))
        var bottle = try bottleStore.create(name: "Steam", role: .steam, runWineboot: false)
        try makePrefixHealthy(paths: paths, bottleId: bottle.id)
        let steamRoot = paths.root.appendingPathComponent("fake-steam", isDirectory: true)
        let steamapps = steamRoot.appendingPathComponent("steamapps", isDirectory: true)
        try FileManager.default.createDirectory(at: steamapps, withIntermediateDirectories: true)
        let steamExe = steamRoot.appendingPathComponent("steam.exe")
        FileManager.default.createFile(atPath: steamExe.path, contents: Data())
        try bottleStore.setSteamPath(id: bottle.id, path: steamExe.path)
        bottle = try bottleStore.load(id: bottle.id)

        try FileManager.default.copyItem(
            at: try fixtureURL("appmanifest_570.acf"),
            to: steamapps.appendingPathComponent("appmanifest_570.acf")
        )
        try FileManager.default.copyItem(
            at: try fixtureURL("appmanifest_440_installing.acf"),
            to: steamapps.appendingPathComponent("appmanifest_440.acf")
        )

        let steam = SteamLibrary(paths: paths)
        let games = try steam.sync(bottleId: bottle.id)
        XCTAssertEqual(games.count, 2)
        XCTAssertEqual(games.first(where: { $0.steamAppId == 570 })?.installState, .ready)
        XCTAssertEqual(games.first(where: { $0.steamAppId == 440 })?.installState, .updating)

        try FileManager.default.removeItem(at: steamapps.appendingPathComponent("appmanifest_570.acf"))
        let after = try steam.sync(bottleId: bottle.id)
        XCTAssertEqual(after.first(where: { $0.steamAppId == 570 })?.installState, .missing)
    }

    func testSteamOpenRequiresPath() throws {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        try seedRuntime(paths: paths)
        let bottleStore = BottleStore(paths: paths, runtimeStore: RuntimeStore(paths: paths))
        let bottle = try bottleStore.create(name: "Steam", role: .steam, runWineboot: false)
        try makePrefixHealthy(paths: paths, bottleId: bottle.id)
        let planner = LaunchPlanner(paths: paths)
        XCTAssertThrowsError(try planner.planSteamOpen()) { error in
            XCTAssertEqual(error as? MacGamerError, .steamPathMissing)
        }
    }

    func testSteamOpenDryRunCommand() throws {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        try seedRuntime(paths: paths)
        let bottleStore = BottleStore(paths: paths, runtimeStore: RuntimeStore(paths: paths))
        let bottle = try bottleStore.create(name: "Steam", role: .steam, runWineboot: false)
        try makePrefixHealthy(paths: paths, bottleId: bottle.id)
        let steamExe = paths.root.appendingPathComponent("steam.exe")
        FileManager.default.createFile(atPath: steamExe.path, contents: Data())
        try bottleStore.setSteamPath(id: bottle.id, path: steamExe.path)

        let planner = LaunchPlanner(paths: paths)
        let command = try planner.planSteamOpen(bottleId: bottle.id)
        XCTAssertEqual(command.backend, .dxmt)
        XCTAssertTrue(command.arguments.contains(steamExe.path))
        XCTAssertEqual(command.environment["WINEDEBUG"], "-all")
        XCTAssertTrue(
            command.environment["WINEDLLPATH"] != nil
                || command.environment["WINEDLLPATH_PREPEND"] != nil
        )
        XCTAssertTrue(command.environment["WINEDLLOVERRIDES"]?.contains("d3d11=n,b") == true)
    }

    func testSteamLaunchApplLaunch() throws {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        try seedRuntime(paths: paths)
        let bottleStore = BottleStore(paths: paths, runtimeStore: RuntimeStore(paths: paths))
        let bottle = try bottleStore.create(name: "Steam", role: .steam, runWineboot: false)
        try makePrefixHealthy(paths: paths, bottleId: bottle.id)
        let steamExe = paths.root.appendingPathComponent("steam.exe")
        FileManager.default.createFile(atPath: steamExe.path, contents: Data())
        try bottleStore.setSteamPath(id: bottle.id, path: steamExe.path)
        let command = try LaunchPlanner(paths: paths).planSteamLaunch(appId: 570, bottleId: bottle.id)
        XCTAssertEqual(command.arguments, [steamExe.path, "-applaunch", "570"])
        XCTAssertEqual(command.backend, .dxmt)
    }

    func testBackendSwitchChangesEnvironment() throws {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        try seedRuntime(paths: paths)
        let bottleStore = BottleStore(paths: paths, runtimeStore: RuntimeStore(paths: paths))
        let bottle = try bottleStore.create(name: "Steam", role: .steam, backend: .dxmt, runWineboot: false)
        try makePrefixHealthy(paths: paths, bottleId: bottle.id)
        let steamExe = paths.root.appendingPathComponent("steam.exe")
        FileManager.default.createFile(atPath: steamExe.path, contents: Data())
        try bottleStore.setSteamPath(id: bottle.id, path: steamExe.path)

        let planner = LaunchPlanner(paths: paths)
        let dxmt = try planner.planSteamOpen(bottleId: bottle.id)
        try bottleStore.setBackend(id: bottle.id, backend: .dxvk)
        let dxvk = try planner.planSteamOpen(bottleId: bottle.id)
        XCTAssertEqual(dxmt.backend, .dxmt)
        XCTAssertTrue(dxmt.environment["WINEDLLPATH_PREPEND"]?.contains("overlays/dxmt") == true)
        XCTAssertTrue(dxmt.environment["WINEDLLPATH_PREPEND"]?.hasSuffix("v0.80") == true)
        XCTAssertEqual(dxvk.backend, .dxvk)
        XCTAssertNotEqual(dxmt.environment["WINEDLLOVERRIDES"], dxvk.environment["WINEDLLOVERRIDES"])
    }

    func testD3DMetalRejectedWhenNotCapable() {
        XCTAssertThrowsError(
            try BackendOverlay.environment(
                backend: .d3dmetal,
                overlayURL: URL(fileURLWithPath: "/tmp"),
                hud: false,
                gptkCapable: false,
                gptkImported: true
            )
        ) { error in
            XCTAssertEqual(error as? MacGamerError, .gptkNotCapable)
        }
    }

    func testGPTKImportFromLibRoot() throws {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        let fixture = try fixtureURL("gptk-lib")
        let importer = GPTKImporter(paths: paths)
        try importer.importFromLibRoot(fixture)
        XCTAssertTrue(importer.isImported())
        try importer.validatePayload(libRoot: paths.gptkStore)
    }

    func testLogSummary() throws {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        let log = paths.logs.appendingPathComponent("sample.log")
        let body = """
        backend=dxmt
        prefix=/tmp/prefix
        cmd=/usr/bin/arch -x86_64 wine64 steam.exe
        hello
        last-line
        """
        try body.write(to: log, atomically: true, encoding: .utf8)
        let summary = try Diagnostics.summarizeLog(at: log.path)
        XCTAssertTrue(summary.contains("backend=dxmt"))
        XCTAssertTrue(summary.contains("last: last-line"))
    }

    func testVCRUNDryRunPlan() throws {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        try seedRuntime(paths: paths)
        let bottleStore = BottleStore(paths: paths, runtimeStore: RuntimeStore(paths: paths))
        let bottle = try bottleStore.create(name: "Steam", role: .steam, runWineboot: false)
        try makePrefixHealthy(paths: paths, bottleId: bottle.id)
        let installer = paths.root.appendingPathComponent("VC_redist.x64.exe")
        FileManager.default.createFile(atPath: installer.path, contents: Data())
        let command = try DependencyInstaller(paths: paths).plannedCommand(
            bottleId: bottle.id,
            installerPath: installer.path
        )
        XCTAssertTrue(command.arguments.contains(installer.path))
        XCTAssertTrue(command.arguments.contains("/quiet"))
    }

    private func temporaryPaths() -> AppPaths {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgamer-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return AppPaths(root: url)
    }

    private func fixtureURL(_ relative: String) throws -> URL {
        let root = try XCTUnwrap(Bundle.module.resourceURL)
        let url = root.appendingPathComponent("Fixtures").appendingPathComponent(relative)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing fixture \(relative)")
        return url
    }

    private func makePrefixHealthy(paths: AppPaths, bottleId: String) throws {
        let prefix = paths.bottlePrefix(id: bottleId)
        try FileManager.default.createDirectory(
            at: prefix.appendingPathComponent("drive_c/windows/system32", isDirectory: true),
            withIntermediateDirectories: true
        )
        try Data().write(to: prefix.appendingPathComponent("user.reg"))
    }

    private func seedRuntime(paths: AppPaths) throws {
        let manifest = try RuntimeStore(paths: paths).loadManifest()
        let root = paths.runtimeDirectory(id: manifest.id)
        let bin = root.appendingPathComponent("wine/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let wine64 = bin.appendingPathComponent("wine64")
        FileManager.default.createFile(atPath: wine64.path, contents: Data("#!/bin/sh\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine64.path)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("overlays/dxmt/v0.80/x86_64-windows", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("overlays/dxvk/v1.10.3/x86_64-windows", isDirectory: true),
            withIntermediateDirectories: true
        )
        let info = InstalledRuntimeInfo(
            id: manifest.id,
            gptkCapable: manifest.gptkCapable,
            wineVersion: manifest.components.wine.version,
            dxmtVersion: manifest.components.dxmt.version,
            dxvkVersion: manifest.components.dxvk.version,
            installedAt: Date()
        )
        try JSONCoding.encoder.encode(info).write(to: root.appendingPathComponent("runtime-info.json"))
    }
}
