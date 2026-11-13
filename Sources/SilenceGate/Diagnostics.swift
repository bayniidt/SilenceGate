import CoreAudio
import Foundation

/// 命令行诊断（--probe / --selftest / --set-output），不启动界面。
enum Diagnostics {

    static func printReport() {
        print(reportText())
    }

    static func reportText() -> String {
        var out: [String] = []
        let devices = AudioDevice.outputDevices()
        let defaultID = CA.defaultOutputDevice()
        let systemID = CA.defaultSystemOutputDevice()

        out.append(L.t(.diagTitle))
        out.append(L.t(.diagDefaultOut, defaultID.map(String.init) ?? L.t(.none)))
        out.append(L.t(.diagSystemOut, systemID.map(String.init) ?? L.t(.none)))
        out.append(L.t(.diagRule, Preferences.shared.mode.title))
        if let owner = SingleInstance.shared.probeOwner() {
            let text = owner > 0 ? String(owner) : "?"
            out.append(L.t(.diagInstance, L.t(.diagInstanceTaken, text)))
        } else {
            out.append(L.t(.diagInstance, L.t(.diagInstanceFree)))
        }
        out.append(Preferences.shared.ignoreVirtualDevices ? L.t(.diagVirtualIgnored) : L.t(.diagVirtualMuted))
        out.append("")
        for device in devices {
            let volume = device.currentVolume.map { String(format: "%.2f", $0) } ?? "-"
            let muted: String
            if device.muteElements.isEmpty {
                muted = L.t(.diagMuteNone)
            } else {
                muted = device.isMutedNow ? L.t(.diagMuteYes) : L.t(.diagMuteNo)
            }
            let muteElements = device.muteElements.map { String($0) }.joined(separator: ",")
            let volumeElements = device.volumeElements.map { String($0) }.joined(separator: ",")

            var line = "• \(device.name) [\(device.transportLabel)] \(device.outputChannels)ch"
            if device.id == defaultID { line += "  ← " + L.t(.tagDefaultOut) }
            if device.id == systemID { line += "  ← " + L.t(.tagSystemOut) }
            if device.isBluetooth { line += "  ★" + L.t(.tagBluetooth) }
            if device.isVirtual { line += "  ◇" + L.t(.tpVirtual) }
            out.append(line)
            out.append("    \(L.t(.diagVolume, volume)) / \(muted) / \(L.t(.diagControllable)) "
                       + (device.isControllable ? L.t(.diagYes) : L.t(.diagNo)))
            out.append("    mute[\(muteElements)] volume[\(volumeElements)]")
            out.append("    uid: \(device.uid)")
        }

        let bluetooth = devices.filter { $0.isBluetooth }
        out.append("")
        out.append(L.t(.diagBtDevices,
                       bluetooth.isEmpty ? L.t(.diagBtNone) : bluetooth.map { $0.name }.joined(separator: ", ")))
        let targets = devices.filter { !$0.isBluetooth && !(Preferences.shared.ignoreVirtualDevices && $0.isVirtual) }
        out.append(L.t(.diagTargets, targets.map { $0.name }.joined(separator: ", ")))
        return out.joined(separator: "\n")
    }

    /// 调试用：把默认输出切到名字含指定子串的设备
    static func setOutput(matching needle: String) -> Int32 {
        let devices = AudioDevice.outputDevices()
        guard let device = devices.first(where: { $0.name.localizedCaseInsensitiveContains(needle) }) else {
            print(L.t(.diagSetOutputMissing, needle, devices.map { $0.name }.joined(separator: ", ")))
            return 1
        }
        CA.setDefaultOutputDevice(device.id)
        CA.setDefaultSystemOutputDevice(device.id)
        print(L.t(.diagSetOutputDone, device.name))
        return 0
    }

    /// 真刀真枪跑一遍：压住全部非蓝牙输出 → 读回确认 → 还原。
    static func selfTest() {
        let devices = AudioDevice.outputDevices()
        let targets = devices.filter { !$0.isBluetooth && !$0.isVirtual }
        guard !targets.isEmpty else {
            print(L.t(.diagSelftestSkipped))
            return
        }

        var originals: [String: [UInt32: (Float?, UInt32?)]] = [:]
        for device in targets {
            var record: [UInt32: (Float?, UInt32?)] = [:]
            for element in device.muteElements {
                record[UInt32(element)] = (nil, CA.uint32(device.id, CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: element)))
            }
            for element in device.volumeElements {
                let existing = record[UInt32(element)] ?? (nil, nil)
                record[UInt32(element)] = (CA.float32(device.id, CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: element)), existing.1)
            }
            originals[device.uid] = record
        }

        print(L.t(.diagSelftestMuting))
        for device in targets {
            for element in device.muteElements {
                CA.setUInt32(device.id, CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: element), 1)
            }
            for element in device.volumeElements {
                CA.setFloat32(device.id, CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: element), 0)
            }
        }

        Thread.sleep(forTimeInterval: 0.6)
        var failures = 0
        for device in AudioDevice.outputDevices() {
            guard originals[device.uid] != nil else { continue }
            if !device.isControllable {
                print("  " + L.t(.diagSelftestNoControl, device.name))
                continue
            }
            let volume = device.currentVolume.map { String(format: "%.3f", $0) } ?? "-"
            let muted = device.muteElements.isEmpty
                ? L.t(.diagMuteNone)
                : (device.isMutedNow ? L.t(.diagMuteYes) : L.t(.diagMuteNo))
            let ok = (device.currentVolume ?? 0) < 0.001
            if !ok { failures += 1 }
            print("  \(ok ? "✓" : "✗") \(device.name): \(L.t(.diagVolume, volume)), \(muted)")
        }

        print(L.t(.diagSelftestRestoring))
        for device in AudioDevice.outputDevices() {
            guard let record = originals[device.uid] else { continue }
            for (element, value) in record {
                let e = AudioObjectPropertyElement(element)
                if let volume = value.0 {
                    CA.setFloat32(device.id, CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: e), volume)
                }
                if let muted = value.1 {
                    CA.setUInt32(device.id, CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: e), muted)
                }
            }
            let volume = device.currentVolume.map { String(format: "%.3f", $0) } ?? "-"
            print("  \(device.name): \(L.t(.diagVolume, volume))")
        }

        print("")
        print(failures == 0 ? L.t(.diagSelftestPass) : L.t(.diagSelftestFail, failures))
    }
}
