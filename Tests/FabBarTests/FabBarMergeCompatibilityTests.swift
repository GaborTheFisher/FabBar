import SwiftUI
import UIKit
import XCTest
@testable import FabBar

@MainActor
@available(iOS 26.0, *)
final class FabBarMergeCompatibilityTests: XCTestCase {
  func testCompactHorizontalContentAndHostedPrimarySurviveRailRoundTrip() throws {
    let control = FabBarTabControl()
    control.setTabs(descriptors)
    control.selectedSegmentIndex = 1
    let native = control.horizontalControl
    let hosted = UIHostingController(rootView: Color.clear)
    hosted.safeAreaRegions = []
    let hostedView = try XCTUnwrap(hosted.view)
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
    var primaryCalls = 0
    let subject = GlassTabBarView(segmentedControl: control, tabCount: descriptors.count,
      action: FabBarAction(systemImage: "plus", accessibilityLabel: "Measure", view: hosted) {
        primaryCalls += 1
      }, secondaryActions: [], isSecondaryActionMenuEnabled: false)
    let primary = subject.fabButton
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 844))
    window.addSubview(subject)
    window.isHidden = false
    defer { window.isHidden = true }
    var selections: [Int] = []
    control.addAction(UIAction { _ in selections.append(control.selectedSegmentIndex) }, for: .valueChanged)

    func layout(_ placement: FabBarPlacement, density: FabBarDensity) {
      subject.updateLayout(placement: placement, density: density, maximumLength: 220)
      subject.frame = placement.isVertical
        ? CGRect(x: 526, y: 600, width: 50, height: 220)
        : CGRect(x: 20, y: 740,
          width: density == .compact ? subject.intrinsicContentSize.width : 560,
          height: density.barHeight)
      subject.setNeedsLayout()
      subject.layoutIfNeeded()
      hostedView.layoutIfNeeded()
    }
    func assertPrimary(_ context: String) {
      XCTAssertTrue(subject.fabButton === primary, context)
      XCTAssertTrue(hostedView.superview === primary, context)
      XCTAssertEqual(hostedView.frame, primary.bounds, context)
      let center = marker.convert(CGPoint(x: marker.bounds.midX, y: marker.bounds.midY), to: primary)
      XCTAssertEqual(center.x, primary.bounds.midX, accuracy: 0.1, context)
      XCTAssertEqual(center.y, primary.bounds.midY, accuracy: 0.1, context)
      assertReceivesTouches(primary, in: window)
      primary.sendActions(for: .touchUpInside)
    }

    layout(.bottom, density: .compact)
    let labeledWidths = (0..<control.numberOfSegments).map { control.widthForSegment(at: $0) }
    XCTAssertLessThan(subject.bounds.width, 560, "Compact horizontal content must retain its intrinsic width")
    XCTAssertGreaterThan(labeledWidths[1], labeledWidths[0], "Unequal localized labels keep their own widths")
    XCTAssertTrue(control.areInlineTitlesVisible)
    XCTAssertFalse(subject.isCompactContentCollapsed)
    assertPrimary("Initial compact bottom")

    layout(.trailing, density: .compact)
    XCTAssertTrue(control.isVertical)
    XCTAssertTrue(native.isHidden)
    XCTAssertFalse(control.areInlineTitlesVisible)
    XCTAssertFalse(control.isCollapsed)
    XCTAssertEqual(subject.segmentedGlassView.bounds.width, 50, accuracy: 0.1)
    XCTAssertEqual(primary.bounds.size, CGSize(width: 50, height: 50))
    for button in control.buttons {
      XCTAssertNil(button.configuration?.attributedTitle, "Inline labels must not change the side rail")
      assertReceivesTouches(button, in: window)
    }
    control.buttons[2].sendActions(for: .touchUpInside)
    assertPrimary("Compact side rail")

    layout(.bottom, density: .compact)
    XCTAssertTrue(control.horizontalControl === native)
    XCTAssertFalse(native.isHidden)
    XCTAssertEqual(control.selectedSegmentIndex, 2)
    XCTAssertEqual(native.selectedSegmentIndex, 2)
    XCTAssertTrue(control.areInlineTitlesVisible)
    XCTAssertEqual((0..<control.numberOfSegments).map { control.widthForSegment(at: $0) }, labeledWidths)
    assertReceivesTouches(native, in: window)
    assertPrimary("Returned compact bottom")

    layout(.bottom, density: .regular)
    XCTAssertTrue(control.horizontalControl === native)
    XCTAssertEqual(control.selectedSegmentIndex, 2)
    XCTAssertEqual((0..<control.numberOfSegments).map { control.widthForSegment(at: $0) }, [0, 0, 0])
    XCTAssertEqual(subject.bounds.width, 560, accuracy: 0.1)
    assertReceivesTouches(native, in: window)
    assertPrimary("Regular bottom")
    XCTAssertEqual(selections, [2], "Only the real tab action may change selection")
    XCTAssertEqual(primaryCalls, 4, "Axis and density changes must retain the primary action callback")
    withExtendedLifetime((window, hosted, subject)) {}
  }

  func testCompactRTLSegmentEdgesRouteToTheirLogicalDestination() throws {
    let control = FabBarTabControl()
    control.semanticContentAttribute = .forceRightToLeft
    control.horizontalControl.semanticContentAttribute = .forceRightToLeft
    control.setTabs(descriptors)
    control.density = .compact
    let subject = GlassTabBarView(segmentedControl: control, tabCount: descriptors.count,
      action: FabBarAction(systemImage: "plus", accessibilityLabel: "Measure", action: {}),
      secondaryActions: [], isSecondaryActionMenuEnabled: false)
    subject.semanticContentAttribute = .forceRightToLeft
    subject.updateLayout(placement: .bottom, density: .compact, maximumLength: nil)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 844))
    window.semanticContentAttribute = .forceRightToLeft
    subject.frame = CGRect(x: 20, y: 740, width: subject.intrinsicContentSize.width, height: 52)
    window.addSubview(subject)
    window.isHidden = false
    defer { window.isHidden = true }
    window.layoutIfNeeded()
    subject.setNeedsLayout()
    subject.layoutIfNeeded()
    let native = control.horizontalControl
    let frames = native.segmentFramesInControlCoordinates()
    XCTAssertEqual(frames.count, 3)
    guard frames.count == 3 else { return }
    XCTAssertGreaterThan(frames[0].midX, frames[2].midX, "RTL geometry must retain logical item order")
    XCTAssertGreaterThan(frames[1].width, frames[0].width)
    for (logicalIndex, frame) in frames.enumerated() {
      for x in [frame.minX + 1, frame.midX, frame.maxX - 1] {
        XCTAssertEqual(native.segmentIndex(at: CGPoint(x: x, y: frame.midY)), logicalIndex,
          "A touch inside a wide segment must not choose its nearer neighbor")
      }
    }
    var selections: [Int] = []
    control.addAction(UIAction { _ in selections.append(control.selectedSegmentIndex) }, for: .valueChanged)
    let lastDestination = try XCTUnwrap(native.accessibilityElement(at: 2) as? UIAccessibilityElement)
    XCTAssertTrue(lastDestination.accessibilityActivate())
    XCTAssertEqual(control.selectedSegmentIndex, 2)
    XCTAssertEqual(selections, [2])
    withExtendedLifetime((window, subject)) {}
  }

  private var descriptors: [FabBarTabDescriptor] {
    [
      FabBarTabDescriptor(title: "Home", image: UIImage(systemName: "house"), accessibilityIdentifier: "home"),
      FabBarTabDescriptor(title: "Communities", image: UIImage(systemName: "person.3"), accessibilityIdentifier: "communities"),
      FabBarTabDescriptor(title: "Profile", image: UIImage(systemName: "person"), accessibilityIdentifier: "profile"),
    ]
  }

  private func assertReceivesTouches(_ view: UIView, in window: UIWindow,
    file: StaticString = #filePath, line: UInt = #line) {
    let point = view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: window)
    let hit = window.hitTest(point, with: nil)
    XCTAssertTrue(hit === view || hit?.isDescendant(of: view) == true,
      "The visible control must receive its real window hit", file: file, line: line)
  }
}
