import UIKit
import XCTest
@testable import FabBar

@MainActor
@available(iOS 26.0, *)
final class FabBarTabControlTests: XCTestCase {
  func testButtonsDispatchSelectionAndReselectionOnBothAxes() {
    for vertical in [false, true] {
      let subject = makeSubject()
      subject.isVertical = vertical
      subject.frame = vertical
        ? CGRect(x: 0, y: 0, width: 58, height: 244)
        : CGRect(x: 0, y: 0, width: 300, height: 58)
      subject.layoutIfNeeded()
      var selected: [Int] = []
      var reselected: [Int] = []
      subject.addAction(UIAction { _ in selected.append(subject.selectedSegmentIndex) }, for: .valueChanged)
      subject.onReselect = { reselected.append($0) }

      subject.buttons[2].sendActions(for: .touchUpInside)
      subject.buttons[2].sendActions(for: .touchUpInside)

      XCTAssertEqual(selected, [2])
      XCTAssertEqual(reselected, [2])
      XCTAssertTrue(subject.buttons[2].isSelected)
      XCTAssertTrue(subject.buttons[2].accessibilityTraits.contains(.selected))
      XCTAssertFalse(subject.buttons[0].accessibilityTraits.contains(.selected))
      XCTAssertEqual(subject.buttons.map(\.accessibilityIdentifier), ["tab.0", "tab.1", "tab.2", "tab.3"])
      XCTAssertTrue(subject.accessibilityTraits.contains(.tabBar))
      XCTAssertTrue(subject.buttons.allSatisfy { $0.bounds.width >= 44 && $0.bounds.height >= 44 })
    }
  }

  func testAxisAndPresentationUpdatesPreserveButtonIdentityAndSelection() {
    let subject = makeSubject()
    subject.selectedSegmentIndex = 2
    let identities = subject.buttons.map(ObjectIdentifier.init)

    subject.isVertical = true
    subject.frame = CGRect(x: 0, y: 0, width: 58, height: 244)
    subject.layoutIfNeeded()
    subject.setTabs(makeTabs(prefix: "Updated"))
    subject.isVertical = false
    subject.frame = CGRect(x: 0, y: 0, width: 300, height: 58)
    subject.layoutIfNeeded()

    XCTAssertEqual(subject.buttons.map(ObjectIdentifier.init), identities)
    XCTAssertEqual(subject.selectedSegmentIndex, 2)
    XCTAssertEqual(subject.buttons[2].accessibilityLabel, "Updated Feed")
    XCTAssertEqual(subject.buttons[2].largeContentTitle, "Updated Feed")
    XCTAssertTrue(subject.buttons[2].showsLargeContentViewer)
  }

  func testCollapsedNativeMenuSelectsEveryDestinationAndSupportsReselect() throws {
    let subject = makeSubject()
    subject.isVertical = true
    subject.isCollapsed = true
    subject.selectedSegmentIndex = 1
    var changes: [Int] = []
    var reselects: [Int] = []
    subject.addAction(UIAction { _ in changes.append(subject.selectedSegmentIndex) }, for: .valueChanged)
    subject.onReselect = { reselects.append($0) }
    let button = subject.navigationMenuButton
    XCTAssertEqual(button.accessibilityIdentifier, "FabBar.navigationMenu")
    XCTAssertEqual(button.accessibilityLabel, "Precision")
    XCTAssertTrue(button.showsMenuAsPrimaryAction)
    XCTAssertEqual(subject.accessibilityElements?.count, 1)
    XCTAssertTrue((subject.accessibilityElements?.first as? UIButton) === button)
    let firstMenu = try XCTUnwrap(button.menu?.children as? [UIAction])
    XCTAssertEqual(firstMenu.map(\.title), ["Collection", "Precision", "Feed", "Profile"])
    XCTAssertEqual(firstMenu.filter { $0.state == .on }.map(\.title), ["Precision"])

    button.sendAction(firstMenu[2])
    let updatedMenu = try XCTUnwrap(button.menu?.children as? [UIAction])
    button.sendAction(updatedMenu[2])

    XCTAssertEqual(changes, [2])
    XCTAssertEqual(reselects, [2])
    XCTAssertEqual(subject.selectedSegmentIndex, 2)
    XCTAssertEqual(button.accessibilityLabel, "Feed")
    XCTAssertEqual(updatedMenu.filter { $0.state == .on }.map(\.title), ["Feed"])
  }

  func testUnchangedDescriptorsPreserveAnOpenNativeMenu() {
    let subject = makeSubject()
    subject.isCollapsed = true
    let menu = subject.navigationMenuButton.menu

    subject.setTabs(makeTabs())
    let currentSelection = subject.selectedSegmentIndex
    let currentTint = subject.activeTintColor
    subject.selectedSegmentIndex = currentSelection
    subject.activeTintColor = currentTint

    XCTAssertTrue(subject.navigationMenuButton.menu === menu)
  }

  func testLargestDynamicTypeKeepsLocalizedLabelsAndLargeContentWhileIconsFit() {
    let subject = makeSubject(category: .accessibilityExtraExtraExtraLarge)
    subject.frame = CGRect(x: 0, y: 0, width: 300, height: 48)
    subject.layoutIfNeeded()

    XCTAssertEqual(subject.traitCollection.preferredContentSizeCategory, .accessibilityExtraExtraExtraLarge)
    XCTAssertTrue(subject.buttons.allSatisfy { $0.configuration?.attributedTitle == nil })
    XCTAssertEqual(subject.buttons.map(\.accessibilityLabel), ["Collection", "Precision", "Feed", "Profile"])
    XCTAssertEqual(subject.buttons.map(\.largeContentTitle), ["Collection", "Precision", "Feed", "Profile"])
    XCTAssertTrue(subject.buttons.allSatisfy { $0.configuration?.image != nil })
    XCTAssertTrue(subject.buttons.allSatisfy { $0.bounds.height >= 44 })
  }

