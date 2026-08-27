import AVFoundation
import Foundation

@MainActor
final class AudioIO: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var recordingID: String?
    @Published var playingID: String?
    @Published var seconds: Int = 0

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var tick: Timer?
    private var recURL: URL?

    func startRecording(id: String) throws {
        stopEverything()
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("primspaste-\(id).m4a")
        recURL = url
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 22_050,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let rec = try AVAudioRecorder(url: url, settings: settings)
        rec.prepareToRecord()
        guard rec.record() else {
            throw NSError(domain: "PrimsPaste", code: 1, userInfo: [NSLocalizedDescriptionKey: "recorder failed"])
        }
        recorder = rec
        recordingID = id
        seconds = 0
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.seconds += 1
            }
        }
    }

    func stopRecording() -> Data? {
        recorder?.stop()
        recorder = nil
        tick?.invalidate()
        tick = nil
        recordingID = nil
        seconds = 0
        guard let url = recURL else { return nil }
        recURL = nil
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        return data
    }

    func play(id: String, data: Data) throws {
        stopPlay()
        let p = try AVAudioPlayer(data: data)
        p.delegate = self
        p.prepareToPlay()
        p.play()
        player = p
        playingID = id
    }

    func stopPlay() {
        player?.stop()
        player = nil
        playingID = nil
    }

    func stopEverything() {
        _ = stopRecording()
        stopPlay()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.stopPlay()
        }
    }
}
