import UIKit

@available(iOS 26.0, *)
struct FabBarTabDescriptor: Equatable {
  let title: String
  let image: UIImage?
  let accessibilityIdentifier: String?
}

/// One stable selection model hosts the original native segmented control
/// horizontally and the adaptive button rail vertically.
@available(iOS 26.0, *)
final class FabBarTabControl: UIControl, UIGestureRecognizerDelegate {
  private let stack = UIStackView()
  private let selectionView: UIVisualEffectView
  let horizontalControl = TabBarSegmentedControl(items: [])
  private var horizontalBaseViews: [TabItemContentView] = []
  private var horizontalAccentViews: [TabItemContentView] = []
  private(set) var buttons: [UIButton] = []
  let navigationMenuButton = UIButton(type: .system)
  private(set) var tabs: [FabBarTabDescriptor] = []
  var onReselect: ((Int) -> Void)?
  private var dragOriginalIndex: Int?
  private var lastTitleVisibility: Bool?

  var selectedSegmentIndex: Int = 0 {
    didSet {
      guard oldValue != selectedSegmentIndex else { return }
      updateSelection(animated: true)
    }
  }
  var activeTintColor: UIColor = .tintColor {
    didSet {
      guard oldValue != activeTintColor else { return }
      updateButtonConfigurations()
      updateSelection(animated: false)
    }
  }
  var isVertical = false {
    didSet {
      guard oldValue != isVertical else { return }
      let hadFocus = containsNavigationFocus
      cancelSelectionDrag()
      horizontalControl.cancelInteraction()
      dismissNavigationMenu()
      updateButtonConfigurations()
      updateRendererVisibility()
      updateSelection(animated: false)
      setNeedsLayout()
      if hadFocus { UIAccessibility.post(notification: .layoutChanged, argument: selectedAccessibilityTarget) }
    }
  }
  var isCollapsed = false {
    didSet {
      guard oldValue != isCollapsed else { return }
      let hadNavigationFocus = containsNavigationFocus
      cancelSelectionDrag()
      horizontalControl.cancelInteraction()
      dismissNavigationMenu()
      updateRendererVisibility()
      updateSelection(animated: false)
      setNeedsLayout()
      if hadNavigationFocus {
        UIAccessibility.post(notification: .layoutChanged, argument: selectedAccessibilityTarget)
      }
    }
  }
  var numberOfSegments: Int { tabs.count }

  override var semanticContentAttribute: UISemanticContentAttribute {
    didSet { if oldValue != semanticContentAttribute { setNeedsLayout() } }
  }

