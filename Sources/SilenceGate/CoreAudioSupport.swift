import CoreAudio
import Foundation

/// 薄薄一层 CoreAudio C API 的 Swift 封装。
enum CA {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static let outScope = kAudioObjectPropertyScopeOutput

    static func addr(_ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    // MARK: - 属性查询

    static func size(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var a = address
        var s: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &s) == noErr else { return nil }
        return s
    }

    static func has(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var a = address
        return AudioObjectHasProperty(object, &a)
    }

    static func isSettable(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Bool {
        var a = address
        var settable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(object, &a, &settable) == noErr else { return false }
        return settable.boolValue
    }

    static func uint32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> UInt32? {
        var a = address
        var value: UInt32 = 0
        var s = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &s, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    static func setUInt32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: UInt32) -> Bool {
        var a = address
        var v = value
        return AudioObjectSetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v) == noErr
    }

    static func float32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> Float32? {
        var a = address
        var value: Float32 = 0
        var s = UInt32(MemoryLayout<Float32>.size)
        guard AudioObjectGetPropertyData(object, &a, 0, nil, &s, &value) == noErr else { return nil }
        return value
    }

    @discardableResult
    static func setFloat32(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress, _ value: Float32) -> Bool {
        var a = address
        var v = value
        return AudioObjectSetPropertyData(object, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &v) == noErr
    }

    static func string(_ object: AudioObjectID, _ address: AudioObjectPropertyAddress) -> String? {
        var a = address
        var raw: Unmanaged<CFString>?
        var s = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let err = withUnsafeMutablePointer(to: &raw) { pointer in
            AudioObjectGetPropertyData(object, &a, 0, nil, &s, pointer)
        }
        guard err == noErr, let value = raw else { return nil }
        return value.takeRetainedValue() as String
    }

    // MARK: - 设备枚举

    static func deviceList() -> [AudioDeviceID] {
        let a = addr(kAudioHardwarePropertyDevices)
        guard let s = size(system, a), s > 0 else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(s) / MemoryLayout<AudioDeviceID>.size)
        var aa = a
        var ss = s
        let err = ids.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(system, &aa, 0, nil, &ss, buffer.baseAddress!)
        }
        guard err == noErr else { return [] }
        return Array(ids.prefix(Int(ss) / MemoryLayout<AudioDeviceID>.size))
    }

    static func channelCount(_ device: AudioDeviceID, scope: AudioObjectPropertyScope) -> Int {
        let a = addr(kAudioDevicePropertyStreamConfiguration, scope: scope)
        guard let s = size(device, a), s >= UInt32(MemoryLayout<AudioBufferList>.size) else { return 0 }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(s),
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        var aa = a
        var ss = s
        guard AudioObjectGetPropertyData(device, &aa, 0, nil, &ss, raw) == noErr else { return 0 }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        var total = 0
        for buffer in list { total += Int(buffer.mNumberChannels) }
        return total
    }

    // MARK: - 默认输出设备

    static func defaultOutputDevice() -> AudioDeviceID? {
        guard let id = uint32(system, addr(kAudioHardwarePropertyDefaultOutputDevice)), id != 0 else { return nil }
        return id
    }

    @discardableResult
    static func setDefaultOutputDevice(_ id: AudioDeviceID) -> Bool {
        setUInt32(system, addr(kAudioHardwarePropertyDefaultOutputDevice), id)
    }

    /// 系统提示音那一路出口，通常和默认输出相同，但可以不一样。
    static func defaultSystemOutputDevice() -> AudioDeviceID? {
        guard let id = uint32(system, addr(kAudioHardwarePropertyDefaultSystemOutputDevice)), id != 0 else { return nil }
        return id
    }

    @discardableResult
    static func setDefaultSystemOutputDevice(_ id: AudioDeviceID) -> Bool {
        setUInt32(system, addr(kAudioHardwarePropertyDefaultSystemOutputDevice), id)
    }
}
