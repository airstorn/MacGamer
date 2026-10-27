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

    func testBundledWineArchiveIsAvailable() throws {
        let manifest = try RuntimeStore(paths: temporaryPaths()).loadManifest()
        let archive = try XCTUnwrap(RuntimeStore.bundledWineArchive(named: manifest.components.wine.archive))
        XCTAssertTrue(FileManager.default.fileExists(atPath: archive.path))
        let size = try FileManager.default.attributesOfItem(atPath: archive.path)[.size] as? NSNumber
        XCTAssertGreaterThan(size?.int64Value ?? 0, 1_000_000)
    }

    func testDoctorReportsChip() {
        let report = Doctor(paths: temporaryPaths()).report()
        XCTAssertFalse(report.chip.isEmpty)
        XCTAssertFalse(report.macOSVersion.isEmpty)
    }

    func testSetupGuideRequiresAppleSilicon() {
        let status = SetupGuide.status(doctor: doctorReport(chip: "x86_64"), steamConfigured: true)
        XCTAssertEqual(status.step, .unsupportedChip)
    }

    func testSetupGuideRequiresRosetta() {
        let status = SetupGuide.status(
            doctor: doctorReport(rosettaInstalled: false, runtimeInstalled: false),
            steamConfigured: false
        )
        XCTAssertEqual(status.step, .rosetta)
    }

    func testSetupGuideRequiresRuntime() {
        let status = SetupGuide.status(
            doctor: doctorReport(runtimeInstalled: false),
            steamConfigured: false
        )
        XCTAssertEqual(status.step, .runtime)
    }

    func testSetupGuideRequiresSteam() {
        let status = SetupGuide.status(doctor: doctorReport(), steamConfigured: false)
        XCTAssertEqual(status.step, .steam)
        let bottles = [
            BottleConfig(name: "Steam", role: .steam, steamExePath: nil)
        ]
        XCTAssertEqual(SetupGuide.status(doctor: doctorReport(), bottles: bottles).step, .steam)
    }

    func testSetupGuideReadyWhenSteamConfigured() {
        let bottles = [
            BottleConfig(name: "Steam", role: .steam, steamExePath: "/tmp/steam.exe")
        ]
        let status = SetupGuide.status(doctor: doctorReport(), bottles: bottles)
        XCTAssertEqual(status.step, .ready)
        XCTAssertEqual(status.title, "Готово к играм")
    }

    func testSetupGuideServicesShowHealthIcons() {
        let missing = SetupGuide.services(
            doctor: doctorReport(rosettaInstalled: false, runtimeInstalled: false),
            steamConfigured: false
        )
        XCTAssertEqual(missing.first { $0.id == "silicon" }?.health, .ok)
        XCTAssertEqual(missing.first { $0.id == "rosetta" }?.health, .missing)
        XCTAssertEqual(missing.first { $0.id == "runtime" }?.health, .missing)
        XCTAssertEqual(missing.first { $0.id == "steam" }?.health, .missing)
        XCTAssertEqual(missing.first { $0.id == "d3dmetal" }?.health, .optionalMissing)

        let ready = SetupGuide.services(
            doctor: doctorReport(),
            steamConfigured: true
        )
        XCTAssertTrue(ready.filter { $0.id != "d3dmetal" }.allSatisfy { $0.health == .ok })
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
        XCTAssertNil(command.virtualDesktop)
        XCTAssertTrue(LaunchPlanner(paths: paths).describe(command).contains("desktop: off"))
    }

    func testGameLaunchSettingsOverrideBottle() throws {
        let (paths, bottle, steamExe) = try seededSteamBottle()
        let store = LibraryStore(paths: paths)
        try store.upsert(GameEntry(
            name: "Dota 2",
            bottleId: bottle.id,
            source: .steam,
            steamAppId: 570,
            backend: .dxvk,
            hud: true,
            virtualDesktop: VirtualDesktop(width: 1920, height: 1080)
        ))

        let planner = LaunchPlanner(paths: paths)
        let command = try planner.planSteamLaunch(appId: 570, bottleId: bottle.id)
        XCTAssertEqual(command.backend, .dxvk)
        XCTAssertEqual(command.environment["DXVK_HUD"], "1")
        XCTAssertEqual(command.virtualDesktop, VirtualDesktop(width: 1920, height: 1080))
        XCTAssertEqual(
            command.arguments,
            ["explorer", "/desktop=mg-570,1920x1080", steamExe.path, "-applaunch", "570"]
        )
        XCTAssertTrue(planner.describe(command).contains("desktop: 1920x1080"))

        let withoutHud = try planner.planSteamLaunch(appId: 570, bottleId: bottle.id, hud: false)
        XCTAssertNil(withoutHud.environment["DXVK_HUD"])
        let withoutDesktop = try planner.planSteamLaunch(appId: 570, bottleId: bottle.id, desktop: .disabled)
        XCTAssertEqual(withoutDesktop.arguments, [steamExe.path, "-applaunch", "570"])
        XCTAssertNil(withoutDesktop.virtualDesktop)

        let dxmtHud = try planner.planSteamLaunch(appId: 570, bottleId: bottle.id, backend: .dxmt, hud: true)
        XCTAssertEqual(dxmtHud.backend, .dxmt)
        XCTAssertEqual(dxmtHud.environment["DXMT_DEBUG"], "1")

        let wined3d = try planner.planSteamLaunch(appId: 570, bottleId: bottle.id, backend: .wined3d)
        XCTAssertEqual(wined3d.backend, .wined3d)

        let open = try planner.planSteamOpen(bottleId: bottle.id)
        XCTAssertEqual(open.backend, .dxmt)
        XCTAssertEqual(open.arguments, [steamExe.path])
        XCTAssertNil(open.virtualDesktop)
        XCTAssertFalse(open.arguments.contains { $0.hasPrefix("/desktop=") })
    }

    func testInvalidDesktopSizeIsRejected() throws {
        XCTAssertThrowsError(try VirtualDesktop.parse("100x100")) { error in
            XCTAssertEqual(error as? MacGamerError, .invalidDesktopSize("100x100"))
        }
        XCTAssertThrowsError(try VirtualDesktop.parse("0x1080")) { error in
            XCTAssertEqual(error as? MacGamerError, .invalidDesktopSize("0x1080"))
        }
        let (paths, bottle, _) = try seededSteamBottle()
        XCTAssertThrowsError(
            try LaunchPlanner(paths: paths).planSteamLaunch(
                appId: 570,
                bottleId: bottle.id,
                desktop: .enabled(VirtualDesktop(width: 100, height: 1080))
            )
        ) { error in
            XCTAssertEqual(error as? MacGamerError, .invalidDesktopSize("100x1080"))
        }
    }

    func testUpsertPreservesLaunchSettings() throws {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        let store = LibraryStore(paths: paths)
        try store.upsert(GameEntry(
            name: "Dota 2",
            bottleId: "bottle",
            source: .steam,
            steamAppId: 570,
            backend: .dxvk,
            hud: true,
            virtualDesktop: VirtualDesktop(width: 1920, height: 1080)
        ))
        try store.upsert(GameEntry(
            name: "Dota 2",
            bottleId: "bottle",
            source: .steam,
            steamAppId: 570,
            installState: .ready
        ))
        let loaded = try store.game(steamAppId: 570)
        XCTAssertEqual(loaded.backend, .dxvk)
        XCTAssertTrue(loaded.hud)
        XCTAssertEqual(loaded.virtualDesktop, VirtualDesktop(width: 1920, height: 1080))

        let updated = try store.updateLaunchSettings(
            id: loaded.id,
            backend: .dxmt,
            hud: false,
            resetDesktop: true
        )
        XCTAssertEqual(updated.backend, .dxmt)
        XCTAssertFalse(updated.hud)
        XCTAssertNil(updated.virtualDesktop)
    }

    func testSteamSyncKeepsLaunchSettings() throws {
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

        let steam = SteamLibrary(paths: paths)
        let first = try steam.sync(bottleId: bottle.id)
        let game = try XCTUnwrap(first.first(where: { $0.steamAppId == 570 }))
        let store = LibraryStore(paths: paths)
        _ = try store.updateLaunchSettings(
            id: game.id,
            backend: .dxvk,
            hud: true,
            virtualDesktop: VirtualDesktop(width: 1600, height: 900)
        )
        let after = try steam.sync(bottleId: bottle.id)
        let kept = try XCTUnwrap(after.first(where: { $0.steamAppId == 570 }))
        XCTAssertEqual(kept.backend, .dxvk)
        XCTAssertTrue(kept.hud)
        XCTAssertEqual(kept.virtualDesktop, VirtualDesktop(width: 1600, height: 900))
    }

    func testGameIconPrefersClientIcon() throws {
        let root = try makeIconRoot()
        let folder = libraryCacheFolder(root: root, appId: 570)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("header".utf8).write(to: folder.appendingPathComponent("header.jpg"))
        try Data("icon".utf8).write(to: folder.appendingPathComponent("icon.jpg"))
        let found = GameIcons.existingLocal(appId: 570, steamRoots: [root])
        XCTAssertEqual(found?.lastPathComponent, "icon.jpg")
    }

    func testGameIconUsesPortraitAndSkipsHero() throws {
        let root = try makeIconRoot()
        let folder = libraryCacheFolder(root: root, appId: 570)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("hero".utf8).write(to: folder.appendingPathComponent("library_hero.jpg"))
        try Data("portrait".utf8).write(to: folder.appendingPathComponent("library_600x900.jpg"))
        let found = GameIcons.existingLocal(appId: 570, steamRoots: [root])
        XCTAssertEqual(found?.lastPathComponent, "library_600x900.jpg")
    }

    func testGameIconReadsFlatCacheAndGrid() throws {
        let root = try makeIconRoot()
        let libraryCache = root
            .appendingPathComponent("appcache", isDirectory: true)
            .appendingPathComponent("librarycache", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryCache, withIntermediateDirectories: true)
        let flat = libraryCache.appendingPathComponent("570_icon.jpg")
        try Data("flat".utf8).write(to: flat)
        XCTAssertEqual(GameIcons.existingLocal(appId: 570, steamRoots: [root])?.lastPathComponent, "570_icon.jpg")

        let grid = root
            .appendingPathComponent("userdata", isDirectory: true)
            .appendingPathComponent("1000", isDirectory: true)
            .appendingPathComponent("config", isDirectory: true)
            .appendingPathComponent("grid", isDirectory: true)
        try FileManager.default.createDirectory(at: grid, withIntermediateDirectories: true)
        try Data("other".utf8).write(to: grid.appendingPathComponent("5700_icon.png"))
        try Data("portrait".utf8).write(to: grid.appendingPathComponent("440p.jpg"))
        try Data("icon".utf8).write(to: grid.appendingPathComponent("440_icon.png"))
        XCTAssertEqual(GameIcons.existingLocal(appId: 440, steamRoots: [root])?.lastPathComponent, "440_icon.png")
        XCTAssertEqual(GameIcons.existingLocal(appId: 5700, steamRoots: [root])?.lastPathComponent, "5700_icon.png")
    }

    func testGameIconPrefersSquareClientIconOverLogo() throws {
        let root = try makeIconRoot()
        let folder = libraryCacheFolder(root: root, appId: 570)
        let nested = folder.appendingPathComponent("6cddc26cb124bd87d3fbacd58cd83ba33e4cb0e7", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try png(width: 640, height: 137).write(to: folder.appendingPathComponent("logo.png"))
        try png(width: 460, height: 215).write(to: nested.appendingPathComponent("library_header.jpg"))
        try png(width: 300, height: 450).write(to: nested.appendingPathComponent("library_capsule.jpg"))
        try png(width: 1000, height: 1000).write(to: folder.appendingPathComponent("be5f649217d4c7f6fc031b237e37124928d3063f.jpg"))
        let client = folder.appendingPathComponent("48eb825bb93787945065b460bdc109e395384ebf.jpg")
        try jpeg(width: 32, height: 32).write(to: client)
        XCTAssertEqual(
            GameIcons.existingLocal(appId: 570, steamRoots: [root])?.standardizedFileURL.path,
            client.standardizedFileURL.path
        )
    }

    func testGameIconLoadSkipsBrokenFile() async throws {
        let paths = temporaryPaths()
        let root = try makeIconRoot()
        let folder = libraryCacheFolder(root: root, appId: 570)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0x11, count: 48).write(to: folder.appendingPathComponent("icon.jpg"))
        try png(width: 640, height: 137).write(to: folder.appendingPathComponent("logo.png"))
        try png(width: 460, height: 215).write(to: folder.appendingPathComponent("header.jpg"))
        let client = jpeg(width: 32, height: 32)
        try client.write(to: folder.appendingPathComponent("48eb825bb93787945065b460bdc109e395384ebf.jpg"))
        let loaded = await GameIcons.load(appId: 570, steamRoots: [root], paths: paths)
        XCTAssertEqual(loaded, client)
    }

    func testGameIconCacheReplacesPreviousFile() throws {
        let paths = temporaryPaths()
        let cache = GameIconCache(paths: paths)
        let png = samplePNG()
        let saved = try cache.save(png, appId: 570)
        XCTAssertEqual(saved.pathExtension, "png")
        XCTAssertEqual(try Data(contentsOf: saved), png)
        var jpeg = Data([0xFF, 0xD8, 0xFF, 0xE1])
        jpeg.append(Data(repeating: 0x22, count: 40))
        let replaced = try cache.save(jpeg, appId: 570)
        XCTAssertEqual(replaced.pathExtension, "jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: paths.icons.appendingPathComponent("570.png").path))
        XCTAssertThrowsError(try cache.save(Data(repeating: 0x01, count: 40), appId: 570)) { error in
            XCTAssertEqual(error as? MacGamerError, .io("Некорректные данные иконки"))
        }
    }

    func testRemoteIconURLUsesAppID() throws {
        let urls = GameIcons.remoteURLs(appId: 570)
        XCTAssertEqual(
            urls.first?.absoluteString,
            "https://cdn.cloudflare.steamstatic.com/steam/apps/570/library_600x900.jpg"
        )
        XCTAssertEqual(urls.count, 2)
        XCTAssertFalse(urls.contains { $0.absoluteString.contains("header") || $0.absoluteString.contains("logo") })
        let paths = temporaryPaths()
        let bottle = BottleConfig(
            id: "b1",
            name: "Steam",
            role: .steam,
            steamExePath: "/Games/Steam/steam.exe"
        )
        let roots = GameIcons.clientRoots(bottle: bottle, paths: paths)
        XCTAssertEqual(roots.first?.lastPathComponent, "Steam")
        XCTAssertTrue(roots.contains { $0.path.contains("Program Files (x86)/Steam") })
        XCTAssertFalse(GameIcons.isImageData(Data("<html>this is not an image file</html>".utf8)))
    }

    func testLegacyLibraryJSONDecodesWithoutDesktop() throws {
        let json = """
        {"id":"g1","name":"Dota 2","bottleId":"b1","source":"steam","steamAppId":570,"installState":"ready","hud":true}
        """
        let game = try JSONDecoder().decode(GameEntry.self, from: Data(json.utf8))
        XCTAssertNil(game.virtualDesktop)
        XCTAssertNil(game.backend)
        XCTAssertTrue(game.hud)
        XCTAssertEqual(game.arguments, [])
        XCTAssertEqual(game.env, [:])
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

    private func makeIconRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("macgamer-icons-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func libraryCacheFolder(root: URL, appId: Int) -> URL {
        root
            .appendingPathComponent("appcache", isDirectory: true)
            .appendingPathComponent("librarycache", isDirectory: true)
            .appendingPathComponent(String(appId), isDirectory: true)
    }

    private func jpeg(width: Int, height: Int) -> Data {
        var data = Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00, 0x0B, 0x08])
        data.append(UInt8((height >> 8) & 0xFF))
        data.append(UInt8(height & 0xFF))
        data.append(UInt8((width >> 8) & 0xFF))
        data.append(UInt8(width & 0xFF))
        data.append(contentsOf: [0x01, 0x01, 0x11, 0x00, 0xFF, 0xD9])
        if data.count < 32 {
            data.append(Data(count: 32 - data.count))
        }
        return data
    }

    private func png(width: Int, height: Int, fill: UInt8 = 0xAB) -> Data {
        var data = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52
        ])
        for value in [width, height] {
            data.append(UInt8((value >> 24) & 0xFF))
            data.append(UInt8((value >> 16) & 0xFF))
            data.append(UInt8((value >> 8) & 0xFF))
            data.append(UInt8(value & 0xFF))
        }
        data.append(contentsOf: [0x08, 0x02, 0x00, 0x00, 0x00])
        data.append(Data(repeating: fill, count: 24))
        return data
    }

    private func samplePNG() -> Data {
        var data = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        data.append(Data(repeating: 0xAB, count: 40))
        return data
    }

    private func seededSteamBottle() throws -> (AppPaths, BottleConfig, URL) {
        let paths = temporaryPaths()
        try paths.ensureLayout()
        try seedRuntime(paths: paths)
        let bottleStore = BottleStore(paths: paths, runtimeStore: RuntimeStore(paths: paths))
        let bottle = try bottleStore.create(name: "Steam", role: .steam, backend: .dxmt, runWineboot: false)
        try makePrefixHealthy(paths: paths, bottleId: bottle.id)
        let steamExe = paths.root.appendingPathComponent("steam.exe")
        FileManager.default.createFile(atPath: steamExe.path, contents: Data())
        try bottleStore.setSteamPath(id: bottle.id, path: steamExe.path)
        return (paths, try bottleStore.load(id: bottle.id), steamExe)
    }

    private func doctorReport(
        chip: String = "arm64",
        rosettaInstalled: Bool = true,
        runtimeInstalled: Bool = true
    ) -> DoctorReport {
        DoctorReport(
            chip: chip,
            macOSVersion: "Version 14.0",
            rosettaInstalled: rosettaInstalled,
            runtimeInstalled: runtimeInstalled,
            runtimeId: runtimeInstalled ? "winecx-26.2" : nil,
            gptkCapable: runtimeInstalled,
            gptkImported: false,
            issues: []
        )
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
