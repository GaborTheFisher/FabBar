import UIKit

/// One stable glass surface with separate destination and primary-action groups.
@available(iOS 26.0, *)
final class GlassTabBarView: UIView {
  let containerEffectView: UIVisualEffectView
  let segmentedGlassView: UIVisualEffectView
  let segmentedControl: FabBarTabControl
  let fabGlassView: UIVisualEffectView
  let fabButton = UIButton(type: .system)

  private(set) var tabCount: Int
  private(set) var placement: FabBarPlacement = .bottom
  private var density: FabBarDensity = .regular
  private var maximumLength: CGFloat?
  private var primaryAction: () -> Void
  private var isSecondaryActionMenuEnabled: Bool
  private var primaryCustomView: UIView?
  private var primaryCustomViewController: UIViewController?
  private var secondaryActions: [FabBarAction]
  private var secondaryItems: [SecondaryItem] = []
  private var backdropView: UIView?
  private var menuScrollView: UIScrollView?
  private(set) var isExpanded = false
  private(set) var secondaryMenuFrame: CGRect = .zero
  var secondaryButtons: [UIButton] { secondaryItems.map(\.button) }

  private struct SecondaryItem {
    let glassView: UIVisualEffectView
    let button: UIButton
    let customView: UIView?
  }
  private var expandedWindowBounds: CGRect = .zero
  private var expandedWindowSafeArea: UIEdgeInsets = .zero
  private var expandedBarBounds: CGRect = .zero
  private var expandedFABFrame: CGRect = .zero
  private var lastLayoutBounds: CGRect = .zero
  private var lastFABInWindow: CGRect = .zero
  private let notificationObservers = FabBarNotificationObservers()

  override var semanticContentAttribute: UISemanticContentAttribute {
    didSet { if oldValue != semanticContentAttribute { setNeedsLayout() } }
  }

