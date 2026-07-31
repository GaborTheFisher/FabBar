import UIKit

@available(iOS 26.0, *)
enum FabBarTabItemLayout: Int, Sendable {
  case stacked
  case inline
}

/// A custom-draw view that renders a tab item (SF Symbol icon + title) at the current graphics context scale.
///
/// This view supports `NSCoding` so it survives the system accessibility popover's archive/unarchive cycle.
/// When the popover copies segment content, it archives this view and unarchives a copy. Because the
/// symbol name and title are encoded as simple strings, the copy can re-render via `draw(_:)` at whatever
/// scale the popover uses — producing crisp output without any timing hacks or pre-rendered bitmaps.
@available(iOS 26.0, *)
@objc(FabBarTabItemContentView)
final class TabItemContentView: UIView {
  private var symbolName: String = ""
  private var customImageName: String = ""
  private var customImageBundleIdentifier: String = ""
  private var title: String = ""
  private(set) var layout: FabBarTabItemLayout = .stacked
  private(set) var showsInlineTitle = true

  private var font: UIFont {
    UIFont.systemFont(
      ofSize: layout == .inline
        ? Constants.inlineTabTitleFontSize
        : Constants.tabTitleFontSize,
      weight: .semibold
    )
  }

  init(title: String, symbolName: String, layout: FabBarTabItemLayout = .stacked) {
    self.title = title
    self.symbolName = symbolName
    self.layout = layout
    super.init(frame: .zero)
    isOpaque = false
    isUserInteractionEnabled = false
    contentMode = .redraw
  }

  init(
    title: String,
    imageName: String,
    imageBundle: Bundle?,
    layout: FabBarTabItemLayout = .stacked
  ) {
    self.title = title
    self.customImageName = imageName
    self.customImageBundleIdentifier = imageBundle?.bundleIdentifier ?? ""
    self.layout = layout
    super.init(frame: .zero)
    isOpaque = false
    isUserInteractionEnabled = false
    contentMode = .redraw
  }

  // MARK: - NSCoding

  required init?(coder: NSCoder) {
    self.symbolName = coder.decodeObject(forKey: "symbolName") as? String ?? ""
    self.customImageName = coder.decodeObject(forKey: "customImageName") as? String ?? ""
    self.customImageBundleIdentifier = coder.decodeObject(forKey: "customImageBundleIdentifier") as? String ?? ""
    self.title = coder.decodeObject(forKey: "title") as? String ?? ""
    self.layout = FabBarTabItemLayout(rawValue: coder.decodeInteger(forKey: "layout")) ?? .stacked
    self.showsInlineTitle = coder.containsValue(forKey: "showsInlineTitle")
      ? coder.decodeBool(forKey: "showsInlineTitle")
      : true
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
    coder.encode(layout.rawValue, forKey: "layout")
    coder.encode(showsInlineTitle, forKey: "showsInlineTitle")
  }

  /// Keeps the compact presentation mounted while allowing its labels to
  /// collapse at an exceptionally narrow local proposal. The intrinsic size
  /// remains the labeled ideal so widening the window restores the reference
  /// treatment automatically.
  func setShowsInlineTitle(_ showsInlineTitle: Bool) {
    guard self.showsInlineTitle != showsInlineTitle else { return }
    self.showsInlineTitle = showsInlineTitle
    setNeedsDisplay()
  }

  override func tintColorDidChange() {
    super.tintColorDidChange()
    setNeedsDisplay()
  }

  // MARK: - Sizing

  override var intrinsicContentSize: CGSize {
    let textSize = (title as NSString).size(withAttributes: [.font: font])
    let icon = loadIcon()
    switch layout {
    case .stacked:
      let contentWidth = max(icon?.size.width ?? 0, textSize.width)
      return CGSize(width: contentWidth, height: Constants.iconViewSize + textSize.height)
    case .inline:
      let hasIcon = icon != nil
      let hasTitle = !title.isEmpty
      let iconWidth = hasIcon ? Constants.iconViewSize : 0
      let spacing = hasIcon && hasTitle ? Constants.inlineIconTitleSpacing : 0
      return CGSize(
        width: iconWidth + spacing + textSize.width,
        height: max(Constants.iconViewSize, ceil(textSize.height))
      )
    }
  }

  // MARK: - Drawing

  override func draw(_ rect: CGRect) {
    let tintColor = tintColor ?? .label

    let icon = loadIcon()
    let textAttributes: [NSAttributedString.Key: Any] = [
      .font: font,
      .foregroundColor: tintColor,
    ]
    let textSize = (title as NSString).size(withAttributes: textAttributes)

    switch layout {
    case .stacked:
      drawStacked(icon: icon, textSize: textSize, textAttributes: textAttributes, tintColor: tintColor)
    case .inline:
      drawInline(icon: icon, textSize: textSize, textAttributes: textAttributes, tintColor: tintColor)
    }
  }

  // MARK: - Private

  private func loadIcon() -> UIImage? {
    let config = UIImage.SymbolConfiguration(
      pointSize: Constants.tabIconPointSize,
      weight: .medium,
      scale: .large
    )

    if !symbolName.isEmpty {
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

  private func drawStacked(
    icon: UIImage?,
    textSize: CGSize,
    textAttributes: [NSAttributedString.Key: Any],
    tintColor: UIColor
  ) {
    let contentNudgeUp: CGFloat = 1
    let iconTextGap: CGFloat = 1

    if let icon {
      let imageSize = icon.size
      let imageX = (bounds.width - imageSize.width) / 2
      let imageY = (Constants.iconViewSize - imageSize.height) / 2 - contentNudgeUp
      tintColor.setFill()
      icon.withRenderingMode(.alwaysTemplate).draw(
        in: CGRect(x: imageX, y: imageY, width: imageSize.width, height: imageSize.height)
      )
    }

    let textX = (bounds.width - textSize.width) / 2
    let textPoint = CGPoint(
      x: textX,
      y: Constants.iconViewSize - contentNudgeUp + iconTextGap
    )
    (title as NSString).draw(at: textPoint, withAttributes: textAttributes)
  }

  private func drawInline(
    icon: UIImage?,
    textSize: CGSize,
    textAttributes: [NSAttributedString.Key: Any],
    tintColor: UIColor
  ) {
    let hasIcon = icon != nil
    let hasTitle = showsInlineTitle && !title.isEmpty
    let iconWidth = hasIcon ? Constants.iconViewSize : 0
    let spacing = hasIcon && hasTitle ? Constants.inlineIconTitleSpacing : 0
    let visibleTextWidth = hasTitle ? textSize.width : 0
    let contentWidth = iconWidth + spacing + visibleTextWidth
    let contentX = (bounds.width - contentWidth) / 2

    if let icon {
      let imageSize = icon.size
      let imageRect = CGRect(
        x: contentX + (Constants.iconViewSize - imageSize.width) / 2,
        y: (bounds.height - imageSize.height) / 2,
        width: imageSize.width,
        height: imageSize.height
      )
      tintColor.setFill()
      icon.withRenderingMode(.alwaysTemplate).draw(in: imageRect)
    }

    if hasTitle {
      let textPoint = CGPoint(
        x: contentX + iconWidth + spacing,
        y: (bounds.height - textSize.height) / 2
      )
      (title as NSString).draw(at: textPoint, withAttributes: textAttributes)
    }
  }
}
