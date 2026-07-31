import SwiftUI
import UIKit
import XCTest
@testable import FabBar

@MainActor
@available(iOS 26.0, *)
final class FabBarModifierLayoutTests: XCTestCase {
  func testRegularWidthKeepsPrimaryTabNavigationVisibleAndCappedByDefault() {
    XCTAssertTrue(
      FabBarModifierLayout.showsBar(
        isVisible: true,
        horizontalSizeClass: .regular,
        regularWidthBehavior: .visible
      )
    )
    XCTAssertEqual(
      FabBarModifierLayout.maximumBarWidth(horizontalSizeClass: .regular),
      Constants.regularWidthMaximumBarWidth
    )
  }

  func testRegularWidthCanHideOnlyThroughExplicitAlternativeNavigationBehavior() {
    XCTAssertFalse(
      FabBarModifierLayout.showsBar(
        isVisible: true,
        horizontalSizeClass: .regular,
        regularWidthBehavior: .hiddenWhenAlternativeNavigationIsProvided
      )
    )
  }

  func testCompactWidthRemainsVisibleAndUncapped() {
    XCTAssertTrue(
      FabBarModifierLayout.showsBar(
        isVisible: true,
        horizontalSizeClass: .compact,
        regularWidthBehavior: .hiddenWhenAlternativeNavigationIsProvided
      )
    )
    XCTAssertEqual(
      FabBarModifierLayout.maximumBarWidth(horizontalSizeClass: .compact),
      .infinity
    )
  }

  func testSafeAreaPaddingUsesRenderedFrameForBothDensities() {
    let regularFrame = CGRect(
      x: 0,
      y: 0,
      width: 390,
      height: FabBarDensity.regular.barHeight + Constants.bottomPadding
    )
    let compactFrame = CGRect(
      x: 0,
      y: 0,
      width: 390,
      height: FabBarDensity.compact.barHeight + Constants.bottomPadding
    )

    XCTAssertEqual(
      FabBarModifierLayout.bottomSafeAreaPadding(
        showsBar: true,
        renderedBarFrame: regularFrame,
        bottomSafeAreaInset: 34
      ),
      49
    )
    XCTAssertEqual(
      FabBarModifierLayout.bottomSafeAreaPadding(
        showsBar: true,
        renderedBarFrame: compactFrame,
        bottomSafeAreaInset: 34
      ),
      39
    )
  }

  func testHiddenBarPublishesNoObstruction() {
    XCTAssertEqual(
      FabBarModifierLayout.bottomSafeAreaPadding(
        showsBar: false,
        renderedBarFrame: CGRect(x: 0, y: 0, width: 390, height: 83),
        bottomSafeAreaInset: 34
      ),
      0
    )
  }

  func testRecommendedModifierKeepsRegularWidthBarVisibleAndCapped() {
    var selection = 0
    let rootView = Color.clear
      .fabBar(
        selection: Binding(get: { selection }, set: { selection = $0 }),
        tabs: makeTabs(),
        action: makeAction()
      )
      .environment(\.horizontalSizeClass, .regular)
    let (window, controller) = host(rootView, size: CGSize(width: 1_024, height: 768))

    let bar = waitForBar(in: controller.view)

    XCTAssertNotNil(bar)
    XCTAssertEqual(
      bar?.bounds.width ?? 0,
      Constants.regularWidthMaximumBarWidth,
      accuracy: 0.5
    )
    let barFrame = bar?.convert(bar?.bounds ?? .zero, to: window) ?? .zero
    XCTAssertEqual(barFrame.midX, window.bounds.midX, accuracy: 0.5)
    withExtendedLifetime(window) {}
  }

  func testRecommendedModifierForwardsCompactDensityAndSecondaryActions() {
    var selection = 0
    let rootView = Color.clear
      .fabBar(
        selection: Binding(get: { selection }, set: { selection = $0 }),
        tabs: makeTabs(),
        action: makeAction(),
        secondaryActions: [
          FabBarAction(
            systemImage: "square.and.pencil",
            accessibilityLabel: "Secondary",
            action: {}
          )
        ],
        density: .compact
      )
      .environment(\.horizontalSizeClass, .compact)
    let (window, controller) = host(rootView, size: CGSize(width: 390, height: 844))
    guard let bar = waitForBar(in: controller.view) else {
      XCTFail("The recommended modifier did not mount GlassTabBarView")
      return
    }

    XCTAssertEqual(bar.bounds.height, FabBarDensity.compact.barHeight, accuracy: 0.5)
    bar.fabButton.sendActions(for: .touchUpInside)
    XCTAssertTrue(bar.isExpanded)
    withExtendedLifetime(window) {}
  }

  private func makeTabs() -> [FabBarTab<Int>] {
    [
      FabBarTab(value: 0, title: "First", systemImage: "circle"),
      FabBarTab(value: 1, title: "Second", systemImage: "square"),
      FabBarTab(value: 2, title: "Third", systemImage: "triangle"),
    ]
  }

  private func makeAction() -> FabBarAction {
    FabBarAction(systemImage: "plus", accessibilityLabel: "Primary", action: {})
  }

  private func host<Content: View>(
    _ rootView: Content,
    size: CGSize
  ) -> (UIWindow, UIHostingController<Content>) {
    let controller = UIHostingController(rootView: rootView)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = controller
    window.isHidden = false
    window.layoutIfNeeded()
    controller.view.setNeedsLayout()
    controller.view.layoutIfNeeded()
    return (window, controller)
  }

  private func waitForBar(in root: UIView, timeout: TimeInterval = 2) -> GlassTabBarView? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if let bar = findSubview(of: GlassTabBarView.self, in: root) {
        return bar
      }
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    } while Date() < deadline
    return nil
  }

  private func findSubview<T: UIView>(of type: T.Type, in root: UIView) -> T? {
    if let match = root as? T { return match }
    for subview in root.subviews {
      if let match = findSubview(of: type, in: subview) {
        return match
      }
    }
    return nil
  }
}
