import Accelerate
import Foundation

/// Loudness of a few frequency bands in one block of audio, for the equalizer bars.
public struct Spectrum {
    /// Roughly an octave and a half each, from the kick drum up to cymbals.
    public static let bands: [ClosedRange<Double>] = [40...120, 120...400, 400...1_500, 1_500...5_000, 5_000...14_000]
    public let size: Int
    private let dft: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private let zeros: [Float]

    public init(size: Int = 1024) {
        self.size = size
        dft = try! vDSP.DiscreteFourierTransform(count: size, direction: .forward,
                                                  transformType: .complexComplex, ofType: Float.self)
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: size, isHalfWindow: false)
        zeros = [Float](repeating: 0, count: size)
    }

    /// Power in each band, in decibels where a full-scale sine is about 0. `samples` holds `size` mono samples.
    public func decibels(_ samples: [Float], sampleRate: Double) -> [Float] {
        let (real, imaginary) = dft.transform(real: vDSP.multiply(samples, window), imaginary: zeros)
        let binWidth = sampleRate / Double(size)
        // A Hann-windowed full-scale sine peaks at size/4 in its bin.
        let scale = 16 / Float(size * size)
        return Self.bands.map { band in
            let low = max(1, Int(band.lowerBound / binWidth))
            let high = min(size / 2 - 1, Int(band.upperBound / binWidth))
            guard low <= high else { return -120 }
            // Summing (not averaging) bins evens out music's natural fall-off towards the treble.
            var power: Float = 0
            for bin in low...high { power += real[bin] * real[bin] + imaginary[bin] * imaginary[bin] }
            return 10 * log10(max(power * scale, 1e-12))
        }
    }
}

/// Turns band decibels into steady 0...1 bar heights. Each band is measured against its own
/// recent peak, so quiet songs still move, and bars rise fast but fall slowly so they don't flicker.
public struct BandMeter {
    public private(set) var levels: [Float]
    private var peaks: [Float]
    /// How many decibels below a band's peak count as an empty bar.
    public var range: Float = 30
    /// Peaks never drop below this, so near-silence doesn't get blown up into noise.
    public var floor: Float = -55

    public init(count: Int) {
        levels = [Float](repeating: 0, count: count)
        peaks = [Float](repeating: -55, count: count)
    }

    public mutating func update(_ decibels: [Float]) -> [Float] {
        for index in levels.indices {
            let value = decibels[index]
            peaks[index] = max(value, peaks[index] - 0.15, floor)
            let target = min(1, max(0, (value - (peaks[index] - range)) / range))
            let rate: Float = target > levels[index] ? 0.7 : 0.18
            levels[index] += (target - levels[index]) * rate
        }
        return levels
    }
}
