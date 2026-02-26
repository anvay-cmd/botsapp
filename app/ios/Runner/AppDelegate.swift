import Flutter
import UIKit
import PushKit
import CallKit
import AVFoundation
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate, CXProviderDelegate {
  private let channelName = "botsapp/callkit"
  private let cachedVoipTokenKey = "cached_voip_token"
  private let cachedApnsTokenKey = "cached_apns_token"
  private let pendingIncomingCallKey = "pending_incoming_call_payload"

  private var callkitChannel: FlutterMethodChannel?
  private var voipRegistry: PKPushRegistry?
  private var callProvider: CXProvider?
  private let callController = CXCallController()
  private var callPayloadByUUID: [UUID: [String: Any]] = [:]
  private var uuidByCallId: [String: UUID] = [:]

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupStandardPushNotifications(application: application)
    setupCallkitBridgeChannel()
    setupCallKit()
    setupVoipPushRegistry()
    return ok
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    setupCallkitBridgeChannel()
    UNUserNotificationCenter.current().getNotificationSettings { settings in
      if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
        DispatchQueue.main.async {
          application.registerForRemoteNotifications()
        }
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // MARK: - Setup

  private func setupCallKit() {
    let config = CXProviderConfiguration(localizedName: "Botsapp AI")
    config.supportsVideo = false
    config.includesCallsInRecents = true
    config.maximumCallsPerCallGroup = 1
    config.supportedHandleTypes = [.generic]
    config.iconTemplateImageData = nil
    config.ringtoneSound = "ringtone.caf"
    let provider = CXProvider(configuration: config)
    provider.setDelegate(self, queue: nil)
    self.callProvider = provider
  }

  private func setupStandardPushNotifications(application: UIApplication) {
    let center = UNUserNotificationCenter.current()
    center.delegate = self

    // Register notification categories for custom UI
    let chatMessageCategory = UNNotificationCategory(
      identifier: "CHAT_MESSAGE",
      actions: [],
      intentIdentifiers: [],
      options: []
    )
    center.setNotificationCategories([chatMessageCategory])

    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        print("[APNS] Notification permission error: \(error)")
      }
      print("[APNS] Notification permission granted: \(granted)")
      DispatchQueue.main.async {
        application.registerForRemoteNotifications()
      }
    }
  }

  private func setupVoipPushRegistry() {
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    self.voipRegistry = registry
  }

  private func setupCallkitBridgeChannel() {
    if callkitChannel != nil { return }
    guard let flutterVC = currentFlutterController() else { return }
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: flutterVC.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "getCachedVoipToken":
        result(UserDefaults.standard.string(forKey: self.cachedVoipTokenKey))
      case "getCachedApnsToken":
        result(UserDefaults.standard.string(forKey: self.cachedApnsTokenKey))
      case "drainPendingIncomingCall":
        let payload = UserDefaults.standard.dictionary(forKey: self.pendingIncomingCallKey)
        UserDefaults.standard.removeObject(forKey: self.pendingIncomingCallKey)
        result(payload)
      case "endNativeCall":
        guard
          let args = call.arguments as? [String: Any],
          let callId = args["call_id"] as? String,
          let uuid = self.uuidByCallId[callId]
        else {
          result(nil)
          return
        }
        let action = CXEndCallAction(call: uuid)
        let transaction = CXTransaction(action: action)
        self.callController.request(transaction) { _ in
          result(nil)
        }
      case "configureCallAudio":
        self.configureCallAudioSession()
        result(nil)
      case "resetCallAudio":
        self.resetCallAudioSession()
        result(nil)
      case "setSpeakerEnabled":
        let args = call.arguments as? [String: Any]
        let enabled = (args?["enabled"] as? Bool) ?? true
        self.setSpeakerEnabled(enabled)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.callkitChannel = channel
  }

  private func configureCallAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(
        .playAndRecord,
        mode: .videoChat,
        options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
      )
      try session.setActive(true, options: [])
      try session.overrideOutputAudioPort(.speaker)
      print("[CallAudio] Configured playAndRecord/videoChat + speaker route")
    } catch {
      print("[CallAudio] Failed to configure call audio session: \(error)")
    }
  }

  private func resetCallAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.overrideOutputAudioPort(.none)
      try session.setActive(false, options: [.notifyOthersOnDeactivation])
      print("[CallAudio] Reset call audio session")
    } catch {
      print("[CallAudio] Failed to reset call audio session: \(error)")
    }
  }

  private func setSpeakerEnabled(_ enabled: Bool) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setActive(true, options: [])
      try session.overrideOutputAudioPort(enabled ? .speaker : .none)
      print("[CallAudio] Speaker route set: \(enabled)")
    } catch {
      print("[CallAudio] Failed to set speaker route: \(error)")
    }
  }

  private func currentFlutterController() -> FlutterViewController? {
    if let vc = window?.rootViewController as? FlutterViewController {
      return vc
    }
    let scenes = UIApplication.shared.connectedScenes
    for scene in scenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for w in windowScene.windows {
        if let vc = w.rootViewController as? FlutterViewController {
          return vc
        }
      }
    }
    return nil
  }

  private func emitToFlutter(method: String, args: [String: Any]) {
    if callkitChannel == nil {
      setupCallkitBridgeChannel()
    }
    if let channel = callkitChannel {
      channel.invokeMethod(method, arguments: args)
    } else if method == "incomingCallAccepted" {
      UserDefaults.standard.set(args, forKey: pendingIncomingCallKey)
    }
  }

  // MARK: - PushKit

  func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, for type: PKPushType) {
    let token = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set(token, forKey: cachedVoipTokenKey)
    emitToFlutter(method: "voipToken", args: ["token": token])
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    UserDefaults.standard.removeObject(forKey: cachedVoipTokenKey)
  }

  // MARK: - Standard APNs

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    UserDefaults.standard.set(token, forKey: cachedApnsTokenKey)
    emitToFlutter(method: "apnsToken", args: ["token": token])
    print("[APNS] device token updated")
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("[APNS] failed to register: \(error)")
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound, .badge])
    } else {
      completionHandler([.alert, .sound, .badge])
    }
  }

  func pushRegistry(
    _ registry: PKPushRegistry,
    didReceiveIncomingPushWith payload: PKPushPayload,
    for type: PKPushType,
    completion: @escaping () -> Void
  ) {
    let payloadDict = payload.dictionaryPayload
    let call = payloadDict["call"] as? [String: Any] ?? [:]
    let callId = (call["call_id"] as? String) ?? UUID().uuidString
    let chatId = (call["chat_id"] as? String) ?? ""
    let botName = (call["bot_name"] as? String) ?? "AI Assistant"
    let botAvatar = (call["bot_avatar"] as? String) ?? ""
    let message = (call["message"] as? String) ?? ""

    let uuid = UUID(uuidString: callId) ?? UUID()
    uuidByCallId[callId] = uuid
    callPayloadByUUID[uuid] = [
      "call_id": callId,
      "chat_id": chatId,
      "bot_name": botName,
      "bot_avatar": botAvatar,
      "message": message,
    ]

    let update = CXCallUpdate()
    update.remoteHandle = CXHandle(type: .generic, value: botName)
    update.localizedCallerName = botName
    update.supportsDTMF = false
    update.supportsHolding = false
    update.supportsGrouping = false
    update.supportsUngrouping = false
    update.hasVideo = false

    callProvider?.reportNewIncomingCall(with: uuid, update: update, completion: { error in
      if error != nil {
        UserDefaults.standard.set(self.callPayloadByUUID[uuid], forKey: self.pendingIncomingCallKey)
      }
      completion()
    })
  }

  // MARK: - CXProviderDelegate

  func providerDidReset(_ provider: CXProvider) {
    callPayloadByUUID.removeAll()
  }

  func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
    defer { action.fulfill() }
    guard let payload = callPayloadByUUID[action.callUUID] else { return }
    emitToFlutter(method: "incomingCallAccepted", args: payload)
  }

  func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
    defer { action.fulfill() }
    if let payload = callPayloadByUUID[action.callUUID] {
      emitToFlutter(method: "incomingCallEnded", args: payload)
    }
    callPayloadByUUID.removeValue(forKey: action.callUUID)
  }
}
