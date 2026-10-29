import AVFoundation
import ChessCoachKit
import UIKit

/// Plays move sounds from a preloaded player pool, plus the matching haptic.
@MainActor
final class SoundPlayer: SoundSink {
  /// Several players per sound so fast sequences (premove + reply) overlap cleanly.
  private var pools: [SoundEvent: [AVAudioPlayer]] = [:]
  private var next: [SoundEvent: Int] = [:]

  var isEnabled: Bool {
    UserDefaults.standard.object(forKey: BoardSettings.soundKey) as? Bool ?? true
  }

  init() {
    // .ambient: respects the silent switch and mixes with the user's music.
    try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    for event in SoundEvent.allCases {
      guard let url = Bundle.main.url(forResource: event.rawValue, withExtension: "wav") else { continue }
      pools[event] = (0..<3).compactMap { _ in
        let player = try? AVAudioPlayer(contentsOf: url)
        player?.prepareToPlay()
        return player
      }
    }
  }

  func play(_ event: SoundEvent) { play(event, byUser: true) }

  /// The opponent's moves make a sound but no haptic (spec W9: nothing on opponent moves).
  func play(_ event: SoundEvent, byUser: Bool) {
    if byUser || event == .gameEnd || event == .check { haptic(for: event) }
    guard isEnabled, let pool = pools[event], !pool.isEmpty else { return }
    let index = next[event, default: 0]
    next[event] = (index + 1) % pool.count
    let player = pool[index]
    player.currentTime = 0
    player.play()
  }

  private func haptic(for event: SoundEvent) {
    switch event {
    case .move, .castle, .premove: Haptics.light()
    case .capture, .promote: Haptics.medium()
    case .check: Haptics.rigid()
    case .illegal: Haptics.warning()
    case .gameEnd: Haptics.success()
    case .gameStart, .lowTime: break
    }
  }
}
