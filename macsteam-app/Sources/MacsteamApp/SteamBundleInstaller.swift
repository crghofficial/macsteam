// Steam.app bundle installer
import Foundation

enum SteamBundleInstaller {

    static let dmgURL = "https://media.steampowered.com/client/installer/steam.dmg"

    static let valveTeamID = "MXGJJ98X76"

    static func downloadAndReplace(progress: (@Sendable (String) -> Void)? = nil) throws {
        let fm = FileManager.default
        let work = Paths.configDir.appendingPathComponent("steam-dmg", isDirectory: true)
        let staleMount = work.appendingPathComponent("mnt")
        _ = Subprocess.run("/usr/bin/hdiutil", ["detach", staleMount.path, "-force"])
        try? fm.removeItem(at: work)
        _ = Subprocess.run("/bin/rm", ["-rf", work.path])
        try Paths.ensureDir(work)
        let dmg = work.appendingPathComponent("steam.dmg")
        defer {
            if (try? fm.removeItem(at: work)) == nil {
                _ = Subprocess.run("/bin/rm", ["-rf", work.path])
            }
        }

        progress?(L10n.text("Downloading a clean Steam from Valve"))
        try downloadDMG(to: dmg)

        progress?(L10n.text("Verifying the downloaded Steam"))
        let mount = work.appendingPathComponent("mnt", isDirectory: true)
        try Paths.ensureDir(mount)
        try attach(dmg, at: mount)
        defer { detach(mount) }

        let source = mount.appendingPathComponent("Steam.app")
        guard fm.fileExists(atPath: source.path) else {
            throw StepFailure(step: L10n.text("Read image"), detail: L10n.text("No Steam.app inside the downloaded image."))
        }
        try verifyValveSigned(source)

        progress?(L10n.text("Installing the clean Steam"))
        try replaceInstalled(with: source, asideDir: work)

        try verifyValveSigned(Paths.steamApp)
    }

    // MARK: - Download

    private static func downloadDMG(to dest: URL) throws {
        let r = Subprocess.run("/usr/bin/curl", ["-fSL", dmgURL, "-o", dest.path])
        guard r.code == 0, FileManager.default.fileExists(atPath: dest.path) else {
            throw StepFailure(step: L10n.text("Download Steam"),
                          detail: r.stderr.isEmpty ? L10n.format("curl exit %1$@", r.code) : r.stderr)
        }
    }

    // MARK: - Mount

    private static func attach(_ dmg: URL, at mount: URL) throws {
        let r = Subprocess.run("/usr/bin/hdiutil",
                               ["attach", dmg.path, "-nobrowse", "-readonly",
                                "-mountpoint", mount.path])
        guard r.code == 0 else {
            throw StepFailure(step: L10n.text("Mount image"),
                          detail: r.stderr.isEmpty ? L10n.format("hdiutil exit %1$@", r.code) : r.stderr)
        }
    }

    private static func detach(_ mount: URL) {
        _ = Subprocess.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
    }

    // MARK: - Verify

    static func isPristineValveBundle(_ app: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: app.path) else { return false }
        let strict = Subprocess.run("/usr/bin/codesign",
                                    ["--verify", "--strict", app.path])
        guard strict.code == 0 else { return false }
        let info = Subprocess.run("/usr/bin/codesign", ["-dvv", app.path])
        return info.stderr.contains("TeamIdentifier=\(valveTeamID)")
    }

    static func hasLoadableInjectedLibraries(_ app: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: app.path) else { return false }
        guard let insert = SteamInstaller.lsEnvironmentInsert() else { return false }
        let paths = insert.split(separator: ":").map(String.init)
        return !paths.isEmpty && paths.allSatisfy(fm.fileExists(atPath:))
    }

    private static func verifyValveSigned(_ app: URL) throws {
        let strict = Subprocess.run("/usr/bin/codesign",
                                    ["--verify", "--strict", "--verbose=2", app.path])
        guard strict.code == 0 else {
            throw StepFailure(step: L10n.text("Verify signature"),
                          detail: L10n.text("codesign strict check failed: ")
                                + (strict.stderr.isEmpty ? L10n.format("exit %1$@", strict.code) : strict.stderr))
        }
        let info = Subprocess.run("/usr/bin/codesign", ["-dvv", app.path])
        guard info.stderr.contains("TeamIdentifier=\(valveTeamID)") else {
            throw StepFailure(step: L10n.text("Verify signature"),
                          detail: L10n.format("Bundle is not signed by Valve (team %1$@).", valveTeamID))
        }
    }

    // MARK: - Replace

    private static func replaceInstalled(with source: URL, asideDir: URL) throws {
        let fm = FileManager.default
        let target = Paths.steamApp
        let aside = asideDir.appendingPathComponent("Steam.app.previous")

        Subprocess.killSteam()

        let hadExisting = fm.fileExists(atPath: target.path)
        if hadExisting {
            do {
                try? fm.removeItem(at: aside)
                try fm.moveItem(at: target, to: aside)
            } catch {
                throw StepFailure(step: L10n.text("Replace Steam"),
                              detail: L10n.format("Couldn't move the old Steam aside: %1$@", error.localizedDescription))
            }
        }

        do {
            try fm.copyItem(at: source, to: target)
        } catch {
            if hadExisting {
                try? fm.removeItem(at: target)
                try? fm.moveItem(at: aside, to: target)
            }
            throw StepFailure(step: L10n.text("Replace Steam"),
                          detail: L10n.format("Couldn't copy the clean Steam in: %1$@", error.localizedDescription))
        }
    }
}
