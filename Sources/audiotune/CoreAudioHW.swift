import Foundation
import CoreAudio

/// An output device the user can pick, identified by its stable UID.
struct AudioOutputDevice: Identifiable, Hashable {
    let uid: String
    let name: String
    var id: String { uid }
}

/// Small conveniences over the Core Audio HAL system object.
enum CoreAudioHW {

    /// Every device that can play audio, for the "auto-apply on device" picker.
    /// Skips AudioTune's own aggregate devices so our plumbing never shows up.
    static func outputDevices() -> [AudioOutputDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)

        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == noErr else { return [] }
        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.stride
        guard count > 0 else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: count)
        let status = ids.withUnsafeMutableBytes { buf in
            AudioObjectGetPropertyData(system, &address, 0, nil, &dataSize, buf.baseAddress!)
        }
        guard status == noErr else { return [] }

        var result: [AudioOutputDevice] = []
        for id in ids where hasOutputChannels(id) {
            guard let uid = deviceUID(id), let name = deviceName(id) else { continue }
            if uid.hasPrefix("com.zjzack.audiotune.agg.") { continue } // our own aggregates
            result.append(AudioOutputDevice(uid: uid, name: name))
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func hasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else {
            return false
        }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size),
                                                      alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, buffer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self))
        return list.contains { $0.mNumberChannels > 0 }
    }

    static func deviceName(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var name: CFString? = nil
        let status = withUnsafeMutablePointer(to: &name) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let name else { return nil }
        return name as String
    }
    static func defaultOutputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    static func deviceUID(_ deviceID: AudioDeviceID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<CFString?>.size)
        var uid: CFString? = nil
        let status = withUnsafeMutablePointer(to: &uid) { ptr in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, ptr)
        }
        guard status == noErr, let uid else { return nil }
        return uid as String
    }

    static func defaultOutputDeviceUID() -> String? {
        guard let id = defaultOutputDeviceID() else { return nil }
        return deviceUID(id)
    }
}
