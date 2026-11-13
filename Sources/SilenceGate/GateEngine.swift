import CoreAudio
import Foundation

/// 我们压住某个设备之前，它原来的样子。程序崩溃后靠这份记录把音量还回去。
struct SilentTarget: Codable {
    var element: UInt32
    var volume: Float?
    var muted: UInt32?
}

struct SavedState: Codable {
    var uid: String
    var targets: [SilentTarget]
}

/// 屏蔽引擎：盯着设备列表 / 默认输出 / 音量变化，把非蓝牙输出压死。
final class GateEngine {
    static let shared = GateEngine()

    struct DeviceRow {
        let device: AudioDevice
        let isDefault: Bool
        let silenced: Bool
        let ignored: Bool
    }

    struct Snapshot {
        var rows: [DeviceRow] = []
        var defaultDeviceName: String = "—"
        var defaultIsBluetooth = false
        var bluetoothConnected = false
        var bluetoothNames: [String] = []
        var silencing = false
        var gateHolding = false
        var uncontrollable: [String] = []
        var reroutedFrom: String?
        var systemOutputName: String = "—"
    }

    private let queue = DispatchQueue(label: "com.cc.silencegate.engine")
    private let listenerQueue = DispatchQueue(label: "com.cc.silencegate.listeners")

    private var saved: [String: SavedState] = [:]
    private var knownBluetooth = Set<String>()
    private var listenerDeviceIDs = Set<AudioDeviceID>()
    private var applying = false
    private var systemListenersReady = false
    private var started = false
    private var watchdog: DispatchSourceTimer?

    private(set) var gateHolding = false
    private(set) var snapshot = Snapshot()

    /// 因为原输出"压不住"而被我们改道的记录：from 是用户原本的输出
    private var reroutedOutputFrom: AudioDeviceID?
    private var reroutedSystemFrom: AudioDeviceID?
    private var reroutedTo: AudioDeviceID?

    /// 引擎状态变了（在主线程回调）
    var onChange: (() -> Void)?
    /// 需要提示用户的事件（在主线程回调）
    var onEvent: ((String) -> Void)?

    private static let ledgerKey = "silencegate.pendingRestore"

    /// 调试开关：SILENCEGATE_SIMULATE_NO_BLUETOOTH=1 时假装没有连蓝牙耳机
    static let simulateNoBluetooth = ProcessInfo.processInfo.environment["SILENCEGATE_SIMULATE_NO_BLUETOOTH"] == "1"

    private init() {}

    // MARK: - 生命周期

    func start() {
        queue.async { [self] in
            guard !started else { return }
            started = true
            loadLeftoverLedger()
            installSystemListeners()
            startWatchdog()
            _reconcile(reason: "start")
        }
    }

    func reconcile(reason: String = "manual") {
        queue.async { [self] in _reconcile(reason: reason) }
    }

    /// 退出前把一切还原。
    func shutdown() {
        watchdog?.cancel()
        watchdog = nil
        queue.sync {
            applying = true
            let devices = AudioDevice.outputDevices()
            restoreAll(devices: devices)
            if let from = reroutedOutputFrom, let to = reroutedTo,
               CA.defaultOutputDevice() == to,
               devices.contains(where: { $0.id == from }) {
                CA.setDefaultOutputDevice(from)
            }
            if let from = reroutedSystemFrom, let to = reroutedTo,
               CA.defaultSystemOutputDevice() == to,
               devices.contains(where: { $0.id == from }) {
                CA.setDefaultSystemOutputDevice(from)
            }
            reroutedOutputFrom = nil
            reroutedSystemFrom = nil
            reroutedTo = nil
            applying = false
            gateHolding = false
        }
    }

    /// 不还原，直接掐掉（相当于"现在立刻静音"）
    func silenceNow() {
        queue.async { [self] in
            let devices = AudioDevice.outputDevices()
            applying = true
            for device in devices where include(device) && !device.isBluetooth {
                applySilence(to: device)
            }
            applying = false
            gateHolding = true
            _reconcile(reason: "silence now")
        }
    }

    func setDefaultOutput(_ id: AudioDeviceID) {
        queue.async { [self] in
            CA.setDefaultOutputDevice(id)
            _reconcile(reason: "switch output")
        }
    }

    // MARK: - 核心决策

