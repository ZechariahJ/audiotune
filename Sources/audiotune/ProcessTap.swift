import Foundation
import CoreAudio
import AudioToolbox

/// Holds the mutable gain read by the realtime IO callback. Kept as a plain
/// class (not actor-isolated) so the audio thread can touch it without hopping
/// actors. A torn read of a Float is harmless for a volume knob.
// Deliberately @unchecked Sendable: the audio thread and main thread share this
// via raw pointer; a torn Float read for a volume knob is acceptable.
final class TapRenderContext: @unchecked Sendable {
    var gain: Float = 1.0
    // Lightweight instrumentation so we can confirm audio is really flowing.
    var peak: Float = 0
    var frames: UInt64 = 0
    var callbacks: UInt64 = 0
    // One-shot capture of the first callback's buffer layout, for diagnosis.
    var layoutCaptured = false
    var layout = ""
}

/// Realtime IO callback: copy tapped input audio to the aggregate's output,
/// scaled by the current gain. Assumes Float32 samples (Core Audio canonical).
private let renderCallback: AudioDeviceIOProc = {
    (_, _, inInputData, _, outOutputData, _, clientData) -> OSStatus in
    guard let clientData else { return noErr }
    let ctx = Unmanaged<TapRenderContext>.fromOpaque(clientData).takeUnretainedValue()
    let gain = ctx.gain

    let input = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
    let output = UnsafeMutableAudioBufferListPointer(outOutputData)

    if !ctx.layoutCaptured {
        var s = "in.buffers=\(input.count)"
        for i in 0..<input.count {
            s += " [in\(i) ch=\(input[i].mNumberChannels) bytes=\(input[i].mDataByteSize)]"
        }
        s += " out.buffers=\(output.count)"
        for i in 0..<output.count {
            s += " [out\(i) ch=\(output[i].mNumberChannels) bytes=\(output[i].mDataByteSize)]"
        }
        ctx.layout = s
        ctx.layoutCaptured = true
    }

    var peak: Float = 0
    let pairs = min(input.count, output.count)
    for i in 0..<pairs {
        let inBuf = input[i]
        let outBuf = output[i]
        guard let src = inBuf.mData, let dst = outBuf.mData else {
            if let dst = outBuf.mData { memset(dst, 0, Int(outBuf.mDataByteSize)) }
            continue
        }
        let copyBytes = min(inBuf.mDataByteSize, outBuf.mDataByteSize)
        let count = Int(copyBytes) / MemoryLayout<Float32>.size
        let s = src.assumingMemoryBound(to: Float32.self)
        let d = dst.assumingMemoryBound(to: Float32.self)
        for n in 0..<count {
            let v = s[n] * gain
            d[n] = v
            let a = v < 0 ? -v : v
            if a > peak { peak = a }
        }
        // If the output buffer is larger than what we filled, silence the rest.
        if outBuf.mDataByteSize > copyBytes {
            memset(dst.advanced(by: Int(copyBytes)), 0, Int(outBuf.mDataByteSize - copyBytes))
        }
    }
    // Silence any output buffers we had no input for.
    for i in pairs..<output.count {
        if let dst = output[i].mData { memset(dst, 0, Int(output[i].mDataByteSize)) }
    }

    if peak > ctx.peak { ctx.peak = peak }
    ctx.callbacks &+= 1
    if input.count > 0 {
        ctx.frames &+= UInt64(input[0].mDataByteSize) / UInt64(MemoryLayout<Float32>.size)
    }
    return noErr
}

/// A per-app tap: mutes the target processes' normal output, captures their
/// audio, and re-renders it through an aggregate device at an adjustable gain.
// @unchecked Sendable: start() runs off the main thread while stop()/deinit may
// run on it. In practice a tap is reserved in the controller before start and
// only torn down after; the residual race window is acceptable for this tool.
final class ProcessTap: @unchecked Sendable {
    let appName: String
    private(set) var gain: Float {
        get { context.gain }
        set { context.gain = newValue }
    }

    private let processObjects: [AudioObjectID]
    private let context = TapRenderContext()

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var running = false

    init(appName: String, processObjects: [AudioObjectID], gain: Float = 1.0) {
        self.appName = appName
        self.processObjects = processObjects
        self.context.gain = gain
    }