  override init(frame: CGRect) {
    let glass = UIGlassEffect()
    glass.isInteractive = true
    glass.tintColor = UIColor.label.withAlphaComponent(0.10)
    selectionView = UIVisualEffectView(effect: glass)
    super.init(frame: frame)
    isAccessibilityElement = false
    accessibilityTraits = .tabBar
    accessibilityIdentifier = "FabBar.navigation"
    selectionView.isUserInteractionEnabled = false
    selectionView.cornerConfiguration = .capsule()
    addSubview(selectionView)
    horizontalControl.accessibilityIdentifier = "FabBar.horizontalNavigation"
    horizontalControl.showsLargeContentViewer = false
    horizontalControl.addTarget(self, action: #selector(horizontalSelectionChanged(_:)), for: .valueChanged)
    horizontalControl.onAccessibilityActivate = { [weak self] index in
      guard let self, !self.isVertical, !self.isCollapsed else { return }
      self.activateTab(at: index)
    }
    horizontalControl.onReselect = { [weak self] index in
      guard let self, !self.isVertical, !self.isCollapsed, self.tabs.indices.contains(index) else { return }
      self.onReselect?(index)
    }
    addSubview(horizontalControl)
    stack.axis = .vertical
    stack.distribution = .fillEqually
    stack.spacing = 0
    addSubview(stack)
    navigationMenuButton.showsMenuAsPrimaryAction = true
    navigationMenuButton.isHidden = true
    navigationMenuButton.accessibilityIdentifier = "FabBar.navigationMenu"
    navigationMenuButton.showsLargeContentViewer = true
    addSubview(navigationMenuButton)
    addInteraction(UILargeContentViewerInteraction())
    let selectionDrag = UIPanGestureRecognizer(target: self, action: #selector(selectionDragged(_:)))
    selectionDrag.maximumNumberOfTouches = 1
    selectionDrag.delegate = self
    addGestureRecognizer(selectionDrag)
    updateRendererVisibility()
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitLayoutDirection.self, UITraitUserInterfaceStyle.self]) {
      (view: FabBarTabControl, _: UITraitCollection) in
      view.updateButtonConfigurations()
      view.setNeedsLayout()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  func setTabs(_ newTabs: [FabBarTabDescriptor], replacingIdentity: Bool = false) {
    guard replacingIdentity || newTabs != tabs else { return }
    cancelSelectionDrag()
    horizontalControl.cancelInteraction()
    dismissNavigationMenu()
    let hadNavigationFocus = containsNavigationFocus
    let focusedIdentifier = buttons.first { $0.accessibilityElementIsFocused() }?.accessibilityIdentifier
    tabs = newTabs
    let rebuildsButtons = replacingIdentity || buttons.count != newTabs.count
    if rebuildsButtons {
      for button in buttons { stack.removeArrangedSubview(button); button.removeFromSuperview() }
      buttons = newTabs.indices.map { index in
        let button = UIButton(type: .system)
        button.showsLargeContentViewer = true
        button.scalesLargeContentImage = true
        button.addAction(UIAction { [weak self] _ in self?.activateTab(at: index) }, for: .touchUpInside)
        stack.addArrangedSubview(button)
        return button
      }
    }
    let rebuildsSegments = replacingIdentity || horizontalControl.numberOfSegments != newTabs.count
    if rebuildsSegments {
      horizontalControl.removeAllSegments()
      for index in newTabs.indices {
        horizontalControl.insertSegment(with: UIImage(systemName: "circle"), at: index, animated: false)
      }
      horizontalBaseViews = newTabs.map { TabItemContentView(title: $0.title, image: $0.image) }
      horizontalAccentViews = newTabs.map { TabItemContentView(title: $0.title, image: $0.image) }
      horizontalControl.configureContentViews(horizontalBaseViews, accentViews: horizontalAccentViews)
    }
    updateButtonConfigurations()
    updateRendererVisibility()
    updateSelection(animated: false)
    setNeedsLayout()
    if (rebuildsButtons || rebuildsSegments), hadNavigationFocus {
      let replacement: Any? = isCollapsed ? navigationMenuButton : isVertical
        ? buttons.first { $0.accessibilityIdentifier == focusedIdentifier } : selectedAccessibilityTarget
      UIAccessibility.post(notification: .layoutChanged, argument: replacement)
    }
  }

  func activateTab(at index: Int) {
    guard tabs.indices.contains(index) else { return }
    if selectedSegmentIndex == index {
      onReselect?(index)
      return
    }
    selectedSegmentIndex = index
    sendActions(for: .valueChanged)
  }

  private func updateButtonConfigurations() {
    let hidesTitles = shouldHideTitles
    lastTitleVisibility = hidesTitles
    for (index, button) in buttons.enumerated() where tabs.indices.contains(index) {
      let tab = tabs[index]
      // The glass selection surface supplies feedback without a second tinted fill.
      var configuration = UIButton.Configuration.plain()
      configuration.automaticallyUpdateForSelection = false
      configuration.background.backgroundColor = .clear
      configuration.image = tab.image
      configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
        pointSize: Constants.tabIconPointSize, weight: .medium)
      configuration.imagePlacement = .top
      configuration.imagePadding = 2
      configuration.contentInsets = .zero
      if !hidesTitles {
        var title = AttributedString(tab.title)
        title.font = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
        configuration.attributedTitle = title
      }
      configuration.baseForegroundColor = index == selectedSegmentIndex ? activeTintColor : .label
      button.configuration = configuration
      button.accessibilityLabel = tab.title
      button.accessibilityIdentifier = tab.accessibilityIdentifier ?? "FabBar.tab.\(index)"
      button.largeContentTitle = tab.title
      button.largeContentImage = tab.image
    }
    updateHorizontalContent(hidesTitles: hidesTitles)
    updateNavigationMenu()
  }

  private var shouldHideTitles: Bool {
    guard !isVertical, !traitCollection.preferredContentSizeCategory.isAccessibilityCategory else { return true }
    guard !tabs.isEmpty, bounds.width > 0 else { return false }
    let font = UIFont.systemFont(ofSize: Constants.tabTitleFontSize, weight: .semibold)
    let availableWidth = bounds.width / CGFloat(tabs.count) - 8
    let availableHeight = bounds.height - 1
    return Constants.iconViewSize + font.lineHeight > availableHeight || tabs.contains {
      ($0.title as NSString).size(withAttributes: [.font: font]).width > availableWidth
    }
  }

  private func updateHorizontalContent(hidesTitles: Bool) {
    horizontalControl.activeTintColor = activeTintColor
    horizontalControl.selectedSegmentTintColor = UIColor.label.withAlphaComponent(
      traitCollection.userInterfaceStyle == .dark ? 0.15 : 0.08)
    horizontalControl.segmentAccessibilityIdentifiers = tabs.enumerated().map {
      $0.element.accessibilityIdentifier ?? "FabBar.tab.\($0.offset)"
    }
    for (index, tab) in tabs.enumerated() where horizontalBaseViews.indices.contains(index) {
      if horizontalControl.titleForSegment(at: index) != tab.title {
        horizontalControl.setTitle(tab.title, forSegmentAt: index)
      }
      let width = tabs.count < 3 ? Constants.fewTabsSegmentWidth : 0
      if horizontalControl.widthForSegment(at: index) != width {
        horizontalControl.setWidth(width, forSegmentAt: index)
      }
      horizontalBaseViews[index].update(title: tab.title, image: tab.image, showsTitle: !hidesTitles)
      horizontalAccentViews[index].update(title: tab.title, image: tab.image, showsTitle: !hidesTitles)
    }
    horizontalControl.setNeedsLayout()
  }

  @objc private func horizontalSelectionChanged(_ control: UISegmentedControl) {
    guard !isVertical, !isCollapsed, tabs.indices.contains(control.selectedSegmentIndex),
          control.selectedSegmentIndex != selectedSegmentIndex else { return }
    selectedSegmentIndex = control.selectedSegmentIndex
    sendActions(for: .valueChanged)
  }

  private func updateRendererVisibility() {
    horizontalControl.isHidden = isVertical || isCollapsed
    horizontalControl.accessibilityElementsHidden = horizontalControl.isHidden
    horizontalControl.isRendererActive = !horizontalControl.isHidden && window != nil
    stack.isHidden = !isVertical || isCollapsed
    stack.accessibilityElementsHidden = stack.isHidden
    navigationMenuButton.isHidden = !isCollapsed
    navigationMenuButton.accessibilityElementsHidden = !isCollapsed
    selectionView.isHidden = !isVertical && !isCollapsed
    if isCollapsed {
      accessibilityElements = [navigationMenuButton]
    } else if isVertical {
      accessibilityElements = buttons
    } else {
      // Preserve UIKit's native per-segment accessibility container.
      accessibilityElements = nil
    }
  }

  private var containsNavigationFocus: Bool {
    func containsFocus(_ view: UIView) -> Bool {
      view.accessibilityElementIsFocused() || view.subviews.contains(where: containsFocus)
    }
    return containsFocus(self) || (horizontalControl.accessibilityElements?.contains {
      ($0 as? UIAccessibilityElement)?.accessibilityElementIsFocused() == true
    } ?? false)
  }

  private var selectedAccessibilityTarget: Any? {
    if isCollapsed { return navigationMenuButton }
    guard tabs.indices.contains(selectedSegmentIndex) else { return nil }
    if isVertical { return buttons[selectedSegmentIndex] }
    if let element = horizontalControl.accessibilityElement(at: selectedSegmentIndex) { return element }
    let identifier = tabs[selectedSegmentIndex].accessibilityIdentifier ?? "FabBar.tab.\(selectedSegmentIndex)"
    func find(_ view: UIView) -> UIView? {
      if view.accessibilityIdentifier == identifier { return view }
      return view.subviews.lazy.compactMap { find($0) }.first
    }
    return find(horizontalControl) ?? horizontalControl
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    updateRendererVisibility()
  }

  /// Dismisses only this button's native chooser, never a host presentation.
  func dismissNavigationMenu() {
    for interaction in navigationMenuButton.interactions {
      (interaction as? UIContextMenuInteraction)?.dismissMenu()
      (interaction as? UIEditMenuInteraction)?.dismissMenu()
    }
  }

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard isVertical, !isCollapsed, !traitCollection.preferredContentSizeCategory.isAccessibilityCategory,
          let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
    let translation = pan.translation(in: self)
    return abs(translation.y) > abs(translation.x)
  }

