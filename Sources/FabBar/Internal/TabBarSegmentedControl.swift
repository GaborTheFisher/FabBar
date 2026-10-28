import UIKit

/// A UISegmentedControl subclass customized for use as a tab bar replacement.
///
/// This subclass provides four key customizations:
///
/// 1. **Injected segment content**: Replaces the default segment labels with custom `TabItemContentView`
///    instances injected directly into each segment's view subtree. These views render via `draw(_:)` at
///    the current graphics context scale and support `NSCoding`, so the system accessibility popover
///    (which archives/unarchives segment content) gets crisp rendering at its native resolution.
///
/// 2. **Immediate glass effect on touch down**: By default, UISegmentedControl only shows
///    the interactive glass hover effect when dragging from the currently selected segment.
///    This subclass overrides touch handling to move the indicator immediately on touch down,
///    which triggers the glass effect animation for any segment tap—matching the behavior
///    of UITabBar. The actual selection change is deferred until touch up via `sendActions(for:)`.
///
/// 3. **Accent masking**: Tracks the glass indicator's animated position via `CADisplayLink`
///    and masks accent-colored content views to the indicator rect, so content under the glass
///    appears in the accent color — matching native UITabBar behavior.
///
/// 4. **Reselection callback**: Notifies when user taps an already-selected segment.
@available(iOS 26.0, *)
final class TabBarSegmentedControl: UISegmentedControl {
  /// The segment index before touch began, used to restore on cancel and detect actual changes.
  private var originalIndex: Int?
  private var isDeferringNativeActions = false
  private var ignoresRemainingTouchSequence = false
  private var accessibilitySegments: [TabBarSegmentAccessibilityElement] = []
  private var accessibilitySegmentIdentities: [String] = []

  /// Tag used to identify injected content views within segments.
  private static let injectedViewTag = 7_777
  /// Tag used to identify accent (active-colored) content views within segments.
  private static let accentViewTag = 7_778

  /// Stored tab content views to inject into segments (always inactive color).
  private var contentViews: [TabItemContentView] = []
  /// Accent-colored duplicates, masked to the glass indicator position.
  private var accentContentViews: [TabItemContentView] = []
  private var inlineTitlesVisible = true

  /// Display link for updating accent masks each frame.
  private var displayLink: CADisplayLink?
  /// Weak proxy to avoid CADisplayLink retain cycle.
  private var displayLinkProxy: DisplayLinkProxy?

  /// Tracks indicator position stability for display link pausing.
  private var lastIndicatorRect: CGRect = .zero
  private var stableFrameCount: Int = 0
  private static let stableFrameThreshold = 3

  /// Whether the segment-frame fallback log has already been emitted.
  private var didLogFallback = false

  /// Cached reference to the internal glass indicator view. Invalidated on segment rebuild.
  private weak var cachedIndicatorView: UIView?

  /// Tint color for the selected/highlighted tab's content view.
  /// Set to a concrete color (not the dynamic `.tintColor`) to avoid auto-dimming during sheet presentation.
  var activeTintColor: UIColor = .tintColor {
    didSet { updateContentViewColors() }
  }

  /// Tint color for unselected tab content views.
  var inactiveTintColor: UIColor = .label {
    didSet { updateContentViewColors() }
  }

  /// Called when user taps the already-selected segment.
  var onReselect: ((Int) -> Void)?

  /// Routes assistive activation through the same logical selection owner as
  /// the vertical renderer, without adding a view over UIKit's glass control.
  var onAccessibilityActivate: ((Int) -> Void)?

  /// Stable identifiers belong to logical segment values, including in RTL.
  var segmentAccessibilityIdentifiers: [String?] = [] {
    didSet {
      updateSegmentAccessibility()
      setNeedsLayout()
    }
  }

