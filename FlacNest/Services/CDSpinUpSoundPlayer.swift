import AppKit
import AVFoundation
import CoreAudio
import Foundation

struct AudioOutputDevice: Identifiable, Hashable {
    var id: String { uid }
    let uid: String
    let name: String
    let deviceID: AudioDeviceID
}

enum AudioOutputDeviceList {
    static func devices() -> [AudioOutputDevice] {
        allDeviceIDs()
            .filter(hasOutputChannels)
            .compactMap { deviceID in
                guard let uid = stringProperty(deviceID, selector: kAudioDevicePropertyDeviceUID),
                      let name = stringProperty(deviceID, selector: kAudioObjectPropertyName) ?? stringProperty(deviceID, selector: kAudioDevicePropertyDeviceNameCFString) else {
                    return nil
                }
                return AudioOutputDevice(uid: uid, name: name, deviceID: deviceID)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func deviceID(forUID uid: String) -> AudioDeviceID? {
        guard !uid.isEmpty else { return nil }
        return devices().first { $0.uid == uid }?.deviceID
    }

    private static func allDeviceIDs() -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return []
        }

        let count = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var ids = Array(repeating: AudioDeviceID(), count: count)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func hasOutputChannels(_ deviceID: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return false
        }

        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(dataSize), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, buffer) == noErr else {
            return false
        }

        let list = buffer.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = UnsafeMutableAudioBufferListPointer(list)
        return buffers.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func stringProperty(_ deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize) == noErr,
              dataSize > 0 else {
            return nil
        }

        var cfString: Unmanaged<CFString>?
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &dataSize, &cfString) == noErr,
              let value = cfString?.takeUnretainedValue() as String?,
              !value.isEmpty else {
            return nil
        }
        return value
    }
}

@MainActor
final class CDSpinUpSoundPlayer {
    static let shared = CDSpinUpSoundPlayer()

    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var audioFile: AVAudioFile?
    private var configuredDeviceUID: String?

    private init() {
        engine.attach(playerNode)
    }

    func playIfStartingPlayback() {
        switch AppSettings.cdSpinUpSoundMode {
        case .never:
            return
        case .always:
            break
        case .whenCDShown:
            guard AppSettings.showSpinningCDWhilePlaying else { return }
        }

        play()
    }

    func stop() {
        if playerNode.isPlaying {
            playerNode.stop()
        }
        if engine.isRunning {
            engine.stop()
        }
    }

    private func play() {
        guard let file = preparedFile() else { return }

        do {
            try prepareEngine(for: file)
            if playerNode.isPlaying {
                playerNode.stop()
            }
            playerNode.scheduleFile(file, at: nil)
            playerNode.play()
        } catch {
            engine.stop()
        }
    }

    private func preparedFile() -> AVAudioFile? {
        if let audioFile {
            return audioFile
        }
        guard let asset = NSDataAsset(name: "spin") else { return nil }

        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("flacnest-cd-spinup.mp3")
        do {
            try asset.data.write(to: cacheURL, options: .atomic)
            let file = try AVAudioFile(forReading: cacheURL)
            audioFile = file
            return file
        } catch {
            return nil
        }
    }

    private func prepareEngine(for file: AVAudioFile) throws {
        let deviceUID = AppSettings.cdSpinUpOutputDeviceUID ?? ""
        let needsReconnect = !engine.isRunning
            || engine.outputNode.outputFormat(forBus: 0).sampleRate != file.processingFormat.sampleRate
            || configuredDeviceUID != deviceUID

        if needsReconnect {
            if engine.isRunning {
                engine.stop()
            }
            engine.disconnectNodeOutput(playerNode)
            engine.connect(playerNode, to: engine.mainMixerNode, format: file.processingFormat)
            applyOutputDevice(uid: deviceUID)
            try engine.start()
            configuredDeviceUID = deviceUID
        } else if !engine.isRunning {
            try engine.start()
        }
        engine.mainMixerNode.outputVolume = AppSettings.cdSpinUpSoundVolume.gain
    }

    private func applyOutputDevice(uid: String) {
        guard let audioUnit = engine.outputNode.audioUnit else { return }

        var deviceID: AudioDeviceID
        if let selected = AudioOutputDeviceList.deviceID(forUID: uid) {
            deviceID = selected
        } else {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var defaultID = AudioDeviceID()
            var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
            guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &dataSize, &defaultID) == noErr else {
                return
            }
            deviceID = defaultID
        }

        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }
}
