import Foundation

enum GateMode: String, CaseIterable {
    /// 只要开启屏蔽，所有非蓝牙输出一律静音（推荐）。蓝牙耳机照样出声。
    case silenceNonBluetoothAlways
    /// 只有没连蓝牙耳机时才静音；连上耳机后把外放交还给系统。
    case silenceWhenNoBluetooth

    var title: String {
        switch self {
        case .silenceNonBluetoothAlways: return L.t(.ruleAlwaysTitle)
        case .silenceWhenNoBluetooth: return L.t(.ruleWhenNoBtTitle)
        }
    }

    var detail: String {
        switch self {
        case .silenceNonBluetoothAlways: return L.t(.ruleAlwaysDetail)
        case .silenceWhenNoBluetooth: return L.t(.ruleWhenNoBtDetail)
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let mode = "mode"
        static let autoSwitchToBluetooth = "autoSwitchToBluetooth"
        static let ignoreVirtualDevices = "ignoreVirtualDevices"
    }

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.mode: GateMode.silenceNonBluetoothAlways.rawValue,
            Key.autoSwitchToBluetooth: true,
            Key.ignoreVirtualDevices: true
        ])
    }

    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var mode: GateMode {
        get { GateMode(rawValue: defaults.string(forKey: Key.mode) ?? "") ?? .silenceNonBluetoothAlways }
        set { defaults.set(newValue.rawValue, forKey: Key.mode) }
    }

    /// 蓝牙耳机接上时，自动把系统默认输出切到它（否则某些耳机会"连上但没声音"）。
    var autoSwitchToBluetooth: Bool {
        get { defaults.bool(forKey: Key.autoSwitchToBluetooth) }
        set { defaults.set(newValue, forKey: Key.autoSwitchToBluetooth) }
    }

    /// 跳过虚拟声卡（向日葵、OBS、Loopback 之类），别把远程音频也掐掉。
    var ignoreVirtualDevices: Bool {
        get { defaults.bool(forKey: Key.ignoreVirtualDevices) }
        set { defaults.set(newValue, forKey: Key.ignoreVirtualDevices) }
    }
}