  /// The wrapper keeps this control mounted across axis changes. A hidden
  /// horizontal renderer must not keep its display link or a pending gesture.
  var isRendererActive = true {
    didSet {
      guard oldValue != isRendererActive else { return }
      if isRendererActive {
        setNeedsLayout()
        wakeAccentMasks()
      } else {
        cancelInteraction()
        stopDisplayLink()
      }
    }
  }

  override var isAccessibilityElement: Bool {
    get { false }
    set {}
  }

  override func accessibilityElementCount() -> Int {
    accessibilitySegments.count
  }

  override func accessibilityElement(at index: Int) -> Any? {
    accessibilitySegments.indices.contains(index) ? accessibilitySegments[index] : nil
  }

  override func index(ofAccessibilityElement element: Any) -> Int {
    guard let segment = element as? TabBarSegmentAccessibilityElement else { return NSNotFound }
    return accessibilitySegments.firstIndex { $0 === segment } ?? NSNotFound
  }

  override var selectedSegmentIndex: Int {
    didSet {
      if oldValue != selectedSegmentIndex {
        updateSegmentAccessibility()
        wakeAccentMasks()
      }
    }
  }

  /// Cancel a finger-down preview without committing navigation when the
  /// surrounding layout or descriptor identity changes.
  func cancelInteraction() {
    let pendingIndex = originalIndex
    if originalIndex != nil || isDeferringNativeActions {
      ignoresRemainingTouchSequence = true
    }
    originalIndex = nil
    isDeferringNativeActions = true
    cancelTracking(with: nil)
    if let pendingIndex { selectedSegmentIndex = pendingIndex }
    isDeferringNativeActions = false
    wakeAccentMasks()
  }

