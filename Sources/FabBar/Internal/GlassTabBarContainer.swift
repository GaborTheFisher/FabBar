import UIKit

/// A container view that wraps the segmented control and FAB button with UIKit glass effects.
/// Uses UIGlassContainerEffect to enable morphing between the glass elements.
@available(iOS 26.0, *)
final class GlassTabBarContainer<Tab: Hashable>: UIView {
    let containerEffectView: UIVisualEffectView
    let segmentedGlassView: UIVisualEffectView
    let segmentedControl: HiddenLabelSegmentedControl
    let labelsOverlay: TabItemLabelsOverlay<Tab>
    let fabGlassView: UIVisualEffectView
    let fabButton: UIButton

    private let spacing: CGFloat = Constants.fabSpacing
    private let contentPadding: CGFloat = Constants.contentPadding

    init(
        segmentedControl: HiddenLabelSegmentedControl,
        tabItems: [FabBarItem<Tab>],
        selectedIndex: Int,
        action: FabAction
    ) {
        self.segmentedControl = segmentedControl
        labelsOverlay = TabItemLabelsOverlay(tabItems: tabItems, selectedIndex: selectedIndex)

        // Create glass container effect for morphing
        let containerEffect = UIGlassContainerEffect()
        containerEffect.spacing = Constants.fabSpacing
        containerEffectView = UIVisualEffectView(effect: containerEffect)

        // Create segmented control glass effect
        let segmentedGlassEffect = UIGlassEffect()
        segmentedGlassEffect.isInteractive = true
        segmentedGlassView = UIVisualEffectView(effect: segmentedGlassEffect)

        // Create FAB button
        let fabGlassEffect = UIGlassEffect()
        fabGlassEffect.isInteractive = true
        fabGlassEffect.tintColor = .tintColor
        fabGlassView = UIVisualEffectView(effect: fabGlassEffect)

        let button = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: Constants.fabIconPointSize, weight: .medium)
        let buttonImage = UIImage(systemName: action.systemImage, withConfiguration: config)
        button.setImage(buttonImage, for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = action.accessibilityLabel
        button.accessibilityTraits = .button
        fabButton = button

        super.init(frame: .zero)

        // Ensure tint adjustment mode is automatic so views dim when sheets are presented
        tintAdjustmentMode = .automatic
        fabGlassView.tintAdjustmentMode = .automatic
        fabButton.tintAdjustmentMode = .automatic

        setupViews(action: action)
        setupHighlightCallbacks()
    }

    private func setupViews(action: FabAction) {
        // Add container effect view
        addSubview(containerEffectView)
        containerEffectView.translatesAutoresizingMaskIntoConstraints = false

        // Add segmented glass view to container's contentView
        containerEffectView.contentView.addSubview(segmentedGlassView)
        segmentedGlassView.translatesAutoresizingMaskIntoConstraints = false

        // Add segmented control to segmented glass view's contentView
        segmentedGlassView.contentView.addSubview(segmentedControl)
        segmentedControl.translatesAutoresizingMaskIntoConstraints = false

        // Add labels overlay on top of segmented control
        segmentedGlassView.contentView.addSubview(labelsOverlay)
        labelsOverlay.translatesAutoresizingMaskIntoConstraints = false

        // Add FAB glass view
        containerEffectView.contentView.addSubview(fabGlassView)
        fabGlassView.translatesAutoresizingMaskIntoConstraints = false

        fabGlassView.contentView.addSubview(fabButton)
        fabButton.translatesAutoresizingMaskIntoConstraints = false

        // Store action for button
        fabButton.addAction(UIAction { _ in action.action() }, for: .touchUpInside)

        NSLayoutConstraint.activate([
            containerEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
            containerEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
            containerEffectView.topAnchor.constraint(equalTo: topAnchor),
            containerEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

            segmentedGlassView.leadingAnchor.constraint(equalTo: containerEffectView.contentView.leadingAnchor),
            segmentedGlassView.topAnchor.constraint(equalTo: containerEffectView.contentView.topAnchor),
            segmentedGlassView.bottomAnchor.constraint(equalTo: containerEffectView.contentView.bottomAnchor),
            segmentedGlassView.trailingAnchor.constraint(equalTo: fabGlassView.leadingAnchor, constant: -spacing),

            segmentedControl.leadingAnchor.constraint(equalTo: segmentedGlassView.contentView.leadingAnchor, constant: contentPadding),
            segmentedControl.trailingAnchor.constraint(equalTo: segmentedGlassView.contentView.trailingAnchor, constant: -contentPadding),
            segmentedControl.topAnchor.constraint(equalTo: segmentedGlassView.contentView.topAnchor, constant: contentPadding),
            segmentedControl.bottomAnchor.constraint(equalTo: segmentedGlassView.contentView.bottomAnchor, constant: -contentPadding),

            // Labels overlay matches segmented control exactly
            labelsOverlay.leadingAnchor.constraint(equalTo: segmentedControl.leadingAnchor),
            labelsOverlay.trailingAnchor.constraint(equalTo: segmentedControl.trailingAnchor),
            labelsOverlay.topAnchor.constraint(equalTo: segmentedControl.topAnchor),
            labelsOverlay.bottomAnchor.constraint(equalTo: segmentedControl.bottomAnchor),

            // FAB glass view
            fabGlassView.trailingAnchor.constraint(equalTo: containerEffectView.contentView.trailingAnchor),
            fabGlassView.topAnchor.constraint(equalTo: containerEffectView.contentView.topAnchor),
            fabGlassView.bottomAnchor.constraint(equalTo: containerEffectView.contentView.bottomAnchor),
            fabGlassView.widthAnchor.constraint(equalTo: fabGlassView.heightAnchor),

            // Fill the entire glass area so taps anywhere trigger the action
            fabButton.leadingAnchor.constraint(equalTo: fabGlassView.contentView.leadingAnchor),
            fabButton.trailingAnchor.constraint(equalTo: fabGlassView.contentView.trailingAnchor),
            fabButton.topAnchor.constraint(equalTo: fabGlassView.contentView.topAnchor),
            fabButton.bottomAnchor.constraint(equalTo: fabGlassView.contentView.bottomAnchor),
        ])
    }

    private func setupHighlightCallbacks() {
        segmentedControl.onHighlightChange = { [weak self] index in
            self?.labelsOverlay.setHighlightedIndex(index)
        }

        segmentedControl.onHighlightEnd = { [weak self] in
            self?.labelsOverlay.setHighlightedIndex(nil)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Capsule shape for segmented control
        segmentedGlassView.cornerConfiguration = .capsule()

        // Circle shape for FAB button (capsule with equal width/height = circle)
        fabGlassView.cornerConfiguration = .capsule()
    }

    override func tintColorDidChange() {
        super.tintColorDidChange()
        // Update FAB glass effect tint when tintAdjustmentMode changes
        // Create a new effect since modifying existing effect's tintColor doesn't update visuals
        let newEffect = UIGlassEffect()
        newEffect.isInteractive = true
        newEffect.tintColor = tintColor
        fabGlassView.effect = newEffect
    }
}
