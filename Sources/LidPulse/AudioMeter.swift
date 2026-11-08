import Foundation
import CoreAudio
import os

final class AudioMeter {
    struct Reading {
        var lastBeat = -Double.infinity
        var beatStrength = 0.0
        var energy = 0.0
        var buffers = 0
    }

    struct Failure: LocalizedError {
        let stage: String
        let status: OSStatus
        var errorDescription: String? { "\(stage)（\(status)）。請檢查「系統設定 → 私隱與保安 → 螢幕與系統音訊錄製」。" }
    }

    private let queue = DispatchQueue(label: "local.lidpulse.audio", qos: .userInitiated)
    private let meter = OSAllocatedUnfairLock(initialState: Reading())
    private var tap: AudioObjectID = 0
    private var device: AudioObjectID = 0
    private var proc: AudioDeviceIOProcID?

    var reading: Reading { meter.withLock { $0 } }

    func start() throws {
        guard proc == nil else { return }
        var ready = false
        defer { if !ready { stop() } }
        meter.withLock { $0 = Reading() }
        let desc = CATapDescription(monoGlobalTapButExcludeProcesses: [])
        desc.name = "LidPulse"
        desc.isPrivate = true
        desc.muteBehavior = .unmuted
        try check(AudioHardwareCreateProcessTap(desc, &tap), "未能擷取系統音訊")
        var format = AudioStreamBasicDescription()
        var formatSize = UInt32(MemoryLayout.size(ofValue: format))
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &formatSize, &format), "未能讀取音訊格式")
        guard format.mFormatID == kAudioFormatLinearPCM, format.mBitsPerChannel == 32,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              format.mSampleRate > 0 else { throw Failure(stage: "不支援嘅系統音訊格式", status: -1) }

        let properties: [String: Any] = [
            kAudioAggregateDeviceNameKey: "LidPulse Meter",
            kAudioAggregateDeviceUIDKey: "local.lidpulse." + UUID().uuidString,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapUIDKey: desc.uuid.uuidString, kAudioSubTapDriftCompensationKey: true]
            ]
        ]
        try check(AudioHardwareCreateAggregateDevice(properties as CFDictionary, &device), "未能建立系統音訊擷取裝置")
        let detector = BeatDetector(sampleRate: format.mSampleRate)
        let reading = meter
        try check(AudioDeviceCreateIOProcIDWithBlock(&proc, device, queue) { _, input, _, _, _ in
            let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
            guard let buffer = buffers.first(where: { $0.mData != nil }), let data = buffer.mData else { return }
            let count = Int(buffer.mDataByteSize) / MemoryLayout<Float>.stride
            guard count > 0 else { return }
            let channels = max(1, Int(buffer.mNumberChannels))
            let samples = data.assumingMemoryBound(to: Float.self)
            let now = ProcessInfo.processInfo.systemUptime
            let signal = detector.process(samples, count: count, channels: channels, at: now)
            reading.withLock {
                $0.buffers += 1
                $0.energy = signal.energy
                if let beat = signal.beat { $0.lastBeat = now; $0.beatStrength = beat }
            }
        }, "未能接收系統音訊")
        try check(AudioDeviceStart(device, proc), "未能開始聆聽")
        ready = true
    }

    func stop() {
        if let proc {
            AudioDeviceStop(device, proc)
            AudioDeviceDestroyIOProcID(device, proc)
            self.proc = nil
        }
        if device != 0 { AudioHardwareDestroyAggregateDevice(device); device = 0 }
        if tap != 0 { AudioHardwareDestroyProcessTap(tap); tap = 0 }
    }

    deinit { stop() }

    private func check(_ status: OSStatus, _ stage: String) throws {
        if status != noErr { throw Failure(stage: stage, status: status) }
    }
}

private final class BeatDetector {
    private let sampleRate: Double
    private let bassMix: Double
    private var low = 0.0
    private var baseline = 0.0
    private var envelope = 0.0
    private var lastBeat = -Double.infinity

    init(sampleRate: Double) {
        self.sampleRate = sampleRate
        bassMix = 1 - exp(-2 * .pi * 145 / sampleRate)
    }

    func process(_ samples: UnsafePointer<Float>, count: Int, channels: Int, at now: Double) -> (energy: Double, beat: Double?) {
        var total = 0.0, bass = 0.0, frames = 0
        for index in stride(from: 0, to: count, by: channels) {
            let sample = Double(samples[index])
            guard sample.isFinite else { continue }
            low += bassMix * (sample - low)
            total += sample * sample
            bass += low * low
            frames += 1
        }
        guard frames > 0 else { return (0, nil) }
        let rms = sqrt(total / Double(frames))
        let onset = 0.72 * sqrt(bass / Double(frames)) + 0.28 * rms
        let seconds = Double(frames) / sampleRate
        let previous = envelope
        envelope += (1 - exp(-seconds / 0.025)) * (onset - envelope)
        let baselineBefore = baseline
        baseline += (1 - exp(-seconds / 0.45)) * (envelope - baseline)
        guard now - lastBeat >= 0.17, envelope > max(0.002, baselineBefore * 1.30),
              envelope - previous > max(0.00035, baselineBefore * 0.028) else { return (rms, nil) }
        lastBeat = now
        return (rms, min(1, max(0.35, envelope / max(0.006, baselineBefore) / 2)))
    }
}
