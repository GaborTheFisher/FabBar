import UIKit

/// A UIView that displays a single tab item with an icon and title stacked vertically.
/// Uses tintColor for both image and text to get automatic tintAdjustmentMode support.
@available(iOS 26.0, *)
final class TabItemLabelView<Tab: Hashable>: UIView {
    private let contentView: TintedTabItemView

    var activeTintColor: UIColor = .tintColor {
        didSet { updateColors() }
    }

    var inactiveTintColor: UIColor = .label {
        didSet { updateColors() }
    }

    var isHighlighted: Bool = false

    init(tabItem: FabBarItem<Tab>) {
        contentView = TintedTabItemView()

        super.init(frame: .zero)

        setupViews(tabItem: tabItem)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews(tabItem: FabBarItem<Tab>) {
        // Configure image
        let config = UIImage.SymbolConfiguration(
            pointSize: Constants.tabIconPointSize,
            weight: .medium,
            scale: .large
        )

        var image: UIImage?
        if let imageName = tabItem.image {
            let bundle = tabItem.imageBundle ?? .main
            image = UIImage(named: imageName, in: bundle, with: config)
            if image == nil {
                fabBarLogger.warning("Failed to load image '\(imageName)' from bundle for tab '\(tabItem.title)'")
            }
        } else if let systemImageName = tabItem.systemImage {
            image = UIImage(systemName: systemImageName, withConfiguration: config)
            if image == nil {
                fabBarLogger.warning("Failed to load SF Symbol '\(systemImageName)' for tab '\(tabItem.title)'")
            }
        }

        contentView.image = image
        contentView.text = tabItem.title
        contentView.font = .systemFont(ofSize: Constants.tabTitleFontSize, weight: .medium)
        contentView.imageAreaHeight = Constants.iconViewSize
        contentView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentView)

        NSLayoutConstraint.activate([
            contentView.centerXAnchor.constraint(equalTo: centerXAnchor),
            contentView.centerYAnchor.constraint(equalTo: centerYAnchor),
            contentView.widthAnchor.constraint(equalTo: widthAnchor),
            contentView.heightAnchor.constraint(equalToConstant: Constants.iconViewSize + Constants.tabTitleFontSize + 4),
        ])

        updateColors()
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
}
