import AVFoundation
import Foundation

/// After a paste: speak the prompt, listen, whisper the answer into the caption.
@MainActor
final class VoiceAsk: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    enum Phase: String {
        case idle, speaking, listening, transcribing
    }

    @Published var phase: Phase = .idle
    @Published var itemID: String?

    private let synth = AVSpeechSynthesizer()
    private var speakDone: CheckedContinuation<Void, Never>?
    private var recorder: AVAudioRecorder?
    private var recURL: URL?
    private var meter: Timer?
    private var heard = false
    private var silence: TimeInterval = 0
    private var elapsed: TimeInterval = 0
    private var recDone: CheckedContinuation<URL?, Never>?

    override init() {
        super.init()
        synth.delegate = self
    }

    func captureCaption(for id: String) async -> String? {
        itemID = id
        phase = .speaking
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        await speak("What did you just paste?")
        phase = .listening
        guard let wav = await recordVoice() else {
            phase = .idle
            itemID = nil
            return nil
        }
        phase = .transcribing
        let text = await Whisper.transcribe(wav: wav)
        try? FileManager.default.removeItem(at: wav)
        phase = .idle
        itemID = nil
        return text
    }

    func cancel() {
        synth.stopSpeaking(at: .immediate)
        meter?.invalidate()
        recorder?.stop()
        recorder = nil
        if let url = recURL { try? FileManager.default.removeItem(at: url) }
        recURL = nil
        if let c = speakDone { speakDone = nil; c.resume() }
        if let c = recDone { recDone = nil; c.resume(returning: nil) }
        phase = .idle
        itemID = nil
    }

    private func speak(_ line: String) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            speakDone = cont
            let u = AVSpeechUtterance(string: line)
            u.voice = AVSpeechSynthesisVoice(language: "en-US")
            u.rate = 0.47
            u.pitchMultiplier = 0.95
            synth.speak(u)
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            self.speakDone?.resume()
            self.speakDone = nil
        }
    }

    private func recordVoice() async -> URL? {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-ask-\(UUID().uuidString).wav")
        recURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            rec.prepareToRecord()
            guard rec.record() else { return nil }
            recorder = rec
        } catch {
            return nil
        }
        heard = false
        silence = 0
        elapsed = 0
        return await withCheckedContinuation { cont in
            recDone = cont
            meter = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.tick()
                }
            }
        }
    }

    private func tick() {
        guard let rec = recorder else { return }
        rec.updateMeters()
        elapsed += 0.1
        let db = rec.averagePower(forChannel: 0)
        if db > -32 {
            heard = true
            silence = 0
        } else if heard {
            silence += 0.1
        }
        let stop = (heard && silence >= 1.3 && elapsed >= 1.4) || elapsed >= 12
        if stop {
            finishRecord()
        }
    }

    private func finishRecord() {
        meter?.invalidate()
        meter = nil
        recorder?.stop()
        recorder = nil
        let url = recURL
        recURL = nil
        let result = heard ? url : nil
        recDone?.resume(returning: result)
        recDone = nil
    }
}
