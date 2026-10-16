import AVFoundation
import Observation

/// Speaks the in-game coach's lines. Uses the most natural installed English voice
/// (Premium, then Enhanced) at normal pace and pitch — pitch-shifting is what makes
/// system voices sound robotic.
@MainActor
@Observable
final class CoachSpeaker: NSObject, AVSpeechSynthesizerDelegate {
  static let shared = CoachSpeaker()
  private(set) var isSpeaking = false
  @ObservationIgnored private let synth = AVSpeechSynthesizer()
  @ObservationIgnored private(set) lazy var voice = Self.naturalVoice()

  /// True when a Premium/Enhanced voice is installed (otherwise Settings suggests downloading one).
  var hasNaturalVoice: Bool { (voice?.quality ?? .default) != .default }
  var voiceName: String { voice.map { "\($0.name) (\($0.quality == .premium ? "Premium" : $0.quality == .enhanced ? "Enhanced" : "Standard"))" } ?? "System" }

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
    // A touch slower than default reads as calm, not drawn out.
    utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
    utterance.pitchMultiplier = 1
    utterance.preUtteranceDelay = 0.05
    utterance.postUtteranceDelay = 0.2
    isSpeaking = true
    synth.speak(utterance)
  }

  func stop() {
    synth.stopSpeaking(at: .immediate)
    isSpeaking = false
  }

  nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in
      guard !self.synth.isSpeaking else { return }
      self.isSpeaking = false
      // Back to move sounds that respect the silent switch.
      try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }
  }

  /// Quality dominates (a Premium voice of any accent beats a Standard one), then a
  /// male British/American voice for the old-club-coach feel.
  static func naturalVoice() -> AVSpeechSynthesisVoice? {
    let all = AVSpeechSynthesisVoice.speechVoices()
    // The coach's chosen voice: Aman, English (India) — best installed quality of it.
    if let aman = all.filter({ $0.name.hasPrefix("Aman") && $0.language == "en-IN" }).max(by: { $0.quality.rawValue < $1.quality.rawValue }) {
      return aman
    }
    let preferred = ["Jamie", "Daniel", "Arthur", "Oliver", "Evan", "Nathan", "Tom", "Aaron"]
    func score(_ v: AVSpeechSynthesisVoice) -> Int {
      var s = v.quality == .premium ? 100 : v.quality == .enhanced ? 50 : 0
      if v.gender == .male { s += 10 }
      if v.language == "en-GB" { s += 6 } else if v.language == "en-US" { s += 4 }
      if let i = preferred.firstIndex(where: v.name.contains) { s += 8 - i }
      // Novelty voices (Bells, Bubbles, Zarvox…) are never right.
      if v.voiceTraits.contains(.isNoveltyVoice) { s -= 1000 }
      return s
    }
    let english = all.filter { $0.language.hasPrefix("en") }
    return english.max { score($0) < score($1) } ?? AVSpeechSynthesisVoice(language: "en-GB")
  }
}
