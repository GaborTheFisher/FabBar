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
  func testResolvedImageAndPresentationUpdateSurviveInlineArchiving() throws {
    let subject = TabItemContentView(title: "Home", image: UIImage(systemName: "house"))
    subject.update(title: "A longer collection", image: UIImage(systemName: "clock"), layout: .inline)
    let ideal = subject.intrinsicContentSize
    subject.setShowsInlineTitle(false)
    XCTAssertEqual(subject.intrinsicContentSize, ideal,
      "Collapsing a narrow inline title must preserve its ideal for widening")

    let data = try NSKeyedArchiver.archivedData(withRootObject: subject, requiringSecureCoding: false)
    let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchiveTopLevelObjectWithData(data) as? TabItemContentView)
    XCTAssertEqual(decoded.layout, .inline)
    XCTAssertFalse(decoded.showsInlineTitle)
    XCTAssertEqual(decoded.intrinsicContentSize, ideal)
    XCTAssertTrue(decoded.isHidden)

    subject.update(title: "Home", image: UIImage(systemName: "house"), layout: .stacked)
    XCTAssertEqual(subject.layout, .stacked)
    XCTAssertGreaterThan(subject.intrinsicContentSize.height, ideal.height)
  }

}