  override init(items: [Any]?) {
    super.init(items: items)
    // The outer wrapper supplies tab-bar grouping. Keep the native control
    // a container so its individual segments retain their accessibility.
    isAccessibilityElement = false
    registerForTraitChanges([UITraitLayoutDirection.self, UITraitPreferredContentSizeCategory.self]) {
      (view: TabBarSegmentedControl, _: UITraitCollection) in
      view.cancelInteraction()
      view.setNeedsLayout()
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    wakeAccentMasks()
    hideSegmentBackgrounds()
    hideDefaultLabels()
    updateSegmentAccessibility()
    injectContentViewsIfNeeded()
    updateContentViewColors()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if window != nil && isRendererActive {
      startDisplayLink()
    } else {
      stopDisplayLink()
    }
  }

  override func didAddSubview(_ subview: UIView) {
    super.didAddSubview(subview)
    // UISegmentedControl may recreate labels on layout; hide them immediately.
    hideLabelsRecursively(in: subview)
  }

  // MARK: - Content View Injection

  /// Configures the tab content views to be injected into each segment's view subtree.
  /// Base views are always inactive-colored; accent views are always active-colored and
  /// masked to the glass indicator position.
  func configureContentViews(_ baseViews: [TabItemContentView], accentViews: [TabItemContentView]) {
    cachedIndicatorView = nil
    // This entry point accompanies a logical segment rebuild. Ordinary title,
    // image, tint, geometry and axis changes retain their accessibility objects.
    accessibilitySegments = []
    accessibilitySegmentIdentities = []
    accessibilityElements = []

    // Remove previously injected views from segment subtrees.
    // Uses tag-based lookup so this works even if segments were rebuilt
    // (the old tagged views will have been removed with their parent segments).
    for segmentView in findSegmentViews() {
      segmentView.viewWithTag(Self.injectedViewTag)?.removeFromSuperview()
      segmentView.viewWithTag(Self.accentViewTag)?.removeFromSuperview()
    }
    contentViews = baseViews
    accentContentViews = accentViews
    for view in contentViews + accentContentViews {
      view.setShowsInlineTitle(inlineTitlesVisible)
    }
    setNeedsLayout()
  }

  func setInlineTitlesVisible(_ areVisible: Bool) {
    guard inlineTitlesVisible != areVisible else { return }
    inlineTitlesVisible = areVisible
    for view in contentViews + accentContentViews {
      view.setShowsInlineTitle(areVisible)
    }
    setNeedsLayout()
  }

  var areInlineTitlesVisible: Bool {
    inlineTitlesVisible && contentViews.allSatisfy(\.showsInlineTitle)
  }

  /// Finds each internal segment view and injects base + accent `TabItemContentView`s as subviews.
  private func injectContentViewsIfNeeded() {
    let segmentViews = findSegmentViews()
    guard segmentViews.count == contentViews.count,
          segmentViews.count == accentContentViews.count,
          bounds.width > 0, bounds.height > 0,
          segmentViews.allSatisfy({ $0.bounds.width > 0 && $0.bounds.height > 0 }) else { return }

    // UIKit can first materialize its segments with unresolved positions and
    // later reorder them during layout or RTL changes. Reconcile identity,
    // not just the presence of a tagged child, before attaching this layout.
    for (index, segmentView) in segmentViews.enumerated() {
      if let existing = segmentView.viewWithTag(Self.injectedViewTag), existing !== contentViews[index] {
        existing.removeFromSuperview()
      }
      if let existing = segmentView.viewWithTag(Self.accentViewTag), existing !== accentContentViews[index] {
        existing.removeFromSuperview()
      }
    }

    for (index, segmentView) in segmentViews.enumerated() {
      if segmentAccessibilityIdentifiers.indices.contains(index) {
        segmentView.accessibilityIdentifier = segmentAccessibilityIdentifiers[index]
      }
      let contentView = contentViews[index]
      if contentView.superview !== segmentView {
        contentView.tag = Self.injectedViewTag
        contentView.translatesAutoresizingMaskIntoConstraints = false
        segmentView.addSubview(contentView)
        NSLayoutConstraint.activate([
          contentView.centerXAnchor.constraint(equalTo: segmentView.centerXAnchor),
          contentView.centerYAnchor.constraint(equalTo: segmentView.centerYAnchor),
        ])
      }
      updateContentSizeConstraints(for: contentView, inside: segmentView)

      let accentView = accentContentViews[index]
      if accentView.superview !== segmentView {
        accentView.tag = Self.accentViewTag
        accentView.translatesAutoresizingMaskIntoConstraints = false
        segmentView.addSubview(accentView)
        NSLayoutConstraint.activate([
          accentView.centerXAnchor.constraint(equalTo: segmentView.centerXAnchor),
          accentView.centerYAnchor.constraint(equalTo: segmentView.centerYAnchor),
        ])
        let maskLayer = CAShapeLayer()
        maskLayer.path = UIBezierPath(rect: .zero).cgPath
        accentView.layer.mask = maskLayer
      }
      updateContentSizeConstraints(for: accentView, inside: segmentView)
    }
  }

  /// Text, image and label-fit changes reuse the injected views. Refresh the
  /// original explicit size constraints instead of leaving their first size.
  private func updateContentSizeConstraints(for view: TabItemContentView, inside segment: UIView) {
    let size = view.intrinsicContentSize
    let width = view.constraints.first { $0.identifier == "FabBar.content.width" }
      ?? view.widthAnchor.constraint(equalToConstant: size.width)
    let height = view.constraints.first { $0.identifier == "FabBar.content.height" }
      ?? view.heightAnchor.constraint(equalToConstant: size.height)
    width.identifier = "FabBar.content.width"
    height.identifier = "FabBar.content.height"
    width.constant = size.width
    width.priority = .defaultHigh
    height.constant = size.height
    NSLayoutConstraint.activate([width, height])
    if !segment.constraints.contains(where: { $0.identifier == "FabBar.content.maximumWidth" && $0.firstItem === view }) {
      let maximumWidth = view.widthAnchor.constraint(lessThanOrEqualTo: segment.widthAnchor)
      maximumWidth.identifier = "FabBar.content.maximumWidth"
      maximumWidth.isActive = true
    }
  }

  // MARK: - Content View Colors

  /// Sets base content views to inactive color and accent content views to active color.
  /// The visual accent effect is handled by masking accent views to the glass indicator.
  private func updateContentViewColors() {
    for contentView in contentViews {
      contentView.tintColor = inactiveTintColor
    }
    for accentView in accentContentViews {
      accentView.tintColor = activeTintColor
    }
  }

  // MARK: - Segment Discovery

  /// Recursively finds the internal UISegment views within the control's hierarchy.
  /// In iOS 26, segments are nested several levels deep inside container views.
  private func findSegmentViews() -> [UIView] {
    var segments: [UIView] = []
    findSegments(in: self, results: &segments)
    let physicalOrder = segments.sorted {
      $0.convert($0.bounds, to: self).midX < $1.convert($1.bounds, to: self).midX
    }
    return effectiveUserInterfaceLayoutDirection == .rightToLeft
      ? Array(physicalOrder.reversed()) : physicalOrder
  }

  func segmentFramesInControlCoordinates() -> [CGRect] {
    findSegmentViews().map { $0.convert($0.bounds, to: self) }
  }

  /// UIKit's segment views stay the hit targets and rendering owners. The
  /// nonvisual elements supply supported activation and stable logical focus;
  /// their frames always come from the corresponding real native segment.
  private func updateSegmentAccessibility() {
    let segments = findSegmentViews()
    guard segments.count == numberOfSegments else { return }
    let identities = segments.indices.map { index in
      (segmentAccessibilityIdentifiers.indices.contains(index)
        ? segmentAccessibilityIdentifiers[index] : nil) ?? "FabBar.tab.\(index)"
    }
    if identities != accessibilitySegmentIdentities || accessibilitySegments.count != segments.count {
      accessibilitySegmentIdentities = identities
      accessibilitySegments = segments.indices.map {
        TabBarSegmentAccessibilityElement(control: self, segmentIndex: $0)
      }
    }
    for (index, segment) in segments.enumerated() {
      let label = titleForSegment(at: index)
      let traits: UIAccessibilityTraits = index == selectedSegmentIndex ? [.button, .selected] : [.button]
      // Keep native metadata for UIKit's large-content popover and diagnostics;
      // expose only the activatable element to avoid duplicate announcements.
      segment.isAccessibilityElement = false
      segment.accessibilityElementsHidden = false
      segment.accessibilityLabel = label
      segment.accessibilityValue = nil
      segment.accessibilityIdentifier = identities[index]
      segment.accessibilityTraits = traits
      let element = accessibilitySegments[index]
      element.segmentView = segment
      element.accessibilityLabel = label
      element.accessibilityValue = nil
      element.accessibilityIdentifier = identities[index]
      element.accessibilityTraits = traits
    }
    accessibilityElements = accessibilitySegments
  }

  fileprivate func activateAccessibilitySegment(at index: Int) -> Bool {
    guard isRendererActive, !isHidden, !accessibilityElementsHidden, isEnabled,
          (0..<numberOfSegments).contains(index), isEnabledForSegment(at: index) else { return false }
    cancelInteraction()
    if let onAccessibilityActivate {
      onAccessibilityActivate(index)
    } else if selectedSegmentIndex == index {
      onReselect?(index)
    } else {
      selectedSegmentIndex = index
      sendActions(for: .valueChanged)
    }
    return true
  }

  private func findSegments(in view: UIView, results: inout [UIView]) {
    for subview in view.subviews {
      if String(describing: type(of: subview)) == "UISegment" {
        results.append(subview)
      } else {
        findSegments(in: subview, results: &results)
      }
    }
  }

  // MARK: - Label Hiding

  /// Hides all default UILabels recursively within the segmented control.
  /// Skips labels inside our injected content views (identified by parent tag).
  private func hideDefaultLabels() {
    hideLabelsRecursively(in: self)
  }

  private func hideLabelsRecursively(in view: UIView) {
    if let label = view as? UILabel,
       label.superview?.tag != Self.injectedViewTag,
       label.superview?.tag != Self.accentViewTag {
      label.isHidden = true
    }
    for subview in view.subviews {
      hideLabelsRecursively(in: subview)
    }
  }

  // MARK: - Background Image Hiding

  /// Hides all segment background and separator images.
  ///
  /// UISegmentedControl uses UIImageView subviews for backgrounds, separators,
  /// and selection indicators. We hide all of them because:
  /// - The glass effect comes from UIGlassEffect on the parent view, not from these images
  /// - Segmented control comes with a default background tint which we don't want to mimic the standard tab bar appearance
  private func hideSegmentBackgrounds() {
    for subview in subviews where subview is UIImageView {
      subview.alpha = 0
    }
  }

  // MARK: - Indicator Tracking & Accent Masking

  private func wakeAccentMasks() {
    guard isRendererActive, window != nil else { return }
    startDisplayLink()
    displayLink?.isPaused = false
    stableFrameCount = 0
  }

  private func startDisplayLink() {
    guard displayLink == nil else { return }
    let proxy = DisplayLinkProxy(control: self)
    displayLinkProxy = proxy
    displayLink = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.handleDisplayLink))
    displayLink?.add(to: .main, forMode: .common)
  }

  private func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
    displayLinkProxy = nil
  }

  /// Finds the glass indicator view within the segmented control's internal hierarchy.
  ///
  /// Primary: finds by class name. Fallback: finds the sibling of the segments container
  /// that has subviews. The indicator has child subviews (glass rendering stack),
  /// while DestOutView is a leaf.
  private func findIndicatorView() -> UIView? {
    // Primary: class name lookup
    if let found = findDescendant(named: "_UILiquidLensView") {
      return found
    }

    // Fallback: find the sibling of the segments container that has subviews.
    // The indicator, segments container, and DestOutView share a parent wrapper.
    // The indicator has subviews (glass rendering stack); DestOutView is a leaf.
    let segments = findSegmentViews()
    guard let segmentsContainer = segments.first?.superview,
          let wrapper = segmentsContainer.superview else { return nil }

    return wrapper.subviews.first { sibling in
      sibling !== segmentsContainer && !sibling.subviews.isEmpty
    }
  }

  private func findDescendant(named className: String) -> UIView? {
    func search(in view: UIView) -> UIView? {
      for subview in view.subviews {
        if String(describing: type(of: subview)) == className {
          return subview
        }
        if let found = search(in: subview) {
          return found
        }
      }
      return nil
    }
    return search(in: self)
  }

  /// Returns the indicator rect by tracking the internal glass indicator view's presentation layer,
  /// or falls back to the selected segment's frame if the indicator view can't be found.
  private func currentIndicatorRect() -> CGRect {
    // Try to use the cached/found indicator view for smooth animation tracking
    if cachedIndicatorView == nil {
      cachedIndicatorView = findIndicatorView()
    }
    if let indicatorView = cachedIndicatorView {
      // Stay in the presentation layer tree for both sides of the conversion
      let presLayer = indicatorView.layer.presentation() ?? indicatorView.layer
      let selfPresLayer = self.layer.presentation() ?? self.layer
      return selfPresLayer.convert(presLayer.bounds, from: presLayer)
    }

    // Fallback: use the selected segment's frame (no animation, but always correct)
    if !didLogFallback {
      fabBarLogger.warning("Glass indicator view not found — accent masking will snap without animation. Internal UISegmentedControl hierarchy may have changed.")
      didLogFallback = true
    }
    let segments = findSegmentViews()
    if selectedSegmentIndex >= 0, selectedSegmentIndex < segments.count {
      return segments[selectedSegmentIndex].convert(segments[selectedSegmentIndex].bounds, to: self)
    }
    return .zero
  }

  /// Called each frame to update accent view masks based on the glass indicator's animated position.
  fileprivate func updateAccentMasks() {
    let indicatorRect = currentIndicatorRect()

    // Pause display link when indicator is stationary to save power
    if indicatorRect == lastIndicatorRect {
      stableFrameCount += 1
      if stableFrameCount >= Self.stableFrameThreshold {
        displayLink?.isPaused = true
        return
      }
    } else {
      stableFrameCount = 0
      lastIndicatorRect = indicatorRect
    }

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    for (index, accentView) in accentContentViews.enumerated() {
      let baseView = contentViews[index]
      updateMasks(base: baseView, accent: accentView, indicatorRect: indicatorRect)
    }

    CATransaction.commit()
  }

  private func updateMasks(base baseView: TabItemContentView, accent accentView: TabItemContentView, indicatorRect: CGRect) {
    // Use presentation layers for consistency with indicatorRect
    let accentPres = accentView.layer.presentation() ?? accentView.layer
    let selfPres = self.layer.presentation() ?? self.layer
    let viewRectInControl = selfPres.convert(accentPres.bounds, from: accentPres)

    // Convert the indicator rect into the content view's local coordinate space.
    // Using the full capsule path (not a rect intersection) ensures rounded
    // corners are preserved even when the indicator partially overlaps.
    let localIndicator = CGRect(
      x: indicatorRect.origin.x - viewRectInControl.origin.x,
      y: indicatorRect.origin.y - viewRectInControl.origin.y,
      width: indicatorRect.width,
      height: indicatorRect.height
    )
    let cornerRadius = indicatorRect.height / 2
    let capsulePath = UIBezierPath(roundedRect: localIndicator, cornerRadius: cornerRadius)

    let accentMask = accentView.layer.mask as? CAShapeLayer ?? {
      let m = CAShapeLayer()
      accentView.layer.mask = m
      return m
    }()

    // Accent: show only inside the indicator capsule
    accentMask.path = capsulePath.cgPath

    // Base: cut out the indicator capsule using even-odd fill
    if indicatorRect.intersects(viewRectInControl) {
      let baseMask = baseView.layer.mask as? CAShapeLayer ?? {
        let m = CAShapeLayer()
        baseView.layer.mask = m
        return m
      }()
      let basePath = UIBezierPath(rect: baseView.bounds)
      basePath.append(capsulePath)
      baseMask.fillRule = .evenOdd
      baseMask.path = basePath.cgPath
    } else {
      baseView.layer.mask = nil
    }
  }

  // MARK: - Touch Handling

  func segmentIndex(at point: CGPoint) -> Int {
    guard numberOfSegments > 0 else { return 0 }
    let frames = segmentFramesInControlCoordinates()
    if frames.count == numberOfSegments {
      // Inline segments have different widths. A nearest-center-only test
      // switches a wide segment too early near its narrow neighbor.
      if let index = frames.firstIndex(where: { point.x >= $0.minX && point.x <= $0.maxX }) {
        return index
      }
      if let nearest = frames.indices.min(by: {
        abs(frames[$0].midX - point.x) < abs(frames[$1].midX - point.x)
      }) {
        return nearest
      }
    }
    guard bounds.width > 0 else { return 0 }
    let segmentWidth = bounds.width / CGFloat(numberOfSegments)
    let physicalIndex = min(max(Int(point.x / segmentWidth), 0), numberOfSegments - 1)
    return effectiveUserInterfaceLayoutDirection == .rightToLeft
      ? numberOfSegments - 1 - physicalIndex : physicalIndex
  }

  /// Whether to override `selectedSegmentIndex` on touch down for immediate glass indicator movement.
  /// Disabled for accessibility content sizes because it interferes with the segment popover behavior.
  private var shouldMoveIndicatorOnTouchDown: Bool {
    !traitCollection.preferredContentSizeCategory.isAccessibilityCategory
  }

  /// Native target dispatch is deferred only while the immediate-lens touch
  /// preview is active. The final native selection emits one value change.
  /// Accessibility and ordinary programmatic control events retain UIKit's path.
  override func sendAction(_ action: Selector, to target: Any?, for event: UIEvent?) {
    guard !isDeferringNativeActions else { return }
    super.sendAction(action, to: target, for: event)
  }

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
    ignoresRemainingTouchSequence = false
    guard isRendererActive, let touch = touches.first else {
      super.touchesBegan(touches, with: event)
      return
    }
    wakeAccentMasks()
    if shouldMoveIndicatorOnTouchDown {
      originalIndex = selectedSegmentIndex
      isDeferringNativeActions = true
      selectedSegmentIndex = segmentIndex(at: touch.location(in: self))
    }
    super.touchesBegan(touches, with: event)
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard !ignoresRemainingTouchSequence else { return }
    guard let touch = touches.first else {
      super.touchesMoved(touches, with: event)
      return
    }
    wakeAccentMasks()
    if shouldMoveIndicatorOnTouchDown, originalIndex != nil {
      selectedSegmentIndex = segmentIndex(at: touch.location(in: self))
    }
    super.touchesMoved(touches, with: event)
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
    guard !ignoresRemainingTouchSequence else {
      ignoresRemainingTouchSequence = false
      return
    }
    wakeAccentMasks()
    guard let startingIndex = originalIndex, isDeferringNativeActions else {
      super.touchesEnded(touches, with: event)
      return
    }
    // Let UIKit finish its lens interaction while suppressing its target
    // callbacks, then commit the resulting value exactly once.
    super.touchesEnded(touches, with: event)
    originalIndex = nil
    isDeferringNativeActions = false
    if selectedSegmentIndex != startingIndex {
      sendActions(for: .valueChanged)
    } else {
      onReselect?(selectedSegmentIndex)
    }
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
    wakeAccentMasks()
    let startingIndex = originalIndex
    super.touchesCancelled(touches, with: event)
    if let startingIndex { selectedSegmentIndex = startingIndex }
    originalIndex = nil
    isDeferringNativeActions = false
    ignoresRemainingTouchSequence = false
  }

}

