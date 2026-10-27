import UIKit

/// A custom-draw view that renders a tab item (SF Symbol icon + title) at the current graphics context scale.
///
/// This view supports `NSCoding` so it survives the system accessibility popover's archive/unarchive cycle.
/// When the popover copies segment content, it archives this view and unarchives a copy. Because the
/// named-image fields, title and resolved image are encoded so a copied view retains its content.
/// Normal rendering still uses `draw(_:)` at the current graphics context scale; the native popover
/// uses its own segment labels after unarchiving rather than a pre-rendered tab bitmap.
@available(iOS 26.0, *)
@objc(FabBarTabItemContentView)
final class TabItemContentView: UIView {
  private var symbolName: String = ""
  private var customImageName: String = ""
  private var customImageBundleIdentifier: String = ""
  private var title: String = ""
  private var resolvedImage: UIImage?
  private var showsTitle = true

  private let font = UIFont.systemFont(ofSize: Constants.tabTitleFontSize, weight: .semibold)
  private let imageAreaHeight = Constants.iconViewSize

  init(title: String, symbolName: String) {
    self.title = title
    self.symbolName = symbolName
    super.init(frame: .zero)
    isOpaque = false
    isUserInteractionEnabled = false
    contentMode = .redraw
  }

  init(title: String, imageName: String, imageBundle: Bundle?) {
    self.title = title
    self.customImageName = imageName
    self.customImageBundleIdentifier = imageBundle?.bundleIdentifier ?? ""
    super.init(frame: .zero)
    isOpaque = false
    isUserInteractionEnabled = false
    contentMode = .redraw
  }

  /// Descriptors already resolve both asset and symbol images. Keep the
  /// original drawing metrics without losing the resolved bundle's image.
  init(title: String, image: UIImage?, showsTitle: Bool = true) {
    self.title = title
    self.resolvedImage = image
    self.showsTitle = showsTitle
    super.init(frame: .zero)
    isOpaque = false
    isUserInteractionEnabled = false
    contentMode = .redraw
  }

  func update(title: String, image: UIImage?, showsTitle: Bool = true) {
    self.title = title
    resolvedImage = image
    symbolName = ""
    customImageName = ""
    customImageBundleIdentifier = ""
    self.showsTitle = showsTitle
    invalidateIntrinsicContentSize()
    setNeedsDisplay()
  }

  // MARK: - NSCoding

  required init?(coder: NSCoder) {
    self.symbolName = coder.decodeObject(forKey: "symbolName") as? String ?? ""
    self.customImageName = coder.decodeObject(forKey: "customImageName") as? String ?? ""
    self.customImageBundleIdentifier = coder.decodeObject(forKey: "customImageBundleIdentifier") as? String ?? ""
    self.title = coder.decodeObject(forKey: "title") as? String ?? ""
    self.resolvedImage = coder.decodeObject(forKey: "resolvedImage") as? UIImage
    self.showsTitle = coder.containsValue(forKey: "showsTitle") ? coder.decodeBool(forKey: "showsTitle") : true
    super.init(coder: coder)
    // When unarchived by the accessibility popover, hide this view so only the
    // native segment labels are visible. The system renders those at popover scale.
    isHidden = true
  }

  override func encode(with coder: NSCoder) {
    super.encode(with: coder)
    coder.encode(symbolName, forKey: "symbolName")
    coder.encode(customImageName, forKey: "customImageName")
    coder.encode(customImageBundleIdentifier, forKey: "customImageBundleIdentifier")
    coder.encode(title, forKey: "title")
    coder.encode(resolvedImage, forKey: "resolvedImage")
    coder.encode(showsTitle, forKey: "showsTitle")
  }

  override func tintColorDidChange() {
    super.tintColorDidChange()
    setNeedsDisplay()
  }

  // MARK: - Sizing

  override var intrinsicContentSize: CGSize {
    let textSize = showsTitle ? (title as NSString).size(withAttributes: [.font: font]) : .zero
    let icon = loadIcon()
    let contentWidth = max(icon?.size.width ?? 0, textSize.width)
    let height = imageAreaHeight + textSize.height
    return CGSize(width: contentWidth, height: height)
  }

  // MARK: - Drawing

  override func draw(_ rect: CGRect) {
    let tintColor = tintColor ?? .label

    let icon = loadIcon()
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: tintColor,
    ]
    let textSize = showsTitle ? (title as NSString).size(withAttributes: textAttributes) : .zero

    let contentNudgeUp: CGFloat = 1
    let iconTextGap: CGFloat = 1

    // Draw icon centered in top area
    if let icon {
      let imageSize = icon.size
      let imageX = (bounds.width - imageSize.width) / 2
      let imageY = showsTitle
        ? (imageAreaHeight - imageSize.height) / 2 - contentNudgeUp
        : (bounds.height - imageSize.height) / 2
      let imageRect = CGRect(x: imageX, y: imageY, width: imageSize.width, height: imageSize.height)

      tintColor.setFill()
      icon.withRenderingMode(.alwaysTemplate).draw(in: imageRect)
    }

    // Draw text centered below icon area
    let textX = (bounds.width - textSize.width) / 2
    let textPoint = CGPoint(x: textX, y: imageAreaHeight - contentNudgeUp + iconTextGap)
    if showsTitle { (title as NSString).draw(at: textPoint, withAttributes: textAttributes) }
  }

  // MARK: - Private

  private func loadIcon() -> UIImage? {
    let config = UIImage.SymbolConfiguration(
      pointSize: Constants.tabIconPointSize,
      weight: .medium,
      scale: .large
    )

    if let resolvedImage {
      return resolvedImage.applyingSymbolConfiguration(config) ?? resolvedImage
    } else if !symbolName.isEmpty {
      return UIImage(systemName: symbolName, withConfiguration: config)
    } else if !customImageName.isEmpty {
      let bundle: Bundle?
      if customImageBundleIdentifier.isEmpty {
        bundle = .main
      } else {
        bundle = Bundle(identifier: customImageBundleIdentifier)
      }
      return UIImage(named: customImageName, in: bundle, with: config)
    }

    return nil
  }
}
