import SwiftUI
import XCTest
@testable import FabBar

@MainActor
@available(iOS 26.0, *)
final class FabBarPlacementTests: XCTestCase {
  func testAutomaticPlacementUsesThePreferredEdgeWithoutDeviceAssumptions() {
    XCTAssertEqual(FabBarPlacement.automatic.resolved(preferredVerticalEdge: nil), .bottom)
    XCTAssertEqual(FabBarPlacement.automatic.resolved(preferredVerticalEdge: .leading), .leading)
    XCTAssertEqual(FabBarPlacement.automatic.resolved(preferredVerticalEdge: .trailing), .trailing)
    XCTAssertEqual(FabBarPlacement.bottom.resolved(preferredVerticalEdge: .leading), .bottom)
    XCTAssertEqual(FabBarPlacement.trailing.resolved(preferredVerticalEdge: nil), .trailing)
  }

  func testSideRailRetainsAllDestinationsWhenThereIsRoom() {
    XCTAssertEqual(FabBarLayoutPolicy.verticalLength(
      tabCount: 4, density: .regular, maximumLength: 600), 318)
    XCTAssertEqual(FabBarLayoutPolicy.verticalLength(
      tabCount: 4, density: .compact, maximumLength: 300), 268)
  }

  func testShortRailKeepsSeparateNavigationAndActionHitRegions() {
    XCTAssertEqual(FabBarLayoutPolicy.verticalLength(
      tabCount: 4, density: .regular, maximumLength: 240), 132)
    XCTAssertEqual(FabBarLayoutPolicy.verticalLength(
      tabCount: 4, density: .compact, maximumLength: 220), 112)
  }

  func testRailCompressionBoundaryTriplets() {
    for length in [CGFloat(317), 318, 319] {
      XCTAssertEqual(FabBarLayoutPolicy.verticalLength(
        tabCount: 4, density: .regular, maximumLength: length), length < 318 ? 132 : 318)
    }
    for length in [CGFloat(267), 268, 269] {
      XCTAssertEqual(FabBarLayoutPolicy.verticalLength(
        tabCount: 4, density: .compact, maximumLength: length), length < 268 ? 112 : 268)
    }
  }

  func testUnknownLengthDoesNotPrematurelyCollapseNavigation() {
    for length in [CGFloat?.none, .some(0), .some(.nan), .some(.infinity)] {
      XCTAssertEqual(FabBarLayoutPolicy.verticalLength(
        tabCount: 4, density: .regular, maximumLength: length), 318)
    }
  }

  func testMeasuredClearanceUsesTheSelectedEdgeAndLocalCoordinateScale() {
    let host = CGRect(x: 10, y: 20, width: 200, height: 400)
    let size = CGSize(width: 400, height: 800)
    let bottom = FabBarModifierLayout.safeAreaInsets(
      placement: .bottom, renderedBarFrame: CGRect(x: 30, y: 360, width: 160, height: 40),
      hostFrame: host, hostSize: size, layoutDirection: .leftToRight)
    XCTAssertEqual(bottom.bottom, 120)
    XCTAssertEqual(bottom.leading, 0)
    XCTAssertEqual(bottom.trailing, 0)

    let leading = FabBarModifierLayout.safeAreaInsets(
      placement: .leading, renderedBarFrame: CGRect(x: 20, y: 100, width: 30, height: 300),
      hostFrame: host, hostSize: size, layoutDirection: .leftToRight)
    XCTAssertEqual(leading.leading, 80)
    XCTAssertEqual(leading.bottom, 0)
    XCTAssertEqual(leading.trailing, 0)

    let trailing = FabBarModifierLayout.safeAreaInsets(
      placement: .trailing, renderedBarFrame: CGRect(x: 170, y: 100, width: 30, height: 300),
      hostFrame: host, hostSize: size, layoutDirection: .leftToRight)
    XCTAssertEqual(trailing.trailing, 80)
    XCTAssertEqual(trailing.bottom, 0)
    XCTAssertEqual(trailing.leading, 0)
  }

  func testLogicalEdgesResolveRightToLeftExactlyOnce() {
    let host = CGRect(x: 0, y: 0, width: 400, height: 800)
    let leading = FabBarModifierLayout.safeAreaInsets(
      placement: .leading, renderedBarFrame: CGRect(x: 310, y: 100, width: 62, height: 600),
      hostFrame: host, hostSize: host.size, layoutDirection: .rightToLeft)
    XCTAssertEqual(leading.leading, 90)
    XCTAssertEqual(leading.trailing, 0)

    let trailing = FabBarModifierLayout.safeAreaInsets(
      placement: .trailing, renderedBarFrame: CGRect(x: 28, y: 100, width: 62, height: 600),
      hostFrame: host, hostSize: host.size, layoutDirection: .rightToLeft)
    XCTAssertEqual(trailing.trailing, 90)
    XCTAssertEqual(trailing.leading, 0)
  }

  func testSideRailInsideEitherExistingReservedStripAddsNoContentClearance() {
    let host = CGRect(x: 96, y: 76, width: 208, height: 704)
    for (placement, direction, rail) in [
      (FabBarPlacement.leading, LayoutDirection.leftToRight, CGRect(x: 16, y: 400, width: 62, height: 256)),
      (.trailing, .rightToLeft, CGRect(x: 16, y: 400, width: 62, height: 256)),
      (.trailing, .leftToRight, CGRect(x: 322, y: 400, width: 62, height: 256)),
      (.leading, .rightToLeft, CGRect(x: 322, y: 400, width: 62, height: 256))
    ] {
      XCTAssertEqual(FabBarModifierLayout.safeAreaInsets(placement: placement,
        renderedBarFrame: rail, hostFrame: host, hostSize: host.size,
        layoutDirection: direction), EdgeInsets())
    }
  }

  func testAbsentOrDetachedFrameDoesNotReserveContent() {
    let host = CGRect(x: 0, y: 0, width: 400, height: 800)
    let insets = FabBarModifierLayout.safeAreaInsets(
      placement: .trailing, renderedBarFrame: CGRect(x: 600, y: 0, width: 62, height: 318),
      hostFrame: host, hostSize: host.size, layoutDirection: .leftToRight)
    XCTAssertEqual(insets, EdgeInsets())
  }
}