  init(
    segmentedControl: FabBarTabControl,
    tabCount: Int,
    action: FabBarAction,
    secondaryActions: [FabBarAction],
    isSecondaryActionMenuEnabled: Bool
  ) {
    self.segmentedControl = segmentedControl
    self.tabCount = tabCount
    self.primaryAction = action.action
    self.secondaryActions = secondaryActions
    self.isSecondaryActionMenuEnabled = isSecondaryActionMenuEnabled

    let containerEffect = UIGlassContainerEffect()
    containerEffect.spacing = Constants.fabSpacing
    containerEffectView = UIVisualEffectView(effect: containerEffect)
    let navigationGlass = UIGlassEffect()
    navigationGlass.isInteractive = true
    segmentedGlassView = UIVisualEffectView(effect: navigationGlass)
    let actionGlass = UIGlassEffect()
    actionGlass.isInteractive = true
    actionGlass.tintColor = .tintColor
    fabGlassView = UIVisualEffectView(effect: actionGlass)
    super.init(frame: .zero)

    isAccessibilityElement = false
    clipsToBounds = false
    tintAdjustmentMode = .automatic
    addSubview(containerEffectView)
    containerEffectView.contentView.addSubview(segmentedGlassView)
    segmentedGlassView.contentView.addSubview(segmentedControl)
    containerEffectView.contentView.addSubview(fabGlassView)
    fabGlassView.contentView.addSubview(fabButton)
    segmentedGlassView.cornerConfiguration = .capsule()
    fabGlassView.cornerConfiguration = .capsule()
    fabButton.accessibilityTraits = .button
    fabButton.accessibilityIdentifier = "FabBar.primaryAction"
    fabButton.showsLargeContentViewer = true
    fabButton.scalesLargeContentImage = true
    fabButton.addAction(UIAction { [weak self] _ in self?.primaryButtonTapped() }, for: .touchUpInside)
    addInteraction(UILargeContentViewerInteraction())
    configurePrimaryContent(action)
    rebuildSecondaryItems()

    for name in [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                 UIScene.willDeactivateNotification, UIResponder.keyboardWillChangeFrameNotification] {
      notificationObservers.tokens.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] notification in
        let scene = notification.object as? UIScene
        Task { @MainActor [weak self, weak scene] in
          guard let self else { return }
          if let scene, let windowScene = self.window?.windowScene,
             scene !== windowScene { return }
          self.collapseSecondaryActions()
        }
      })
    }
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitLayoutDirection.self]) {
      (view: GlassTabBarView, _: UITraitCollection) in
      view.collapseSecondaryActions()
      view.setNeedsLayout()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func updateLayout(placement: FabBarPlacement, density: FabBarDensity, maximumLength: CGFloat?) {
    let resolvedPlacement: FabBarPlacement = placement == .automatic ? .bottom : placement
    if self.placement != resolvedPlacement || self.density != density || self.maximumLength != maximumLength {
      collapseSecondaryActions()
      self.placement = resolvedPlacement
      self.density = density
      self.maximumLength = maximumLength
      segmentedControl.isVertical = resolvedPlacement.isVertical
      setNeedsLayout()
    }
  }

  func updateTabCount(_ count: Int) {
    if tabCount != count {
      collapseSecondaryActions()
      tabCount = count
      setNeedsLayout()
    }
  }

  func updatePrimaryAction(_ action: @escaping () -> Void, isSecondaryActionMenuEnabled: Bool) {
    primaryAction = action
    if self.isSecondaryActionMenuEnabled != isSecondaryActionMenuEnabled {
      self.isSecondaryActionMenuEnabled = isSecondaryActionMenuEnabled
      if !isSecondaryActionMenuEnabled { collapse(animated: false) }
    }
  }

  func updateAction(_ action: FabBarAction, secondaryActions: [FabBarAction], isSecondaryActionMenuEnabled: Bool) {
    updatePrimaryAction(action.action, isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled)
    configurePrimaryContent(action)
    let changed = self.secondaryActions.count != secondaryActions.count
      || zip(self.secondaryActions, secondaryActions).contains { lhs, rhs in
        lhs.systemImage != rhs.systemImage || lhs.accessibilityLabel != rhs.accessibilityLabel
          || lhs.customView !== rhs.customView
      }
    self.secondaryActions = secondaryActions
    if changed {
      collapse(animated: false)
      rebuildSecondaryItems()
    }
  }

  private func configurePrimaryContent(_ action: FabBarAction) {
    primaryCustomViewController = action.customView
    let customView = action.customView?.view
    // A retained hosting controller can hand its view to a replacement bar
    // during resizing. Reclaim it on update even when its identity is stable.
    if primaryCustomView !== customView || (customView != nil && customView?.superview !== fabButton) {
      if primaryCustomView?.superview === fabButton {
        primaryCustomView?.removeFromSuperview()
      }
      primaryCustomView = customView
      if let customView {
        customView.backgroundColor = .clear
        customView.isUserInteractionEnabled = false
        fabButton.addSubview(customView)
      }
    }
    let symbol = UIImage(systemName: action.systemImage,
      withConfiguration: UIImage.SymbolConfiguration(pointSize: Constants.fabIconPointSize, weight: .medium))
    fabButton.setImage(customView == nil ? symbol : nil, for: .normal)
    fabButton.tintColor = .white
    fabButton.accessibilityLabel = action.accessibilityLabel
    fabButton.largeContentTitle = action.accessibilityLabel
    fabButton.largeContentImage = symbol
    setNeedsLayout()
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    containerEffectView.frame = bounds
    let thickness = max(44, placement.isVertical ? bounds.width : bounds.height)
    let gap = Constants.fabSpacing
    let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
    let navigationFrame: CGRect
    if placement.isVertical {
      let actionY = max(0, bounds.height - thickness)
      fabGlassView.frame = CGRect(x: 0, y: actionY, width: bounds.width, height: thickness)
      let available = max(0, actionY - gap)
      segmentedControl.isCollapsed = available + 1 < FabBarLayoutPolicy.navigationVerticalLength(tabCount: tabCount)
      navigationFrame = CGRect(x: 0, y: 0, width: bounds.width, height: available)
    } else {
      let fabX = isRTL ? 0 : max(0, bounds.width - thickness)
      fabGlassView.frame = CGRect(x: fabX, y: 0, width: thickness, height: bounds.height)
      let available = max(0, bounds.width - thickness - gap)
      let width = tabCount < 3
        ? min(available, CGFloat(tabCount) * Constants.fewTabsSegmentWidth + Constants.contentPadding * 2)
        : available
      segmentedControl.isCollapsed = width < CGFloat(tabCount) * 44
      navigationFrame = CGRect(x: isRTL ? bounds.width - width : 0,
        y: 0, width: width, height: bounds.height)
    }
    segmentedGlassView.frame = navigationFrame
    segmentedControl.frame = segmentedGlassView.bounds.insetBy(
      dx: Constants.contentPadding,
      dy: placement.isVertical && !segmentedControl.isCollapsed
        ? Constants.verticalContentPadding : Constants.contentPadding)
    segmentedControl.setNeedsLayout()
    segmentedControl.layoutIfNeeded()
    fabButton.frame = fabGlassView.bounds
    primaryCustomView?.frame = fabButton.bounds
    for item in secondaryItems where item.glassView.superview === self {
      item.glassView.frame = fabGlassView.frame
    }

    guard let window else { return }
    let frame = fabGlassView.convert(fabGlassView.bounds, to: window)
    if !lastLayoutBounds.isEmpty, bounds != lastLayoutBounds || frame != lastFABInWindow {
      segmentedControl.dismissNavigationMenu()
    }
    lastLayoutBounds = bounds
    lastFABInWindow = frame
    guard isExpanded else { return }
    if window.bounds != expandedWindowBounds || window.safeAreaInsets != expandedWindowSafeArea
      || bounds != expandedBarBounds || frame != expandedFABFrame {
      collapse(animated: false)
    }
  }

  override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
    // Transparent spacing belongs to the underlying scrollable content.
    segmentedGlassView.frame.contains(point) || fabGlassView.frame.contains(point)
  }

  private func rebuildSecondaryItems() {
    for item in secondaryItems { item.glassView.removeFromSuperview() }
    secondaryItems = secondaryActions.enumerated().map { index, action in
      let effect = UIGlassEffect()
      effect.isInteractive = true
      let glass = UIVisualEffectView(effect: effect)
      glass.cornerConfiguration = .capsule()
      let button = UIButton(type: .system)
      let custom = action.customView?.view
      if let custom {
        custom.backgroundColor = .clear
        custom.isUserInteractionEnabled = false
        button.addSubview(custom)
      }
      glass.contentView.addSubview(button)
      button.accessibilityLabel = action.accessibilityLabel
      button.accessibilityIdentifier = "FabBar.secondaryAction.\(index)"
      button.accessibilityTraits = .button
      button.showsLargeContentViewer = true
      button.largeContentTitle = action.accessibilityLabel
      button.addAction(UIAction { [weak self] _ in
        guard let self, self.secondaryActions.indices.contains(index) else { return }
        let action = self.secondaryActions[index].action
        self.collapse(animated: false)
        action()
      }, for: .touchUpInside)
      let item = SecondaryItem(glassView: glass, button: button, customView: custom)
      park(item)
      return item
    }
  }

  private func park(_ item: SecondaryItem) {
    insertSubview(item.glassView, belowSubview: containerEffectView)
    item.glassView.frame = fabGlassView.frame
    item.button.frame = item.glassView.bounds
    item.customView?.frame = item.button.bounds
    item.glassView.isHidden = true
    item.glassView.isUserInteractionEnabled = false
  }

  private func primaryButtonTapped() {
    primaryAction()
    guard isSecondaryActionMenuEnabled, !secondaryItems.isEmpty else {
      collapse(animated: false)
      return
    }
    if isExpanded { collapse(animated: true) } else { expand() }
  }

  private func secondarySize(_ item: SecondaryItem, action: FabBarAction, maximumWidth: CGFloat, thickness: CGFloat) -> CGSize {
    let largeText = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
    var configuration = UIButton.Configuration.plain()
    configuration.baseForegroundColor = .label
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12)
    if largeText || item.customView == nil {
      configuration.image = UIImage(systemName: action.systemImage,
        withConfiguration: UIImage.SymbolConfiguration(pointSize: Constants.fabIconPointSize, weight: .medium))
      if largeText {
        var title = AttributedString(action.accessibilityLabel)
        title.font = UIFont.preferredFont(forTextStyle: .body, compatibleWith: traitCollection)
        configuration.attributedTitle = title
        configuration.titleLineBreakMode = .byWordWrapping
        configuration.titleAlignment = .center
      }
    }
    item.button.configuration = configuration
    item.customView?.isHidden = largeText
    if largeText {
      item.button.titleLabel?.numberOfLines = 0
      item.button.titleLabel?.preferredMaxLayoutWidth = max(0, maximumWidth - 24)
      let fitted = item.button.sizeThatFits(CGSize(width: maximumWidth, height: .greatestFiniteMagnitude))
      return CGSize(width: maximumWidth, height: max(44, fitted.height))
    }
    if let custom = item.customView {
      custom.bounds.size = CGSize(width: max(0, maximumWidth - 24), height: thickness)
      custom.setNeedsLayout()
      custom.layoutIfNeeded()
      let proposal = CGSize(width: max(0, maximumWidth - 24), height: CGFloat.greatestFiniteMagnitude)
      let fitting = action.customViewSizeThatFits?(proposal)
        ?? custom.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
      let width = fitting.width.isFinite && fitting.width > 0 ? min(maximumWidth, ceil(fitting.width) + 24) : maximumWidth
      let contentWidth = max(0, width - 24)
      let height = action.customViewSizeThatFits?(CGSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)).height
        ?? custom.systemLayoutSizeFitting(CGSize(width: contentWidth, height: 0),
          withHorizontalFittingPriority: .required, verticalFittingPriority: .fittingSizeLevel).height
      return CGSize(width: max(44, width), height: max(thickness, height.isFinite ? ceil(height) + 16 : thickness))
    }
    return CGSize(width: thickness, height: thickness)
  }

  private func expand() {
    guard !isExpanded, !secondaryItems.isEmpty, let window else { return }
    layoutIfNeeded()
    var safe = window.safeAreaLayoutGuide.layoutFrame.insetBy(dx: 12, dy: 12)
    let keyboard = window.keyboardLayoutGuide.layoutFrame
    if keyboard.height > 0, keyboard.minY < safe.maxY,
       keyboard.maxX > safe.minX, keyboard.minX < safe.maxX {
      safe.size.height = max(0, min(safe.maxY, keyboard.minY - 12) - safe.minY)
    }
    guard safe.width >= 44, safe.height >= 44 else { return }
    let fab = fabGlassView.convert(fabGlassView.bounds, to: window)
    let barIsRight = fab.midX >= window.bounds.midX
    let sideSpace = barIsRight ? fab.minX - safe.minX - 12 : safe.maxX - fab.maxX - 12
    let maximumWidth = placement.isVertical
      ? min(safe.width, max(44, sideSpace))
      : safe.width
    let sizes = zip(secondaryItems, secondaryActions).map {
      secondarySize($0.0, action: $0.1, maximumWidth: maximumWidth, thickness: max(44, fab.height))
    }
    let width = min(safe.width, sizes.map(\.width).max() ?? 44)
    let contentHeight = sizes.reduce(CGFloat(0)) { $0 + $1.height }
      + CGFloat(max(0, sizes.count - 1)) * 12
    let availableHeight = placement.isVertical ? safe.height : max(44, fab.minY - safe.minY - 12)
    let height = min(safe.height, availableHeight, contentHeight)
    let x: CGFloat
    if placement.isVertical {
      x = barIsRight ? max(safe.minX, fab.minX - 12 - width) : min(safe.maxX - width, fab.maxX + 12)
    } else {
      let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
      x = min(max(isRTL ? fab.minX : fab.maxX - width, safe.minX), safe.maxX - width)
    }
    let y = min(max(fab.minY - 12 - height, safe.minY), safe.maxY - height)
    secondaryMenuFrame = CGRect(x: x, y: y, width: width, height: height)
    expandedWindowBounds = window.bounds
    expandedWindowSafeArea = window.safeAreaInsets
    expandedBarBounds = bounds
    expandedFABFrame = fab
    isExpanded = true

    let backdrop = UIView(frame: window.bounds)
    backdrop.backgroundColor = .clear
    backdrop.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backdropTapped)))
    window.addSubview(backdrop)
    backdropView = backdrop
    let scroll = FabBarSecondaryMenuScrollView(frame: secondaryMenuFrame)
    scroll.onEscape = { [weak self] in self?.collapse(animated: true) }
    scroll.backgroundColor = .clear
    scroll.contentInsetAdjustmentBehavior = .never
    scroll.showsVerticalScrollIndicator = contentHeight > height
    scroll.accessibilityIdentifier = "FabBar.secondaryMenu"
    scroll.accessibilityViewIsModal = true
    scroll.shouldGroupAccessibilityChildren = true
    scroll.addInteraction(UILargeContentViewerInteraction())
    window.addSubview(scroll)
    menuScrollView = scroll
    var top: CGFloat = 0
    for (item, size) in zip(secondaryItems, sizes) {
      scroll.addSubview(item.glassView)
      item.glassView.frame = CGRect(x: width - size.width, y: top, width: size.width, height: size.height)
      item.button.frame = item.glassView.bounds
      item.customView?.frame = item.button.bounds.insetBy(dx: 12, dy: 8)
      item.glassView.isHidden = false
      item.glassView.isUserInteractionEnabled = true
      top += size.height + 12
    }
    scroll.contentSize = CGSize(width: width, height: contentHeight)
    let duration = UIAccessibility.isReduceMotionEnabled ? 0 : 0.2
    scroll.alpha = 0
    UIView.animate(withDuration: duration, delay: 0,
      options: [.allowUserInteraction, .beginFromCurrentState]) {
      scroll.alpha = 1
      self.fabButton.transform = CGAffineTransform(rotationAngle: .pi / 4)
    }
    if UIAccessibility.isVoiceOverRunning {
      UIAccessibility.post(notification: .layoutChanged, argument: secondaryItems.first?.button)
    }
  }

  @objc private func backdropTapped() { collapse(animated: true) }

  func collapseSecondaryActions() {
    segmentedControl.dismissNavigationMenu()
    collapse(animated: true)
  }

  func prepareForRemoval() {
    segmentedControl.dismissNavigationMenu()
    collapse(animated: false)
  }

  private func collapse(animated: Bool) {
    guard isExpanded else { return }
    let restoresPrimaryFocus = secondaryItems.contains { $0.button.accessibilityElementIsFocused() }
    isExpanded = false
    backdropView?.removeFromSuperview()
    backdropView = nil
    let scroll = menuScrollView
    menuScrollView = nil
    // Remove all hit regions synchronously; fading never leaves an invisible
    // backdrop in front of the app or a previous window.
    scroll?.isUserInteractionEnabled = false
    for item in secondaryItems { park(item) }
    scroll?.removeFromSuperview()
    secondaryMenuFrame = .zero
    let duration = animated && !UIAccessibility.isReduceMotionEnabled ? 0.16 : 0
    UIView.animate(withDuration: duration) { self.fabButton.transform = .identity }
    if restoresPrimaryFocus, window != nil {
      UIAccessibility.post(notification: .layoutChanged, argument: fabButton)
    }
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window == nil { prepareForRemoval() }
  }

  override func tintColorDidChange() {
    super.tintColorDidChange()
    segmentedControl.activeTintColor = tintColor
    let effect = UIGlassEffect()
    effect.isInteractive = true
    effect.tintColor = tintColor
    fabGlassView.effect = effect
  }
}

/// The modal menu must provide the standard VoiceOver cancellation route.
@available(iOS 26.0, *)
private final class FabBarSecondaryMenuScrollView: UIScrollView {
  var onEscape: (() -> Void)?

  override func accessibilityPerformEscape() -> Bool {
    guard let onEscape else { return super.accessibilityPerformEscape() }
    onEscape()
    return true
  }
}

/// Tokens are installed on the main actor. NotificationCenter permits removal
/// from the deinitializing thread, after this owner has no remaining references.
private final class FabBarNotificationObservers: @unchecked Sendable {
  var tokens: [NSObjectProtocol] = []
  deinit {
    for token in tokens { NotificationCenter.default.removeObserver(token) }
  }
}
