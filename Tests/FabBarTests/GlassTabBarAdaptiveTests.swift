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
    XCTAssertEqual(subject.fabGlassView.frame.height, 50, accuracy: 0.1)
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

  func testNativeReferenceRailGeometryKeepsFullHitTargetsAcrossCountsDensityAndAX5() {
    for density in [FabBarDensity.regular, .compact] {
      for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
        for (count, capsuleHeight, totalHeight) in [(2, CGFloat(112), CGFloat(170)), (3, 162, 220), (4, 212, 270)] {
          let subject = makeSubject(tabCount: count)
          let window = host(subject, placement: .trailing, length: totalHeight, density: density)
          window.traitOverrides.preferredContentSizeCategory = category
          subject.setNeedsLayout()
          subject.layoutIfNeeded()
          let context = "\(count) tabs, \(density), \(category)"
          let control = subject.segmentedControl
          XCTAssertEqual(subject.bounds.width, 50, accuracy: 0.1, context)
          XCTAssertEqual(subject.segmentedGlassView.bounds.size,
            CGSize(width: 50, height: capsuleHeight), context)
          XCTAssertEqual(control.frame.minY, 6, accuracy: 0.1, context)
          XCTAssertEqual(subject.segmentedGlassView.bounds.maxY - control.frame.maxY, 6, accuracy: 0.1, context)
          XCTAssertEqual(subject.fabButton.bounds.size, CGSize(width: 50, height: 50), context)
          XCTAssertFalse(control.isCollapsed, context)
          XCTAssertEqual(control.buttons.count, count, context)
          var centers: [CGFloat] = []
          for button in control.buttons {
            XCTAssertGreaterThanOrEqual(button.bounds.width, 44, context)
            XCTAssertGreaterThanOrEqual(button.bounds.height, 44, context)
            XCTAssertEqual(button.bounds.height, 50, accuracy: 0.1, context)
            XCTAssertNotNil(button.accessibilityLabel, context)
            XCTAssertTrue(button.showsLargeContentViewer, context)
            assertReceivesTouches(button, in: window)
            centers.append(button.convert(button.bounds, to: subject).midY)
          }
          for (first, second) in zip(centers, centers.dropFirst()) {
            XCTAssertEqual(second - first, 50, accuracy: 0.1, context)
          }
          assertReceivesTouches(subject.fabButton, in: window)
          window.isHidden = true
        }
      }
    }
  }

  func testConstrainedVerticalNavigationCollapsesWhilePrimaryActionRemainsDirect() {
    var calls = 0
    let subject = makeSubject(primary: { calls += 1 })
    let window = host(subject, placement: .trailing, length: 108)

    XCTAssertTrue(subject.segmentedControl.isCollapsed)
    XCTAssertEqual(subject.segmentedControl.navigationMenuButton.menu?.children.count, 4)
    XCTAssertGreaterThanOrEqual(subject.segmentedControl.navigationMenuButton.bounds.height, 44)
    subject.fabButton.sendActions(for: .touchUpInside)

    XCTAssertEqual(calls, 1)
    XCTAssertFalse(subject.isExpanded)
    XCTAssertEqual(subject.fabButton.bounds.size, CGSize(width: 50, height: 50))
    withExtendedLifetime(window) {}
  }

  func testAxisChangesPreserveBothRenderersAndForwardSelectionThroughTheActiveOne() {
    let subject = makeSubject()
    let window = host(subject, placement: .leading)
    let native = subject.segmentedControl.horizontalControl
    let buttons = subject.segmentedControl.buttons.map(ObjectIdentifier.init)
    let primary = subject.fabButton
    var changes: [Int] = []
    subject.segmentedControl.addAction(UIAction { _ in
      changes.append(subject.segmentedControl.selectedSegmentIndex)
    }, for: .valueChanged)
    subject.segmentedControl.buttons[2].sendActions(for: .touchUpInside)

    subject.updateLayout(placement: .bottom, density: .compact, maximumLength: nil)
    subject.frame = CGRect(x: 12, y: 760, width: 360, height: 52)
    subject.layoutIfNeeded()
    XCTAssertFalse(native.isHidden)
    XCTAssertTrue(native.isRendererActive)
    XCTAssertEqual(native.selectedSegmentIndex, 2)
    assertReceivesTouches(native, in: window)
    native.selectedSegmentIndex = 1
    dispatchNativeValueChanged(native)
    XCTAssertEqual(subject.segmentedControl.selectedSegmentIndex, 1)

    subject.updateLayout(placement: .trailing, density: .regular, maximumLength: 108)
    subject.frame = CGRect(x: 316, y: 650, width: 50, height: 108)
    subject.layoutIfNeeded()

    XCTAssertTrue(subject.segmentedControl.horizontalControl === native)
    XCTAssertTrue(subject.fabButton === primary)
    XCTAssertEqual(subject.segmentedControl.buttons.map(ObjectIdentifier.init), buttons)
    XCTAssertEqual(subject.segmentedControl.selectedSegmentIndex, 1)
    XCTAssertEqual(native.selectedSegmentIndex, 1)
    XCTAssertTrue(native.isHidden)
    XCTAssertFalse(native.isRendererActive)
    XCTAssertTrue(subject.segmentedControl.isCollapsed)
    XCTAssertEqual(subject.segmentedControl.navigationMenuButton.accessibilityLabel, "Precision")
    assertReceivesTouches(subject.segmentedControl.navigationMenuButton, in: window)
    subject.updateLayout(placement: .bottom, density: .regular, maximumLength: nil)
    subject.frame = CGRect(x: 12, y: 740, width: 366, height: 62)
    subject.layoutIfNeeded()
    XCTAssertTrue(subject.segmentedControl.horizontalControl === native)
    XCTAssertTrue(subject.fabButton === primary)
    XCTAssertFalse(native.isHidden)
    XCTAssertEqual(native.selectedSegmentIndex, 1)
    assertReceivesTouches(native, in: window)
    assertReceivesTouches(primary, in: window)
    XCTAssertEqual(changes, [2, 1], "Axis and density changes must not emit additional destination changes")
    withExtendedLifetime(window) {}
  }

  func testHorizontalNativeNavigationAndPrimaryRemainHittableThroughDensityChanges() {
    let subject = makeSubject()
    let window = host(subject, placement: .bottom)
    let native = subject.segmentedControl.horizontalControl
    let primary = subject.fabButton

    for density in [FabBarDensity.regular, .compact, .regular] {
      subject.updateLayout(placement: .bottom, density: density, maximumLength: nil)
      subject.frame = CGRect(x: 12, y: 740, width: 366, height: density.barHeight)
      subject.setNeedsLayout()
      subject.layoutIfNeeded()
      XCTAssertTrue(subject.segmentedControl.horizontalControl === native)
      XCTAssertTrue(subject.fabButton === primary)
      XCTAssertFalse(native.isHidden)
      XCTAssertFalse(subject.segmentedControl.isCollapsed)
      XCTAssertEqual(native.numberOfSegments, 4)
      XCTAssertEqual(subject.segmentedGlassView.frame.maxX + 8, subject.fabGlassView.frame.minX, accuracy: 0.1)
      XCTAssertGreaterThanOrEqual(native.bounds.height, 44)
      assertReceivesTouches(native, in: window)
      assertReceivesTouches(primary, in: window)
    }
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

    // SwiftUI can briefly mount a replacement bar with the same controller.
    // The bar receiving the latest update must own the actual hosted view.
    let replacement = makeSubject()
    replacement.updateAction(action, secondaryActions: [], isSecondaryActionMenuEnabled: false)
    XCTAssertTrue(hostedView?.superview === replacement.fabButton)
    subject.updateAction(action, secondaryActions: [], isSecondaryActionMenuEnabled: false)
    XCTAssertTrue(hostedView?.superview === subject.fabButton)
    XCTAssertTrue(controller.view === hostedView)

    // Tearing down the previous owner must not detach the reclaimed content.
    replacement.updateAction(FabBarAction(systemImage: "camera", accessibilityLabel: "Capture", action: {}),
      secondaryActions: [], isSecondaryActionMenuEnabled: false)
    XCTAssertTrue(hostedView?.superview === subject.fabButton)
    withExtendedLifetime((window, controller, replacement)) {}
  }

  func testObsoleteBarLayoutCannotResizeOrDecenterReparentedPrimaryContent() throws {
    let controller = UIHostingController(rootView: Image(systemName: "plus")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .ignoresSafeArea())
    let hostedView = try XCTUnwrap(controller.view)
    // A native marker inside the real hosting view makes the inner content's
    // center measurable independently of the bar's outer glass geometry.
    let marker = UIView()
    marker.isUserInteractionEnabled = false
    marker.translatesAutoresizingMaskIntoConstraints = false
    hostedView.addSubview(marker)
    NSLayoutConstraint.activate([
      marker.centerXAnchor.constraint(equalTo: hostedView.centerXAnchor),
      marker.centerYAnchor.constraint(equalTo: hostedView.centerYAnchor),
      marker.widthAnchor.constraint(equalToConstant: 20),
      marker.heightAnchor.constraint(equalToConstant: 20),
    ])
    var calls = 0
    let action = FabBarAction(systemImage: "plus", accessibilityLabel: "Add reading",
      view: controller, action: { calls += 1 })
    let obsolete = makeSubject()
    let window = host(obsolete, placement: .bottom)
    obsolete.updateAction(action, secondaryActions: [], isSecondaryActionMenuEnabled: false)
    obsolete.layoutIfNeeded()
    let replacement = makeSubject()
    window.addSubview(replacement)
    replacement.updateAction(action, secondaryActions: [], isSecondaryActionMenuEnabled: false)
    XCTAssertTrue(hostedView.superview === replacement.fabButton)

    let liveLayouts: [(FabBarPlacement, FabBarDensity)] = [
      (.trailing, .regular), (.bottom, .regular), (.bottom, .compact),
      (.leading, .compact), (.trailing, .regular),
    ]
    let obsoleteLayouts: [(FabBarPlacement, FabBarDensity, CGRect)] = [
      (.trailing, .regular, CGRect(x: 316, y: 550, width: 0, height: 270)),
      (.bottom, .regular, CGRect(x: 12, y: 758, width: 366, height: 62)),
      (.bottom, .compact, CGRect(x: 12, y: 768, width: 366, height: 52)),
      (.leading, .compact, CGRect(x: 24, y: 550, width: 20, height: 270)),
      (.trailing, .regular, CGRect(x: 316, y: 550, width: 50, height: 270)),
    ]
    for (placement, density) in liveLayouts {
      let thickness = density.barThickness(for: placement)
      replacement.updateLayout(placement: placement, density: density, maximumLength: 270)
      replacement.frame = placement.isVertical
        ? CGRect(x: placement == .leading ? 24 : window.bounds.width - thickness - 24,
          y: window.bounds.height - 294, width: thickness, height: 270)
        : CGRect(x: 12, y: window.bounds.height - thickness - 24,
          width: window.bounds.width - 24, height: thickness)
      replacement.setNeedsLayout()
      replacement.layoutIfNeeded()
      hostedView.layoutIfNeeded()
      XCTAssertEqual(replacement.fabButton.bounds.size,
        CGSize(width: thickness, height: thickness))
      for (oldPlacement, oldDensity, oldFrame) in obsoleteLayouts {
        // The old representable can receive one more layout while SwiftUI
        // changes axis or removes it, including a zero-width proposal.
        obsolete.updateLayout(placement: oldPlacement, density: oldDensity, maximumLength: 270)
        obsolete.frame = oldFrame
        obsolete.setNeedsLayout()
        obsolete.layoutIfNeeded()
        hostedView.layoutIfNeeded()
        let context = "live=\(placement)/\(density), obsolete=\(oldPlacement)/\(oldFrame.size)"
        XCTAssertTrue(hostedView.superview === replacement.fabButton, context)
        XCTAssertEqual(hostedView.frame, replacement.fabButton.bounds, context)
        let center = marker.convert(CGPoint(x: marker.bounds.midX, y: marker.bounds.midY),
          to: replacement.fabButton)
        XCTAssertEqual(center.x, replacement.fabButton.bounds.midX, accuracy: 0.1, context)
        XCTAssertEqual(center.y, replacement.fabButton.bounds.midY, accuracy: 0.1, context)
        assertReceivesTouches(replacement.fabButton, in: window)
      }
    }
    replacement.fabButton.sendActions(for: .touchUpInside)
    XCTAssertEqual(calls, 1)
    XCTAssertEqual(replacement.fabButton.accessibilityLabel, "Add reading")
    withExtendedLifetime((window, controller, obsolete, replacement)) {}
  }

  func testExpandedPrimaryKeepsItsBoundsAndContentCenteredThroughRelayoutAndResize() throws {
    let controller = UIHostingController(rootView: Image(systemName: "plus")
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .ignoresSafeArea())
    let hostedView = try XCTUnwrap(controller.view)
    let marker = UIView()
    marker.isUserInteractionEnabled = false
    marker.translatesAutoresizingMaskIntoConstraints = false
    hostedView.addSubview(marker)
    NSLayoutConstraint.activate([
      marker.centerXAnchor.constraint(equalTo: hostedView.centerXAnchor),
      marker.centerYAnchor.constraint(equalTo: hostedView.centerYAnchor),
      marker.widthAnchor.constraint(equalToConstant: 20),
      marker.heightAnchor.constraint(equalToConstant: 20),
    ])
    let secondary = [FabBarAction(systemImage: "plus", accessibilityLabel: "Add reading", action: {})]
    let subject = makeSubject(secondary: secondary)
    subject.updateAction(FabBarAction(systemImage: "plus", accessibilityLabel: "Precision",
      view: controller, action: {}), secondaryActions: secondary, isSecondaryActionMenuEnabled: true)
    let window = host(subject, placement: .bottom)
    let baselineWindowSubviews = window.subviews.count

    func assertCenteredContent(_ context: String) {
      let expected = subject.fabGlassView.bounds.size
      XCTAssertEqual(subject.fabButton.bounds.size, expected, context)
      XCTAssertEqual(hostedView.frame, subject.fabButton.bounds, context)
      let localCenter = marker.convert(CGPoint(x: marker.bounds.midX, y: marker.bounds.midY),
        to: subject.fabButton)
      XCTAssertEqual(localCenter.x, subject.fabButton.bounds.midX, accuracy: 0.1, context)
      XCTAssertEqual(localCenter.y, subject.fabButton.bounds.midY, accuracy: 0.1, context)
      let markerCenter = marker.convert(CGPoint(x: marker.bounds.midX, y: marker.bounds.midY), to: window)
      let glassCenter = subject.fabGlassView.convert(
        CGPoint(x: subject.fabGlassView.bounds.midX, y: subject.fabGlassView.bounds.midY), to: window)
      XCTAssertEqual(markerCenter.x, glassCenter.x, accuracy: 0.1, context)
      XCTAssertEqual(markerCenter.y, glassCenter.y, accuracy: 0.1, context)
      XCTAssertGreaterThanOrEqual(subject.fabButton.bounds.width, 44, context)
      XCTAssertGreaterThanOrEqual(subject.fabButton.bounds.height, 44, context)
    }

    let layouts: [(FabBarPlacement, FabBarDensity, CGRect, CGRect)] = [
      (.bottom, .regular, CGRect(x: 12, y: 758, width: 366, height: 62),
        CGRect(x: 12, y: 768, width: 366, height: 52)),
      (.bottom, .compact, CGRect(x: 12, y: 768, width: 366, height: 52),
        CGRect(x: 20, y: 768, width: 350, height: 52)),
      (.trailing, .regular, CGRect(x: 316, y: 550, width: 50, height: 270),
        CGRect(x: 316, y: 550, width: 50, height: 220)),
      (.leading, .compact, CGRect(x: 24, y: 550, width: 50, height: 270),
        CGRect(x: 24, y: 550, width: 50, height: 240)),
    ]
    for (placement, density, initialFrame, resizedFrame) in layouts {
      subject.updateLayout(placement: placement, density: density, maximumLength: 270)
      subject.frame = initialFrame
      subject.setNeedsLayout()
      subject.layoutIfNeeded()
      hostedView.layoutIfNeeded()
      assertCenteredContent("Before opening at \(placement)/\(density)")
      subject.fabButton.sendActions(for: .touchUpInside)
      XCTAssertTrue(subject.isExpanded)
      let expandedTransform = subject.fabButton.transform
      XCTAssertNotEqual(expandedTransform, .identity)

      // A normal extra layout pass must preserve square bounds while the
      // native button is rotated, rather than inverse-fitting its frame.
      subject.setNeedsLayout()
      subject.layoutIfNeeded()
      hostedView.layoutIfNeeded()
      XCTAssertTrue(subject.isExpanded)
      XCTAssertEqual(subject.fabButton.transform, expandedTransform)
      assertCenteredContent("Expanded relayout at \(placement)/\(density)")

      // SwiftUI can supply the new frame before updateLayout receives its
      // matching density/axis. This layout closes the old chooser only after
      // positioning its button, so the transform is still nonidentity then.
      subject.frame = resizedFrame
      subject.setNeedsLayout()
      subject.layoutIfNeeded()
      hostedView.layoutIfNeeded()
      XCTAssertFalse(subject.isExpanded)
      XCTAssertEqual(subject.fabButton.transform, .identity)
      assertCenteredContent("Resize collapsed chooser at \(placement)/\(density)")
      XCTAssertEqual(window.subviews.count, baselineWindowSubviews)
      assertReceivesTouches(subject.fabButton, in: window)
    }
    withExtendedLifetime((window, controller, subject)) {}
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

  func testHostedSecondaryLabelsUseTheirIdealTextWidthWithinTheAvailablePane() throws {
    let cases: [(FabBarPlacement, CGSize)] = [
      (.bottom, CGSize(width: 393, height: 852)),
      (.leading, CGSize(width: 440, height: 956)),
      (.trailing, CGSize(width: 240, height: 320)),
    ]
    let labels = ["Start new cycle", "Measurement"]
    let font = UIFont.monospacedSystemFont(ofSize: 16, weight: .medium)
    for (placement, windowSize) in cases {
      for category in [UIContentSizeCategory.large, .accessibilityExtraExtraExtraLarge] {
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
        let window = host(subject, placement: placement, windowSize: windowSize)
        window.traitOverrides.preferredContentSizeCategory = category
        subject.updateTraitsIfNeeded()
        subject.layoutIfNeeded()
        subject.fabButton.sendActions(for: .touchUpInside)
        let menu = try XCTUnwrap(window.subviews.first {
          $0.accessibilityIdentifier == "FabBar.secondaryMenu"
        } as? UIScrollView)
        let windowSafe = window.safeAreaLayoutGuide.layoutFrame
        let safe = windowSafe.insetBy(dx: 12, dy: 12)
        XCTAssertTrue(windowSafe.contains(menu.frame))
        let fab = subject.fabGlassView.convert(subject.fabGlassView.bounds, to: window)
        let availableWidth = placement.isVertical
          ? max(fab.minX - safe.minX - 12, safe.maxX - fab.maxX - 12) : safe.width
        for (index, button) in subject.secondaryButtons.enumerated() {
          let context = "\(placement), \(windowSize), \(category.rawValue), \(labels[index])"
          let buttonFrame = button.convert(button.bounds, to: window)
          XCTAssertGreaterThanOrEqual(buttonFrame.minX, safe.minX - 1, context)
          XCTAssertLessThanOrEqual(buttonFrame.maxX, safe.maxX + 1, context)
          if menu.contentSize.height <= menu.bounds.height + 1 {
            XCTAssertTrue(safe.insetBy(dx: -1, dy: -1).contains(buttonFrame), context)
          }
          XCTAssertLessThanOrEqual(button.bounds.width, availableWidth + 1, context)
          XCTAssertGreaterThanOrEqual(button.bounds.height, 44, context)
          if category.isAccessibilityCategory {
            XCTAssertTrue(controllers[index].view.isHidden, context)
            let nativeTitle = button.configuration?.attributedTitle
            XCTAssertEqual(nativeTitle.map { String($0.characters) }, labels[index], context)
            XCTAssertEqual(button.titleLabel?.numberOfLines, 0, context)
          } else {
            let textWidth = ceil((labels[index] as NSString).size(withAttributes: [.font: font]).width)
            let idealWidth = 24 + 20 + 6 + textWidth
            if idealWidth <= availableWidth {
              XCTAssertGreaterThanOrEqual(button.bounds.width, idealWidth - 1,
                "The visible label must receive its ideal text width when the pane allows it. \(context)")
            } else {
              // A constrained HStack can choose a slightly narrower line break
              // than the proposal. It must still reserve a readable text area
              // and enough height for the wrapped label instead of collapsing.
              XCTAssertGreaterThanOrEqual(controllers[index].view.bounds.width - 26, 44, context)
              XCTAssertGreaterThanOrEqual(controllers[index].view.bounds.height, font.lineHeight * 2 - 1, context)
            }
            XCTAssertGreaterThan(controllers[index].view.bounds.width, 26,
              "Icon and spacing must leave usable width for the visible text. \(context)")
          }
        }
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
    let window = host(subject, placement: .trailing, length: 108,
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

  private func assertReceivesTouches(_ view: UIView, in window: UIWindow,
    file: StaticString = #filePath, line: UInt = #line) {
    let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
    let hit = window.hitTest(point, with: nil)
    XCTAssertTrue(hit === view || hit?.isDescendant(of: view) == true,
      "The visible renderer must receive touches: \(view.accessibilityIdentifier ?? "view")", file: file, line: line)
  }

  private func makeSubject(primary: @escaping () -> Void = {}, secondary: [FabBarAction] = [], tabCount: Int = 4) -> GlassTabBarView {
    let control = FabBarTabControl()
    control.setTabs(["Collection", "Precision", "Feed", "Profile"].prefix(tabCount).enumerated().map { index, title in
      FabBarTabDescriptor(title: title, image: UIImage(systemName: "circle"), accessibilityIdentifier: "tab.\(index)")
    })
    return GlassTabBarView(segmentedControl: control, tabCount: tabCount,
      action: FabBarAction(systemImage: "waveform", accessibilityLabel: "Measure", action: primary),
      secondaryActions: secondary, isSecondaryActionMenuEnabled: !secondary.isEmpty)
  }

  private func host(_ subject: GlassTabBarView, placement: FabBarPlacement, length: CGFloat = 270,
    windowSize: CGSize = CGSize(width: 390, height: 844), density: FabBarDensity = .regular) -> UIWindow {
    let window = UIWindow(frame: CGRect(origin: .zero, size: windowSize))
    window.isHidden = false
    subject.updateLayout(placement: placement, density: density, maximumLength: length)
    let thickness = density.barThickness(for: placement)
    subject.frame = placement.isVertical
      ? CGRect(x: placement == .leading ? 24 : windowSize.width - thickness - 24,
        y: max(12, windowSize.height - length - 24), width: thickness, height: length)
      : CGRect(x: 12, y: windowSize.height - thickness - 24,
        width: windowSize.width - 24, height: thickness)
    window.addSubview(subject)
    window.layoutIfNeeded()
    subject.setNeedsLayout()
    subject.layoutIfNeeded()
    return window
  }
}
