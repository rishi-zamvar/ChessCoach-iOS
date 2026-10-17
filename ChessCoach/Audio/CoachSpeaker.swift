import AVFoundation
import ChessCoachKit
import Observation

/// Speaks the in-game coach's lines in Aman's voice from recordings bundled with the app
/// (scripts/render-coach-voice.sh), so no phone needs to download a voice. A line without a
/// recording falls back to the best installed system voice.
@MainActor
@Observable
final class CoachSpeaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
  static let shared = CoachSpeaker()
  private(set) var isSpeaking = false
  @ObservationIgnored private let synth = AVSpeechSynthesizer()
  @ObservationIgnored private var player: AVAudioPlayer?
  @ObservationIgnored private(set) lazy var voice = Self.naturalVoice()

  let voiceName = "Aman (English, India)"

  override private init() {
    super.init()
    synth.delegate = self
  }

  func say(_ text: String) {
    // Spoken audio plays even on silent (it's the point of the feature) and ducks music.
    try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers, .duckOthers])
    synth.stopSpeaking(at: .word)
    player?.stop()
    if let url = Bundle.main.url(forResource: "coach-" + CoachVoice.clipName(CoachVoice.spoken(text)), withExtension: "m4a"),
      let clip = try? AVAudioPlayer(contentsOf: url)
    {
      clip.delegate = self
      player = clip
      isSpeaking = clip.play()
      return
    }
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
    player?.stop()
    synth.stopSpeaking(at: .immediate)
    isSpeaking = false
  }

  nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in self.finished() }
  }

  nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in self.finished() }
  }

  private func finished() {
    guard !synth.isSpeaking, player?.isPlaying != true else { return }
    isSpeaking = false
    // Back to move sounds that respect the silent switch.
    try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
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