/// Accessibility-only representation of a real UIKit segment. It draws
/// nothing and leaves the native control's touch handling and glass untouched.
@available(iOS 26.0, *)
@MainActor
private final class TabBarSegmentAccessibilityElement: UIAccessibilityElement {
  private weak var control: TabBarSegmentedControl?
  weak var segmentView: UIView?
  private let segmentIndex: Int

  init(control: TabBarSegmentedControl, segmentIndex: Int) {
    self.control = control
    self.segmentIndex = segmentIndex
    super.init(accessibilityContainer: control)
    isAccessibilityElement = true
  }

  override var accessibilityFrame: CGRect {
    get {
      guard let segmentView else { return .zero }
      return UIAccessibility.convertToScreenCoordinates(segmentView.bounds, in: segmentView)
    }
    set {}
  }

  override var accessibilityFrameInContainerSpace: CGRect {
    get {
      guard let control, let segmentView else { return .zero }
      return segmentView.convert(segmentView.bounds, to: control)
    }
    set {}
  }

  override func accessibilityActivate() -> Bool {
    control?.activateAccessibilitySegment(at: segmentIndex) ?? false
  }
}

/// Weak-reference proxy that prevents `CADisplayLink` from retaining the segmented control.
@available(iOS 26.0, *)
@MainActor
private final class DisplayLinkProxy: NSObject {
  weak var control: TabBarSegmentedControl?

  init(control: TabBarSegmentedControl) {
    self.control = control
  }

  @objc func handleDisplayLink(_ link: CADisplayLink) {
    guard let control else {
      link.invalidate()
      return
    }
    control.updateAccentMasks()
  }
}
