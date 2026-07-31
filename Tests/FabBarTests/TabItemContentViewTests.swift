import UIKit
import XCTest
@testable import FabBar

@MainActor
@available(iOS 26.0, *)
final class TabItemContentViewTests: XCTestCase {
  func testInlineLayoutPlacesTheSameContentInAWiderShorterFootprint() {
    let stacked = TabItemContentView(
      title: "Communities",
      symbolName: "person.3",
      layout: .stacked
    )
    let inline = TabItemContentView(
      title: "Communities",
      symbolName: "person.3",
      layout: .inline
    )

    XCTAssertGreaterThan(inline.intrinsicContentSize.width, stacked.intrinsicContentSize.width)
    XCTAssertLessThan(inline.intrinsicContentSize.height, stacked.intrinsicContentSize.height)
    XCTAssertEqual(inline.layout, .inline)
  }

  func testAccessibilityArchivePreservesInlineLayout() throws {
    let subject = TabItemContentView(
      title: "Updates",
      symbolName: "circle.dashed.inset.filled",
      layout: .inline
    )

    let data = try NSKeyedArchiver.archivedData(
      withRootObject: subject,
      requiringSecureCoding: false
    )
    let decoded = try XCTUnwrap(
      NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? TabItemContentView
    )

    XCTAssertEqual(decoded.layout, .inline)
    XCTAssertTrue(decoded.isHidden, "Archived popover copies must leave native labels visible")
  }
}
