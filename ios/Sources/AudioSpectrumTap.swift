import AVFoundation
import MediaToolbox

final class AudioSpectrumTap: @unchecked Sendable {
    private(set) var processingTap: MTAudioProcessingTap?
    private let onAnalysis: @Sendable ([Double], [Double]) -> Void
    private let sampleBuffer = UnsafeMutablePointer<Float>.allocate(capacity: 1024)
    private let windowBuffer = UnsafeMutablePointer<Double>.allocate(capacity: 1024)
    private var sampleCount = 0
    private var channelCount = 0
    private var sampleRate: Double = 44_100
    private var isFloat = false
    private var isNonInterleaved = false
    private var bitDepth: UInt32 = 0
    private var smoothedLevels = Array(repeating: 0.0, count: 12)

    private init(onAnalysis: @escaping @Sendable ([Double], [Double]) -> Void) {
        self.onAnalysis = onAnalysis
    }

    deinit {
        sampleBuffer.deallocate()
        windowBuffer.deallocate()
    }

    static func create(onAnalysis: @escaping @Sendable ([Double], [Double]) -> Void) throws -> AudioSpectrumTap {
        let analyzer = AudioSpectrumTap(onAnalysis: onAnalysis)
        let context = Unmanaged.passRetained(analyzer).toOpaque()
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: context,
            init: spectrumTapInit,
            finalize: spectrumTapFinalize,
            prepare: spectrumTapPrepare,
            unprepare: spectrumTapUnprepare,
            process: spectrumTapProcess
        )

        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(
            kCFAllocatorDefault,
            &callbacks,
            kMTAudioProcessingTapCreationFlag_PostEffects,
            &tap
        )
        guard status == noErr, tap != nil else {
            Unmanaged<AudioSpectrumTap>.fromOpaque(context).release()
            throw NSError(
                domain: NSOSStatusErrorDomain,
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Could not attach the audio visualizer."]
            )
        }
        analyzer.processingTap = tap
        return analyzer
    }

    fileprivate static func recover(_ pointer: UnsafeMutableRawPointer?) -> AudioSpectrumTap? {
        guard let pointer else { return nil }
        return Unmanaged<AudioSpectrumTap>.fromOpaque(pointer).takeUnretainedValue()
    }

    fileprivate func prepare(_ format: AudioStreamBasicDescription) {
        channelCount = max(1, Int(format.mChannelsPerFrame))
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        isNonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        bitDepth = format.mBitsPerChannel
        sampleCount = 0
        smoothedLevels = Array(repeating: 0, count: 12)
        for index in 0..<1024 {
            windowBuffer[index] = 0.5 - 0.5 * cos(2.0 * Double.pi * Double(index) / 1023.0)
        }
    }

    fileprivate func analyze(_ buffers: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        let list = UnsafeMutableAudioBufferListPointer(buffers)
        guard !list.isEmpty else { return }
        let availableChannels = isNonInterleaved ? min(channelCount, list.count) : channelCount
        guard availableChannels > 0 else { return }

        for frame in 0..<frames {
            var mono: Float = 0
            var channelSamples = 0
            for channel in 0..<availableChannels {
                let bufferIndex = isNonInterleaved ? channel : 0
                guard let data = list[bufferIndex].mData else { continue }
                let sampleIndex = isNonInterleaved ? frame : frame * channelCount + channel
                let offset = sampleIndex * Int(bitDepth / 8)
                let sample: Float
                if isFloat && bitDepth == 32 {
                    sample = UnsafeRawPointer(data).loadUnaligned(fromByteOffset: offset, as: Float.self)
                } else if isFloat && bitDepth == 64 {
                    sample = Float(UnsafeRawPointer(data).loadUnaligned(fromByteOffset: offset, as: Double.self))
                } else if bitDepth == 16 {
                    sample = Float(UnsafeRawPointer(data).loadUnaligned(fromByteOffset: offset, as: Int16.self)) / 32_768
                } else if bitDepth == 32 {
                    sample = Float(UnsafeRawPointer(data).loadUnaligned(fromByteOffset: offset, as: Int32.self))
                        / 2_147_483_648
                } else {
                    continue
                }
                mono += sample
                channelSamples += 1
            }
            guard channelSamples > 0 else { continue }
            sampleBuffer[sampleCount] = mono / Float(channelSamples)
            sampleCount += 1
            if sampleCount == 1024 {
                publishSpectrum()
                sampleCount = 0
            }
        }
    }

    private func publishSpectrum() {
        let waveform = stride(from: 0, to: 1024, by: 16).map { Double(sampleBuffer[$0]) }
        let size = 1024.0
        let minimumFrequency = 45.0
        let maximumFrequency = min(16_000.0, sampleRate * 0.46)
        let ratio = pow(maximumFrequency / minimumFrequency, 1.0 / 12.0)
        var levels = [Double]()
        levels.reserveCapacity(12)

        for band in 0..<12 {
            let lower = minimumFrequency * pow(ratio, Double(band))
            let upper = minimumFrequency * pow(ratio, Double(band + 1))
            var peak = 0.0

            for probe in 0..<4 {
                let frequency = lower * pow(upper / lower, (Double(probe) + 0.5) / 4.0)
                let omega = 2.0 * Double.pi * frequency / sampleRate
                let coefficient = 2.0 * cos(omega)
                var previous = 0.0
                var previousPrevious = 0.0

                for index in 0..<1024 {
                    let input = Double(sampleBuffer[index]) * windowBuffer[index]
                    let current = input + coefficient * previous - previousPrevious
                    previousPrevious = previous
                    previous = current
                }
                let power = max(
                    0,
                    previous * previous + previousPrevious * previousPrevious
                        - coefficient * previous * previousPrevious
                )
                peak = max(peak, min(1.0, 4.0 * sqrt(power) / size))
            }

            let decibels = 20 * log10(max(peak, 0.000_001))
            let level = min(1, max(0, (decibels + 60) / 60))
            smoothedLevels[band] = max(level, smoothedLevels[band] * 0.72)
            levels.append(smoothedLevels[band])
        }
        onAnalysis(levels, waveform)
    }
}