  @objc private func selectionDragged(_ recognizer: UIPanGestureRecognizer) {
    processSelectionDrag(at: recognizer.location(in: self), state: recognizer.state)
  }

  /// Preview locally while dragging; navigation receives a single committed
  /// selection at release, matching the previous segmented-control behavior.
  func processSelectionDrag(at point: CGPoint, state: UIGestureRecognizer.State) {
    guard isVertical, !isCollapsed, !buttons.isEmpty else { cancelSelectionDrag(); return }
    switch state {
    case .began:
      dragOriginalIndex = selectedSegmentIndex
      selectedSegmentIndex = nearestTabIndex(to: point)
    case .changed:
      guard dragOriginalIndex != nil else { return }
      selectedSegmentIndex = nearestTabIndex(to: point)
    case .ended:
      guard let original = dragOriginalIndex else { return }
      selectedSegmentIndex = nearestTabIndex(to: point)
      dragOriginalIndex = nil
      if original == selectedSegmentIndex { onReselect?(selectedSegmentIndex) }
      else { sendActions(for: .valueChanged) }
    case .cancelled, .failed:
      cancelSelectionDrag()
    default: break
    }
  }

  private func nearestTabIndex(to point: CGPoint) -> Int {
    buttons.indices.min { lhs, rhs in
      let first = buttons[lhs].convert(buttons[lhs].bounds, to: self)
      let second = buttons[rhs].convert(buttons[rhs].bounds, to: self)
      return isVertical ? abs(first.midY - point.y) < abs(second.midY - point.y)
        : abs(first.midX - point.x) < abs(second.midX - point.x)
    } ?? selectedSegmentIndex
  }

