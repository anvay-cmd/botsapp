import UIKit
import UserNotifications
import UserNotificationsUI

class NotificationViewController: UIViewController, UNNotificationContentExtension {
  private let avatarImageView = UIImageView()
  private let appIconBadge = UIImageView()
  private let titleLabel = UILabel()
  private let bodyLabel = UILabel()

  override func viewDidLoad() {
    super.viewDidLoad()
    setupUI()
  }

  private func setupUI() {
    print("[NotificationContent] Setting up UI")
    view.backgroundColor = UIColor.systemBackground

    // Avatar image (large circular image)
    avatarImageView.contentMode = .scaleAspectFill
    avatarImageView.clipsToBounds = true
    avatarImageView.layer.cornerRadius = 30
    avatarImageView.backgroundColor = UIColor(red: 0.2, green: 0.7, blue: 0.6, alpha: 1.0)
    avatarImageView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(avatarImageView)

    // App icon badge (small icon in bottom-right)
    appIconBadge.contentMode = .scaleAspectFit
    appIconBadge.clipsToBounds = true
    appIconBadge.layer.cornerRadius = 10
    appIconBadge.layer.borderWidth = 2
    appIconBadge.layer.borderColor = UIColor.white.cgColor
    appIconBadge.backgroundColor = .white
    // Try to get app icon
    if let appIcon = getAppIcon() {
      appIconBadge.image = appIcon
      print("[NotificationContent] App icon loaded")
    } else {
      print("[NotificationContent] Failed to load app icon")
    }
    appIconBadge.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(appIconBadge)

    // Title label
    titleLabel.font = UIFont.boldSystemFont(ofSize: 15)
    titleLabel.textColor = .label
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(titleLabel)

    // Body label
    bodyLabel.font = UIFont.systemFont(ofSize: 14)
    bodyLabel.textColor = .secondaryLabel
    bodyLabel.numberOfLines = 3
    bodyLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(bodyLabel)

    NSLayoutConstraint.activate([
      // Avatar positioning (left side)
      avatarImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
      avatarImageView.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),
      avatarImageView.widthAnchor.constraint(equalToConstant: 60),
      avatarImageView.heightAnchor.constraint(equalToConstant: 60),
      avatarImageView.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),

      // App icon badge (bottom-right of avatar)
      appIconBadge.trailingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 2),
      appIconBadge.bottomAnchor.constraint(equalTo: avatarImageView.bottomAnchor, constant: 2),
      appIconBadge.widthAnchor.constraint(equalToConstant: 20),
      appIconBadge.heightAnchor.constraint(equalToConstant: 20),

      // Title label
      titleLabel.leadingAnchor.constraint(equalTo: avatarImageView.trailingAnchor, constant: 12),
      titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
      titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 12),

      // Body label
      bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
      bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
      bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
      bodyLabel.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -12),
    ])
  }

  func didReceive(_ notification: UNNotification) {
    let content = notification.request.content
    print("[NotificationContent] didReceive called")
    print("[NotificationContent] Title: \(content.title)")
    print("[NotificationContent] Body: \(content.body)")
    print("[NotificationContent] Category: \(content.categoryIdentifier)")
    print("[NotificationContent] UserInfo: \(content.userInfo)")

    // Set title and body
    titleLabel.text = content.title
    bodyLabel.text = content.body

    // Load avatar from attachment if available
    if let attachment = content.attachments.first(where: { $0.identifier == "avatar" }) {
      print("[NotificationContent] Found avatar attachment")
      loadImage(from: attachment.url)
    } else {
      print("[NotificationContent] No avatar attachment, checking userInfo")
      // Fallback: try to load from URL in userInfo
      if let avatarUrlString = content.userInfo["avatar_url"] as? String,
         let avatarUrl = URL(string: avatarUrlString) {
        print("[NotificationContent] Downloading avatar from: \(avatarUrl)")
        downloadImage(from: avatarUrl)
      } else {
        // Show placeholder with first letter of title
        print("[NotificationContent] Using placeholder avatar")
        setPlaceholderAvatar(title: content.title)
      }
    }
  }

  private func loadImage(from url: URL) {
    if let imageData = try? Data(contentsOf: url),
       let image = UIImage(data: imageData) {
      avatarImageView.image = image
    } else {
      setPlaceholderAvatar(title: titleLabel.text ?? "")
    }
  }

  private func downloadImage(from url: URL) {
    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data = data, let image = UIImage(data: data) else {
        DispatchQueue.main.async {
          self?.setPlaceholderAvatar(title: self?.titleLabel.text ?? "")
        }
        return
      }
      DispatchQueue.main.async {
        self?.avatarImageView.image = image
      }
    }.resume()
  }

  private func setPlaceholderAvatar(title: String) {
    let firstLetter = String(title.prefix(1)).uppercased()
    let size = CGSize(width: 60, height: 60)
    let renderer = UIGraphicsImageRenderer(size: size)
    let image = renderer.image { context in
      UIColor(red: 0.2, green: 0.7, blue: 0.6, alpha: 1.0).setFill()
      context.fill(CGRect(origin: .zero, size: size))

      let attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.boldSystemFont(ofSize: 28),
        .foregroundColor: UIColor.white
      ]
      let textSize = firstLetter.size(withAttributes: attributes)
      let textRect = CGRect(
        x: (size.width - textSize.width) / 2,
        y: (size.height - textSize.height) / 2,
        width: textSize.width,
        height: textSize.height
      )
      firstLetter.draw(in: textRect, withAttributes: attributes)
    }
    avatarImageView.image = image
  }

  private func getAppIcon() -> UIImage? {
    guard let iconsDictionary = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
          let primaryIconsDictionary = iconsDictionary["CFBundlePrimaryIcon"] as? [String: Any],
          let iconFiles = primaryIconsDictionary["CFBundleIconFiles"] as? [String],
          let lastIcon = iconFiles.last else {
      return nil
    }
    return UIImage(named: lastIcon)
  }
}
