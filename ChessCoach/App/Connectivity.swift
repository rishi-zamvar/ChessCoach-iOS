import Foundation
import Network
import Observation

/// Online or not (NWPathMonitor). Screens that need the network show `ConnectionBanner` when
/// offline; coming back online sends any feedback waiting in the outbox.
@MainActor
@Observable
final class Connectivity {
  private(set) var isOnline = true
  @ObservationIgnored private let monitor = NWPathMonitor()
  @ObservationIgnored var onReconnect: () -> Void = {}

  init() {
    monitor.pathUpdateHandler = { [weak self] path in
      let online = path.status == .satisfied
      Task { @MainActor in
        guard let self else { return }
        let wasOffline = !self.isOnline
        self.isOnline = online
        if online, wasOffline { self.onReconnect() }
      }
    }
    monitor.start(queue: DispatchQueue(label: "knightlight.connectivity"))
  }
}
