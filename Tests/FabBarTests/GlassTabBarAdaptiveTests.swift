import SwiftUI
import UIKit
import XCTest
@testable import FabBar

@MainActor
@available(iOS 26.0, *)
final class GlassTabBarAdaptiveTests: XCTestCase {
  func testVerticalRailKeepsPrimarySeparateAndAllDestinationHitTargetsAvailable() {
    let subject = makeSubject()
    let window = host(subject, placement: .leading)

    XCTAssertTrue(subject.segmentedControl.isVertical)
    XCTAssertFalse(subject.segmentedControl.isCollapsed)
    XCTAssertEqual(subject.fabGlassView.frame.height, 62, accuracy: 0.1)
    XCTAssertEqual(subject.segmentedGlassView.frame.maxY + 8, subject.fabGlassView.frame.minY, accuracy: 0.1)
    XCTAssertTrue(subject.segmentedControl.buttons.allSatisfy { $0.bounds.height >= 44 })
    for button in subject.segmentedControl.buttons + [subject.fabButton] {
      let point = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
      let hit = window.hitTest(point, with: nil)
      XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true,
        "The \(button.accessibilityIdentifier ?? "button") hit region must reach the actual button")
    }
    withExtendedLifetime(window) {}
  }

  func testConstrainedVerticalNavigationCollapsesWhilePrimaryActionRemainsDirect() {
    var calls = 0
    let subject = makeSubject(primary: { calls += 1 })
    let window = host(subject, placement: .trailing, length: 132)

    XCTAssertTrue(subject.segmentedControl.isCollapsed)
    XCTAssertEqual(subject.segmentedControl.navigationMenuButton.menu?.children.count, 4)
    XCTAssertGreaterThanOrEqual(subject.segmentedControl.navigationMenuButton.bounds.height, 44)
    subject.fabButton.sendActions(for: .touchUpInside)

    XCTAssertEqual(calls, 1)
    XCTAssertFalse(subject.isExpanded)
    XCTAssertEqual(subject.fabButton.bounds.size, CGSize(width: 62, height: 62))
    withExtendedLifetime(window) {}
  }

  func testAxisChangesPreserveSelectionAndExistingButtons() {
    let subject = makeSubject()
    let window = host(subject, placement: .leading)
    subject.segmentedControl.buttons[2].sendActions(for: .touchUpInside)
    let buttons = subject.segmentedControl.buttons.map(ObjectIdentifier.init)

    subject.updateLayout(placement: .bottom, density: .compact, maximumLength: nil)
    subject.frame = CGRect(x: 12, y: 760, width: 360, height: 52)
    subject.layoutIfNeeded()
    subject.updateLayout(placement: .trailing, density: .regular, maximumLength: 132)
    subject.frame = CGRect(x: 316, y: 650, width: 62, height: 132)
    subject.layoutIfNeeded()

    XCTAssertEqual(subject.segmentedControl.buttons.map(ObjectIdentifier.init), buttons)
    XCTAssertEqual(subject.segmentedControl.selectedSegmentIndex, 2)
    XCTAssertTrue(subject.segmentedControl.isCollapsed)
    XCTAssertEqual(subject.segmentedControl.navigationMenuButton.accessibilityLabel, "Feed")
    withExtendedLifetime(window) {}
  }

  func testUpdatedPrimaryActionRefreshesAccessibilityAndUsesNewCallback() {
    var oldCalls = 0
    var newCalls = 0
    let subject = makeSubject(primary: { oldCalls += 1 })
    let window = host(subject, placement: .bottom)
    let originalImage = subject.fabButton.image(for: .normal)

    subject.updateAction(FabBarAction(systemImage: "camera", accessibilityLabel: "Take a photo") {
      newCalls += 1
    }, secondaryActions: [], isSecondaryActionMenuEnabled: false)
    subject.fabButton.sendActions(for: .touchUpInside)

    XCTAssertEqual(oldCalls, 0)
    XCTAssertEqual(newCalls, 1)
    XCTAssertEqual(subject.fabButton.accessibilityLabel, "Take a photo")
    XCTAssertEqual(subject.fabButton.largeContentTitle, "Take a photo")
    XCTAssertNotEqual(subject.fabButton.image(for: .normal), originalImage)
    withExtendedLifetime(window) {}
  }

  func testUpdatingActionRetainsPrimaryHostedViewWhenControllerIsUnchanged() {
    let controller = UIHostingController(rootView: Text("Primary"))
    let subject = makeSubject()
    let window = host(subject, placement: .leading)
    let action = FabBarAction(systemImage: "plus", accessibilityLabel: "Add reading", view: controller, action: {})

    subject.updateAction(action, secondaryActions: [], isSecondaryActionMenuEnabled: false)
    subject.layoutIfNeeded()
    let hostedView = controller.view
    subject.updateLayout(placement: .trailing, density: .compact, maximumLength: nil)
    subject.updateAction(action, secondaryActions: [], isSecondaryActionMenuEnabled: false)
    subject.layoutIfNeeded()

    XCTAssertTrue(hostedView?.superview === subject.fabButton)
    XCTAssertTrue(controller.view === hostedView)
    XCTAssertEqual(subject.fabButton.accessibilityLabel, "Add reading")
    withExtendedLifetime((window, controller)) {}
  }

  func testSecondaryMenusOpenInwardOnBothPhysicalSidesAndCleanupAfterDispatch() {
    for placement in [FabBarPlacement.leading, .trailing] {
      var calls = 0
      let subject = makeSubject(secondary: [FabBarAction(systemImage: "plus", accessibilityLabel: "Add reading") {
        calls += 1
      }])
      let window = host(subject, placement: placement)
      let baselineSubviews = window.subviews.count

      subject.fabButton.sendActions(for: .touchUpInside)

      XCTAssertTrue(subject.isExpanded)
      let safe = window.safeAreaLayoutGuide.layoutFrame
      XCTAssertTrue(safe.contains(subject.secondaryMenuFrame))
      let fab = subject.fabGlassView.convert(subject.fabGlassView.bounds, to: window)
      if placement == .leading {
        XCTAssertGreaterThan(subject.secondaryMenuFrame.minX, fab.maxX)
      } else {
        XCTAssertLessThan(subject.secondaryMenuFrame.maxX, fab.minX)
      }
      subject.secondaryButtons[0].sendActions(for: .touchUpInside)
      XCTAssertEqual(calls, 1)
      XCTAssertFalse(subject.isExpanded)
      XCTAssertEqual(window.subviews.count, baselineSubviews)
      withExtendedLifetime(window) {}
    }
  }

  func testSecondaryMenuAccessibilityEscapeDismissesWithoutDispatchingCommands() throws {
    for placement in [FabBarPlacement.bottom, .leading, .trailing] {
      var primaryCalls = 0
      var secondaryCalls = 0
      let subject = makeSubject(primary: { primaryCalls += 1 }, secondary: [
        FabBarAction(systemImage: "plus", accessibilityLabel: "Start new cycle") { secondaryCalls += 1 },
        FabBarAction(systemImage: "clock", accessibilityLabel: "Measurement") { secondaryCalls += 1 }
      ])
      let window = host(subject, placement: placement)
      let baselineSubviews = window.subviews.count
      subject.fabButton.sendActions(for: .touchUpInside)
      let menu = try XCTUnwrap(window.subviews.first {
        $0.accessibilityIdentifier == "FabBar.secondaryMenu"
      } as? UIScrollView)
      XCTAssertTrue(menu.accessibilityViewIsModal)
      XCTAssertTrue(subject.isExpanded)

      XCTAssertTrue(menu.accessibilityPerformEscape(), "The modal menu must handle VoiceOver's escape gesture")

      XCTAssertFalse(subject.isExpanded)
      XCTAssertNil(menu.superview)
      XCTAssertEqual(window.subviews.count, baselineSubviews)
      XCTAssertEqual(primaryCalls, 1)
      XCTAssertEqual(secondaryCalls, 0)
      XCTAssertTrue(subject.fabButton.isUserInteractionEnabled)
      subject.prepareForRemoval()
      window.isHidden = true
      withExtendedLifetime(window) {}
    }
  }

  func testHostedSecondaryLabelsKeepBothButtonCentersInsideTheInteractiveMenu() async throws {
    let animationsWereEnabled = UIView.areAnimationsEnabled
    UIView.setAnimationsEnabled(true)
    defer { UIView.setAnimationsEnabled(animationsWereEnabled) }
    for placement in [FabBarPlacement.bottom, .leading, .trailing] {
      for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
        let labels = ["Start new cycle", "Measurement"]
        let controllers = labels.map { label in
          UIHostingController(rootView: HStack(spacing: 6) {
            Image(systemName: "clock").frame(width: 20, height: 20)
            Text(label).font(.system(size: 16, weight: .medium, design: .monospaced))
          })
        }
        let actions = zip(labels, controllers).map { label, controller in
          FabBarAction(systemImage: "", accessibilityLabel: label, view: controller, action: {})
        }
        let subject = makeSubject(secondary: actions)
        subject.semanticContentAttribute = direction
        let window = host(subject, placement: placement,
          windowSize: placement.isVertical ? CGSize(width: 440, height: 956) : CGSize(width: 393, height: 852))
        window.traitOverrides.preferredContentSizeCategory = .large
        subject.updateTraitsIfNeeded()
        subject.layoutIfNeeded()
        subject.fabButton.sendActions(for: .touchUpInside)
        let menu = try XCTUnwrap(window.subviews.first {
          $0.accessibilityIdentifier == "FabBar.secondaryMenu"
        } as? UIScrollView)
        func assertInteractiveCenters(stage: String) {
          for (index, button) in subject.secondaryButtons.enumerated() {
            let frame = button.convert(button.bounds, to: window)
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let hit = window.hitTest(center, with: nil)
            let diagnostics = "stage=\(stage), placement=\(placement), direction=\(direction.rawValue), index=\(index), button=\(frame), center=\(center), menu=\(menu.frame), content=\(menu.contentSize), hit=\(String(describing: hit))"
            XCTAssertTrue(menu.frame.contains(center), diagnostics)
            XCTAssertTrue(hit === button || hit?.isDescendant(of: button) == true, diagnostics)
          }
        }
        assertInteractiveCenters(stage: "animation in flight")
        try await Task.sleep(for: .milliseconds(80))
        print("FabBar hosted-hit diagnostics: placement=\(placement), direction=\(direction.rawValue), animations=\(String(describing: menu.layer.animationKeys())), modelOpacity=\(menu.layer.opacity), presentationOpacity=\(String(describing: menu.layer.presentation()?.opacity))")
        assertInteractiveCenters(stage: "80ms after opening")
        try await Task.sleep(for: .milliseconds(220))
        window.layoutIfNeeded()
        assertInteractiveCenters(stage: "animation complete")
        subject.prepareForRemoval()
        window.isHidden = true
        withExtendedLifetime(controllers) {}
      }
    }
  }

  func testLargestTextSecondaryActionsAreScrollableAndReadableInShortWindow() throws {
    let actions = (0..<5).map { index in
      FabBarAction(systemImage: "plus", accessibilityLabel: "Add a precision reading for the selected watch \(index)", action: {})
    }
    let subject = makeSubject(secondary: actions)
    let window = host(subject, placement: .trailing, length: 112,
      windowSize: CGSize(width: 640, height: 320))
    window.traitOverrides.preferredContentSizeCategory = .accessibilityExtraExtraExtraLarge
    subject.layoutIfNeeded()

    subject.fabButton.sendActions(for: .touchUpInside)

    let scroll = try XCTUnwrap(window.subviews.first { $0.accessibilityIdentifier == "FabBar.secondaryMenu" } as? UIScrollView)
    XCTAssertGreaterThan(scroll.contentSize.height, scroll.bounds.height)
    XCTAssertTrue(window.safeAreaLayoutGuide.layoutFrame.contains(scroll.frame))
    for button in subject.secondaryButtons {
      XCTAssertGreaterThanOrEqual(button.bounds.height, 44)
      XCTAssertNotNil(button.configuration?.attributedTitle)
      XCTAssertGreaterThan(button.configuration?.attributedTitle?.font?.pointSize ?? 0, 40)
      XCTAssertEqual(button.titleLabel?.numberOfLines, 0)
      XCTAssertEqual(button.configuration?.titleLineBreakMode, .byWordWrapping)
    }
    subject.prepareForRemoval()
    XCTAssertFalse(window.subviews.contains { $0.accessibilityIdentifier == "FabBar.secondaryMenu" })
    withExtendedLifetime(window) {}
  }

  func testPlacementSizeKeyboardAndBackgroundChangesRemoveExpandedHitOverlays() async {
    let subject = makeSubject(secondary: [FabBarAction(systemImage: "plus", accessibilityLabel: "Add reading", action: {})])
    let window = host(subject, placement: .leading)
    let baselineSubviews = window.subviews.count
    subject.fabButton.sendActions(for: .touchUpInside)
    XCTAssertTrue(subject.isExpanded)
    subject.updateLayout(placement: .trailing, density: .regular, maximumLength: nil)
    XCTAssertFalse(subject.isExpanded)
    XCTAssertEqual(window.subviews.count, baselineSubviews)

    for name in [UIResponder.keyboardWillChangeFrameNotification, UIApplication.willResignActiveNotification,
                 UIApplication.didEnterBackgroundNotification] {
      subject.fabButton.sendActions(for: .touchUpInside)
      XCTAssertTrue(subject.isExpanded)
      NotificationCenter.default.post(name: name, object: nil)
      await waitForMenuCleanup(subject)
      XCTAssertFalse(subject.isExpanded)
      XCTAssertEqual(window.subviews.count, baselineSubviews)
    }
    subject.fabButton.sendActions(for: .touchUpInside)
    subject.frame.size.height -= 10
    subject.setNeedsLayout()
    subject.layoutIfNeeded()
    XCTAssertFalse(subject.isExpanded)
    XCTAssertEqual(window.subviews.count, baselineSubviews)
    withExtendedLifetime(window) {}
  }

  func testLifecycleNotificationsHopToMainActorFromBackgroundAndMainOperationQueue() async {
    let subject = makeSubject(secondary: [FabBarAction(systemImage: "plus", accessibilityLabel: "Add reading", action: {})])
    let window = host(subject, placement: .leading)
    let baselineSubviews = window.subviews.count
    let names = [UIResponder.keyboardWillChangeFrameNotification, UIApplication.willResignActiveNotification,
                 UIApplication.didEnterBackgroundNotification]

    for name in names {
      subject.fabButton.sendActions(for: .touchUpInside)
      XCTAssertTrue(subject.isExpanded)
      await Task.detached {
        NotificationCenter.default.post(name: name, object: nil)
      }.value
      await waitForMenuCleanup(subject)
      XCTAssertFalse(subject.isExpanded)
      XCTAssertEqual(window.subviews.count, baselineSubviews)

      subject.fabButton.sendActions(for: .touchUpInside)
      XCTAssertTrue(subject.isExpanded)
      await withCheckedContinuation { continuation in
        OperationQueue.main.addOperation {
          NotificationCenter.default.post(name: name, object: nil)
          continuation.resume()
        }
      }
      await waitForMenuCleanup(subject)
      XCTAssertFalse(subject.isExpanded)
      XCTAssertEqual(window.subviews.count, baselineSubviews)
    }
    subject.prepareForRemoval()
    withExtendedLifetime(window) {}
  }

  private func waitForMenuCleanup(_ subject: GlassTabBarView) async {
    for _ in 0..<50 {
      if !subject.isExpanded { return }
      try? await Task.sleep(for: .milliseconds(10))
    }
  }

  func testTransparentGlassSpacingPassesTouchesToUnderlyingContent() {
    let subject = makeSubject()
    let window = host(subject, placement: .leading)
    let content = UIView(frame: window.bounds)
    window.insertSubview(content, at: 0)
    let gapPoint = subject.convert(CGPoint(x: 31, y: subject.segmentedGlassView.frame.maxY + 4), to: window)

    XCTAssertTrue(window.hitTest(gapPoint, with: nil) === content)
    withExtendedLifetime(window) {}
  }

  func testRTLPutsHorizontalPrimaryActionOnLogicalTrailingEdge() {
    let subject = makeSubject()
    subject.semanticContentAttribute = .forceRightToLeft
    let window = host(subject, placement: .bottom)

    XCTAssertEqual(subject.fabGlassView.frame.minX, 0, accuracy: 0.1)
    XCTAssertGreaterThan(subject.segmentedGlassView.frame.minX, subject.fabGlassView.frame.maxX)
    withExtendedLifetime(window) {}
  }

  private func makeSubject(primary: @escaping () -> Void = {}, secondary: [FabBarAction] = []) -> GlassTabBarView {
    let control = FabBarTabControl()
    control.setTabs(["Collection", "Precision", "Feed", "Profile"].enumerated().map { index, title in
      FabBarTabDescriptor(title: title, image: UIImage(systemName: "circle"), accessibilityIdentifier: "tab.\(index)")
    })
    return GlassTabBarView(segmentedControl: control, tabCount: 4,
      action: FabBarAction(systemImage: "waveform", accessibilityLabel: "Measure", action: primary),
      secondaryActions: secondary, isSecondaryActionMenuEnabled: !secondary.isEmpty)
  }

  private func host(_ subject: GlassTabBarView, placement: FabBarPlacement, length: CGFloat = 318,
    windowSize: CGSize = CGSize(width: 390, height: 844)) -> UIWindow {
    let window = UIWindow(frame: CGRect(origin: .zero, size: windowSize))
    window.isHidden = false
    subject.updateLayout(placement: placement, density: .regular, maximumLength: length)
    subject.frame = placement.isVertical
      ? CGRect(x: placement == .leading ? 12 : windowSize.width - 74,
        y: max(12, windowSize.height - length - 24), width: 62, height: length)
      : CGRect(x: 12, y: windowSize.height - 86, width: windowSize.width - 24, height: 62)
    window.addSubview(subject)
    window.layoutIfNeeded()
    subject.setNeedsLayout()
    subject.layoutIfNeeded()
    return window
  }
}