    private func _reconcile(reason: String) {
        let prefs = Preferences.shared
        let allDevices = AudioDevice.outputDevices()
        let defaultID = CA.defaultOutputDevice()
        let systemID = CA.defaultSystemOutputDevice()
        let defaultDevice = allDevices.first { $0.id == defaultID }
        let systemDevice = allDevices.first { $0.id == systemID }
        let managed = allDevices.filter { include($0) }
        let bluetooth = Self.simulateNoBluetooth ? [] : managed.filter { $0.isBluetooth }

        // 蓝牙耳机刚接上：某些耳机不会自动接管输出，这里帮它一把
        let currentBluetooth = Set(bluetooth.map { $0.uid })
        let newlyArrived = currentBluetooth.subtracting(knownBluetooth)
        knownBluetooth = currentBluetooth

        if prefs.enabled, prefs.autoSwitchToBluetooth, !newlyArrived.isEmpty,
           let arrival = bluetooth.first(where: { newlyArrived.contains($0.uid) }),
           let current = defaultDevice, !current.isBluetooth {
            if CA.setDefaultOutputDevice(arrival.id) {
                onEvent?(L.t(.eventSwitched, arrival.name))
            }
        }

        let shouldSilence: Bool
        switch prefs.mode {
        case .silenceNonBluetoothAlways:
            shouldSilence = prefs.enabled
        case .silenceWhenNoBluetooth:
            shouldSilence = prefs.enabled && bluetooth.isEmpty
        }

        gateHolding = shouldSilence
        applying = true
        if shouldSilence {
            for device in managed where !device.isBluetooth {
                applySilence(to: device)
            }
        } else {
            restoreAll(devices: allDevices)
        }
        applying = false

        // HDMI / DisplayPort 这类数字输出根本没有音量或静音接口，
        // 端口静音做不到，那就把默认输出改道到一个"已经哑掉"的出口去。
        if shouldSilence {
            let stuck = [defaultDevice, systemDevice].compactMap { $0 }
                .filter { !$0.isBluetooth && !$0.isControllable }
            if let first = stuck.first, let sink = silentSink(in: managed) {
                if let current = defaultDevice, !current.isBluetooth, !current.isControllable,
                   sink.id != current.id, CA.setDefaultOutputDevice(sink.id) {
                    reroutedOutputFrom = current.id
                    reroutedTo = sink.id
                    onEvent?(L.t(.eventRerouted, current.name, sink.name))
                }
                if let current = systemDevice, !current.isBluetooth, !current.isControllable,
                   sink.id != current.id, CA.setDefaultSystemOutputDevice(sink.id) {
                    reroutedSystemFrom = current.id
                    reroutedTo = sink.id
                    onEvent?(L.t(.eventReroutedSystem, current.name))
                }
                _ = first
            }
        } else {
            // 放开屏蔽时，把用户原来选的输出还回去
            if let from = reroutedOutputFrom, let to = reroutedTo,
               CA.defaultOutputDevice() == to,
               allDevices.contains(where: { $0.id == from }) {
                CA.setDefaultOutputDevice(from)
            }
            if let from = reroutedSystemFrom, let to = reroutedTo,
               CA.defaultSystemOutputDevice() == to,
               allDevices.contains(where: { $0.id == from }) {
                CA.setDefaultSystemOutputDevice(from)
            }
            reroutedOutputFrom = nil
            reroutedSystemFrom = nil
            reroutedTo = nil
        }

        for device in managed { installDeviceListeners(device) }

        publish(allDevices: allDevices,
                defaultID: defaultID,
                systemID: systemID,
                bluetooth: bluetooth,
                silencing: shouldSilence,
                reason: reason)
    }

    /// 找一个"已经被我们静音、而且真的压得住"的出口，用来接收被改道的音频。
    private func silentSink(in devices: [AudioDevice]) -> AudioDevice? {
        let candidates = devices.filter { !$0.isBluetooth && $0.isControllable && saved[$0.uid] != nil }
        if let builtIn = candidates.first(where: { $0.isBuiltIn }) { return builtIn }
        return candidates.first
    }

    private func include(_ device: AudioDevice) -> Bool {
        if Preferences.shared.ignoreVirtualDevices && device.isVirtual { return false }
        return true
    }

    // MARK: - 压住 / 放开

