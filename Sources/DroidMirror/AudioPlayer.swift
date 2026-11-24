import AVFoundation

/// Plays scrcpy "raw" audio: 48 kHz, stereo, signed 16-bit little-endian PCM.
final class AudioPlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private let lock = NSLock()
    private var pending = 0
    private let maxPending = 6 // ~130 ms; beyond that drop packets to keep latency low

    func start() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            node.play()
        } catch {
            NSLog("DroidMirror: audio engine failed: \(error)")
        }
    }

    func stop() {
        node.stop()
        engine.stop()
    }

    func push(_ data: Data) {
        let frames = data.count / 4
        guard frames > 0, engine.isRunning else { return }
        lock.lock()
        if pending >= maxPending {
            lock.unlock()
            return
        }
        pending += 1
        lock.unlock()

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            lock.lock(); pending -= 1; lock.unlock()
            return
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        let left = channels[0], right = channels[1]
        data.withUnsafeBytes { raw in
            let samples = raw.bindMemory(to: Int16.self)
            for i in 0..<frames {
                left[i] = Float(Int16(littleEndian: samples[2 * i])) / 32768
                right[i] = Float(Int16(littleEndian: samples[2 * i + 1])) / 32768
            }
        }
        node.scheduleBuffer(buffer) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.pending -= 1
            self.lock.unlock()
        }
    }
}
