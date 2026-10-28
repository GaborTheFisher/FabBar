import UIKit
import SwiftUI
import XCTest
@testable import FabBar

@MainActor
@available(iOS 26.0, *)
final class GlassTabBarViewTests: XCTestCase {
  func testDirectModeExecutesPrimaryActionWithoutExpanding() {
    var primaryCallCount = 0
    let subject = makeSubject(
      isSecondaryActionMenuEnabled: false,
      primaryAction: { primaryCallCount += 1 }
    )
    let window = host(subject)

    subject.fabButton.sendActions(for: .touchUpInside)

    XCTAssertEqual(primaryCallCount, 1)
    XCTAssertFalse(subject.isExpanded)
    withExtendedLifetime(window) {}
  }

  func testMenuModeExecutesPrimaryActionAndExpands() {
    var primaryCallCount = 0
    let subject = makeSubject(
      isSecondaryActionMenuEnabled: true,
      primaryAction: { primaryCallCount += 1 }
    )
    let window = host(subject)

    subject.fabButton.sendActions(for: .touchUpInside)

    XCTAssertEqual(primaryCallCount, 1)
    XCTAssertTrue(subject.isExpanded)
    withExtendedLifetime(window) {}
  }

  func testDisablingMenuCollapsesAndUsesUpdatedPrimaryAction() {
    var originalCallCount = 0
    var updatedCallCount = 0
    let subject = makeSubject(
      isSecondaryActionMenuEnabled: true,
      primaryAction: { originalCallCount += 1 }
    )
    let window = host(subject)
    subject.fabButton.sendActions(for: .touchUpInside)
    XCTAssertTrue(subject.isExpanded)

    subject.updatePrimaryAction(
      { updatedCallCount += 1 },
      isSecondaryActionMenuEnabled: false
    )
    subject.fabButton.sendActions(for: .touchUpInside)

    XCTAssertFalse(subject.isExpanded)
    XCTAssertEqual(originalCallCount, 1)
    XCTAssertEqual(updatedCallCount, 1)
    withExtendedLifetime(window) {}
  }

  func testDensityHeightChangeInSameWindowCollapsesExpandedMenu() {
    let subject = makeSubject(
      isSecondaryActionMenuEnabled: true,
      primaryAction: {}
    )
    let window = host(subject)
    subject.fabButton.sendActions(for: .touchUpInside)
    XCTAssertTrue(subject.isExpanded)

    subject.frame.size.height = FabBarDensity.compact.barHeight
    subject.setNeedsLayout()
    subject.layoutIfNeeded()

    XCTAssertFalse(subject.isExpanded)
    withExtendedLifetime(window) {}
  }

  func testContainerMoveInSameWindowCollapsesExpandedMenu() {
    let subject = makeSubject(
      isSecondaryActionMenuEnabled: true,
      primaryAction: {}
    )
    let window = host(subject)
    subject.fabButton.sendActions(for: .touchUpInside)
    XCTAssertTrue(subject.isExpanded)

    subject.frame.origin.x += 20
    subject.setNeedsLayout()
    subject.layoutIfNeeded()

    XCTAssertFalse(subject.isExpanded)
    withExtendedLifetime(window) {}
  }

  func testExpandedHostedContentReceivesWindowTraitsBeforeResizeCollapsesMenu() {
    let record = TraitRecord()
    let hostedController = UIHostingController(
      rootView: TraitProbeView(record: record)
    )
    let subject = makeSubject(
      secondaryAction: FabBarAction(
        systemImage: "square.and.pencil",
        accessibilityLabel: "Secondary",
        view: hostedController,
        action: {}
      ),
      isSecondaryActionMenuEnabled: true,
      primaryAction: {}
    )
    let window = host(subject)
    window.traitOverrides.verticalSizeClass = .regular
    window.layoutIfNeeded()
    subject.fabButton.sendActions(for: .touchUpInside)
    XCTAssertTrue(subject.isExpanded)

    window.traitOverrides.verticalSizeClass = .compact
    window.layoutIfNeeded()
    XCTAssertTrue(waitUntil { record.verticalSizeClasses.contains(.compact) })
    XCTAssertTrue(subject.isExpanded)

    window.frame.size.height = 700
    window.layoutIfNeeded()
    subject.setNeedsLayout()
    subject.layoutIfNeeded()

    XCTAssertFalse(subject.isExpanded)
    withExtendedLifetime((window, hostedController)) {}
  }

  func testRemovingExpandedBarCleansWindowHostedBackdropAndPills() {
    let subject = makeSubject(
      isSecondaryActionMenuEnabled: true,
      primaryAction: {}
    )
    let window = host(subject)
    subject.fabButton.sendActions(for: .touchUpInside)

    XCTAssertTrue(subject.isExpanded)
    XCTAssertGreaterThan(window.subviews.count, 1)

    subject.removeFromSuperview()

    XCTAssertNil(subject.window)
    XCTAssertFalse(subject.isExpanded)
    XCTAssertTrue(window.subviews.isEmpty)
    withExtendedLifetime(window) {}
  }

