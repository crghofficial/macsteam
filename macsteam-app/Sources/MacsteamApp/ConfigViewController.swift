// Mac-friendly editor for config.yaml.

import AppKit
import Combine

final class ConfigViewController: NSViewController {
    let store: ConfigStore

    private var detailContainer: NSView!
    private var currentSection: Section = .settings

    var hideWhatsNewSwitch: NSSwitch!
    private var checkUpdateButton: NSButton?
    private var autoUpdateSwitch: NSSwitch?
    private var updaterSub: AnyCancellable?

    private var appsCardList: AppCardListView?

    enum Section: String, CaseIterable {
        case settings = "macSteam Settings"
        case apps = "Apps"

        var symbol: String {
            switch self {
            case .settings:  return "gearshape"
            case .apps:      return "app.badge"
            }
        }

        var title: String { L10n.text(rawValue) }
    }

    init(store: ConfigStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 540, height: 520))
        root.translatesAutoresizingMaskIntoConstraints = false
        detailContainer = root
        view = root
        showDetail(for: currentSection)
    }

    func select(section: Section) {
        _ = view   // force loadView() if the pane has never been shown
        showDetail(for: section)
    }

    func reloadFromStore() {
        if isViewLoaded {
            showDetail(for: currentSection)
        }
    }

    private func persisting(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            NSSound.beep()
            presentAlert(L10n.text("Couldn’t save config"), error.localizedDescription, style: .warning)
        }
    }

    private func confirmDestructive(_ message: String, informative: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informative
        alert.alertStyle = .warning
        alert.addButton(withTitle: L10n.text("Remove"))     // .alertFirstButtonReturn
        alert.addButton(withTitle: L10n.text("Cancel"))     // .alertSecondButtonReturn
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Detail routing

    private func showDetail(for section: Section) {
        currentSection = section
        appsCardList = nil

        detailContainer.subviews.forEach { $0.removeFromSuperview() }

        let content: NSView
        switch section {
        case .settings:  content = buildSettingsDetail()
        case .apps:      content = buildAppsDetail()
        }
        content.translatesAutoresizingMaskIntoConstraints = false

        detailContainer.addSubview(content)
        let m = Metrics.paneMargin
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: detailContainer.topAnchor, constant: m),
            content.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor, constant: m),
            content.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor, constant: -m),
            content.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor, constant: -m),
        ])
    }

    private func buildSettingsDetail() -> NSView {
        hideWhatsNewSwitch = NSSwitch()
        hideWhatsNewSwitch.state = store.config.hideWhatsNew ? .on : .off
        hideWhatsNewSwitch.target = self
        hideWhatsNewSwitch.action = #selector(settingsChanged)
        hideWhatsNewSwitch.setAccessibilityLabel(L10n.text("Hide What's New shelf"))

        let togglesCard = SettingsCard(rows: [
            SettingRow(title: L10n.text("Hide What's New shelf"),
                       subtitle: nil,
                       control: hideWhatsNewSwitch),
        ])

        let generalHeader = settingsGroupLabel(L10n.text("General"))

        // Updates section
        let updater = UpdaterManager.shared

        let btn = NSButton(title: L10n.text("Check for Updates…"), target: self,
                           action: #selector(checkForUpdatesTapped))
        btn.bezelStyle = .rounded
        btn.controlSize = .regular
        btn.isEnabled = updater.canCheckForUpdates
        checkUpdateButton = btn

        let autoSwitch = NSSwitch()
        autoSwitch.state = updater.automaticallyChecksForUpdates ? .on : .off
        autoSwitch.target = self
        autoSwitch.action = #selector(autoUpdateChanged)
        autoSwitch.setAccessibilityLabel(L10n.text("Automatically check for updates"))
        autoUpdateSwitch = autoSwitch

        let updatesCard = SettingsCard(rows: [
            SettingRow(title: L10n.text("Automatically check for updates"),
                       subtitle: nil,
                       control: autoSwitch),
            SettingRow(title: L10n.text("Check for Updates"),
                       subtitle: nil,
                       control: btn),
        ])

        let updatesHeader = settingsGroupLabel(L10n.text("Updates"))

        updaterSub = updater.$canCheckForUpdates
            .receive(on: DispatchQueue.main)
            .sink { [weak self] can in self?.checkUpdateButton?.isEnabled = can }

        let stack = NSStackView(views: [generalHeader, togglesCard, updatesHeader, updatesCard])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(6, after: generalHeader)
        stack.setCustomSpacing(20, after: togglesCard)
        stack.setCustomSpacing(6, after: updatesHeader)
        stack.translatesAutoresizingMaskIntoConstraints = false
        togglesCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        updatesCard.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        let m = Metrics.paneMargin
        let maxWidth = stack.widthAnchor.constraint(lessThanOrEqualToConstant: Metrics.formColumnWidth)
        let wantWidth = stack.widthAnchor.constraint(equalToConstant: Metrics.formColumnWidth)
        wantWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: root.leadingAnchor, constant: m),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -m),
            maxWidth,
            wantWidth,
        ])
        return root
    }

    @objc private func settingsChanged() {
        persisting { try store.setHideWhatsNew(hideWhatsNewSwitch.state == .on) }
    }

    @objc private func checkForUpdatesTapped() {
        UpdaterManager.shared.checkForUpdates()
    }

    @objc private func autoUpdateChanged() {
        UpdaterManager.shared.automaticallyChecksForUpdates = (autoUpdateSwitch?.state == .on)
    }

    // MARK: Apps detail (Steam game cards)

    private func buildAppsDetail() -> NSView {
        let list = AppCardListView(store: store)
        list.performRemoval = { [weak self] ids in
            guard let self else { return false }
            var ok = true
            self.persisting {
                do { try self.store.removeApps(ids) }
                catch { ok = false; throw error }
            }
            return ok
        }
        list.confirmRemoval = { [weak self, weak list] removed in
            guard let self, let list else { return true }
            let baseGames = removed.filter { list.dlcCount(for: $0) > 0 }
            if let game = baseGames.first, removed.count > 1 {
                let n = list.dlcCount(for: game)
                return self.confirmDestructive(
                    L10n.format("Remove %1$@ and its %2$@ DLC?", list.displayName(for: game), n),
                    informative: L10n.text("This removes the game and its DLC from the macSteam configuration. macSteam will no longer unlock the title."))
            }
            let formatter = ListFormatter()
            formatter.locale = L10n.locale()
            let displayNames = removed.map { list.displayName(for: $0) }
            let names = formatter.string(from: displayNames) ?? displayNames.joined(separator: ", ")
            let titleNoun = removed.count > 1 ? L10n.text("these titles") : L10n.text("the title")
            return self.confirmDestructive(
                L10n.format("Remove %1$@?", names),
                informative: L10n.format("This removes %1$@ from the macSteam configuration. macSteam will no longer unlock %2$@.", names, titleNoun))
        }
        appsCardList = list
        return list.listView
    }

}