private func spectrumTapInit(
    _ tap: MTAudioProcessingTap,
    _ clientInfo: UnsafeMutableRawPointer?,
    _ tapStorageOut: UnsafeMutablePointer<UnsafeMutableRawPointer?>
) {
    tapStorageOut.pointee = clientInfo
}

private func spectrumTapFinalize(_ tap: MTAudioProcessingTap) {
    Unmanaged<AudioSpectrumTap>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private func spectrumTapPrepare(
    _ tap: MTAudioProcessingTap,
    _ maxFrames: CMItemCount,
    _ processingFormat: UnsafePointer<AudioStreamBasicDescription>
) {
    AudioSpectrumTap.recover(MTAudioProcessingTapGetStorage(tap))?.prepare(processingFormat.pointee)
}

private func spectrumTapUnprepare(_ tap: MTAudioProcessingTap) {}

private func spectrumTapProcess(
    _ tap: MTAudioProcessingTap,
    _ numberFrames: CMItemCount,
    _ flags: MTAudioProcessingTapFlags,
    _ bufferListInOut: UnsafeMutablePointer<AudioBufferList>,
    _ numberFramesOut: UnsafeMutablePointer<CMItemCount>,
    _ flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
) {
    var sourceFlags: MTAudioProcessingTapFlags = 0
    let status = MTAudioProcessingTapGetSourceAudio(
        tap,
        numberFrames,
        bufferListInOut,
        &sourceFlags,
        nil,
        numberFramesOut
    )
    flagsOut.pointee = sourceFlags
    guard status == noErr,
          let analyzer = AudioSpectrumTap.recover(MTAudioProcessingTapGetStorage(tap)) else {
        numberFramesOut.pointee = 0
        return
    }
    analyzer.analyze(bufferListInOut, frames: Int(numberFramesOut.pointee))
}
