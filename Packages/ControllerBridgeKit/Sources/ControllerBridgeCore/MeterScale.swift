import Foundation

/// The level meter's scale (#582): Syndicate's raw channel level in decibels, from `floorDB` (empty) to `topDB` (full,
/// the meter's red at clip). The owner's unit showed raw peaks to +2.6 dB while Syndicate's own meter stayed "near the
/// top, no red", so 1.0 isn't its top; a full-rate capture can refine the range.
enum MeterScale {
    static let floorDB = -36.0
    static let topDB = 6.0

    /// `value` (linear, 1.0 is 0 dB) as a place on the meter, 0...1.
    static func position(_ value: Double) -> Double {
        guard value > 0 else { return 0 }
        return min(max((20 * log10(value) - floorDB) / (topDB - floorDB), 0), 1)
    }
}
