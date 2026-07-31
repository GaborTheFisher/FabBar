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
  private var density: FabBarDensity
  private var preferredCompactSegmentWidths: [CGFloat] = []
  private(set) var isCompactContentCollapsed = false

  /// A pre-built secondary action view, parked off-screen until the menu
  /// expands. `isCircle` icon-only pills match the FAB width; custom-view
  /// pills size themselves to their content via Auto Layout.
  private struct SecondaryItem {
    let glassView: UIVisualEffectView
    let button: UIButton
    let isCircle: Bool
  }

  private let secondaryActions: [FabBarAction]
  private var secondaryItems: [SecondaryItem] = []
  private(set) var isExpanded = false
  private var primaryAction: () -> Void
  private var isSecondaryActionMenuEnabled: Bool
  private var backdropView: UIView?

  /// Spacing between the FAB and the first pill / between pills.
  private let secondaryGap: CGFloat = 12

  /// Geometry captured when the menu expanded. The pills use window-space
  /// constraints, so any window, container, density, or FAB-frame change
  /// invalidates their anchor and collapses the menu.
  private var expandedWindowBounds: CGRect = .zero
  private var expandedBarBounds: CGRect = .zero
  private var expandedFABFrame: CGRect = .zero

  init(
    segmentedControl: TabBarSegmentedControl,
    tabCount: Int,
    action: FabBarAction,
    secondaryActions: [FabBarAction],
    isSecondaryActionMenuEnabled: Bool,
    density: FabBarDensity = .regular
  ) {
    self.segmentedControl = segmentedControl
    self.tabCount = tabCount
    self.secondaryActions = secondaryActions
    self.primaryAction = action.action
    self.isSecondaryActionMenuEnabled = isSecondaryActionMenuEnabled
    self.density = density

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

    setupViews()

    if !secondaryActions.isEmpty {
      setupSecondaryActions()
    }
  }

  private func setupViews() {
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

    // Keep one UIKit control in charge of both direct and expandable modes.
    // The mode is updated by the representable as the surrounding app state
    // changes, avoiding a competing SwiftUI hit target above this button.
    fabButton.addAction(UIAction { [weak self] _ in
      self?.primaryButtonTapped()
    }, for: .touchUpInside)

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

  /// Creates the appropriate trailing constraint for the segmented glass
  /// view. Compact density always uses equality because the root view has a
  /// determinate intrinsic width. Regular density fills for 3+ tabs and keeps
  /// the historical leading-aligned treatment for fewer tabs.
  private func makeSegmentedTrailingConstraint() -> NSLayoutConstraint {
    if density.hugsContentHorizontally || tabCount >= 3 {
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
    invalidateIntrinsicContentSize()
  }

  /// Updates the coarse stacked/inline presentation without replacing the
  /// UIKit bar or its hosted SwiftUI controllers.
  func updateDensity(_ newDensity: FabBarDensity) {
    if density != newDensity {
      collapse(animated: false)
      density = newDensity
      segmentedTrailingConstraint?.isActive = false
      segmentedTrailingConstraint = makeSegmentedTrailingConstraint()
      segmentedTrailingConstraint?.isActive = true
    }
    invalidateIntrinsicContentSize()
    setNeedsLayout()
  }

  /// Stores the labeled compact widths independently of the widths currently
  /// applied to `UISegmentedControl`. A narrow layout may temporarily replace
  /// them with equal icon-only segments; keeping the ideals here lets a later
  /// resize restore the variable-width labeled strip.
  func updatePreferredCompactSegmentWidths(_ widths: [CGFloat]) {
    guard preferredCompactSegmentWidths != widths else { return }
    preferredCompactSegmentWidths = widths
    invalidateIntrinsicContentSize()
    setNeedsLayout()
  }

  /// Reconciles the current SwiftUI action and menu mode without rebuilding
  /// the UIKit bar. Turning the menu off hides any already-expanded pills
  /// immediately so a simultaneous sheet presentation cannot expose them.
  func updatePrimaryAction(
    _ action: @escaping () -> Void,
    isSecondaryActionMenuEnabled: Bool
  ) {
    primaryAction = action
    guard self.isSecondaryActionMenuEnabled != isSecondaryActionMenuEnabled else {
      return
    }

    self.isSecondaryActionMenuEnabled = isSecondaryActionMenuEnabled
    if !isSecondaryActionMenuEnabled {
      collapse(animated: false)
    }
  }

  // MARK: - Secondary Actions

  /// Builds each secondary-action pill and parks it in the bar, hidden. While
  /// collapsed the pills live here so their (SwiftUI) content lays out and
  /// settles to a correct intrinsic size; on expand they're reparented to the
  /// *window* (see ``expand()``). They can't simply fan out in place because
  /// the bar is laid out at a fixed `barHeight` by the SwiftUI host that wraps
  /// it, and that host clips hit-testing to its own bounds — so a pill above
  /// the bar would render but never receive touches. Hosting them in the window
  /// puts them outside that clip while leaving the bar's footprint untouched.
  private func setupSecondaryActions() {
    for secondaryAction in secondaryActions {
      let glassEffect = UIGlassEffect()
      glassEffect.isInteractive = true
      let glassView = UIVisualEffectView(effect: glassEffect)
      // Sized by Auto Layout from its content; parked in the bar while
      // collapsed and reparented to the window on expand.
      glassView.translatesAutoresizingMaskIntoConstraints = false
      glassView.cornerConfiguration = .capsule()

      let hasCustomView = secondaryAction.customView != nil
      let horizontalPadding: CGFloat = hasCustomView ? 12 : 0

      let button = UIButton(type: .system)
      button.translatesAutoresizingMaskIntoConstraints = false

      // Internal constraints — independent of where the pill is hosted.
      var constraints: [NSLayoutConstraint] = []

      if let customVC = secondaryAction.customView {
        let hostingView = customVC.view!
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.backgroundColor = .clear
        hostingView.isUserInteractionEnabled = false

        // A hosting view's content size isn't reliable until it has laid out
        // on screen, so use this measurement only as a minimum width — the
        // pill's real width is driven by the hosting view's intrinsic content
        // once it's in the window (which is why this is a constraint, not a
        // frame).
        let fittingSize = hostingView.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        let totalWidth = fittingSize.width + horizontalPadding * 2

        button.addSubview(hostingView)
        constraints += [
          hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
          hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
          hostingView.topAnchor.constraint(equalTo: button.topAnchor),
          hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
          glassView.widthAnchor.constraint(greaterThanOrEqualToConstant: totalWidth),
        ]
      } else {
        let config = UIImage.SymbolConfiguration(pointSize: Constants.fabIconPointSize, weight: .medium)
        let buttonImage = UIImage(systemName: secondaryAction.systemImage, withConfiguration: config)
        button.setImage(buttonImage, for: .normal)
        button.tintColor = .label
      }
      button.accessibilityLabel = secondaryAction.accessibilityLabel
      button.accessibilityTraits = .button

      glassView.contentView.addSubview(button)
      constraints += [
        button.leadingAnchor.constraint(equalTo: glassView.contentView.leadingAnchor, constant: horizontalPadding),
        button.trailingAnchor.constraint(equalTo: glassView.contentView.trailingAnchor, constant: -horizontalPadding),
        button.topAnchor.constraint(equalTo: glassView.contentView.topAnchor),
        button.bottomAnchor.constraint(equalTo: glassView.contentView.bottomAnchor),
      ]
      if !hasCustomView {
        // Icon-only pills are circular. This is internal to the pill (width
        // relative to its own height) so it survives reparenting.
        constraints.append(glassView.widthAnchor.constraint(equalTo: glassView.heightAnchor))
      }
      NSLayoutConstraint.activate(constraints)

      // Park hidden in the bar so the content lays out and warms up before the
      // first expansion.
      parkInBar(glassView)

      // Bring to front on touch so the glass highlight isn't obscured by siblings
      button.addAction(UIAction { [weak glassView] _ in
        guard let glassView else { return }
        glassView.superview?.bringSubviewToFront(glassView)
      }, for: .touchDown)

      // Tapping a secondary action fires it and collapses the menu
      let handler = secondaryAction.action
      button.addAction(UIAction { [weak self] _ in
        handler()
        self?.collapse()
      }, for: .touchUpInside)

      secondaryItems.append(SecondaryItem(glassView: glassView, button: button, isCircle: !hasCustomView))
    }
  }

  /// Parks a pill back in the bar — hidden, collapsed, and pinned to the FAB.
  /// Keeps its hosting view laid out (so it stays correctly sized for the next
  /// expansion) and ready to fan out again. Reparenting drops the previous
  /// superview's positioning constraints automatically; the pill's internal
  /// content constraints persist.
  private func parkInBar(_ glassView: UIVisualEffectView) {
    insertSubview(glassView, belowSubview: containerEffectView)
    NSLayoutConstraint.activate([
      glassView.trailingAnchor.constraint(equalTo: fabGlassView.trailingAnchor),
      glassView.centerYAnchor.constraint(equalTo: fabGlassView.centerYAnchor),
      glassView.heightAnchor.constraint(equalTo: fabGlassView.heightAnchor),
    ])
    glassView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
    glassView.alpha = 0
    glassView.isUserInteractionEnabled = false
    glassView.isHidden = true
  }

  private func primaryButtonTapped() {
    primaryAction()

    guard isSecondaryActionMenuEnabled, !secondaryItems.isEmpty else {
      collapse(animated: false)
      return
    }

    if isExpanded { collapse() } else { expand() }
  }

  // MARK: - Backdrop

  private func addBackdrop(to window: UIWindow) {
    // Cover the whole window so a tap anywhere outside the pills collapses
    // the menu. Hosted in the window (not in `self`) for the same reason the
    // pills are — to stay clear of the bar's hit-test clip.
    let backdrop = UIView(frame: window.bounds)
    backdrop.backgroundColor = .clear
    backdrop.addGestureRecognizer(
      UITapGestureRecognizer(target: self, action: #selector(backdropTapped))
    )
    window.addSubview(backdrop)
    backdropView = backdrop
  }

  private func removeBackdrop() {
    backdropView?.removeFromSuperview()
    backdropView = nil
  }

  @objc private func backdropTapped() {
    collapse()
  }

  // MARK: - Expand / Collapse

  private func expand() {
    guard !isExpanded, !secondaryItems.isEmpty, let window else { return }
    isExpanded = true
    expandedWindowBounds = window.bounds
    expandedBarBounds = bounds

    // FAB rect in window space — the anchor everything fans out from.
    let fab = fabGlassView.convert(fabGlassView.bounds, to: window)
    expandedFABFrame = fab

    addBackdrop(to: window)

    for (index, item) in secondaryItems.enumerated() {
      let glassView = item.glassView
      glassView.isHidden = false
      glassView.isUserInteractionEnabled = true
      glassView.transform = .identity
      glassView.alpha = 0
      // Reparent from the bar to the window; the bar-relative constraints drop
      // automatically. The pill keeps its (already warmed) content size.
      window.addSubview(glassView)

      // Pin to the FAB's collapsed position (right-aligned, vertically centred).
      // Width stays content-driven (circle width is an internal constraint), so
      // the expand motion is just a transform on top of a correctly sized pill.
      NSLayoutConstraint.activate([
        glassView.trailingAnchor.constraint(equalTo: window.leadingAnchor, constant: fab.maxX),
        glassView.centerYAnchor.constraint(equalTo: window.topAnchor, constant: fab.midY),
        glassView.heightAnchor.constraint(equalToConstant: fab.height),
      ])
      // Resolve the frame now so the collapsed scale anchors on the FAB.
      window.layoutIfNeeded()

      glassView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)

      let offset = CGFloat(index + 1) * (fab.height + secondaryGap)
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

  /// Public entry point used by the representable's `collapseTrigger`.
  func collapseSecondaryActions() {
    collapse(animated: true)
  }

  /// Synchronously removes any window-hosted expansion UI before this bar is
  /// dismantled or detached. Without this cleanup, the backdrop and pills can
  /// outlive the representable and continue intercepting touches in the old
  /// window.
  func prepareForRemoval() {
    collapse(animated: false)
  }

  private func collapse(animated: Bool = true) {
    guard isExpanded else { return }
    isExpanded = false
    removeBackdrop()

    for (index, item) in secondaryItems.reversed().enumerated() {
      let glassView = item.glassView
      let settle = {
        glassView.transform = CGAffineTransform(scaleX: 0.01, y: 0.01)
        glassView.alpha = 0
      }
      if animated {
        let delay = Double(index) * 0.03
        UIView.animate(
          withDuration: 0.3, delay: delay,
          usingSpringWithDamping: 0.85, initialSpringVelocity: 0,
          animations: settle,
          completion: { [weak self] _ in self?.parkInBar(glassView) }
        )
      } else {
        settle()
        parkInBar(glassView)
      }
    }

    UIView.animate(withDuration: animated ? 0.3 : 0) {
      self.fabButton.transform = .identity
    }
  }

  private func collapse() {
    collapse(animated: true)
  }

  @available(*, unavailable)
  required init?(coder _: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var intrinsicContentSize: CGSize {
    guard density.hugsContentHorizontally else {
      return CGSize(width: UIView.noIntrinsicMetric, height: density.barHeight)
    }

    let segmentedWidth = preferredCompactSegmentWidths.isEmpty
      ? (0..<segmentedControl.numberOfSegments).reduce(CGFloat.zero) {
          $0 + segmentedControl.widthForSegment(at: $1)
        }
      : preferredCompactSegmentWidths.reduce(0, +)
    return CGSize(
      width: ceil(segmentedWidth)
        + contentPadding * 2
        + spacing
        + density.barHeight,
      height: density.barHeight
    )
  }

  override func layoutSubviews() {
    updateCompactSegmentSizingForCurrentBounds()
    super.layoutSubviews()

    // Capsule shape for segmented control
    segmentedGlassView.cornerConfiguration = .capsule()

    // Circle shape for FAB button (capsule with equal width/height = circle)
    fabGlassView.cornerConfiguration = .capsule()

    // The expanded pills live in the window at an anchor captured at expand
    // time. Collapse if a resize, density change, or ancestor layout moves or
    // resizes the FAB within the same window.
    guard isExpanded, let window else { return }
    let currentFABFrame = fabGlassView.convert(fabGlassView.bounds, to: window)
    if window.bounds != expandedWindowBounds
      || bounds != expandedBarBounds
      || currentFABFrame != expandedFABFrame
    {
      collapse(animated: false)
    }
  }

  /// Keeps every tab and the FAB inside the locally proposed width. The
  /// reference inline labels remain visible whenever their intrinsic widths
  /// fit; at narrower widths the labels collapse together and the tabs share
  /// the remaining space instead of clipping or overflowing.
  private func updateCompactSegmentSizingForCurrentBounds() {
    guard density.hugsContentHorizontally,
          bounds.width > 0,
          preferredCompactSegmentWidths.count == segmentedControl.numberOfSegments,
          !preferredCompactSegmentWidths.isEmpty else {
      if isCompactContentCollapsed {
        isCompactContentCollapsed = false
        segmentedControl.setInlineTitlesVisible(true)
      }
      return
    }

    let fixedChromeWidth = contentPadding * 2 + spacing + bounds.height
    let availableSegmentWidth = max(0, bounds.width - fixedChromeWidth)
    let preferredWidth = preferredCompactSegmentWidths.reduce(0, +)
    let shouldCollapse = availableSegmentWidth + 0.5 < preferredWidth
    let appliedWidths: [CGFloat]
    if shouldCollapse {
      let equalWidth = availableSegmentWidth / CGFloat(preferredCompactSegmentWidths.count)
      appliedWidths = Array(
        repeating: equalWidth,
        count: preferredCompactSegmentWidths.count
      )
    } else {
      appliedWidths = preferredCompactSegmentWidths
    }

    for (index, width) in appliedWidths.enumerated()
      where abs(segmentedControl.widthForSegment(at: index) - width) > 0.5
    {
      segmentedControl.setWidth(width, forSegmentAt: index)
    }

    if isCompactContentCollapsed != shouldCollapse {
      isCompactContentCollapsed = shouldCollapse
      segmentedControl.setInlineTitlesVisible(!shouldCollapse)
      segmentedControl.setNeedsLayout()
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil {
      prepareForRemoval()
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