    func setGain(_ value: Float) { context.gain = value }

    var currentPeak: Float { context.peak }
    func resetPeak() { context.peak = 0 }

    /// Build the tap + aggregate and start rendering. Returns true on success.
    @discardableResult
    func start() -> Bool {
        guard !running else { return true }
        Log.msg("ProcessTap[\(appName)]: starting, process objects =", processObjects)

        // 1) Describe a stereo mixdown tap of the target processes, muting their
        //    normal output so we don't double up once we re-render.
        let desc = CATapDescription(stereoMixdownOfProcesses: processObjects)
        desc.name = "AudioTune-\(appName)"
        desc.isPrivate = true
        desc.muteBehavior = .mutedWhenTapped

        var status = AudioHardwareCreateProcessTap(desc, &tapID)
        guard status == noErr, tapID != kAudioObjectUnknown else {
            Log.msg("ProcessTap[\(appName)]: CreateProcessTap FAILED status =", fourCC(status))
            return false
        }
        Log.msg("ProcessTap[\(appName)]: tap created id =", tapID, "uuid =", desc.uuid.uuidString)

        // 2) Build a private aggregate device: the real output device for
        //    playback + the tap as an input source, in one synchronized IOProc.
        guard let outputUID = CoreAudioHW.defaultOutputDeviceUID() else {
            Log.msg("ProcessTap[\(appName)]: no default output device UID")
            teardown()
            return false
        }

        let aggUID = "com.zjzack.audiotune.agg.\(desc.uuid.uuidString)"
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "AudioTune \(appName)",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputUID]
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: desc.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]
            ]
        ]

        status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID)
        guard status == noErr, aggregateID != kAudioObjectUnknown else {
            Log.msg("ProcessTap[\(appName)]: CreateAggregateDevice FAILED status =", fourCC(status))
            teardown()
            return false
        }
        Log.msg("ProcessTap[\(appName)]: aggregate created id =", aggregateID, "output =", outputUID)

        // 3) Install and start the realtime IO callback.
        let clientData = Unmanaged.passUnretained(context).toOpaque()
        status = AudioDeviceCreateIOProcID(aggregateID, renderCallback, clientData, &ioProcID)
        guard status == noErr, ioProcID != nil else {
            Log.msg("ProcessTap[\(appName)]: CreateIOProcID FAILED status =", fourCC(status))
            teardown()
            return false
        }

        status = AudioDeviceStart(aggregateID, ioProcID)
        guard status == noErr else {
            Log.msg("ProcessTap[\(appName)]: AudioDeviceStart FAILED status =", fourCC(status))
            teardown()
            return false
        }

        running = true
        Log.msg("ProcessTap[\(appName)]: RUNNING (passthrough, gain = \(context.gain))")

        // Report activity shortly after start to confirm real audio is flowing.
        let ctx = context
        let name = appName
        DispatchQueue.global().asyncAfter(deadline: .now() + 2.5) {
            Log.msg("ProcessTap[\(name)]: callbacks =", ctx.callbacks,
                    "frames =", ctx.frames, "peak =", String(format: "%.4f", ctx.peak))
            Log.msg("ProcessTap[\(name)]: layout =", ctx.layout)
        }
        return true
    }

    func stop() {
        guard running else { teardown(); return }
        teardown()
        Log.msg("ProcessTap[\(appName)]: stopped")
    }

    private func teardown() {
        if let ioProcID {
            if running { AudioDeviceStop(aggregateID, ioProcID) }
            AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            self.ioProcID = nil
        }
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = AudioObjectID(kAudioObjectUnknown)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = AudioObjectID(kAudioObjectUnknown)
        }
        running = false
    }

    deinit { teardown() }
}

/// Format an OSStatus as its four-char code when printable, else the number.
func fourCC(_ status: OSStatus) -> String {
    let n = UInt32(bitPattern: status)
    let bytes = [UInt8(n >> 24 & 0xff), UInt8(n >> 16 & 0xff), UInt8(n >> 8 & 0xff), UInt8(n & 0xff)]
    if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7f }) {
        return "'\(String(bytes: bytes, encoding: .ascii) ?? "?")' (\(status))"
    }
    return "\(status)"
}
