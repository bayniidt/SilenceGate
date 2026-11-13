import AppKit
import CoreAudio

final class StatusController: NSObject, NSMenuDelegate {
    private let engine = GateEngine.shared
    private let prefs = Preferences.shared
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private var lastEvent = ""

    override init() {
        super.init()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
        engine.onChange = { [weak self] in self?.refreshIcon() }
        engine.onEvent = { [weak self] message in
            self?.lastEvent = message
            self?.refreshIcon()
        }
        refreshIcon()
    }

    // MARK: - 图标与悬浮提示

    private func refreshIcon() {
        let snap = engine.snapshot
        let symbol: String
        if !prefs.enabled {
            symbol = "speaker.wave.2"
        } else if snap.gateHolding {
            symbol = "speaker.slash.fill"
        } else {
            symbol = "headphones"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.toolTip = tooltip(for: snap)
    }

    private func tooltip(for snap: GateEngine.Snapshot) -> String {
        let head: String
        if !prefs.enabled {
            head = L.t(.tooltipOff)
        } else if snap.gateHolding {
            head = snap.bluetoothConnected ? L.t(.tooltipSilencedBt) : L.t(.tooltipSilenced)
        } else {
            head = L.t(.tooltipPass)
        }
        return head + "\n" + L.t(.menuCurrentOutput, snap.defaultDeviceName)
    }

    // MARK: - 菜单

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let snap = engine.snapshot

        let header = NSMenuItem(title: L.t(.menuCurrentOutput, snap.defaultDeviceName),
                                action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        let state = NSMenuItem(title: stateText(snap), action: nil, keyEquivalent: "")
        state.isEnabled = false
        menu.addItem(state)

        if let from = snap.reroutedFrom {
            let note = NSMenuItem(title: L.t(.reroutedNote, from), action: nil, keyEquivalent: "")
            note.isEnabled = false
            menu.addItem(note)
        }

        if !snap.uncontrollable.isEmpty {
            let warn = NSMenuItem(title: L.t(.warnUncontrollable, snap.uncontrollable.joined(separator: ", ")),
                                  action: nil, keyEquivalent: "")
            warn.isEnabled = false
            menu.addItem(warn)
        }

        menu.addItem(.separator())

        let enabledItem = NSMenuItem(title: L.t(.enableGate), action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = prefs.enabled ? .on : .off
        menu.addItem(enabledItem)

        let modeItem = NSMenuItem(title: L.t(.ruleMenu), action: nil, keyEquivalent: "")
        let modeMenu = NSMenu()
        for mode in GateMode.allCases {
            let item = NSMenuItem(title: mode.title, action: #selector(selectMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = prefs.mode == mode ? .on : .off
            item.toolTip = mode.detail
            modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu
        menu.addItem(modeItem)

        let autoSwitch = NSMenuItem(title: L.t(.autoSwitch), action: #selector(toggleAutoSwitch), keyEquivalent: "")
        autoSwitch.target = self
        autoSwitch.state = prefs.autoSwitchToBluetooth ? .on : .off
        menu.addItem(autoSwitch)

        let ignoreVirtual = NSMenuItem(title: L.t(.ignoreVirtual), action: #selector(toggleIgnoreVirtual), keyEquivalent: "")
        ignoreVirtual.target = self
        ignoreVirtual.state = prefs.ignoreVirtualDevices ? .on : .off
        menu.addItem(ignoreVirtual)

        menu.addItem(.separator())

        let deviceItem = NSMenuItem(title: L.t(.devicesMenu), action: nil, keyEquivalent: "")
        deviceItem.submenu = deviceMenu(snapshot: snap)
        menu.addItem(deviceItem)

        let silenceNow = NSMenuItem(title: L.t(.silenceNow), action: #selector(silenceNow), keyEquivalent: "")
        silenceNow.target = self
        menu.addItem(silenceNow)

        let rescan = NSMenuItem(title: L.t(.rescan), action: #selector(rescan), keyEquivalent: "r")
        rescan.target = self
        menu.addItem(rescan)

        menu.addItem(.separator())

        let languageItem = NSMenuItem(title: L.t(.languageMenu), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for language in Language.allCases {
            let item = NSMenuItem(title: language.title, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.rawValue
            item.state = L.preference == language ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        let login = NSMenuItem(title: L.t(.launchAtLogin), action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        let diag = NSMenuItem(title: L.t(.diagnostics), action: #selector(showDiagnostics), keyEquivalent: "")
        diag.target = self
        menu.addItem(diag)

        menu.addItem(.separator())

        let quitRestore = NSMenuItem(title: L.t(.quitRestore), action: #selector(quitRestoring), keyEquivalent: "q")
        quitRestore.target = self
        menu.addItem(quitRestore)

        let quitMuted = NSMenuItem(title: L.t(.quitKeepMuted), action: #selector(quitKeepingSilence), keyEquivalent: "")
        quitMuted.target = self
        menu.addItem(quitMuted)
    }

    private func stateText(_ snap: GateEngine.Snapshot) -> String {
        if !prefs.enabled { return L.t(.statusOff) }
        switch prefs.mode {
        case .silenceNonBluetoothAlways:
            if snap.bluetoothConnected {
                return L.t(.statusSilencedBt, snap.bluetoothNames.joined(separator: ", "))
            }
            return L.t(.statusSilenced)
        case .silenceWhenNoBluetooth:
            if snap.bluetoothConnected { return L.t(.statusPass) }
            return L.t(.statusSilenced)
        }
    }

    private func deviceMenu(snapshot snap: GateEngine.Snapshot) -> NSMenu {
        let submenu = NSMenu()
        if snap.rows.isEmpty {
            let empty = NSMenuItem(title: L.t(.noDevices), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
            return submenu
        }
        for row in snap.rows {
            var tags: [String] = [row.device.transportLabel]
            if row.isDefault { tags.append(L.t(.tagCurrent)) }
            if row.device.isBluetooth { tags.append(L.t(.tagBluetooth)) }
            if row.silenced { tags.append(L.t(.tagMuted)) }
            if row.ignored { tags.append(L.t(.tagIgnored)) }
            if !row.device.isControllable { tags.append(L.t(.tagUncontrollable)) }

            let item = NSMenuItem(title: "\(row.device.name) · \(tags.joined(separator: " · "))",
                                  action: #selector(pickDevice(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = Int(row.device.id)
            item.state = row.isDefault ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    // MARK: - 动作

    @objc private func toggleEnabled() {
        prefs.enabled.toggle()
        engine.reconcile(reason: "toggle")
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = GateMode(rawValue: raw) else { return }
        prefs.mode = mode
        engine.reconcile(reason: "mode")
    }

    @objc private func toggleAutoSwitch() {
        prefs.autoSwitchToBluetooth.toggle()
        engine.reconcile(reason: "autoswitch")
    }

    @objc private func toggleIgnoreVirtual() {
        prefs.ignoreVirtualDevices.toggle()
        engine.reconcile(reason: "virtual")
    }

    @objc private func pickDevice(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int else { return }
        engine.setDefaultOutput(AudioDeviceID(id))
    }

    @objc private func silenceNow() {
        prefs.enabled = true
        engine.silenceNow()
    }

    @objc private func rescan() {
        engine.reconcile(reason: "rescan")
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let language = Language(rawValue: raw) else { return }
        L.preference = language
        refreshIcon()
    }

    @objc private func toggleLoginItem() {
        if LoginItem.isEnabled {
            LoginItem.disable()
        } else if !LoginItem.enable() {
            let alert = NSAlert()
            alert.messageText = L.t(.alertLoginTitle)
            alert.informativeText = L.t(.alertLoginBody)
            alert.runModal()
        }
    }

    @objc private func showDiagnostics() {
        let alert = NSAlert()
        alert.messageText = L.t(.alertDiagTitle)
        var text = Diagnostics.reportText()
        if !lastEvent.isEmpty {
            text = L.t(.alertLastEvent, lastEvent) + "\n\n" + text
        }
        alert.informativeText = text
        alert.addButton(withTitle: L.t(.alertOK))
        alert.runModal()
    }

    @objc private func quitRestoring() {
        AppDelegate.shared?.restoreOnExit = true
        NSApp.terminate(nil)
    }

    @objc private func quitKeepingSilence() {
        AppDelegate.shared?.restoreOnExit = false
        NSApp.terminate(nil)
    }
}
