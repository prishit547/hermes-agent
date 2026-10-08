import Flutter
import UIKit
import CallKit
import AVFoundation
import MediaPlayer

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var nowPlaying: NowPlayingPlugin?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let registrar = self.registrar(forPlugin: "NowPlaying") {
        let messenger = registrar.messenger()

        let channel = FlutterMethodChannel(name: "hermes/callkit", binaryMessenger: messenger)
        channel.setMethodCallHandler { (call, result) in
            if call.method == "startCall" {
                HermesCallKitManager.shared.startCall()
                result(nil)
            } else if call.method == "endCall" {
                HermesCallKitManager.shared.endCall()
                result(nil)
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        let audioChannel = FlutterMethodChannel(name: "hermes/audio", binaryMessenger: messenger)
        audioChannel.setMethodCallHandler { (call, result) in
            if call.method == "getAudioRoutes" {
                result(HermesAudioManager.shared.availableRoutes())
            } else if call.method == "setAudioOutput" {
                guard let args = call.arguments as? [String: Any],
                      let output = args["output"] as? String else {
                    result(false)
                    return
                }
                result(HermesAudioManager.shared.setRoute(output))
            } else {
                result(FlutterMethodNotImplemented)
            }
        }

        nowPlaying = NowPlayingPlugin(messenger: messenger)
    }
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

@available(iOS 10.0, *)
class HermesCallKitManager: NSObject, CXProviderDelegate {
    static let shared = HermesCallKitManager()
    
    private var provider: CXProvider?
    private let callController = CXCallController()
    private var activeCallUUID: UUID?

    override init() {
        super.init()
        let configuration = CXProviderConfiguration(localizedName: "Hermes")
        configuration.supportsVideo = false
        configuration.maximumCallGroups = 1
        configuration.maximumCallsPerCallGroup = 1
        configuration.supportedHandleTypes = [.generic]
        
        provider = CXProvider(configuration: configuration)
        provider?.setDelegate(self, queue: nil)
    }

    func startCall() {
        let uuid = UUID()
        activeCallUUID = uuid
        let handle = CXHandle(type: .generic, value: "Hermes Assistant")
        let startCallAction = CXStartCallAction(call: uuid, handle: handle)
        let transaction = CXTransaction(action: startCallAction)
        
        callController.request(transaction) { error in
            if let error = error {
                print("Error requesting CXStartCallAction: \(error)")
            }
        }
    }

    func endCall() {
        guard let uuid = activeCallUUID else { return }
        let endCallAction = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: endCallAction)
        
        callController.request(transaction) { error in
            if let error = error {
                print("Error requesting CXEndCallAction: \(error)")
            }
        }
        activeCallUUID = nil
    }

    // MARK: - CXProviderDelegate

    func providerDidReset(_ provider: CXProvider) {
        activeCallUUID = nil
    }

    func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        configureAudioSessionForVoIP()
        provider.reportOutgoingCall(with: action.callUUID, connectedAt: nil)
        action.fulfill()
    }

    func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        action.fulfill()
        activeCallUUID = nil
    }

    func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }

    private func configureAudioSessionForVoIP() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)
        } catch {
            print("Failed to configure audio session for CallKit VoIP: \(error)")
        }
    }
}

@available(iOS 10.0, *)
class HermesAudioManager {
    static let shared = HermesAudioManager()

    func availableRoutes() -> [[String: String]] {
        let session = AVAudioSession.sharedInstance()
        var routes: [[String: String]] = [["id": "speaker", "label": "Speaker"]]

        let hasBluetooth = session.availableInputs?.contains(where: Self.isBluetoothInput) ?? false

        if hasBluetooth {
            routes.append(["id": "bluetooth", "label": "Bluetooth"])
        }
        routes.append(["id": "earpiece", "label": "Earpiece"])
        return routes
    }

