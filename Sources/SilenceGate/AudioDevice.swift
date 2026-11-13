import CoreAudio
import Foundation

/// 一个可输出声音的设备，以及我们对它掌握的控制手段。
struct AudioDevice {
    let id: AudioDeviceID
    let name: String
    let uid: String
    let transport: UInt32
    let outputChannels: Int
    /// 可写的静音开关 kAudioDevicePropertyMute 所在元素
    let muteElements: [AudioObjectPropertyElement]
    /// 可写的音量 kAudioDevicePropertyVolumeScalar 所在元素
    let volumeElements: [AudioObjectPropertyElement]

    // MARK: - 分类

    var isBluetooth: Bool {
        transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE
    }

    var isVirtual: Bool {
        transport == kAudioDeviceTransportTypeVirtual
    }

    var isBuiltIn: Bool {
        transport == kAudioDeviceTransportTypeBuiltIn
    }

    var isAggregate: Bool {
        transport == kAudioDeviceTransportTypeAggregate
    }

    /// 能不能由我们真正压住（有 mute 或 volume 可写）
    var isControllable: Bool {
        !muteElements.isEmpty || !volumeElements.isEmpty
    }

    var transportLabel: String {
        switch transport {
        case kAudioDeviceTransportTypeBuiltIn: return L.t(.tpBuiltIn)
        case kAudioDeviceTransportTypeBluetooth: return L.t(.tpBluetooth)
        case kAudioDeviceTransportTypeBluetoothLE: return L.t(.tpBluetoothLE)
        case kAudioDeviceTransportTypeHDMI: return L.t(.tpHDMI)
        case kAudioDeviceTransportTypeDisplayPort: return L.t(.tpDisplayPort)
        case kAudioDeviceTransportTypeUSB: return L.t(.tpUSB)
        case kAudioDeviceTransportTypeThunderbolt: return L.t(.tpThunderbolt)
        case kAudioDeviceTransportTypeVirtual: return L.t(.tpVirtual)
        case kAudioDeviceTransportTypeAggregate: return L.t(.tpAggregate)
        case kAudioDeviceTransportTypeAirPlay: return L.t(.tpAirPlay)
        case kAudioDeviceTransportTypePCI: return L.t(.tpPCI)
        default: return L.t(.tpOther)
        }
    }

    // MARK: - 当前状态

    var currentVolume: Float32? {
        guard let element = volumeElements.first else { return nil }
        return CA.float32(id, CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: element))
    }

    var isMutedNow: Bool {
        guard let element = muteElements.first else { return false }
        let value = CA.uint32(id, CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: element))
        return (value ?? 0) != 0
    }

    // MARK: - 构建

    static func outputDevices() -> [AudioDevice] {
        CA.deviceList().compactMap { makeDevice($0) }
    }

    static func makeDevice(_ id: AudioDeviceID) -> AudioDevice? {
        let channels = CA.channelCount(id, scope: CA.outScope)
        guard channels > 0 else { return nil }

        var name = CA.string(id, CA.addr(kAudioObjectPropertyName))
            ?? CA.string(id, CA.addr(kAudioDevicePropertyDeviceNameCFString))
            ?? ""
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = L.t(.tpUnnamed)
        }
        let uid = CA.string(id, CA.addr(kAudioDevicePropertyDeviceUID)) ?? "id:\(id)"
        let transport = CA.uint32(id, CA.addr(kAudioDevicePropertyTransportType)) ?? 0

        var muteElements: [AudioObjectPropertyElement] = []
        var volumeElements: [AudioObjectPropertyElement] = []

        let mainMute = CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: kAudioObjectPropertyElementMain)
        if CA.isSettable(id, mainMute) { muteElements.append(kAudioObjectPropertyElementMain) }
        let mainVolume = CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: kAudioObjectPropertyElementMain)
        if CA.isSettable(id, mainVolume) { volumeElements.append(kAudioObjectPropertyElementMain) }

        // 有些设备（尤其 HDMI / 多声道）只有按声道可写，没有主控。
        if muteElements.isEmpty {
            for channel in 1...max(channels, 1) {
                let element = AudioObjectPropertyElement(channel)
                let a = CA.addr(kAudioDevicePropertyMute, scope: CA.outScope, element: element)
                if CA.isSettable(id, a) { muteElements.append(element) }
            }
        }
        if volumeElements.isEmpty {
            for channel in 1...max(channels, 1) {
                let element = AudioObjectPropertyElement(channel)
                let a = CA.addr(kAudioDevicePropertyVolumeScalar, scope: CA.outScope, element: element)
                if CA.isSettable(id, a) { volumeElements.append(element) }
            }
        }

        return AudioDevice(id: id,
                           name: name,
                           uid: uid,
                           transport: transport,
                           outputChannels: channels,
                           muteElements: muteElements,
                           volumeElements: volumeElements)
    }
}
