import UIKit
import XCTest
@testable import FabBar

@MainActor
@available(iOS 26.0, *)
final class FabBarTabControlTests: XCTestCase {
  func testActiveRenderersForwardOneSelectionAndReselectionOnBothAxes() {
    for vertical in [false, true] {
      let subject = makeSubject()
      layout(subject, vertical: vertical)
      var selected: [Int] = []
      var reselected: [Int] = []
      subject.addAction(UIAction { _ in selected.append(subject.selectedSegmentIndex) }, for: .valueChanged)
      subject.onReselect = { reselected.append($0) }

      if vertical {
        subject.buttons[2].sendActions(for: .touchUpInside)
        subject.buttons[2].sendActions(for: .touchUpInside)
      } else {
        // Exercise the native child's forwarding, rather than a hidden vertical
        // button. Physical tap/reselect handling has separate app UI coverage.
        subject.horizontalControl.selectedSegmentIndex = 2
        dispatchNativeValueChanged(subject.horizontalControl)
        subject.horizontalControl.onReselect?(2)
      }

      XCTAssertEqual(selected, [2])
      XCTAssertEqual(reselected, [2])
      XCTAssertEqual(subject.selectedSegmentIndex, 2)
      XCTAssertEqual(subject.horizontalControl.selectedSegmentIndex, 2)
      XCTAssertTrue(subject.buttons[2].isSelected)
      XCTAssertTrue(subject.buttons[2].accessibilityTraits.contains(.selected))
      XCTAssertFalse(subject.buttons[0].accessibilityTraits.contains(.selected))
      XCTAssertEqual(subject.buttons.map(\.accessibilityIdentifier), ["tab.0", "tab.1", "tab.2", "tab.3"])
      XCTAssertTrue(subject.accessibilityTraits.contains(.tabBar))
      assertActiveRenderer(subject, vertical: vertical)
    }
  }

  func testHorizontalRendererUsesNativeSegmentsAndNeutralSelectionOnBothAppearances() throws {
    let subject = makeSubject()
    let native = subject.horizontalControl
    XCTAssertTrue(subject.subviews.contains { $0 is UISegmentedControl && $0 === native })
    XCTAssertEqual(native.accessibilityIdentifier, "FabBar.horizontalNavigation")
    XCTAssertEqual(native.numberOfSegments, 4)
    XCTAssertEqual((0..<4).map { native.titleForSegment(at: $0) }, makeTabs().map(\.title))
    let window = try XCTUnwrap(subject.window)

    for style in [UIUserInterfaceStyle.light, .dark] {
      window.traitOverrides.userInterfaceStyle = style
      subject.activeTintColor = .systemOrange
      subject.selectedSegmentIndex = 1
      layout(subject, vertical: false)
      let expected = UIColor.label.withAlphaComponent(style == .dark ? 0.15 : 0.08)
        .resolvedColor(with: native.traitCollection)
      XCTAssertEqual(native.selectedSegmentTintColor?.resolvedColor(with: native.traitCollection), expected)
      XCTAssertEqual(native.activeTintColor, .systemOrange)
      XCTAssertEqual(native.selectedSegmentIndex, 1)
      assertActiveRenderer(subject, vertical: false)
    }
  }

  func testNativeSegmentAccessibilityActivationSelectsAndReselectsOnce() throws {
    let subject = makeSubject()
    let native = subject.horizontalControl
    var changes: [Int] = []
    var reselects: [Int] = []
    subject.addAction(UIAction { _ in changes.append(subject.selectedSegmentIndex) }, for: .valueChanged)
    subject.onReselect = { reselects.append($0) }
    let elements = try XCTUnwrap(native.accessibilityElements as? [NSObject])
    XCTAssertEqual(elements.count, 4)
    let precision = try XCTUnwrap(elements.first { accessibilityIdentifier(of: $0) == "tab.1" })

    XCTAssertTrue(precision.accessibilityActivate(), "A native segment exposed to VoiceOver must support activation")
    XCTAssertEqual(subject.selectedSegmentIndex, 1)
    XCTAssertEqual(native.selectedSegmentIndex, 1)
    XCTAssertEqual(changes, [1])
    XCTAssertTrue(precision.accessibilityActivate())
    XCTAssertEqual(changes, [1])
    XCTAssertEqual(reselects, [1])
  }

