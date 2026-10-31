import SwiftUI
import UIKit
import XCTest
@testable import FabBar

@MainActor
@available(iOS 26.0, *)
final class FabBarSecondaryMenuClippingTests: XCTestCase {
  private let renderGutter: CGFloat = 12

  func testSecondaryPillsKeepRenderGuttersAndCompleteLabelsInNormalAndHighlightedStates() async throws {
    let cases: [(FabBarPlacement, UISemanticContentAttribute, Bool)] = [
      (.bottom, .forceLeftToRight, true),
      (.bottom, .forceRightToLeft, false),
      (.leading, .forceLeftToRight, false),
      (.leading, .forceRightToLeft, true),
      (.trailing, .forceLeftToRight, true),
      (.trailing, .forceRightToLeft, false),
    ]
    for (placement, direction, customLabels) in cases {
      var primaryCalls = 0
      var selected: [Int] = []
      let labels = ["NewCycle", "Reading"]
      let (actions, controllers) = makeActions(labels, custom: customLabels) { selected.append($0) }
      let subject = makeSubject(actions: actions, primary: { primaryCalls += 1 })
      let window = host(subject, placement: placement, direction: direction,
        size: placement.isVertical ? CGSize(width: 440, height: 956) : CGSize(width: 393, height: 852))
      defer { subject.prepareForRemoval(); window.isHidden = true }
      subject.fabButton.sendActions(for: .touchUpInside)
      try await settle(window)
      let menu = try menu(in: window)
      let context = "\(placement), RTL=\(direction == .forceRightToLeft), custom=\(customLabels)"
      XCTAssertTrue(subject.isExpanded, context)
      XCTAssertEqual(primaryCalls, 1, context)
      XCTAssertLessThanOrEqual(menu.contentSize.height, menu.bounds.height + 1, context)
      try assertPills(subject.secondaryButtons, in: menu, window: window, context: context)
      try assertLabels(subject.secondaryButtons, labels: labels, controllers: controllers,
        custom: customLabels, accessibility: false, context: context)
      let firstGlass = try glass(containing: subject.secondaryButtons[0])
      let lastGlass = try glass(containing: subject.secondaryButtons[1])
      let firstFrame = firstGlass.convert(firstGlass.bounds, to: window)
      let lastFrame = lastGlass.convert(lastGlass.bounds, to: window)
      XCTAssertEqual(lastFrame.minY - firstFrame.maxY, 12, accuracy: 1, context)
      XCTAssertEqual(firstFrame.maxX, lastFrame.maxX, accuracy: 1, context)
      let fab = subject.fabGlassView.convert(subject.fabGlassView.bounds, to: window)
      XCTAssertEqual(fab.minY - lastFrame.maxY, 12, accuracy: 1,
        "Render padding must preserve the existing button-to-FAB gap. \(context)")
      if placement == .bottom && direction == .forceLeftToRight && customLabels {
        XCTAssertGreaterThan(abs(firstFrame.width - lastFrame.width), 4,
          "The reproduction must use genuinely unequal label widths")
      }
      for (index, button) in subject.secondaryButtons.enumerated() {
        button.isHighlighted = true
        window.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        try assertPills(subject.secondaryButtons, in: menu, window: window, context: "Highlighted\(index): \(context)")
        try assertLabels(subject.secondaryButtons, labels: labels, controllers: controllers,
          custom: customLabels, accessibility: false, context: context)
        button.isHighlighted = false
      }
      subject.secondaryButtons[1].sendActions(for: .touchUpInside)
      XCTAssertEqual(selected, [1], context)
      XCTAssertFalse(subject.isExpanded, context)
      XCTAssertNil(menu.superview, context)
      withExtendedLifetime(controllers) {}
    }
  }

