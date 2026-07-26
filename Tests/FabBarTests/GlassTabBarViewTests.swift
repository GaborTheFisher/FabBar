import UIKit
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

  private func makeSubject(
    isSecondaryActionMenuEnabled: Bool,
    primaryAction: @escaping () -> Void
  ) -> GlassTabBarView {
    let control = TabBarSegmentedControl(
      items: [UIImage(systemName: "circle")!]
    )
    return GlassTabBarView(
      segmentedControl: control,
      tabCount: 1,
      action: FabBarAction(
        systemImage: "plus",
        accessibilityLabel: "Primary",
        action: primaryAction
      ),
      secondaryActions: [
        FabBarAction(
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
}
