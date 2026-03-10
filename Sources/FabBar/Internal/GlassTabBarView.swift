import UIKit

/// The root UIKit view that assembles the tab bar with glass effects.
/// Uses UIGlassContainerEffect to enable morphing between the segmented control and FAB.
@available(iOS 26.0, *)
final class GlassTabBarView: UIView {
  let containerEffectView: UIVisualEffectView
  let segmentedGlassView: UIVisualEffectView
  let segmentedControl: TabBarSegmentedControl
  let fabGlassView: UIVisualEffectView
  let fabButton: UIButton

  private let spacing: CGFloat = Constants.fabSpacing
  private let contentPadding: CGFloat = Constants.contentPadding

  private(set) var tabCount: Int
  private var segmentedTrailingConstraint: NSLayoutConstraint?

  private let secondaryActions: [FabBarAction]
  private var secondaryActionViews: [(glassView: UIVisualEffectView, button: UIButton)] = []
  private var isExpanded = false
  private var backdropView: UIView?

  init(
    segmentedControl: TabBarSegmentedControl,
    tabCount: Int,
    action: FabBarAction,
    secondaryActions: [FabBarAction]
  ) {
    self.segmentedControl = segmentedControl
    self.tabCount = tabCount
    self.secondaryActions = secondaryActions

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
    if let customVC = action.customView {
      let hostingView = customVC.view!
      hostingView.translatesAutoresizingMaskIntoConstraints = false
      hostingView.backgroundColor = .clear
      hostingView.isUserInteractionEnabled = false
      button.addSubview(hostingView)
      NSLayoutConstraint.activate([
        hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        hostingView.topAnchor.constraint(equalTo: button.topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
      ])
    } else {
      let config = UIImage.SymbolConfiguration(pointSize: Constants.fabIconPointSize, weight: .medium)
      let buttonImage = UIImage(systemName: action.systemImage, withConfiguration: config)
      button.setImage(buttonImage, for: .normal)
      button.tintColor = .white
    }
    button.accessibilityLabel = action.accessibilityLabel
    button.accessibilityTraits = .button
    fabButton = button

    super.init(frame: .zero)

    clipsToBounds = false

    // Ensure tint adjustment mode is automatic so views dim when sheets are presented
    tintAdjustmentMode = .automatic
    fabGlassView.tintAdjustmentMode = .automatic
    fabButton.tintAdjustmentMode = .automatic

    setupViews(action: action)

    if !secondaryActions.isEmpty {
      setupSecondaryActions()
    }
  }

  private func setupViews(action: FabBarAction) {
    // Add container effect view
    addSubview(containerEffectView)
    containerEffectView.translatesAutoresizingMaskIntoConstraints = false

    // Add segmented glass view to container's contentView
    containerEffectView.contentView.addSubview(segmentedGlassView)
    segmentedGlassView.translatesAutoresizingMaskIntoConstraints = false

    // Add segmented control to segmented glass view's contentView
    segmentedGlassView.contentView.addSubview(segmentedControl)
    segmentedControl.translatesAutoresizingMaskIntoConstraints = false

    // Add FAB glass view
    containerEffectView.contentView.addSubview(fabGlassView)
    fabGlassView.translatesAutoresizingMaskIntoConstraints = false

    fabGlassView.contentView.addSubview(fabButton)
    fabButton.translatesAutoresizingMaskIntoConstraints = false

    // Wire FAB tap: toggle expansion when secondary actions exist, otherwise fire directly
    if secondaryActions.isEmpty {
      fabButton.addAction(UIAction { _ in action.action() }, for: .touchUpInside)
    } else {
      fabButton.addAction(UIAction { [weak self] _ in self?.toggleExpansion(action.action) }, for: .touchUpInside)
    }

    // Extra bottom inset compensates for UISegmentedControl's internal padding,
    // visually centering the content within the glass container.
    let segmentedControlBottomInsetAdjustment: CGFloat = 1

    NSLayoutConstraint.activate([
      containerEffectView.leadingAnchor.constraint(equalTo: leadingAnchor),
      containerEffectView.trailingAnchor.constraint(equalTo: trailingAnchor),
      containerEffectView.topAnchor.constraint(equalTo: topAnchor),
      containerEffectView.bottomAnchor.constraint(equalTo: bottomAnchor),

      segmentedGlassView.leadingAnchor.constraint(equalTo: containerEffectView.contentView.leadingAnchor),
      segmentedGlassView.topAnchor.constraint(equalTo: containerEffectView.contentView.topAnchor),
      segmentedGlassView.bottomAnchor.constraint(equalTo: containerEffectView.contentView.bottomAnchor),

      segmentedControl.leadingAnchor.constraint(equalTo: segmentedGlassView.contentView.leadingAnchor, constant: contentPadding),
      segmentedControl.trailingAnchor.constraint(equalTo: segmentedGlassView.contentView.trailingAnchor, constant: -contentPadding),
      segmentedControl.topAnchor.constraint(equalTo: segmentedGlassView.contentView.topAnchor, constant: contentPadding),
      segmentedControl.bottomAnchor.constraint(equalTo: segmentedGlassView.contentView.bottomAnchor, constant: -contentPadding - segmentedControlBottomInsetAdjustment),

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

    // Set up the trailing constraint based on tab count
    segmentedTrailingConstraint = makeSegmentedTrailingConstraint()
    segmentedTrailingConstraint?.isActive = true
  }

  /// Creates the appropriate trailing constraint for the segmented glass view.
  /// For 3+ tabs, fills to the FAB. For fewer tabs, floats leading-aligned.
  private func makeSegmentedTrailingConstraint() -> NSLayoutConstraint {
    if tabCount >= 3 {
      segmentedGlassView.trailingAnchor.constraint(equalTo: fabGlassView.leadingAnchor, constant: -spacing)
    } else {
      segmentedGlassView.trailingAnchor.constraint(lessThanOrEqualTo: fabGlassView.leadingAnchor, constant: -spacing)
    }
  }

  /// Updates the tab count and swaps the trailing constraint to match.
  func updateTabCount(_ newCount: Int) {
    guard newCount != tabCount else { return }
    tabCount = newCount
    segmentedTrailingConstraint?.isActive = false
    segmentedTrailingConstraint = makeSegmentedTrailingConstraint()
    segmentedTrailingConstraint?.isActive = true
  }

  // MARK: - Secondary Actions

  private func setupSecondaryActions() {
    for secondaryAction in secondaryActions {
      let glassEffect = UIGlassEffect()
      glassEffect.isInteractive = true
      let glassView = UIVisualEffectView(effect: glassEffect)
      glassView.translatesAutoresizingMaskIntoConstraints = false

      let hasCustomView = secondaryAction.customView != nil
      let horizontalPadding: CGFloat = hasCustomView ? 12 : 0

      let button = UIButton(type: .system)
      if let customVC = secondaryAction.customView {
        let hostingView = customVC.view!
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.backgroundColor = .clear
        hostingView.isUserInteractionEnabled = false

        // UIHostingController views don't propagate intrinsic content size
        // through Auto Layout. Measure it explicitly and set a fixed width.
        let fittingSize = hostingView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let totalWidth = fittingSize.width + horizontalPadding * 2

        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
          hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
          hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
          hostingView.topAnchor.constraint(equalTo: button.topAnchor),
          hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
          glassView.widthAnchor.constraint(greaterThanOrEqualToConstant: totalWidth),
        ])
      } else {
        let config = UIImage.SymbolConfiguration(pointSize: Constants.fabIconPointSize, weight: .medium)
        let buttonImage = UIImage(systemName: secondaryAction.systemImage, withConfiguration: config)
        button.setImage(buttonImage, for: .normal)
        button.tintColor = .label
      }
      button.accessibilityLabel = secondaryAction.accessibilityLabel
      button.accessibilityTraits = .button
      button.translatesAutoresizingMaskIntoConstraints = false

      glassView.contentView.addSubview(button)

      // Insert below containerEffectView so buttons emerge from behind the FAB
      insertSubview(glassView, belowSubview: containerEffectView)

      // Right-align to FAB and vertically center on FAB for collapsed state
      var constraints = [
        glassView.trailingAnchor.constraint(equalTo: fabGlassView.trailingAnchor),
        glassView.centerYAnchor.constraint(equalTo: fabGlassView.centerYAnchor),
        glassView.heightAnchor.constraint(equalTo: fabGlassView.heightAnchor),

        button.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: horizontalPadding),
        button.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -horizontalPadding),
        button.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
        button.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
      ]

      if !hasCustomView {
        // Circle: match FAB width
        constraints.append(
          glassView.widthAnchor.constraint(equalTo: fabGlassView.widthAnchor)
        )
      }

      NSLayoutConstraint.activate(constraints)

      // Start collapsed
      glassView.alpha = 0
      glassView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)