    private func applySilence(to device: AudioDevice) {
        if saved[device.uid] == nil {
            var targets: [SilentTarget] = []
            for element in device.muteElements {
                let value = CA.uint32(device.id, CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: element))
                targets.append(SilentTarget(element: UInt32(element), volume: nil, muted: value ?? 0))
            }
            for element in device.volumeElements {
                let value = CA.float32(device.id, CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: element))
                if let index = targets.firstIndex(where: { $0.element == UInt32(element) }) {
                    targets[index].volume = value ?? 0
                } else {
                    targets.append(SilentTarget(element: UInt32(element), volume: value ?? 0, muted: nil))
                }
            }
            saved[device.uid] = SavedState(uid: device.uid, targets: targets)
            persistLedger()
        }
        enforceSilence(on: device)
    }

    private func enforceSilence(on device: AudioDevice) {
        for element in device.muteElements {
            let address = CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: element)
            if (CA.uint32(device.id, address) ?? 0) == 0 {
                CA.setUInt32(device.id, address, 1)
            }
        }
        for element in device.volumeElements {
            let address = CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: element)
            if (CA.float32(device.id, address) ?? 0) > 0.0001 {
                CA.setFloat32(device.id, address, 0)
            }
        }
    }

    private func restoreAll(devices: [AudioDevice]) {
        guard !saved.isEmpty else { return }
        let fresh = AudioDevice.outputDevices()
        for state in saved.values {
            guard let device = devices.first(where: { $0.uid == state.uid })
                    ?? fresh.first(where: { $0.uid == state.uid }) else { continue }
            for target in state.targets {
                let element = AudioObjectPropertyElement(target.element)
                if let volume = target.volume {
                    CA.setFloat32(device.id,
                                   CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: element),
                                   volume)
                }
                if let muted = target.muted {
                    CA.setUInt32(device.id,
                                 CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: element),
                                 muted)
                }
            }
        }
        saved.removeAll()
        persistLedger()
    }

    // MARK: - 崩溃残留

    private func persistLedger() {
        if saved.isEmpty {
            UserDefaults.standard.removeObject(forKey: Self.ledgerKey)
            return
        }
        if let data = try? JSONEncoder().encode(Array(saved.values)) {
            UserDefaults.standard.set(data, forKey: Self.ledgerKey)
        }
    }

    private func loadLeftoverLedger() {
        guard let data = UserDefaults.standard.data(forKey: Self.ledgerKey),
              let states = try? JSONDecoder().decode([SavedState].self, from: data),
              !states.isEmpty else { return }
        // 上次没来得及还原就退出了：先把记录接回来，
        // 这一轮该静音就继续压着，该放开就把原音量还回去。
        for state in states { saved[state.uid] = state }
        onEvent?(L.t(.eventRecovered, states.count))
    }

    // MARK: - 监听

    private func installSystemListeners() {
        guard !systemListenersReady else { return }
        systemListenersReady = true
        var addresses = [CA.addr(kAudioHardwarePropertyDevices),
                         CA.addr(kAudioHardwarePropertyDefaultOutputDevice),
                         CA.addr(kAudioHardwarePropertyDefaultSystemOutputDevice)]
        AudioObjectAddPropertyListenerBlock(CA.system, &addresses, listenerQueue) { [weak self] _, _ in
            self?.reconcile(reason: "devices or default output changed")
        }
    }

    private func installDeviceListeners(_ device: AudioDevice) {
        guard !listenerDeviceIDs.contains(device.id) else { return }
        var addresses: [AudioObjectPropertyAddress] = []
        for element in device.muteElements {
            addresses.append(CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: element))
        }
        for element in device.volumeElements {
            addresses.append(CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: element))
        }
        addresses.append(CA.addr(kAudioDevicePropertyDeviceIsAlive))
        guard !addresses.isEmpty else { return }

        listenerDeviceIDs.insert(device.id)
        AudioObjectAddPropertyListenerBlock(device.id, &addresses, listenerQueue) { [weak self] _, _ in
            guard let self else { return }
            self.queue.async {
                guard !self.applying, self.gateHolding else { return }
                self._reconcile(reason: "volume changed")
            }
        }
    }

    private func startWatchdog() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2, leeway: .milliseconds(300))
        timer.setEventHandler { [weak self] in
            guard let self, self.gateHolding else { return }
            self.applying = true
            for device in AudioDevice.outputDevices() where self.include(device) && !device.isBluetooth {
                if self.saved[device.uid] != nil { self.enforceSilence(on: device) }
            }
            self.applying = false
        }
        timer.resume()
        watchdog = timer
    }

    // MARK: - 对外快照

    private func publish(allDevices: [AudioDevice],
                         defaultID: AudioDeviceID?,
                         systemID: AudioDeviceID?,
                         bluetooth: [AudioDevice],
                         silencing: Bool,
                         reason: String) {
        var rows: [DeviceRow] = []
        for device in allDevices {
            rows.append(DeviceRow(device: device,
                                  isDefault: device.id == defaultID,
                                  silenced: saved[device.uid] != nil,
                                  ignored: !include(device)))
        }
        var snap = Snapshot()
        snap.rows = rows
        snap.defaultDeviceName = allDevices.first(where: { $0.id == defaultID })?.name ?? L.t(.none)
        snap.defaultIsBluetooth = allDevices.first(where: { $0.id == defaultID })?.isBluetooth ?? false
        snap.bluetoothConnected = !bluetooth.isEmpty
        snap.bluetoothNames = bluetooth.map { $0.name }
        snap.silencing = silencing
        snap.gateHolding = gateHolding
        snap.reroutedFrom = allDevices.first(where: { $0.id == reroutedOutputFrom || $0.id == reroutedSystemFrom })?.name
        snap.systemOutputName = allDevices.first(where: { $0.id == systemID })?.name ?? L.t(.none)
        snap.uncontrollable = allDevices
            .filter { include($0) && !$0.isBluetooth && !$0.isControllable }
            .map { $0.name }
        snapshot = snap
        _ = reason
        DispatchQueue.main.async { [weak self] in self?.onChange?() }
    }
}
