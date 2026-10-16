import AVFoundation

/// Speaks the in-game coach's lines in a calm, low voice.
@MainActor
final class CoachSpeaker: NSObject, AVSpeechSynthesizerDelegate {
  static let shared = CoachSpeaker()
  private let synth = AVSpeechSynthesizer()
  private lazy var voice = Self.wiseVoice()

  override private init() {
    super.init()
    synth.delegate = self
  }

  func say(_ text: String) {
    // Spoken audio plays even on silent (it's the point of the feature) and ducks music.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
    synth.stopSpeaking(at: .word)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    utterance.rate = 0.43
    utterance.pitchMultiplier = 0.82
    utterance.preUtteranceDelay = 0.1
    synth.speak(utterance)
  }

  func stop() { synth.stopSpeaking(at: .immediate) }

  nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in
      guard !self.synth.isSpeaking else { return }
      // Back to move sounds that respect the silent switch.
      try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }
  }

  /// Best installed English voice: higher quality first, then a male British voice
  /// (Daniel/Arthur sound the most like an old club coach).
  static func wiseVoice() -> AVSpeechSynthesisVoice? {
    let preferred = ["Daniel", "Arthur", "Oliver", "Gordon", "Aaron", "Fred"]
    func score(_ v: AVSpeechSynthesisVoice) -> Int {
      var s = v.quality == .premium ? 40 : v.quality == .enhanced ? 20 : 0
      if v.gender == .male { s += 10 }
      if v.language == "en-GB" { s += 6 }
      if let i = preferred.firstIndex(where: v.name.contains) { s += 5 - i }
      return s
    }
    let english = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
    return english.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: "en-GB")
  }
}
