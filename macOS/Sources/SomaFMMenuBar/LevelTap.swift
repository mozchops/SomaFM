import AVFoundation
import MediaToolbox

/// Measures the peak level of the decoded stream. The tap sits before
/// AVPlayer's volume stage, so the reading does not change with app or system volume.
final class LevelTap: @unchecked Sendable {
    private(set) var processingTap: MTAudioProcessingTap?
    private let onLevel: @Sendable (Double) -> Void
    private var channelCount = 1
    private var isFloat = false
    private var isNonInterleaved = false
    private var bitDepth: UInt32 = 32
    private var sampleRate: Double = 44_100
    private var windowEnergy: Float = 0
    private var windowFrames = 0
    private var smoothed = 0.0

    private init(onLevel: @escaping @Sendable (Double) -> Void) {
        self.onLevel = onLevel
    }

    static func create(onLevel: @escaping @Sendable (Double) -> Void) throws -> LevelTap {
        let meter = LevelTap(onLevel: onLevel)
        let context = Unmanaged.passRetained(meter).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context,
            init: levelTapInit,
            finalize: levelTapFinalize,
            prepare: levelTapPrepare,
            unprepare: levelTapUnprepare,
            process: levelTapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PreEffects, &tap
        )
        guard status == noErr, tap != nil else {
            Unmanaged<LevelTap>.fromOpaque(context).release()
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "Could not attach the level meter."])
        }
        meter.processingTap = tap
        return meter
    }

    fileprivate static func recover(_ pointer: UnsafeMutableRawPointer?) -> LevelTap? {
        guard let pointer else { return nil }
        return Unmanaged<LevelTap>.fromOpaque(pointer).takeUnretainedValue()
    }

    fileprivate func prepare(_ format: AudioStreamBasicDescription) {
        channelCount = max(1, Int(format.mChannelsPerFrame))
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        bitDepth = format.mBitsPerChannel
        windowEnergy = 0
        windowFrames = 0
        smoothed = 0
    }

    fileprivate func analyze(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        guard !list.isEmpty, frames > 0 else { return }
        let channels = isNonInterleaved ? min(channelCount, list.count) : channelCount
        let bytes = Int(bitDepth / 8)
        guard channels > 0, bytes > 0 else { return }

        for frame in 0..<frames {
            for channel in 0..<channels {
                guard let data = list[isNonInterleaved ? channel : 0].mData else { continue }
                let index = isNonInterleaved ? frame : frame * channelCount + channel
                let raw = UnsafeRawPointer(data)
                let sample: Float
                if isFloat && bitDepth == 32 {
                    sample = raw.loadUnaligned(fromByteOffset: index * bytes, as: Float.self)
                } else if bitDepth == 16 {
                    sample = Float(raw.loadUnaligned(fromByteOffset: index * bytes, as: Int16.self)) / 32_768
                } else if bitDepth == 32 {
                    sample = Float(raw.loadUnaligned(fromByteOffset: index * bytes, as: Int32.self)) / 2_147_483_648
                } else {
                    continue
                }
                windowEnergy += sample * sample
            }
        }
        windowFrames += frames

        // Publish about 20 times a second.
        if Double(windowFrames) >= sampleRate / 20 {
            // RMS (average energy) rather than peak: peaks sit near 0 dBFS on mastered music.
            let rms = (Double(windowEnergy) / Double(max(1, windowFrames * channels))).squareRoot()
            let db = 20 * log10(max(rms, 0.000_001))
            // Map roughly -45 dB...-8 dB so typical music swings across the whole bar.
            let raw = min(1, max(0, (db + 45) / 37))
            let level = raw * raw
            smoothed = max(level, smoothed * 0.85)
            windowEnergy = 0
            windowFrames = 0
            onLevel(smoothed)
        }
    }
}

private func levelTapInit(_ tap: MTAudioProcessingTap, _ clientInfo: UnsafeMutableRawPointer?,
                          _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>) {
    tapStorageOut.pointee = clientInfo
}

private func levelTapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<LevelTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func levelTapPrepare(_ tap: MTAudioProcessingTap, _ maxFrames: CMItemCount,
                             _ format: UnsafePointer<AudioStreamBasicDescription>) {
    LevelTap.recover(MTAudioProcessingTapGetStorage(tap))?.prepare(format.pointee)
}

private func levelTapUnprepare(_ tap: MTAudioProcessingTap) {}

private func levelTapProcess(_ tap: MTAudioProcessingTap, _ numberFrames: CMItemCount,
                             _ flags: MTAudioProcessingTapFlags,
                             _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
                             _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
                             _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>) {
    var sourceFlags: MTAudioProcessingTapFlags = 0
    let status = MTAudioProcessingTapGetSourceAudio(tap, numberFrames, bufferListInOut, &sourceFlags, nil, numberFramesOut)
    flagsOut.pointee = sourceFlags
    guard status == noErr, let meter = LevelTap.recover(MTAudioProcessingTapGetStorage(tap)) else {
        numberFramesOut.pointee = 0
        return
    }
    meter.analyze(bufferListInOut, frames: Int(numberFramesOut.pointee))
}