  func testRTLReversesHorizontalPositionsWithoutReversingLogicalValues() {
    let subject = makeSubject()
    subject.semanticContentAttribute = .forceRightToLeft
    subject.frame = CGRect(x: 0, y: 0, width: 300, height: 58)
    subject.layoutIfNeeded()

    let firstFrame = subject.buttons[0].convert(subject.buttons[0].bounds, to: subject)
    let lastFrame = subject.buttons[3].convert(subject.buttons[3].bounds, to: subject)
    XCTAssertGreaterThan(firstFrame.minX, lastFrame.minX)
    subject.buttons[0].sendActions(for: .touchUpInside)
    XCTAssertEqual(subject.selectedSegmentIndex, 0)
  }

  func testLocalizedTitlesFallBackToIconsAtMeasuredCompactWidthAndRestoreAfterResize() {
    let subject = makeSubject()
    let titles = ["Uhrensammlung", "Präzisionsmessungen", "Wristshot Feed", "Mein Profil"]
    subject.setTabs(titles.enumerated().map { index, title in
      FabBarTabDescriptor(title: title, image: UIImage(systemName: "circle"), accessibilityIdentifier: "tab.\(index)")
    })
    let identities = subject.buttons.map(ObjectIdentifier.init)
    subject.frame = CGRect(x: 0, y: 0, width: 900, height: 58)
    subject.layoutIfNeeded()
    XCTAssertTrue(subject.buttons.allSatisfy { $0.configuration?.attributedTitle != nil })

    subject.frame = CGRect(x: 0, y: 0, width: 256, height: 48)
    subject.setNeedsLayout()
    subject.layoutIfNeeded()
    XCTAssertTrue(subject.buttons.allSatisfy { $0.configuration?.attributedTitle == nil })
    XCTAssertEqual(subject.buttons.map(\.accessibilityLabel), titles)
    XCTAssertEqual(subject.buttons.map(\.largeContentTitle), titles)

    subject.frame = CGRect(x: 0, y: 0, width: 900, height: 58)
    subject.setNeedsLayout()
    subject.layoutIfNeeded()
    XCTAssertTrue(subject.buttons.allSatisfy { $0.configuration?.attributedTitle != nil })
    XCTAssertEqual(subject.buttons.map(ObjectIdentifier.init), identities)
  }

  func testDragPreviewsThenCommitsOnceAndCancelRestoresAcrossAxesAndRTL() {
    for vertical in [false, true] {
      for direction in [UISemanticContentAttribute.forceLeftToRight, .forceRightToLeft] {
        let subject = makeSubject()
        subject.semanticContentAttribute = direction
        subject.isVertical = vertical
        subject.frame = vertical ? CGRect(x: 0, y: 0, width: 58, height: 244)
          : CGRect(x: 0, y: 0, width: 300, height: 58)
        subject.layoutIfNeeded()
        var changes: [Int] = []
        var reselects: [Int] = []
        subject.addAction(UIAction { _ in changes.append(subject.selectedSegmentIndex) }, for: .valueChanged)
        subject.onReselect = { reselects.append($0) }
        XCTAssertTrue(subject.gestureRecognizers?.contains { $0 is UIPanGestureRecognizer } == true)
        let start = center(of: subject.buttons[0], in: subject)
        let middle = center(of: subject.buttons[1], in: subject)
        let end = center(of: subject.buttons[3], in: subject)

        subject.processSelectionDrag(at: start, state: .began)
        subject.processSelectionDrag(at: middle, state: .changed)
        XCTAssertEqual(subject.selectedSegmentIndex, 1)
        XCTAssertTrue(changes.isEmpty)
        subject.processSelectionDrag(at: end, state: .ended)
        XCTAssertEqual(changes, [3])
        XCTAssertTrue(reselects.isEmpty)
        subject.processSelectionDrag(at: end, state: .began)
        subject.processSelectionDrag(at: start, state: .changed)
        subject.processSelectionDrag(at: start, state: .cancelled)
        XCTAssertEqual(subject.selectedSegmentIndex, 3)
        XCTAssertEqual(changes, [3])
        subject.processSelectionDrag(at: end, state: .began)
        subject.processSelectionDrag(at: end, state: .ended)
        XCTAssertEqual(reselects, [3])
      }
    }
  }

  private func center(of view: UIView, in subject: UIView) -> CGPoint {
    view.convert(CGPoint(x: view.bounds.midX, y: view.bounds.midY), to: subject)
  }

  private func makeSubject(category: UIContentSizeCategory = .large) -> FabBarTabControl {
    let subject = FabBarTabControl()
    subject.setTabs(makeTabs())
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    window.traitOverrides.preferredContentSizeCategory = category
    subject.frame = CGRect(x: 0, y: 0, width: 300, height: 58)
    window.addSubview(subject)
    window.isHidden = false
    subject.updateTraitsIfNeeded()
    subject.layoutIfNeeded()
    addTeardownBlock { @MainActor in
      window.isHidden = true
      subject.removeFromSuperview()
    }
    return subject
  }

  private func makeTabs(prefix: String = "") -> [FabBarTabDescriptor] {
    ["Collection", "Precision", "Feed", "Profile"].enumerated().map { index, title in
      FabBarTabDescriptor(title: prefix.isEmpty ? title : "\(prefix) \(title)",
        image: UIImage(systemName: "circle"), accessibilityIdentifier: "tab.\(index)")
    }
  }
}
