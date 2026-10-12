#if os(Linux)
import CSDL2

/// Plays mono float sample buffers through SDL audio on a fixed set of voices.
/// Starting a sound on a busy voice cuts off what it was playing (like AVAudioPlayerNode's `.interrupts`).
public final class SoundMixer {
    private struct Voice {
        var clip = -1
        var position = 0
        var volume: Float = 0
    }

    private var device: SDL_AudioDeviceID = 0
    private let masterVolume: Float
    private var clips: [[Float]] = []
    private var voices: [Voice]
    private var nextVoice = 0

    /// Returns nil if no audio output is available.
    public init?(sampleRate: Int, voices: Int, volume: Float) {
        masterVolume = volume
        self.voices = Array(repeating: Voice(), count: voices)
        guard SDL_InitSubSystem(SDL_INIT_AUDIO) == 0 else { return nil }
        var want = SDL_AudioSpec()
        want.freq = Int32(sampleRate)
        want.format = SDL_AudioFormat(AUDIO_F32SYS)
        want.channels = 1
        want.samples = 1024
        want.callback = { userdata, stream, length in
            guard let userdata, let stream else { return }
            Unmanaged<SoundMixer>.fromOpaque(userdata).takeUnretainedValue()
                .mix(into: UnsafeMutableRawPointer(stream).assumingMemoryBound(to: Float.self), count: Int(length) / 4)
        }
        want.userdata = Unmanaged.passUnretained(self).toOpaque()
        let opened = SDL_OpenAudioDevice(nil, 0, &want, nil, 0)
        guard opened != 0 else { return nil }
        device = opened
        SDL_PauseAudioDevice(device, 0)
    }

    /// Registers a clip and returns its handle.
    public func load(_ samples: [Float]) -> Int {
        SDL_LockAudioDevice(device)
        defer { SDL_UnlockAudioDevice(device) }
        clips.append(samples)
        return clips.count - 1
    }

    public func play(_ clip: Int, volume: Float) {
        SDL_LockAudioDevice(device)
        defer { SDL_UnlockAudioDevice(device) }
        voices[nextVoice] = Voice(clip: clip, position: 0, volume: min(1, volume))
        nextVoice = (nextVoice + 1) % voices.count
    }

    /// Called on SDL's audio thread with the device locked.
    private func mix(into out: UnsafeMutablePointer<Float>, count: Int) {
        out.initialize(repeating: 0, count: count)
        for v in voices.indices where voices[v].clip >= 0 {
            let samples = clips[voices[v].clip]
            let start = voices[v].position
            let n = min(count, samples.count - start)
            let gain = voices[v].volume * masterVolume
            for i in 0..<n { out[i] += samples[start + i] * gain }
            voices[v].position += n
            if voices[v].position >= samples.count { voices[v].clip = -1 }
        }
        for i in 0..<count { out[i] = max(-1, min(1, out[i])) }
    }
}
#endif
