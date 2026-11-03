import AppKit
import Combine
import CoreAudio
import NotchCore

/// Live bar heights for the equalizer. Empty means there's no real signal yet,
/// and the bars fall back to their idle wiggle.
final class AudioLevels: ObservableObject {
    static let shared = AudioLevels()
    @Published var bars: [Float] = []
}

/// Listens to Spotify's own output through a Core Audio process tap (macOS 14.2+), only while
/// it's playing. Nothing is recorded or stored: each block is turned into band levels and dropped.
final class AudioTap {
    private let store: NotchStore
    private var subscriptions = Set<AnyCancellable>()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "notch.audiotap", qos: .userInteractive)

    // Only touched on `queue`.
    private let spectrum = Spectrum()
    private var meter = BandMeter(count: Spectrum.bands.count)
    private var pending: [Float] = []
    private var sampleRate = 48_000.0
    private var heardSignal = false

    init(store: NotchStore) {
        self.store = store
        guard #available(macOS 14.2, *) else { return }
        store.$isPlaying
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] playing in playing ? self?.start() : self?.stop() }
            .store(in: &subscriptions)
        // The tap's clock comes from the output device, so follow it when headphones come and go.
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main) { [weak self] _, _ in
            guard let self, self.procID != nil else { return }
            self.stop()
            self.start()
        }
    }

    private func start() {
        guard #available(macOS 14.2, *), procID == nil else { return }
        let processes = Self.spotifyProcesses()
        guard !processes.isEmpty, let outputUID = Self.defaultOutputUID() else { return }

        let description = CATapDescription(stereoMixdownOfProcesses: processes)
        description.uuid = UUID()
        description.name = "Notch equalizer"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return }

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        if AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format) == noErr, format.mSampleRate > 0 {
            let rate = format.mSampleRate
            queue.async { self.sampleRate = rate }
        }

        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Notch equalizer",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                               kAudioSubTapUIDKey: description.uuid.uuidString]],
        ]
        guard AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &deviceID) == noErr else {
            stop()
            return
        }
        queue.async {
            self.meter = BandMeter(count: Spectrum.bands.count)
            self.pending.removeAll(keepingCapacity: true)
            self.heardSignal = false
        }
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, deviceID, queue) { [weak self] _, input, _, _, _ in
            self?.receive(input)
        }
        guard status == noErr, AudioDeviceStart(deviceID, procID) == noErr else {
            stop()
            return
        }
    }

    private func stop() {
        guard #available(macOS 14.2, *) else { return }
        if deviceID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(deviceID, procID)
                AudioDeviceDestroyIOProcID(deviceID, procID)
            }
            AudioHardwareDestroyAggregateDevice(deviceID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        deviceID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        AudioLevels.shared.bars = []
    }

    /// Mixes the tap's buffers down to mono and analyses every full block.
    private func receive(_ input: UnsafePointer<AudioBufferList>) {
        for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
            guard let data = buffer.mData else { continue }
            let channels = max(1, Int(buffer.mNumberChannels))
            let frames = Int(buffer.mDataByteSize) / MemoryLayout<Float>.size / channels
            let samples = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                var sum: Float = 0
                for channel in 0..<channels { sum += samples[frame * channels + channel] }
                pending.append(sum / Float(channels))
            }
        }
        while pending.count >= spectrum.size {
            let block = Array(pending.prefix(spectrum.size))
            pending.removeFirst(spectrum.size)
            let decibels = spectrum.decibels(block, sampleRate: sampleRate)
            let levels = meter.update(decibels)
            // Without the audio-capture permission the tap delivers silence, so keep the wiggle until real sound shows up.
            if !heardSignal, decibels.max() ?? -120 > -70 { heardSignal = true }
            guard heardSignal else { continue }
            DispatchQueue.main.async {
                guard self.procID != nil else { return }
                AudioLevels.shared.bars = levels
            }
        }
    }

    /// Spotify plays from more than one process, so tap every one of them.
    private static func spotifyProcesses() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects.filter { object in
            var bundleAddress = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID,
                                                           mScope: kAudioObjectPropertyScopeGlobal,
                                                           mElement: kAudioObjectPropertyElementMain)
            var bundleID: Unmanaged<CFString>?
            var bundleSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(object, &bundleAddress, 0, nil, &bundleSize, &bundleID) == noErr,
                  let id = bundleID?.takeRetainedValue() as String? else { return false }
            return id.hasPrefix("com.spotify.client")
        }
    }

    private static func defaultOutputUID() -> String? {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &device) == noErr else { return nil }
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid) == noErr else { return nil }
        return uid?.takeRetainedValue() as String?
    }
}