  func testSwitchingToCompactDensityCollapsesAndPublishesContentWidth() {
    let control = FabBarTabControl()
    control.setTabs([
      FabBarTabDescriptor(title: "First", image: UIImage(systemName: "circle"), accessibilityIdentifier: "first"),
      FabBarTabDescriptor(title: "Longer second", image: UIImage(systemName: "square"), accessibilityIdentifier: "second"),
      FabBarTabDescriptor(title: "Third", image: UIImage(systemName: "triangle"), accessibilityIdentifier: "third"),
    ])
    let subject = GlassTabBarView(
      segmentedControl: control,
      tabCount: control.numberOfSegments,
      action: FabBarAction(systemImage: "plus", accessibilityLabel: "Primary", action: {}),
      secondaryActions: [
        FabBarAction(systemImage: "square.and.pencil", accessibilityLabel: "Secondary", action: {})
      ],
      isSecondaryActionMenuEnabled: true
    )
    let window = host(subject)
    subject.fabButton.sendActions(for: .touchUpInside)
    XCTAssertTrue(subject.isExpanded)

    subject.updateDensity(.compact)

    XCTAssertFalse(subject.isExpanded)
    let widths = control.preferredCompactSegmentWidths
    XCTAssertEqual(widths.count, 3)
    XCTAssertGreaterThan(widths[1], widths[0])
    XCTAssertEqual(
      subject.intrinsicContentSize.width,
      widths.reduce(0, +)
        + Constants.contentPadding * 2
        + Constants.fabSpacing
        + FabBarDensity.compact.barHeight,
      accuracy: 0.5
    )
    withExtendedLifetime(window) {}
  }

  func testVariableWidthSegmentsResolveTouchesFromTheirActualFrames() {
    let control = TabBarSegmentedControl(
      items: [
        UIImage(systemName: "circle")!,
        UIImage(systemName: "square")!,
        UIImage(systemName: "triangle")!,
      ]
    )
    for (index, width) in [CGFloat(62), 126, 78].enumerated() {
      control.setWidth(width, forSegmentAt: index)
    }
    control.frame = CGRect(x: 20, y: 100, width: 266, height: 48)
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.addSubview(control)
    window.layoutIfNeeded()
    control.layoutIfNeeded()

    let frames = control.segmentFramesInControlCoordinates()
    XCTAssertEqual(frames.count, 3)
    XCTAssertGreaterThan(frames[1].width, frames[0].width)
    for (index, frame) in frames.enumerated() {
      for x in [frame.minX + 1, frame.midX, frame.maxX - 1] {
        XCTAssertEqual(control.segmentIndex(at: CGPoint(x: x, y: frame.midY)), index)
      }
    }
    withExtendedLifetime(window) {}
  }

  private func makeSubject(
    secondaryAction: FabBarAction? = nil,
    isSecondaryActionMenuEnabled: Bool,
    primaryAction: @escaping () -> Void
  ) -> GlassTabBarView {
    let control = FabBarTabControl()
    control.setTabs([FabBarTabDescriptor(title: "Collection",
      image: UIImage(systemName: "circle"), accessibilityIdentifier: "collection")])
    return GlassTabBarView(
      segmentedControl: control,
      tabCount: 1,
      action: FabBarAction(
        systemImage: "plus",
        accessibilityLabel: "Primary",
        action: primaryAction
      ),
      secondaryActions: [
        secondaryAction ?? FabBarAction(
          systemImage: "square.and.pencil",
          accessibilityLabel: "Secondary",
          action: {}
        )
      ],
      isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled
    )
  }

  private func host(_ subject: GlassTabBarView) -> UIWindow {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    subject.frame = CGRect(x: 16, y: 760, width: 358, height: 62)
    window.addSubview(subject)
    window.layoutIfNeeded()
    return window
  }

  private func waitUntil(
    timeout: TimeInterval = 2,
    condition: () -> Bool
  ) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), RunLoop.current.run(mode: .default, before: deadline) {}
    return condition()
  }

  private final class TraitRecord {
    var verticalSizeClasses: [UserInterfaceSizeClass?] = []
  }

  private struct TraitProbeView: View {
    let record: TraitRecord

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
      Color.clear
        .frame(width: 44, height: 44)
        .onAppear {
          record.verticalSizeClasses.append(verticalSizeClass)
        }
        .onChange(of: verticalSizeClass) { _, newValue in
          record.verticalSizeClasses.append(newValue)
        }
    }
  }
}
