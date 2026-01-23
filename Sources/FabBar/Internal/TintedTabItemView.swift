import UIKit

/// A custom UIView that draws a tab item (image + text) using tintColor.
/// Automatically participates in tintAdjustmentMode for proper dimming behavior.
@available(iOS 26.0, *)
final class TintedTabItemView: UIView {
    var image: UIImage? {
        didSet { setNeedsDisplay() }
    }

    var text: String = "" {
        didSet { setNeedsDisplay() }
    }

    var font: UIFont = .systemFont(ofSize: 10, weight: .medium) {
        didSet { setNeedsDisplay() }
    }

    /// Height allocated for the image area
    var imageAreaHeight: CGFloat = 28 {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let tintColor = tintColor else { return }

        // Draw image centered in top area
        if let image = image {
            let imageSize = image.size
            let imageX = (bounds.width - imageSize.width) / 2
            let imageY = (imageAreaHeight - imageSize.height) / 2
            let imageRect = CGRect(x: imageX, y: imageY, width: imageSize.width, height: imageSize.height)

            tintColor.setFill()
            image.withRenderingMode(.alwaysTemplate).draw(in: imageRect)
        }

        // Draw text centered below image area
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: tintColor
        ]

        let textSize = (text as NSString).size(withAttributes: textAttributes)
        let textX = (bounds.width - textSize.width) / 2
        let textY = imageAreaHeight

        (text as NSString).draw(at: CGPoint(x: textX, y: textY), withAttributes: textAttributes)
    }
}
