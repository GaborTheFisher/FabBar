import UIKit

/// Stable, public UIKit buttons provide the same selection model on both axes.
/// No UISegmentedControl subview inspection is needed for glass or accessibility.
@available(iOS 26.0, *)
struct FabBarTabDescriptor: Equatable {
  let title: String
  let image: UIImage?
  let accessibilityIdentifier: String?
}

@available(iOS 26.0, *)
final class FabBarTabControl: UIControl, UIGestureRecognizerDelegate {
  private let stack = UIStackView()
  private let selectionView: UIVisualEffectView
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
      cancelSelectionDrag()
      dismissNavigationMenu()
      stack.axis = isVertical ? .vertical : .horizontal
      updateButtonConfigurations()
      setNeedsLayout()
    }
  }
  var isCollapsed = false {
    didSet {
      guard oldValue != isCollapsed else { return }
      cancelSelectionDrag()
      dismissNavigationMenu()
      let hadNavigationFocus = buttons.contains { $0.accessibilityElementIsFocused() }
        || navigationMenuButton.accessibilityElementIsFocused()
      stack.isHidden = isCollapsed
      navigationMenuButton.isHidden = !isCollapsed
      updateSelection(animated: false)
      setNeedsLayout()
      if hadNavigationFocus {
        UIAccessibility.post(notification: .layoutChanged, argument: isCollapsed
          ? navigationMenuButton
          : buttons.indices.contains(selectedSegmentIndex) ? buttons[selectedSegmentIndex] : nil)
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
    stack.axis = .horizontal
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
    registerForTraitChanges([UITraitPreferredContentSizeCategory.self, UITraitLayoutDirection.self]) {
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
    dismissNavigationMenu()
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
    updateButtonConfigurations()
    updateSelection(animated: false)
    setNeedsLayout()
    if rebuildsButtons, let focusedIdentifier {
      let replacement = isCollapsed ? navigationMenuButton
        : buttons.first { $0.accessibilityIdentifier == focusedIdentifier }
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
    updateNavigationMenu()
  }

  private var shouldHideTitles: Bool {
    guard !isVertical, !traitCollection.preferredContentSizeCategory.isAccessibilityCategory else { return true }
    guard !tabs.isEmpty, bounds.width > 0 else { return false }
    let font = UIFont.preferredFont(forTextStyle: .caption2, compatibleWith: traitCollection)
    let availableWidth = bounds.width / CGFloat(tabs.count) - 8
    let availableHeight = bounds.height - Constants.tabIconPointSize - 2 - 4
    return font.lineHeight > availableHeight || tabs.contains {
      ($0.title as NSString).size(withAttributes: [.font: font]).width > availableWidth
    }
  }

  /// Dismisses only this button's native chooser, never a host presentation.
  func dismissNavigationMenu() {
    for interaction in navigationMenuButton.interactions {
      (interaction as? UIContextMenuInteraction)?.dismissMenu()
      (interaction as? UIEditMenuInteraction)?.dismissMenu()
    }
  }

  override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
    guard !isCollapsed, !traitCollection.preferredContentSizeCategory.isAccessibilityCategory,
          let pan = gestureRecognizer as? UIPanGestureRecognizer else { return false }
    let translation = pan.translation(in: self)
    return isVertical ? abs(translation.y) > abs(translation.x) : abs(translation.x) > abs(translation.y)
  }

  @objc private func selectionDragged(_ recognizer: UIPanGestureRecognizer) {
    processSelectionDrag(at: recognizer.location(in: self), state: recognizer.state)
  }

  /// Preview locally while dragging; navigation receives a single committed
  /// selection at release, matching the previous segmented-control behavior.
  func processSelectionDrag(at point: CGPoint, state: UIGestureRecognizer.State) {
    guard !isCollapsed, !buttons.isEmpty else { cancelSelectionDrag(); return }
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
    updateNavigationMenu()
    layoutIfNeeded()
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
    accessibilityElements = isCollapsed ? [navigationMenuButton] : buttons
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    if lastTitleVisibility != shouldHideTitles { updateButtonConfigurations() }
    stack.semanticContentAttribute = effectiveUserInterfaceLayoutDirection == .rightToLeft
      ? .forceRightToLeft : .forceLeftToRight
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