      // Bring to front on touch so the glass highlight isn't obscured by siblings
      button.addAction(UIAction { _ in
        glassView.superview?.bringSubviewToFront(glassView)
      }, for: .touchDown)

      // Tapping a secondary action fires it and collapses the menu
      let handler = secondaryAction.action
      button.addAction(UIAction { [weak self] _ in
        handler()
        self?.collapse()
      }, for: .touchUpInside)

      secondaryActionViews.append((glassView: glassView, button: button))
    }
  }

  private func toggleExpansion(_ action: @escaping () -> Void) {
    action()
    if isExpanded { collapse() } else { expand() }
  }

  private func showBackdrop() {
    guard let window = window else { return }
    // Cover the entire window so any tap outside the buttons collapses.
    // Frame is in self's coordinate space so it extends well beyond bounds.
    let windowBounds = window.bounds
    let localRect = convert(windowBounds, from: window)
    let backdrop = UIView(frame: localRect)
    backdrop.backgroundColor = .clear
    backdrop.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
    )
    // Behind everything in this view so buttons remain tappable
    insertSubview(backdrop, at: 0)
    backdropView = backdrop
  }

  private func removeBackdrop() {
    backdropView?.removeFromSuperview()
    backdropView = nil
  }

  @objc private func backdropTapped() {
    collapse()
  }

  private func expand() {
    isExpanded = true
    showBackdrop()
    let buttonHeight = fabGlassView.bounds.height
    let gap: CGFloat = 12

    for (index, (glassView, _)) in secondaryActionViews.enumerated() {
      let offset = CGFloat(index + 1) * (buttonHeight + gap)
      let delay = Double(index) * 0.03

      UIView.animate(
        withDuration: 0.4, delay: delay,
        usingSpringWithDamping: 0.7, initialSpringVelocity: 0.5
      ) {
        glassView.transform = CGAffineTransform(translationX: 0, y: -offset)
        glassView.alpha = 1
      }
    }

    UIView.animate(withDuration: 0.3) {
      self.fabButton.transform = CGAffineTransform(rotationAngle: .pi / 4)
    }
  }

  private func collapse() {
    isExpanded = false
    removeBackdrop()

    for (index, (glassView, _)) in secondaryActionViews.reversed().enumerated() {
      let delay = Double(index) * 0.03

      UIView.animate(
        withDuration: 0.3, delay: delay,
        usingSpringWithDamping: 0.85, initialSpringVelocity: 0
      ) {
        glassView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        glassView.alpha = 0
      }
    }

    UIView.animate(withDuration: 0.3) {
      self.fabButton.transform = .identity
    }
  }

  // MARK: - Hit Testing

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    if super.point(inside: point, with: event) { return true }
    if isExpanded {
      // Accept any point within the backdrop (full screen) so the tap
      // gesture recognizer can fire and collapse the menu
      if let backdrop = backdropView, backdrop.frame.contains(point) {
        return true
      }
      for (glassView, _) in secondaryActionViews {
        let converted = glassView.convert(point, from: self)
        if glassView.point(inside: converted, with: event) { return true }
      }
    }
    return false
  }

  override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
    if isExpanded {
      for (glassView, _) in secondaryActionViews.reversed() {
        let converted = glassView.convert(point, from: self)
        if let hit = glassView.hitTest(converted, with: event) { return hit }
      }
    }
    return super.hitTest(point, with: event)
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

    for (glassView, _) in secondaryActionViews {
      glassView.cornerConfiguration = .capsule()
    }
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