    func setRoute(_ output: String) -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.allowBluetooth, .defaultToSpeaker])
            try session.setActive(true)

            switch output {
            case "speaker":
                try session.overrideOutputAudioPort(.speaker)
            case "earpiece":
                try session.overrideOutputAudioPort(.none)
            case "bluetooth":
                try session.overrideOutputAudioPort(.none)
                guard let bt = session.availableInputs?.first(where: Self.isBluetoothInput) else {
                    return false
                }
                try session.setPreferredInput(bt)
            default:
                return false
            }
            return true
        } catch {
            print("Failed to set audio route '\(output)': \(error)")
            return false
        }
    }

    private static func isBluetoothInput(_ input: AVAudioSessionPortDescription) -> Bool {
        switch input.portType.rawValue {
        case "BluetoothHFP", "BluetoothA2DP", "BluetoothLE", "BluetoothHearingAid":
            return true
        default:
            return false
        }
    }
}

/// Renders Hermes music metadata to `MPNowPlayingInfoCenter` and relays the
/// lock-screen / Control Center / headset / Dynamic Island transport buttons
/// back to Dart over the `hermes/now_playing` channel.
final class NowPlayingPlugin {
    private let channel: FlutterMethodChannel
    private var lastArtworkUrl: String?

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "hermes/now_playing", binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
        setupRemoteCommands()
    }

    private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "start":
            result(nil) // background handled by the `audio` mode
        case "stop", "clear":
            clearNowPlaying()
            result(nil)
        case "update":
            if let args = call.arguments as? [String: Any] { applyNowPlaying(args) }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func clearNowPlaying() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
        lastArtworkUrl = nil
    }

    private func applyNowPlaying(_ args: [String: Any]) {
        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        info[MPMediaItemPropertyTitle] = args["title"] as? String ?? "Hermes"
        info[MPMediaItemPropertyArtist] = args["artist"] as? String ?? ""
        if let durMs = args["durationMs"] as? NSNumber, durMs.doubleValue > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = durMs.doubleValue / 1000.0
            info[MPNowPlayingInfoPropertyIsLiveStream] = false
        } else {
            info.removeValue(forKey: MPMediaItemPropertyPlaybackDuration)
            info[MPNowPlayingInfoPropertyIsLiveStream] = true
        }
        let posMs = (args["positionMs"] as? NSNumber)?.doubleValue ?? 0
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = posMs / 1000.0
        let playing = args["playing"] as? Bool ?? false
        info[MPNowPlayingInfoPropertyPlaybackRate] = playing ? 1.0 : 0.0
        info[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        info[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info

        if #available(iOS 13.0, *) {
            MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
        }

        let cmd = MPRemoteCommandCenter.shared()
        cmd.nextTrackCommand.isEnabled = args["hasNext"] as? Bool ?? false
        cmd.previousTrackCommand.isEnabled = args["hasPrev"] as? Bool ?? false

        let artUrl = args["artworkUrl"] as? String
        if artUrl != lastArtworkUrl {
            lastArtworkUrl = artUrl
            if let urlStr = artUrl, let url = URL(string: urlStr) {
                loadArtwork(url: url, expected: urlStr)
            } else {
                var i = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                i.removeValue(forKey: MPMediaItemPropertyArtwork)
                MPNowPlayingInfoCenter.default().nowPlayingInfo = i
            }
        }
    }

    private func loadArtwork(url: URL, expected: String) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let self = self, let data = data, let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard self.lastArtworkUrl == expected else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = info
            }
        }.resume()
    }

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.isEnabled = true
        c.playCommand.addTarget { [weak self] _ in
            self?.channel.invokeMethod("play", arguments: nil)
            return .success
        }
        c.pauseCommand.isEnabled = true
        c.pauseCommand.addTarget { [weak self] _ in
            self?.channel.invokeMethod("pause", arguments: nil)
            return .success
        }
        c.togglePlayPauseCommand.isEnabled = true
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            self?.channel.invokeMethod("togglePlayPause", arguments: nil)
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            self?.channel.invokeMethod("next", arguments: nil)
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            self?.channel.invokeMethod("previous", arguments: nil)
            return .success
        }
        c.changePlaybackPositionCommand.isEnabled = true
        c.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            self?.channel.invokeMethod("seek", arguments: ["positionMs": Int(e.positionTime * 1000.0)])
            return .success
        }
    }
}