  func testZeroSizeConfigurationKeepsDrawnTitlesInsideTheirLogicalNativeSegments() throws {
    let titles = ["Home", "Explore", "Profile"]
    let descriptors = titles.enumerated().map { index, title in
      FabBarTabDescriptor(title: title, image: UIImage(systemName: "circle"),
        accessibilityIdentifier: "mapping.tab.\(index)")
    }
    // Configuration can cause native segment creation before geometry exists.
    // Later reordering must move the content itself, not just its segment ID.
    let subject = FabBarTabControl(frame: .zero)
    subject.setTabs(descriptors)
    subject.setNeedsLayout()
    subject.layoutIfNeeded()
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.addSubview(subject)
    window.isHidden = false
    defer { window.isHidden = true; subject.removeFromSuperview() }

    for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
      subject.semanticContentAttribute = direction
      for roundTrip in [false, true] {
        if roundTrip { layout(subject, vertical: true) }
        layout(subject, vertical: false, size: CGSize(width: 360, height: 58))
        let native = subject.horizontalControl
        XCTAssertEqual(native.numberOfSegments, titles.count)
        var logicalCenters: [CGFloat] = []
        for (index, title) in titles.enumerated() {
          let segment = try XCTUnwrap(descendant(withIdentifier: "mapping.tab.\(index)", in: native))
          let content = contentViews(in: segment)
          XCTAssertEqual(content.count, 2, "Each native segment needs its base and accent content")
          XCTAssertEqual(try content.map { try archivedTitle($0) }, [title, title],
            "Native logical segment \(index) contains another destination's drawn title: \(direction), round trip \(roundTrip)")
          XCTAssertTrue(content.allSatisfy { $0.intrinsicContentSize.height > Constants.iconViewSize })
          XCTAssertEqual(native.titleForSegment(at: index), title)
          assertReceivesTouches(segment, in: window, routedThrough: native)
          logicalCenters.append(segment.convert(segment.bounds, to: native).midX)
        }
        XCTAssertEqual(logicalCenters, logicalCenters.sorted { direction == .forceRightToLeft ? $0 > $1 : $0 < $1 },
          "Drawn content must follow logical native segment order")
        XCTAssertEqual(subject.selectedSegmentIndex, 0)
        XCTAssertEqual(native.selectedSegmentIndex, 0)
        assertActiveRenderer(subject, vertical: false)
      }
    }
  }

  func testAxisAndPresentationUpdatesPreserveRendererAndContentIdentityWithoutCallbacks() {
    let subject = makeSubject()
    subject.selectedSegmentIndex = 2
    let native = subject.horizontalControl
    let buttons = subject.buttons.map(ObjectIdentifier.init)
    let content = contentViews(in: native)
    XCTAssertEqual(content.count, 8, "Both native content layers must be mounted for every segment")
    let contentIdentities = Set(content.map(ObjectIdentifier.init))
    var changes = 0
    var reselects = 0
    subject.addAction(UIAction { _ in changes += 1 }, for: .valueChanged)
    subject.onReselect = { _ in reselects += 1 }

    for vertical in [true, false, true, false] {
      layout(subject, vertical: vertical)
      subject.activeTintColor = vertical ? .systemPurple : .systemOrange
      subject.setTabs(makeTabs(prefix: "Updated"))
      subject.layoutIfNeeded()
      native.layoutIfNeeded()

      XCTAssertTrue(subject.horizontalControl === native)
      XCTAssertEqual(subject.buttons.map(ObjectIdentifier.init), buttons)
      XCTAssertEqual(Set(contentViews(in: native).map(ObjectIdentifier.init)), contentIdentities)
      XCTAssertEqual(subject.selectedSegmentIndex, 2)
      XCTAssertEqual(native.selectedSegmentIndex, 2)
      XCTAssertEqual(native.titleForSegment(at: 2), "Updated Feed")
      XCTAssertEqual(subject.buttons[2].accessibilityLabel, "Updated Feed")
      XCTAssertEqual(subject.buttons[2].largeContentTitle, "Updated Feed")
      XCTAssertTrue(subject.buttons[2].showsLargeContentViewer)
      assertActiveRenderer(subject, vertical: vertical)
    }
    XCTAssertEqual(changes, 0)
    XCTAssertEqual(reselects, 0)
  }

  func testCollapsedNativeMenuSelectsEveryDestinationAndSupportsReselect() throws {
    let subject = makeSubject()
    layout(subject, vertical: true)
    subject.isCollapsed = true
    subject.selectedSegmentIndex = 1
    subject.layoutIfNeeded()
    var changes: [Int] = []
    var reselects: [Int] = []
    subject.addAction(UIAction { _ in changes.append(subject.selectedSegmentIndex) }, for: .valueChanged)
    subject.onReselect = { reselects.append($0) }
    let button = subject.navigationMenuButton
    XCTAssertEqual(button.accessibilityIdentifier, "FabBar.navigationMenu")
    XCTAssertEqual(button.accessibilityLabel, "Precision")
    XCTAssertTrue(button.showsMenuAsPrimaryAction)
    XCTAssertEqual(subject.accessibilityElements?.count, 1)
    XCTAssertTrue((subject.accessibilityElements?.first as? UIButton) === button)
    XCTAssertTrue(subject.horizontalControl.isHidden)
    XCTAssertTrue(subject.buttons.allSatisfy { !isVisible($0) })
    assertReceivesTouches(button, in: try XCTUnwrap(subject.window))
    let firstMenu = try XCTUnwrap(button.menu?.children as? [UIAction])
    XCTAssertEqual(firstMenu.map(\.title), ["Collection", "Precision", "Feed", "Profile"])
    XCTAssertEqual(firstMenu.filter { $0.state == .on }.map(\.title), ["Precision"])

    button.sendAction(firstMenu[2])
    let updatedMenu = try XCTUnwrap(button.menu?.children as? [UIAction])
    button.sendAction(updatedMenu[2])

    XCTAssertEqual(changes, [2])
    XCTAssertEqual(reselects, [2])
    XCTAssertEqual(subject.selectedSegmentIndex, 2)
    XCTAssertEqual(subject.horizontalControl.selectedSegmentIndex, 2)
    XCTAssertEqual(button.accessibilityLabel, "Feed")
    XCTAssertEqual(updatedMenu.filter { $0.state == .on }.map(\.title), ["Feed"])
  }

  func testUnchangedDescriptorsPreserveAnOpenNativeMenu() {
    let subject = makeSubject()
    layout(subject, vertical: true)
    subject.isCollapsed = true
    let menu = subject.navigationMenuButton.menu

    subject.setTabs(makeTabs())
    let currentSelection = subject.selectedSegmentIndex
    let currentTint = subject.activeTintColor
    subject.selectedSegmentIndex = currentSelection
    subject.activeTintColor = currentTint

    XCTAssertTrue(subject.navigationMenuButton.menu === menu)
  }

  func testLargestDynamicTypeKeepsLocalizedNativeTitlesAndVerticalLargeContent() {
    let subject = makeSubject(category: .accessibilityExtraExtraExtraLarge)
    let titles = ["المجموعة", "الدقة", "الصور", "الملف الشخصي"]
    subject.setTabs(titles.enumerated().map { index, title in
      FabBarTabDescriptor(title: title, image: UIImage(systemName: "circle"), accessibilityIdentifier: "tab.\(index)")
    })
    layout(subject, vertical: false, size: CGSize(width: 300, height: 48))

    XCTAssertEqual(subject.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
    let native = subject.horizontalControl
    XCTAssertEqual((0..<4).map { native.titleForSegment(at: $0) }, titles)
    let content = contentViews(in: native)
    XCTAssertEqual(content.count, 8)
    XCTAssertTrue(content.allSatisfy { $0.intrinsicContentSize.height == Constants.iconViewSize })
    assertActiveRenderer(subject, vertical: false)

    layout(subject, vertical: true)
    XCTAssertTrue(subject.buttons.allSatisfy { $0.configuration?.attributedTitle == nil })
    XCTAssertEqual(subject.buttons.map(\.accessibilityLabel), titles)
    XCTAssertEqual(subject.buttons.map(\.largeContentTitle), titles)
    XCTAssertTrue(subject.buttons.allSatisfy { $0.configuration?.image != nil && $0.showsLargeContentViewer })
    assertActiveRenderer(subject, vertical: true)
  }

  func testRTLReversesNativeSegmentPositionsWithoutReversingLogicalValues() throws {
    let subject = makeSubject()
    subject.semanticContentAttribute = .forceRightToLeft
    layout(subject, vertical: false)
    let native = subject.horizontalControl
    let first = try XCTUnwrap(descendant(withIdentifier: "tab.0", in: native))
    let last = try XCTUnwrap(descendant(withIdentifier: "tab.3", in: native))
    let firstFrame = first.convert(first.bounds, to: subject)
    let lastFrame = last.convert(last.bounds, to: subject)
    XCTAssertGreaterThan(firstFrame.minX, lastFrame.minX)
    XCTAssertEqual(native.titleForSegment(at: 0), "Collection")
    XCTAssertEqual(native.titleForSegment(at: 3), "Profile")
    assertReceivesTouches(first, in: try XCTUnwrap(subject.window), routedThrough: native)
    assertReceivesTouches(last, in: try XCTUnwrap(subject.window), routedThrough: native)
    native.selectedSegmentIndex = 3
    dispatchNativeValueChanged(native)
    XCTAssertEqual(subject.selectedSegmentIndex, 3)

    layout(subject, vertical: true)
    XCTAssertTrue(subject.buttons[3].isSelected)
    subject.buttons[0].sendActions(for: .touchUpInside)
    XCTAssertEqual(subject.selectedSegmentIndex, 0)
    layout(subject, vertical: false)
    XCTAssertEqual(native.selectedSegmentIndex, 0)
  }

  func testLocalizedNativeContentFallsBackToIconsAndRestoresWithoutReplacingViews() {
    let subject = makeSubject()
    let titles = ["Uhrensammlung", "Präzisionsmessungen", "Wristshot Feed", "Mein Profil"]
    subject.setTabs(titles.enumerated().map { index, title in
      FabBarTabDescriptor(title: title, image: UIImage(systemName: "circle"), accessibilityIdentifier: "tab.\(index)")
    })
    layout(subject, vertical: false, size: CGSize(width: 900, height: 58))
    let native = subject.horizontalControl
    let content = contentViews(in: native)
    XCTAssertEqual(content.count, 8)
    let identities = Set(content.map(ObjectIdentifier.init))
    XCTAssertTrue(content.allSatisfy { $0.intrinsicContentSize.height > Constants.iconViewSize })

    layout(subject, vertical: false, size: CGSize(width: 256, height: 48))
    XCTAssertTrue(contentViews(in: native).allSatisfy { $0.intrinsicContentSize.height == Constants.iconViewSize })
    XCTAssertEqual((0..<4).map { native.titleForSegment(at: $0) }, titles)

    layout(subject, vertical: false, size: CGSize(width: 900, height: 58))
    XCTAssertTrue(contentViews(in: native).allSatisfy { $0.intrinsicContentSize.height > Constants.iconViewSize })
    XCTAssertEqual(Set(contentViews(in: native).map(ObjectIdentifier.init)), identities)
  }

  func testVerticalDragPreviewsThenCommitsOnceAndCancelRestoresInBothDirections() {
    for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
      let subject = makeSubject()
      subject.semanticContentAttribute = direction
      layout(subject, vertical: true)
      var changes: [Int] = []
      var reselects: [Int] = []
      subject.addAction(UIAction { _ in changes.append(subject.selectedSegmentIndex) }, for: .valueChanged)
      subject.onReselect = { reselects.append($0) }
      XCTAssertTrue(subject.gestureRecognizers?.contains { $0 is UIPanGestureRecognizer } == true)
      let start = center(of: subject.buttons[0], in: subject)
      let middle = center(of: subject.buttons[1], in: subject)
      let end = center(of: subject.buttons[3], in: subject)

      subject.processSelectionDrag(at: start, state: .began)
      subject.processSelectionDrag(at: middle, state: .changed)
      XCTAssertEqual(subject.selectedSegmentIndex, 1)
      XCTAssertTrue(changes.isEmpty)
      subject.processSelectionDrag(at: end, state: .ended)
      XCTAssertEqual(changes, [3])
      XCTAssertTrue(reselects.isEmpty)
      subject.processSelectionDrag(at: end, state: .began)
      subject.processSelectionDrag(at: start, state: .changed)
      subject.processSelectionDrag(at: start, state: .cancelled)
      XCTAssertEqual(subject.selectedSegmentIndex, 3)
      XCTAssertEqual(changes, [3])
      subject.processSelectionDrag(at: end, state: .began)
      subject.processSelectionDrag(at: end, state: .ended)
      XCTAssertEqual(reselects, [3])
    }
  }

  private func layout(_ subject: FabBarTabControl, vertical: Bool, size: CGSize? = nil) {
    subject.isVertical = vertical
    subject.frame.size = size ?? (vertical ? CGSize(width: 58, height: 244) : CGSize(width: 300, height: 58))
    subject.setNeedsLayout()
    subject.layoutIfNeeded()
    subject.horizontalControl.layoutIfNeeded()
  }

  private func assertActiveRenderer(_ subject: FabBarTabControl, vertical: Bool,
    file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertFalse(subject.isCollapsed, file: file, line: line)
    XCTAssertEqual(subject.horizontalControl.isHidden, vertical, file: file, line: line)
    XCTAssertEqual(subject.horizontalControl.isRendererActive, !vertical, file: file, line: line)
    XCTAssertTrue(subject.navigationMenuButton.isHidden, file: file, line: line)
    guard let window = subject.window else { XCTFail("The renderer must be mounted", file: file, line: line); return }
    if vertical {
      XCTAssertEqual(subject.accessibilityElements?.compactMap { $0 as? UIButton }, subject.buttons, file: file, line: line)
      for button in subject.buttons {
        XCTAssertTrue(isVisible(button), file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.bounds.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(button.bounds.height, 44, file: file, line: line)
        assertReceivesTouches(button, in: window, file: file, line: line)
      }
    } else {
      // Leave horizontal container discovery to UIKit so its native segments
      // remain individual accessibility elements rather than one custom leaf.
      XCTAssertNil(subject.accessibilityElements, file: file, line: line)
      let native = subject.horizontalControl
      XCTAssertFalse(native.isAccessibilityElement, file: file, line: line)
      XCTAssertFalse(native.accessibilityElementsHidden, file: file, line: line)
      let elements = native.accessibilityElements?.compactMap { $0 as? NSObject } ?? []
      XCTAssertEqual(elements.count, native.numberOfSegments, file: file, line: line)
      XCTAssertEqual(native.accessibilityElementCount(), native.numberOfSegments, file: file, line: line)
      for (index, element) in elements.enumerated() {
        XCTAssertTrue((native.accessibilityElement(at: index) as? NSObject) === element, file: file, line: line)
        XCTAssertEqual(native.index(ofAccessibilityElement: element), index, file: file, line: line)
        if let proxy = element as? UIAccessibilityElement {
          XCTAssertTrue((proxy.accessibilityContainer as? UIView) === native, file: file, line: line)
        } else if let view = element as? UIView {
          XCTAssertTrue(view.isDescendant(of: native), file: file, line: line)
        } else {
          XCTFail("A destination must expose its native segment or a nonvisual accessibility element", file: file, line: line)
        }
        if let identifier = accessibilityIdentifier(of: element),
           let segment = descendant(withIdentifier: identifier, in: native) {
          let expected = UIAccessibility.convertToScreenCoordinates(segment.bounds, in: segment)
          let actual = element.accessibilityFrame
          XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.5, file: file, line: line)
          XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.5, file: file, line: line)
          XCTAssertEqual(actual.width, expected.width, accuracy: 0.5, file: file, line: line)
          XCTAssertEqual(actual.height, expected.height, accuracy: 0.5, file: file, line: line)
          if let proxy = element as? UIAccessibilityElement {
            let expectedInContainer = segment.convert(segment.bounds, to: native)
            let actualInContainer = proxy.accessibilityFrameInContainerSpace
            XCTAssertEqual(actualInContainer.minX, expectedInContainer.minX, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(actualInContainer.minY, expectedInContainer.minY, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(actualInContainer.width, expectedInContainer.width, accuracy: 0.5, file: file, line: line)
            XCTAssertEqual(actualInContainer.height, expectedInContainer.height, accuracy: 0.5, file: file, line: line)
          }
        } else {
          XCTFail("The exposed destination must match an actual native segment identifier", file: file, line: line)
        }
        XCTAssertTrue(element.isAccessibilityElement, file: file, line: line)
        XCTAssertFalse(element.accessibilityElementsHidden, file: file, line: line)
        XCTAssertEqual(element.accessibilityLabel, native.titleForSegment(at: index), file: file, line: line)
        XCTAssertTrue(element.accessibilityTraits.contains(.button), file: file, line: line)
        XCTAssertEqual(element.accessibilityTraits.contains(.selected), index == subject.selectedSegmentIndex,
          file: file, line: line)
        XCTAssertNil(element.accessibilityValue, file: file, line: line)
      }
      XCTAssertTrue(subject.buttons.allSatisfy { !isVisible($0) }, file: file, line: line)
      XCTAssertTrue(subject.subviews.compactMap { $0 as? UIVisualEffectView }.allSatisfy(\.isHidden),
        "The custom selection surface must not cover the native segmented control", file: file, line: line)
      assertReceivesTouches(subject.horizontalControl, in: window, file: file, line: line)
    }
  }

  private func dispatchNativeValueChanged(_ control: UISegmentedControl,
    file: StaticString = #filePath, line: UInt = #line) {
    // Standalone SwiftPM xctest has no UIApplication. UIKit logs UIApp-is-nil
    // and drops selector targets sent through sendActions; invoke the actual
    // registered selector to verify wrapper wiring. App UI tests exercise taps.
    let callbacks: [(NSObject, Selector)] = control.allTargets.compactMap { $0.base as? NSObject }.flatMap { target in
      (control.actions(forTarget: target, forControlEvent: .valueChanged) ?? []).map {
        (target, NSSelectorFromString($0))
      }
    }
    XCTAssertEqual(callbacks.count, 1, "The native child must have one destination-change target", file: file, line: line)
    for (target, selector) in callbacks {
      XCTAssertTrue(target.responds(to: selector), file: file, line: line)
      target.perform(selector, with: control)
    }
  }

  private func assertReceivesTouches(_ view: UIView, in window: UIWindow, routedThrough owner: UIView? = nil,
    file: StaticString = #filePath, line: UInt = #line) {
    let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
    let hit = window.hitTest(point, with: nil)
    // UISegmentedControl may route a segment-center touch through its lens
    // sibling; the active native control remains the touch owner.
    let target = owner ?? view
    XCTAssertTrue(hit === target || hit?.isDescendant(of: target) == true,
      "The visible renderer must receive touches: \(view.accessibilityIdentifier ?? "view")", file: file, line: line)
  }

  private func isVisible(_ view: UIView) -> Bool {
    var current: UIView? = view
    while let candidate = current {
      if candidate.isHidden || candidate.alpha <= 0.01 { return false }
      current = candidate.superview
    }
    return view.window != nil
  }

  private func accessibilityIdentifier(of element: NSObject) -> String? {
    (element as? UIAccessibilityElement)?.accessibilityIdentifier ?? (element as? UIView)?.accessibilityIdentifier
  }

  private func archivedTitle(_ view: TabItemContentView) throws -> String {
    // The existing NSCoding contract records the exact title used by draw(_:).
    // Reading it catches a misplaced injected view even when native AX labels
    // and the control's selectedSegmentIndex are independently correct.
    let archiver = NSKeyedArchiver(requiringSecureCoding: false)
    view.encode(with: archiver)
    archiver.finishEncoding()
    let unarchiver = try NSKeyedUnarchiver(forReadingFrom: archiver.encodedData)
    unarchiver.requiresSecureCoding = false
    defer { unarchiver.finishDecoding() }
    return try XCTUnwrap(unarchiver.decodeObject(forKey: "title") as? String)
  }

  private func contentViews(in view: UIView) -> [TabItemContentView] {
    view.subviews.flatMap { child in
      (child as? TabItemContentView).map { [$0] } ?? contentViews(in: child)
    }
  }

  private func descendant(withIdentifier identifier: String, in view: UIView) -> UIView? {
    if view.accessibilityIdentifier == identifier { return view }
    return view.subviews.lazy.compactMap { self.descendant(withIdentifier: identifier, in: $0) }.first
  }

  private func center(of view: UIView, in subject: UIView) -> CGPoint {
    view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: subject)
  }

  private func makeSubject(category: UIContentSizeCategory = .large) -> FabBarTabControl {
    let subject = FabBarTabControl()
    subject.setTabs(makeTabs())
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.traitOverrides.preferredContentSizeCategory = category
    subject.frame = CGRect(x: 0, y: 0, width: 300, height: 58)
    window.addSubview(subject)
    window.isHidden = false
    subject.updateTraitsIfNeeded()
    subject.layoutIfNeeded()
    subject.horizontalControl.layoutIfNeeded()
    addTeardownBlock { @MainActor in
      window.isHidden = true
      subject.removeFromSuperview()
    }
    return subject
  }

  private func makeTabs(prefix: String = "") -> [FabBarTabDescriptor] {
    ["Collection", "Precision", "Feed", "Profile"].enumerated().map { index, title in
      FabBarTabDescriptor(title: prefix.isEmpty ? title : "\(prefix) \(title)",
        image: UIImage(systemName: "circle"), accessibilityIdentifier: "tab.\(index)")
    }
  }
}
