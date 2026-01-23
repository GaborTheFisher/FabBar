import UIKit

/// A UIView that displays a single tab item with an icon and title stacked vertically.
/// Uses tintColor for rendering, automatically participating in tintAdjustmentMode for proper dimming.
@available(iOS 26.0, *)
final class TabItemView<Value: Hashable>: UIView {
    private var image: UIImage?
    private var text: String = ""
    private let font: UIFont = .systemFont(ofSize: Constants.tabTitleFontSize, weight: .medium)
    private let imageAreaHeight: CGFloat = Constants.iconViewSize

    var activeTintColor: UIColor = .tintColor {
        didSet { updateColors() }
    }

    var inactiveTintColor: UIColor = .label {
        didSet { updateColors() }
    }

    var isHighlighted: Bool = false

    init(tab: FabBarTab<Value>) {
        super.init(frame: .zero)

        isOpaque = false
        contentMode = .redraw

        let config = UIImage.SymbolConfiguration(
            pointSize: Constants.tabIconPointSize,
            weight: .medium,
            scale: .large
        )

        if let imageName = tab.image {
            let bundle = tab.imageBundle ?? .main
            image = UIImage(named: imageName, in: bundle, with: config)
            if image == nil {
                fabBarLogger.warning("Failed to load image '\(imageName)' from bundle for tab '\(tab.title)'")
            }
        } else if let systemImageName = tab.systemImage {
            image = UIImage(systemName: systemImageName, withConfiguration: config)
            if image == nil {
                fabBarLogger.warning("Failed to load SF Symbol '\(systemImageName)' for tab '\(tab.title)'")
            }
        }

        text = tab.title
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }

    func updateColors(animated: Bool = false) {
        let color = isHighlighted ? activeTintColor : inactiveTintColor

        if animated {
            UIView.animate(withDuration: Constants.colorTransitionDuration) {
                self.tintColor = color
            }
        } else {
            tintColor = color
        }
    }

    override func draw(_ rect: CGRect) {
        guard let tintColor = tintColor else { return }

        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: tintColor
        ]
        let textSize = (text as NSString).size(withAttributes: textAttributes)

        // Calculate total content height and vertical offset to center
        let contentHeight = imageAreaHeight + textSize.height
        let verticalOffset = (bounds.height - contentHeight) / 2

        // Draw image centered in top area
        if let image = image {
            let imageSize = image.size
            let imageX = (bounds.width - imageSize.width) / 2
            let imageY = verticalOffset + (imageAreaHeight - imageSize.height) / 2
            let imageRect = CGRect(x: imageX, y: imageY, width: imageSize.width, height: imageSize.height)

            tintColor.setFill()
            image.withRenderingMode(.alwaysTemplate).draw(in: imageRect)
        }

        // Draw text centered below image area
        let textX = (bounds.width - textSize.width) / 2
        let textY = verticalOffset + imageAreaHeight

        (text as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: textAttributes)
    }
}
