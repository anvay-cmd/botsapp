import UserNotifications

class NotificationService: UNNotificationServiceExtension {
  private var contentHandler: ((UNNotificationContent) -> Void)?
  private var bestAttemptContent: UNMutableNotificationContent?
  private var downloadTask: URLSessionDownloadTask?

  override func didReceive(
    _ request: UNNotificationRequest,
    withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
  ) {
    self.contentHandler = contentHandler
    guard let bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent) else {
      contentHandler(request.content)
      return
    }
    self.bestAttemptContent = bestAttemptContent

    // Set the category to trigger custom UI
    bestAttemptContent.categoryIdentifier = "CHAT_MESSAGE"
    print("[NotificationService] Set category: CHAT_MESSAGE")

    let userInfo = bestAttemptContent.userInfo
    print("[NotificationService] UserInfo: \(userInfo)")

    guard let rawAvatarUrl = userInfo["avatar_url"] as? String, !rawAvatarUrl.isEmpty else {
      print("[NotificationService] No avatar URL, delivering notification with category only")
      contentHandler(bestAttemptContent)
      return
    }

    guard let resolvedUrl = resolveAvatarUrl(rawAvatarUrl) else {
      print("[NotificationService] Could not resolve avatar URL")
      contentHandler(bestAttemptContent)
      return
    }

    print("[NotificationService] Downloading avatar from: \(resolvedUrl)")

    downloadTask = URLSession.shared.downloadTask(with: resolvedUrl) { [weak self] tempUrl, _, _ in
      guard let self = self else { return }
      guard let tempUrl = tempUrl else {
        self.finishWithBestAttempt()
        return
      }

      do {
        let fileManager = FileManager.default
        let ext = resolvedUrl.pathExtension.isEmpty ? "jpg" : resolvedUrl.pathExtension
        let localUrl = URL(fileURLWithPath: NSTemporaryDirectory())
          .appendingPathComponent(UUID().uuidString)
          .appendingPathExtension(ext)
        try? fileManager.removeItem(at: localUrl)
        try fileManager.copyItem(at: tempUrl, to: localUrl)

        // Create attachment without clipping rect (simpler and more compatible)
        let attachment = try UNNotificationAttachment(
          identifier: "avatar",
          url: localUrl,
          options: nil
        )
        bestAttemptContent.attachments = [attachment]
        print("[NotificationService] Successfully attached avatar image")
      } catch {
        print("[NotificationService] Failed to attach avatar: \(error)")
      }
      self.finishWithBestAttempt()
    }
    downloadTask?.resume()
  }

  override func serviceExtensionTimeWillExpire() {
    downloadTask?.cancel()
    finishWithBestAttempt()
  }

  private func finishWithBestAttempt() {
    guard let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent else { return }
    contentHandler(bestAttemptContent)
  }

  private func resolveAvatarUrl(_ raw: String) -> URL? {
    if let url = URL(string: raw), url.scheme != nil {
      return url
    }
    guard
      let base = Bundle.main.object(forInfoDictionaryKey: "BOTSAPP_BASE_URL") as? String,
      !base.isEmpty
    else {
      return nil
    }
    let normalizedBase = base.hasSuffix("/") ? String(base.dropLast()) : base
    let normalizedPath = raw.hasPrefix("/") ? raw : "/\(raw)"
    return URL(string: "\(normalizedBase)\(normalizedPath)")
  }
}