  func testAX5OverflowKeepsFirstAndLastPillsUnclippedAndDispatchesTheLastAction() async throws {
    let cases: [(FabBarPlacement, UISemanticContentAttribute, Bool)] = [
      (.bottom, .forceRightToLeft, false),
      (.leading, .forceRightToLeft, false),
      (.trailing, .forceLeftToRight, true),
    ]
    for (placement, direction, customLabels) in cases {
      var selected: [Int] = []
      let labels = (1...5).map { "Add a precision reading for the selected watch \($0)" }
      let (actions, controllers) = makeActions(labels, custom: customLabels) { selected.append($0) }
      let subject = makeSubject(actions: actions)
      let window = host(subject, placement: placement, direction: direction,
        size: CGSize(width: 640, height: 320), length: 108)
      defer { subject.prepareForRemoval(); window.isHidden = true }
      window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
      subject.updateTraitsIfNeeded()
      subject.setNeedsLayout()
      subject.layoutIfNeeded()
      subject.fabButton.sendActions(for: .touchUpInside)
      try await settle(window)
      let menu = try menu(in: window)
      let context = "AX5, \(placement), RTL=\(direction == .forceRightToLeft), custom=\(customLabels)"
      XCTAssertGreaterThan(menu.contentSize.height, menu.bounds.height, context)
      XCTAssertTrue(window.safeAreaLayoutGuide.layoutFrame.insetBy(dx: -0.5, dy: -0.5).contains(menu.frame), context)
      try assertLabels(subject.secondaryButtons, labels: labels, controllers: controllers,
        custom: customLabels, accessibility: true, context: context)
      for button in subject.secondaryButtons {
        let pill = try glass(containing: button)
        let padded = pill.convert(pill.bounds, to: menu).insetBy(dx: -renderGutter, dy: -renderGutter)
        if padded.height > menu.bounds.height + 0.5 {
          // An intrinsic multiline row can exceed the short viewport. Reach
          // each protected edge independently instead of demanding that both
          // ends of the oversized row be visible at the same time.
          let minimum = -menu.adjustedContentInset.top
          let maximum = max(minimum, menu.contentSize.height + menu.adjustedContentInset.bottom - menu.bounds.height)
          for edge in [VisibleVerticalEdge.top, .bottom] {
            let desired = edge == .top ? padded.minY : padded.maxY - menu.bounds.height
            menu.setContentOffset(CGPoint(x: menu.contentOffset.x, y: min(maximum, max(minimum, desired))), animated: false)
            window.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(10))
            try assertPills([button], in: menu, window: window, visibleVerticalEdge: edge, context: context)
          }
        } else {
          menu.scrollRectToVisible(padded, animated: false)
          window.layoutIfNeeded()
          try await Task.sleep(for: .milliseconds(10))
          try assertPills([button], in: menu, window: window, context: context)
        }
      }
      let last = try XCTUnwrap(subject.secondaryButtons.last)
      let lastGlass = try glass(containing: last)
      let lastEdge: VisibleVerticalEdge? = lastGlass.bounds.height + renderGutter * 2 > menu.bounds.height + 0.5 ? .bottom : nil
      last.isHighlighted = true
      try assertPills([last], in: menu, window: window, visibleVerticalEdge: lastEdge, context: "Highlighted last: \(context)")
      XCTAssertGreaterThan(menu.contentOffset.y, 0, "The test must actually reach the overflowing last action. \(context)")
      last.isHighlighted = false
      last.sendActions(for: .touchUpInside)
      XCTAssertEqual(selected, [4], context)
      XCTAssertFalse(subject.isExpanded, context)
      XCTAssertNil(menu.superview, context)
      withExtendedLifetime(controllers) {}
    }
  }

  private enum VisibleVerticalEdge: Equatable { case top, bottom }

  private func assertPills(_ buttons: [UIButton], in menu: UIScrollView, window: UIWindow,
    visibleVerticalEdge: VisibleVerticalEdge? = nil, context: String) throws {
    let viewport = menu.convert(menu.bounds, to: window)
    let safe = window.safeAreaLayoutGuide.layoutFrame
    XCTAssertTrue(safe.insetBy(dx: -0.5, dy: -0.5).contains(viewport), context)
    for button in buttons {
      let pill = try glass(containing: button)
      let frame = pill.convert(pill.bounds, to: window)
      let diagnostics = "\(context), pill=\(frame), viewport=\(viewport), content=\(menu.contentSize), offset=\(menu.contentOffset)"
      XCTAssertGreaterThanOrEqual(frame.minX - viewport.minX, renderGutter - 0.5, diagnostics)
      XCTAssertGreaterThanOrEqual(viewport.maxX - frame.maxX, renderGutter - 0.5, diagnostics)
      if visibleVerticalEdge != .bottom {
        XCTAssertGreaterThanOrEqual(frame.minY - viewport.minY, renderGutter - 0.5, diagnostics)
      }
      if visibleVerticalEdge != .top {
        XCTAssertGreaterThanOrEqual(viewport.maxY - frame.maxY, renderGutter - 0.5, diagnostics)
      }
      let paintedFrame = frame.insetBy(dx: -renderGutter, dy: -renderGutter)
      let visiblePaint = visibleVerticalEdge == nil ? paintedFrame : paintedFrame.intersection(viewport)
      XCTAssertTrue(safe.insetBy(dx: -0.5, dy: -0.5).contains(visiblePaint), diagnostics)
      XCTAssertGreaterThanOrEqual(button.bounds.width, 44, diagnostics)
      XCTAssertGreaterThanOrEqual(button.bounds.height, 44, diagnostics)
      let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
      let hit = window.hitTest(center, with: nil)
      XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true,
        "The visible pill must retain its native button hit target. \(diagnostics)")
    }
  }

  private func assertLabels(_ buttons: [UIButton], labels: [String],
    controllers: [UIHostingController<SecondaryMenuLabel>], custom: Bool, accessibility: Bool, context: String) throws {
    for (index, button) in buttons.enumerated() {
      button.layoutIfNeeded()
      XCTAssertEqual(button.accessibilityLabel, labels[index], context)
      if accessibility {
        let title = try XCTUnwrap(button.titleLabel, context)
        let font = try XCTUnwrap(title.font, context)
        XCTAssertEqual(button.configuration?.attributedTitle.map { String($0.characters) }, labels[index], context)
        XCTAssertGreaterThan(font.pointSize, 40, context)
        XCTAssertEqual(title.numberOfLines, 0, context)
        let height = (labels[index] as NSString).boundingRect(
          with: CGSize(width: title.bounds.width, height: .greatestFiniteMagnitude),
          options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height
        XCTAssertGreaterThan(title.bounds.width, 0, context)
        XCTAssertGreaterThanOrEqual(title.bounds.height + 1, ceil(height),
          "Readable text fitting is independent of the glass render gutter. \(context)")
        XCTAssertTrue(button.bounds.insetBy(dx: -1, dy: -1).contains(title.frame), context)
        if custom { XCTAssertTrue(controllers[index].view.isHidden, context) }
      } else if custom {
        let controller = controllers[index]
        let text = try XCTUnwrap(find("secondary-label.\(index)", in: controller.view), context)
        let textFrame = text.convert(text.bounds, to: button)
        let font = UIFont.monospacedSystemFont(ofSize: 16, weight: .medium)
        let expected = (labels[index] as NSString).boundingRect(
          with: CGSize(width: text.bounds.width, height: .greatestFiniteMagnitude),
          options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font], context: nil).height
        XCTAssertGreaterThan(text.bounds.width, 0, context)
        XCTAssertGreaterThanOrEqual(text.bounds.height + 1, ceil(expected), context)
        XCTAssertTrue(button.bounds.insetBy(dx: -1, dy: -1).contains(textFrame),
          "The complete text must fit inside the button before checking the glass perimeter. \(context)")
      }
    }
  }

  private func makeActions(_ labels: [String], custom: Bool, selected: @escaping (Int) -> Void)
    -> ([FabBarAction], [UIHostingController<SecondaryMenuLabel>]) {
    let controllers = custom ? labels.enumerated().map { index, label in
      UIHostingController(rootView: SecondaryMenuLabel(text: label, identifier: "secondary-label.\(index)"))
    } : []
    let actions = labels.enumerated().map { index, label in
      if custom {
        return FabBarAction(systemImage: "clock", accessibilityLabel: label, view: controllers[index]) { selected(index) }
      }
      return FabBarAction(systemImage: "clock", accessibilityLabel: label) { selected(index) }
    }
    return (actions, controllers)
  }

  private func makeSubject(actions: [FabBarAction], primary: @escaping () -> Void = {}) -> GlassTabBarView {
    let control = FabBarTabControl()
    control.setTabs(["Collection", "Precision", "Profile"].enumerated().map { index, title in
      FabBarTabDescriptor(title: title, image: UIImage(systemName: "circle"), accessibilityIdentifier: "tab.\(index)")
    })
    return GlassTabBarView(segmentedControl: control, tabCount: 3,
      action: FabBarAction(systemImage: "plus", accessibilityLabel: "Primary", action: primary),
      secondaryActions: actions, isSecondaryActionMenuEnabled: true)
  }

  private func host(_ subject: GlassTabBarView, placement: FabBarPlacement,
    direction: UISemanticContentAttribute, size: CGSize, length: CGFloat = 270) -> UIWindow {
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.overrideUserInterfaceStyle = .light
    window.backgroundColor = UIColor(white: 0.9, alpha: 1)
    window.semanticContentAttribute = direction
    subject.semanticContentAttribute = direction
    window.isHidden = false
    subject.updateLayout(placement: placement, density: .regular, maximumLength: length)
    let thickness = FabBarDensity.regular.barThickness(for: placement)
    subject.frame = placement.isVertical
      ? CGRect(x: placement == .leading ? 24 : size.width - thickness - 24,
        y: max(12, size.height - length - 24), width: thickness, height: length)
      : CGRect(x: 12, y: size.height - thickness - 24, width: size.width - 24, height: thickness)
    window.addSubview(subject)
    window.layoutIfNeeded()
    subject.setNeedsLayout()
    subject.layoutIfNeeded()
    return window
  }

  private func menu(in window: UIWindow) throws -> UIScrollView {
    try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "FabBar.secondaryMenu" } as? UIScrollView)
  }

  private func glass(containing button: UIButton) throws -> UIVisualEffectView {
    var ancestor = button.superview
    while let view = ancestor {
      if let glass = view as? UIVisualEffectView { return glass }
      ancestor = view.superview
    }
    throw NSError(domain: "FabBarSecondaryMenuClippingTests", code: 1,
      userInfo: [NSLocalizedDescriptionKey: "Secondary button has no glass surface"])
  }

  private func find(_ identifier: String, in view: UIView) -> UIView? {
    if view.accessibilityIdentifier == identifier { return view }
    return view.subviews.lazy.compactMap { self.find(identifier, in: $0) }.first
  }

  private func settle(_ window: UIWindow) async throws {
    try await Task.sleep(for: .milliseconds(250))
    window.layoutIfNeeded()
  }

}

private struct SecondaryMenuLabel: View {
  let text: String
  let identifier: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "clock").frame(width: 20, height: 20)
      Text(text)
        .font(.system(size: 16, weight: .medium, design: .monospaced))
        .fixedSize(horizontal: false, vertical: true)
        .background { SecondaryMenuLabelBounds(identifier: identifier) }
    }
    .foregroundStyle(Color.black)
  }
}

private struct SecondaryMenuLabelBounds: UIViewRepresentable {
  let identifier: String
  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    view.accessibilityIdentifier = identifier
    return view
  }
  func updateUIView(_ view: UIView, context: Context) {}
}
