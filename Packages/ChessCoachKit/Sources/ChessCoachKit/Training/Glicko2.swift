import Foundation

/// Glicko-2 rating (Glickman, "Example of the Glicko-2 system"), the system the
/// Lichess puzzle ratings use. Puzzles are treated as fixed-rating opponents.
public struct Glicko2: Codable, Equatable, Sendable {
  public var rating: Double
  public var deviation: Double
  public var volatility: Double

  public init(rating: Double = 1500, deviation: Double = 350, volatility: Double = 0.06) {
    self.rating = rating
    self.deviation = deviation
    self.volatility = volatility
  }

  public struct Game: Sendable {
    public var opponentRating: Double
    public var opponentDeviation: Double
    /// 1 win, 0.5 draw, 0 loss.
    public var score: Double

    public init(opponentRating: Double, opponentDeviation: Double, score: Double) {
      self.opponentRating = opponentRating
      self.opponentDeviation = opponentDeviation
      self.score = score
    }
  }

  static let scale = 173.7178
  static let tau = 0.5
  /// Lichess-style bounds so ratings stay responsive but never wild.
  static let minDeviation = 45.0
  static let maxDeviation = 350.0

  /// Rating after one rating period containing `games`.
  public func updated(with games: [Game], weight: Double = 1) -> Glicko2 {
    let mu = (rating - 1500) / Self.scale
    let phi = deviation / Self.scale
    guard !games.isEmpty else {
      let grown = min(Self.maxDeviation / Self.scale, (phi * phi + volatility * volatility).squareRoot())
      return Glicko2(rating: rating, deviation: grown * Self.scale, volatility: volatility)
    }

    var vInverse = 0.0
    var deltaSum = 0.0
    for game in games {
      let muJ = (game.opponentRating - 1500) / Self.scale
      let phiJ = game.opponentDeviation / Self.scale
      let gJ = Self.g(phiJ)
      let eJ = 1 / (1 + exp(-gJ * (mu - muJ)))
      vInverse += gJ * gJ * eJ * (1 - eJ)
      deltaSum += gJ * (game.score - eJ)
    }
    let v = 1 / vInverse
    let delta = v * deltaSum

    let sigma = Self.newVolatility(sigma: volatility, phi: phi, v: v, delta: delta)
    let phiStar = (phi * phi + sigma * sigma).squareRoot()
    var phiNew = 1 / (1 / (phiStar * phiStar) + 1 / v).squareRoot()
    var muNew = mu + phiNew * phiNew * deltaSum

    // Partial update (e.g. a puzzle's secondary themes count half).
    if weight < 1 {
      muNew = mu + (muNew - mu) * weight
      phiNew = phi + (phiNew - phi) * weight
    }
    let newDeviation = max(Self.minDeviation, min(Self.maxDeviation, phiNew * Self.scale))
    return Glicko2(rating: muNew * Self.scale + 1500, deviation: newDeviation, volatility: sigma)
  }

  public func updated(vs opponentRating: Double, deviation opponentDeviation: Double, score: Double, weight: Double = 1) -> Glicko2 {
    updated(with: [Game(opponentRating: opponentRating, opponentDeviation: opponentDeviation, score: score)], weight: weight)
  }

  /// Expected score against an opponent.
  public func expectedScore(vs opponentRating: Double, deviation opponentDeviation: Double) -> Double {
    let mu = (rating - 1500) / Self.scale
    let muJ = (opponentRating - 1500) / Self.scale
    return 1 / (1 + exp(-Self.g(opponentDeviation / Self.scale) * (mu - muJ)))
  }

  static func g(_ phi: Double) -> Double {
    1 / (1 + 3 * phi * phi / (Double.pi * Double.pi)).squareRoot()
  }

  /// Illinois-algorithm volatility update (step 5 of the paper).
  static func newVolatility(sigma: Double, phi: Double, v: Double, delta: Double) -> Double {
    let a = log(sigma * sigma)
    let epsilon = 0.000001
    func f(_ x: Double) -> Double {
      let ex = exp(x)
      let num = ex * (delta * delta - phi * phi - v - ex)
      let den = 2 * pow(phi * phi + v + ex, 2)
      return num / den - (x - a) / (tau * tau)
    }
    var A = a
    var B: Double
    if delta * delta > phi * phi + v {
      B = log(delta * delta - phi * phi - v)
    } else {
      var k = 1.0
      while f(a - k * tau) < 0 { k += 1 }
      B = a - k * tau
    }
    var fA = f(A)
    var fB = f(B)
    var iterations = 0
    while abs(B - A) > epsilon, iterations < 100 {
      let C = A + (A - B) * fA / (fB - fA)
      let fC = f(C)
      if fC * fB <= 0 {
        A = B
        fA = fB
      } else {
        fA /= 2
      }
      B = C
      fB = fC
      iterations += 1
    }
    return exp(A / 2)
  }
}
