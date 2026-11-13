import Foundation

/// 语言偏好：跟随系统 / 中文 / English
enum Language: String, CaseIterable {
    case system
    case chinese
    case english

    /// 接受 zh / zh-Hans / cn / en / english 等写法
    static func from(_ raw: String) -> Language {
        switch raw.lowercased() {
        case "zh", "cn", "chinese", "zh-hans", "zh_cn", "zh-cn": return .chinese
        case "en", "english", "en-us", "en_us": return .english
        case "system", "auto": return .system
        default: return .system
        }
    }

    var title: String {
        switch self {
        case .system: return L.t(.langSystem)
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

/// 界面文案键。中英两版放在同一张表里，改一处就够。
enum Key: String {
    // 菜单 - 状态
    case menuCurrentOutput
    case statusSilenced
    case statusSilencedBt
    case statusPass
    case statusOff
    case reroutedNote
    case warnUncontrollable

    // 菜单 - 开关
    case enableGate
    case ruleMenu
    case ruleAlwaysTitle
    case ruleAlwaysDetail
    case ruleWhenNoBtTitle
    case ruleWhenNoBtDetail
    case autoSwitch
    case ignoreVirtual
    case devicesMenu
    case silenceNow
    case rescan
    case launchAtLogin
    case diagnostics
    case quitRestore
    case quitKeepMuted
    case languageMenu

    // 语言
    case langSystem

    // 设备标签
    case tagDefaultOut
    case tagSystemOut
    case tagCurrent
    case tagBluetooth
    case tagMuted
    case tagIgnored
    case tagUncontrollable
    case noDevices
    case none

    // 悬浮提示
    case tooltipOff
    case tooltipSilenced
    case tooltipSilencedBt
    case tooltipPass

    // 弹窗
    case alertLoginTitle
    case alertLoginBody
    case alertAlreadyRunningTitle
    case alertAlreadyRunningBody
    case diagInstance
    case diagInstanceFree
    case diagInstanceTaken
    case alertDiagTitle
    case alertLastEvent
    case alertOK

    // 事件
    case eventSwitched
    case eventRerouted
    case eventReroutedSystem
    case eventRecovered

    // 传输类型
    case tpBuiltIn
    case tpBluetooth
    case tpBluetoothLE
    case tpHDMI
    case tpDisplayPort
    case tpUSB
    case tpThunderbolt
    case tpVirtual
    case tpAggregate
    case tpAirPlay
    case tpPCI
    case tpOther
    case tpUnnamed

    // 诊断
    case diagTitle
    case diagDefaultOut
    case diagSystemOut
    case diagRule
    case diagVirtualIgnored
    case diagVirtualMuted
    case diagVolume
    case diagMuteYes
    case diagMuteNo
    case diagMuteNone
    case diagControllable
    case diagYes
    case diagNo
    case diagBtDevices
    case diagBtNone
    case diagTargets
    case diagSelftestMuting
    case diagSelftestRestoring
    case diagSelftestNoControl
    case diagSelftestPass
    case diagSelftestFail
    case diagSelftestSkipped
    case diagSetOutputDone
    case diagSetOutputMissing

    // 帮助
    case helpText
}

enum L {
    static var preference: Language {
        get { Language(rawValue: UserDefaults.standard.string(forKey: "language") ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "language") }
    }

    /// 实际生效的语言
    static var resolved: Language {
        switch preference {
        case .chinese, .english:
            return preference
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.lowercased().hasPrefix("zh") ? .chinese : .english
        }
    }

    static func t(_ key: Key, _ args: CVarArg...) -> String {
        let entry = table[key] ?? (key.rawValue, key.rawValue)
        let template = resolved == .english ? entry.en : entry.zh
        return args.isEmpty ? template : String(format: template, arguments: args)
    }

    private static let table: [Key: (zh: String, en: String)] = [
        .menuCurrentOutput: ("当前输出：%@", "Output: %@"),
        .statusSilenced: ("状态：外放已静音", "Status: speakers muted"),
        .statusSilencedBt: ("状态：外放已静音，蓝牙耳机可用（%@）", "Status: speakers muted, headphones active (%@)"),
        .statusPass: ("状态：已放行（蓝牙耳机已连接）", "Status: playing through headphones"),
        .statusOff: ("状态：屏蔽已关闭", "Status: gate disabled"),
        .reroutedNote: ("「%@」没有音量接口，输出已改道到静音出口",
                        "%@ has no volume control; output rerouted to a muted sink"),
        .warnUncontrollable: ("⚠️ 压不住：%@", "⚠️ Cannot silence: %@"),

        .enableGate: ("启用屏蔽", "Enable gate"),
        .ruleMenu: ("静音规则", "Mute rule"),
        .ruleAlwaysTitle: ("始终静音非蓝牙输出", "Always mute non-Bluetooth outputs"),
        .ruleAlwaysDetail: ("内置扬声器、显示器 HDMI/DP 喇叭、USB 声卡永久静音；声音只从蓝牙耳机出。",
                            "Built-in speakers, HDMI/DP monitor speakers and USB interfaces stay muted; sound only goes to Bluetooth headphones."),
        .ruleWhenNoBtTitle: ("仅无蓝牙耳机时静音", "Mute only when no headphones"),
        .ruleWhenNoBtDetail: ("没连蓝牙耳机时静音；连上后把外放音量还给你（此时外放也能响）。",
                              "Mute while no Bluetooth headphones are connected; restore speaker volume once they connect."),
        .autoSwitch: ("蓝牙耳机接入时自动切换输出", "Auto-switch output when headphones connect"),
        .ignoreVirtual: ("忽略虚拟声卡（向日葵 / OBS 等）", "Ignore virtual audio devices (remote desktop, OBS…)"),
        .devicesMenu: ("输出设备", "Output devices"),
        .silenceNow: ("立即静音一次", "Silence now"),
        .rescan: ("重新扫描", "Rescan"),
        .launchAtLogin: ("开机自动启动", "Launch at login"),
        .diagnostics: ("诊断信息…", "Diagnostics…"),
        .quitRestore: ("退出并恢复音量", "Quit and restore volume"),
        .quitKeepMuted: ("退出（保持静音）", "Quit (stay muted)"),
        .languageMenu: ("语言 / Language", "Language / 语言"),
        .langSystem: ("跟随系统", "Follow system"),

        .tagDefaultOut: ("默认输出", "default output"),
        .tagSystemOut: ("系统提示音", "alert output"),
        .tagCurrent: ("当前", "current"),
        .tagBluetooth: ("蓝牙", "Bluetooth"),
        .tagMuted: ("已静音", "muted"),
        .tagIgnored: ("已忽略", "ignored"),
        .tagUncontrollable: ("不可控", "no control"),
        .noDevices: ("没有输出设备", "No output devices"),
        .none: ("无", "none"),

        .tooltipOff: ("SilenceGate：屏蔽已关闭，正常外放", "SilenceGate: gate off, speakers active"),
        .tooltipSilenced: ("SilenceGate：外放已静音", "SilenceGate: speakers muted"),
        .tooltipSilencedBt: ("SilenceGate：外放已静音，蓝牙耳机可用", "SilenceGate: speakers muted, headphones active"),
        .tooltipPass: ("SilenceGate：已放行（蓝牙耳机已连接）", "SilenceGate: playing through headphones"),

        .alertLoginTitle: ("无法设置开机自启", "Could not enable launch at login"),
        .alertLoginBody: ("写入 LaunchAgents 失败。请先把 App 放到 /Applications 再试。",
                          "Failed to write the LaunchAgent. Move the app to /Applications and try again."),
        .alertAlreadyRunningTitle: ("SilenceGate 已经在运行", "SilenceGate is already running"),
        .alertAlreadyRunningBody: ("同一时间只能运行一个实例，请直接用菜单栏图标（🔇 / 🎧）操作。\n正在运行的进程：PID %@",
                                   "Only one instance can run at a time. Use the menu bar icon (🔇 / 🎧) instead.\nRunning process: PID %@"),
        .diagInstance: ("运行实例：%@", "Running instance: %@"),
        .diagInstanceFree: ("没有其它实例", "no other instance"),
        .diagInstanceTaken: ("已有实例 PID %@（本次启动会被拒绝）", "already running as PID %@ (a new launch would be refused)"),
        .alertDiagTitle: ("SilenceGate 诊断", "SilenceGate diagnostics"),
        .alertLastEvent: ("最近事件：%@", "Last event: %@"),
        .alertOK: ("好", "OK"),

        .eventSwitched: ("已把输出切换到「%@」", "Switched output to %@"),
        .eventRerouted: ("「%@」没有音量接口，已把输出改道到静音的「%@」",
                         "%@ has no volume control; rerouted output to muted %@"),
        .eventReroutedSystem: ("「%@」没有音量接口，系统提示音也已改道",
                               "%@ has no volume control; system alert sound rerouted too"),
        .eventRecovered: ("检测到上次异常退出，已接管 %d 个设备的音量记录",
                          "Recovered volume records for %d device(s) after an unclean exit"),

        .tpBuiltIn: ("内置", "Built-in"),
        .tpBluetooth: ("蓝牙", "Bluetooth"),
        .tpBluetoothLE: ("蓝牙 LE", "Bluetooth LE"),
        .tpHDMI: ("HDMI", "HDMI"),
        .tpDisplayPort: ("DisplayPort", "DisplayPort"),
        .tpUSB: ("USB", "USB"),
        .tpThunderbolt: ("雷雳", "Thunderbolt"),
        .tpVirtual: ("虚拟", "Virtual"),
        .tpAggregate: ("聚合", "Aggregate"),
        .tpAirPlay: ("AirPlay", "AirPlay"),
        .tpPCI: ("PCI", "PCI"),
        .tpOther: ("其它", "Other"),
        .tpUnnamed: ("未命名输出", "Unnamed output"),

        .diagTitle: ("SilenceGate 诊断报告", "SilenceGate diagnostics report"),
        .diagDefaultOut: ("默认输出设备 ID：%@", "Default output device ID: %@"),
        .diagSystemOut: ("系统提示音输出 ID：%@", "System alert output ID: %@"),
        .diagRule: ("静音规则：%@", "Mute rule: %@"),
        .diagVirtualIgnored: ("虚拟声卡：忽略", "Virtual devices: ignored"),
        .diagVirtualMuted: ("虚拟声卡：同样静音", "Virtual devices: muted too"),
        .diagVolume: ("音量 %@", "volume %@"),
        .diagMuteYes: ("已静音", "muted"),
        .diagMuteNo: ("未静音", "unmuted"),
        .diagMuteNone: ("无静音开关", "no mute switch"),
        .diagControllable: ("可控", "controllable"),
        .diagYes: ("是", "yes"),
        .diagNo: ("否", "no"),
        .diagBtDevices: ("蓝牙输出设备：%@", "Bluetooth outputs: %@"),
        .diagBtNone: ("无（此时应静音全部外放）", "none (every speaker output should be muted now)"),
        .diagTargets: ("应被静音的设备：%@", "Devices that should be muted: %@"),
        .diagSelftestMuting: ("== 静音 ==", "== Muting =="),
        .diagSelftestRestoring: ("== 还原 ==", "== Restoring =="),
        .diagSelftestNoControl: ("⚠️ %@：没有音量/静音接口，只能靠改道到静音出口",
                                 "⚠️ %@: no volume or mute control; only redirecting to a muted sink can silence it"),
        .diagSelftestPass: ("自检通过：所有可控的非蓝牙输出都能被压住。",
                            "Self-test passed: every controllable non-Bluetooth output can be silenced."),
        .diagSelftestFail: ("自检失败：%d 个设备压不住。", "Self-test failed: %d device(s) could not be silenced."),
        .diagSelftestSkipped: ("没有非蓝牙输出设备，跳过。", "No non-Bluetooth output devices, skipped."),
        .diagSetOutputDone: ("默认输出（含系统提示音）已切到 %@", "Default output (and alert output) switched to %@"),
        .diagSetOutputMissing: ("找不到名字含「%@」的输出设备。可选：%@",
                               "No output device whose name contains %@. Available: %@"),

        .helpText: ("""
        SilenceGate — 只在蓝牙耳机上出声，其余输出一律静音

        用法:
          SilenceGate              启动菜单栏 App
          SilenceGate --probe      打印当前所有输出设备与决策（不改动任何设置）
          SilenceGate --selftest   静音全部非蓝牙输出 → 读回校验 → 还原
          SilenceGate --set-output 名字片段   调试：把默认输出切到该设备
        """, """
        SilenceGate — sound only through Bluetooth headphones, all other outputs muted

        Usage:
          SilenceGate              start the menu bar app
          SilenceGate --probe      print every output device and the current decision (changes nothing)
          SilenceGate --selftest   mute all non-Bluetooth outputs, verify, then restore
          SilenceGate --set-output NAME   debug: switch the default output to NAME
        """)
    ]
}
