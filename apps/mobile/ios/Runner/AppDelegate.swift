import Flutter
import UIKit
import CallKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let controller = window?.rootViewController as? FlutterViewController
    if let messenger = controller?.binaryMessenger {
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
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
