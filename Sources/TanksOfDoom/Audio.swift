import AVFoundation
import TanksCore

/// Tiny synthesizer: every sound effect is generated in code at startup.
/// If no audio output is available the game simply runs silently.
final class Audio {
    enum Sound: CaseIterable {
        case cannon, machineGun, explosion, bigExplosion, hit, rocket, pickup, empty
    }

    static let shared = Audio()

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var isReady = false

    private init() {
        for sound in Sound.allCases { buffers[sound] = synthesize(sound) }
        for _ in 0..<16 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        engine.mainMixerNode.outputVolume = 0.6
        do {
            try engine.start()
            players.forEach { $0.play() }
            isReady = true
        } catch {
            isReady = false
        }
    }

    func play(_ sound: Sound, volume: Float = 1) {
        guard isReady, volume > 0.02, let buffer = buffers[sound] else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.volume = min(1, volume)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func synthesize(_ sound: Sound) -> AVAudioPCMBuffer {
        let tau = 2 * Double.pi
        switch sound {
        case .cannon:
            return render(duration: 0.6, cutoff: 900) { (t: Double, n: Double) -> Double in
                let blast = 5 * n * exp(-t * 6)
                let thump = 0.6 * sin(tau * 55 * t) * exp(-t * 8)
                return blast + thump
            }
        case .machineGun:
            return render(duration: 0.08, cutoff: 3_000) { (t: Double, n: Double) -> Double in
                3 * n * exp(-t * 50)
            }
        case .explosion:
            return render(duration: 1.0, cutoff: 600) { (t: Double, n: Double) -> Double in
                let roar = 6 * n * exp(-t * 4)
                let boom = 0.4 * sin(tau * 45 * t) * exp(-t * 5)
                return roar + boom
            }
        case .bigExplosion:
            return render(duration: 1.8, cutoff: 400) { (t: Double, n: Double) -> Double in
                let roar = 9 * n * exp(-t * 2.2)
                let boom = 0.6 * sin(tau * 35 * t) * exp(-t * 3)
                return roar + boom
            }
        case .hit:
            return render(duration: 0.3, cutoff: 4_000) { (t: Double, n: Double) -> Double in
                let crack = 2 * n * exp(-t * 30)
                let ring1 = 0.5 * sin(tau * 420 * t) * exp(-t * 12)
                let ring2 = 0.3 * sin(tau * 690 * t) * exp(-t * 15)
                return crack + ring1 + ring2
            }
        case .rocket:
            return render(duration: 0.5, cutoff: 2_000) { (t: Double, n: Double) -> Double in
                let envelope = t < 0.05 ? t / 0.05 : exp(-(t - 0.05) * 5)
                return 2 * n * envelope
            }
        case .pickup:
            return render(duration: 0.35, cutoff: 1_000) { (t: Double, _: Double) -> Double in
                let phase = tau * (500 * t + 700 * t * t)
                return 0.4 * sin(phase) * (1 - t / 0.35)
            }
        case .empty:
            return render(duration: 0.06, cutoff: 1_000) { (t: Double, _: Double) -> Double in
                0.4 * sin(tau * 1_200 * t) * exp(-t * 80)
            }
        }
    }

    /// Renders `sample(time, lowPassedNoise)` into a mono buffer.
    private func render(duration: Double, cutoff: Double, _ sample: (Double, Double) -> Double) -> AVAudioPCMBuffer {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(duration * rate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let data = buffer.floatChannelData![0]
        var rng = SeededRandom(seed: 0xA0D10)
        let alpha = min(1, 2 * Double.pi * cutoff / rate)
        var noise = 0.0
        for i in 0..<Int(frames) {
            noise += alpha * (Double.random(in: -1...1, using: &rng) - noise)
            data[i] = Float(max(-1, min(1, sample(Double(i) / rate, noise))))
        }
        return buffer
    }
}