  private func cancelSelectionDrag() {
    guard let original = dragOriginalIndex else { return }
    dragOriginalIndex = nil
    selectedSegmentIndex = original
  }

  private func updateNavigationMenu() {
    guard tabs.indices.contains(selectedSegmentIndex) else {
      navigationMenuButton.menu = nil
      return
    }
    let selected = tabs[selectedSegmentIndex]
    var configuration = UIButton.Configuration.plain()
    configuration.automaticallyUpdateForSelection = false
    configuration.background.backgroundColor = .clear
    configuration.image = selected.image
    configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
      pointSize: Constants.tabIconPointSize, weight: .medium)
    configuration.baseForegroundColor = activeTintColor
    configuration.contentInsets = .zero
    navigationMenuButton.configuration = configuration
    navigationMenuButton.accessibilityLabel = selected.title
    navigationMenuButton.accessibilityTraits = [.button, .selected]
    navigationMenuButton.largeContentTitle = selected.title
    navigationMenuButton.largeContentImage = selected.image
    navigationMenuButton.menu = UIMenu(children: tabs.enumerated().map { index, tab in
      UIAction(title: tab.title, image: tab.image,
        state: index == selectedSegmentIndex ? .on : .off) { [weak self] _ in
          self?.activateTab(at: index)
        }
    })
  }

  private func updateSelection(animated: Bool) {
    for (index, button) in buttons.enumerated() {
      button.isSelected = index == selectedSegmentIndex
      button.accessibilityTraits = index == selectedSegmentIndex ? [.button, .selected] : [.button]
      button.configuration?.baseForegroundColor = index == selectedSegmentIndex ? activeTintColor : .label
    }
    let nativeSelection = tabs.indices.contains(selectedSegmentIndex) ? selectedSegmentIndex : UISegmentedControl.noSegment
    if horizontalControl.selectedSegmentIndex != nativeSelection {
      horizontalControl.selectedSegmentIndex = nativeSelection
    }
    updateNavigationMenu()
    updateRendererVisibility()
    layoutIfNeeded()
    guard isVertical || isCollapsed else { return }
    let target: CGRect
    if isCollapsed {
      target = bounds
    } else if buttons.indices.contains(selectedSegmentIndex) {
      target = buttons[selectedSegmentIndex].convert(buttons[selectedSegmentIndex].bounds, to: self)
    } else {
      selectionView.isHidden = true
      return
    }
    selectionView.isHidden = false
    if animated && !UIAccessibility.isReduceMotionEnabled && window != nil {
      UIView.animate(withDuration: 0.24, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
        self.selectionView.frame = target
      }
    } else {
      selectionView.frame = target
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if lastTitleVisibility != shouldHideTitles { updateButtonConfigurations() }
    stack.semanticContentAttribute = effectiveUserInterfaceLayoutDirection == .rightToLeft
      ? .forceRightToLeft : .forceLeftToRight
    horizontalControl.semanticContentAttribute = stack.semanticContentAttribute
    horizontalControl.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - 1))
    horizontalControl.setNeedsLayout()
    horizontalControl.layoutIfNeeded()
    stack.frame = bounds
    navigationMenuButton.frame = bounds
    stack.layoutIfNeeded()
    let target = isCollapsed ? bounds
      : buttons.indices.contains(selectedSegmentIndex)
        ? buttons[selectedSegmentIndex].convert(buttons[selectedSegmentIndex].bounds, to: self)
        : .zero
    selectionView.frame = target
  }
}
