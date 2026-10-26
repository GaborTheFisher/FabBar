import SwiftUI
import UIKit
import XCTest
@testable import FabBar

/// Verifies the public modifier in a mounted window with synthetic safe-area
/// reservations. Standalone SwiftPM xctest has no application scene, so real
/// device hardware safe areas require a separate app-hosted qualification.
@MainActor
@available(iOS 26.0, *)
final class FabBarMeasuredClearanceTests: XCTestCase {
  func testMeasuredEdgeClearancePadsForegroundOnceInsideAsymmetricSafeAreaReservations() throws {
    for direction in [LayoutDirection.leftToRight, .rightToLeft] {
      for placement in [FabBarPlacement.bottom, .leading, .trailing] {
        let record = FabBarClearanceRecord()
        let root = FabBarClearanceContent(record: record)
          .fabBar(
            selection: .constant(0),
            tabs: [
              FabBarTab(value: 0, title: "Collection", systemImage: "clock"),
              FabBarTab(value: 1, title: "Precision", systemImage: "list.bullet"),
              FabBarTab(value: 2, title: "Profile", systemImage: "person")
            ],
            action: FabBarAction(systemImage: "plus", accessibilityLabel: "Primary", action: {}),
            placement: placement
          )
          .environment(\.layoutDirection, direction)
        let controller = UIHostingController(rootView: root)
        // Include phone-style top/bottom reserves plus unequal extra host
        // reservations, without calling these real hardware observations.
        controller.additionalSafeAreaInsets = UIEdgeInsets(top: 76, left: 13, bottom: 63, right: 23)
        let window: UIWindow
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
          window = UIWindow(windowScene: scene)
          window.frame = scene.coordinateSpace.bounds
        } else {
          window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        }
        window.rootViewController = controller
        window.isHidden = false
        defer {
          window.isHidden = true
          window.rootViewController = nil
        }
        layout(window, controller.view)

        let context = "\(placement.rawValue), \(direction)"
        let settled = waitUntil {
          layout(window, controller.view)
          guard let host = record.host, let foreground = record.foreground,
                let bar = findSubview(of: GlassTabBarView.self, in: controller.view),
                record.placement == placement, !record.barFrame.isEmpty else { return false }
          let hostFrame = host.convert(host.bounds, to: window)
          let foregroundFrame = foreground.convert(foreground.bounds, to: window)
          let barFrame = bar.convert(bar.bounds, to: window)
          guard hostFrame.width > 0, hostFrame.height > 0,
                foregroundFrame.width > 0, foregroundFrame.height > 0 else { return false }
          let expected = edgeClearance(placement: placement, direction: direction,
            host: hostFrame, bar: barFrame)
          return abs(activeInset(record.insets, placement: placement) - expected) < 0.5
            && abs(foregroundClearance(placement: placement, direction: direction,
              host: hostFrame, foreground: foregroundFrame) - expected) < 0.5
        }
        XCTAssertTrue(settled, "The published clearance and padded foreground must settle together. \(context)")

        let host = try XCTUnwrap(record.host, context)
        let foreground = try XCTUnwrap(record.foreground, context)
        let bar = try XCTUnwrap(findSubview(of: GlassTabBarView.self, in: controller.view), context)
        let hostFrame = host.convert(host.bounds, to: window)
        let foregroundFrame = foreground.convert(foreground.bounds, to: window)
        let barFrame = bar.convert(bar.bounds, to: window)
        let expected = edgeClearance(placement: placement, direction: direction,
          host: hostFrame, bar: barFrame)

        XCTAssertGreaterThanOrEqual(controller.view.safeAreaInsets.bottom, 63, context)
        XCTAssertGreaterThanOrEqual(hostFrame.minY,
          window.safeAreaInsets.top + controller.additionalSafeAreaInsets.top - 1, context)
        XCTAssertLessThanOrEqual(hostFrame.maxY,
          window.bounds.maxY - window.safeAreaInsets.bottom
            - controller.additionalSafeAreaInsets.bottom + 1, context)
        XCTAssertEqual(activeInset(record.insets, placement: placement), expected, accuracy: 0.5, context)
        XCTAssertEqual(foregroundClearance(placement: placement, direction: direction,
          host: hostFrame, foreground: foregroundFrame), expected, accuracy: 0.5, context)
        XCTAssertEqual(record.barFrame.width, barFrame.width, accuracy: 0.5, context)
        XCTAssertEqual(record.barFrame.height, barFrame.height, accuracy: 0.5, context)
        XCTAssertEqual(record.insets.top, 0, context)
        if placement != .bottom { XCTAssertEqual(record.insets.bottom, 0, context) }
        if placement != .leading { XCTAssertEqual(record.insets.leading, 0, context) }
        if placement != .trailing { XCTAssertEqual(record.insets.trailing, 0, context) }
        // The reserved safe area was already excluded from the host.
        // Subtracting it again would leave foreground beneath the glass.
        XCTAssertGreaterThanOrEqual(expected, FabBarDensity.regular.barHeight, context)
      }
    }
  }

  private func activeInset(_ insets: EdgeInsets, placement: FabBarPlacement) -> CGFloat {
    switch placement {
    case .leading: insets.leading
    case .trailing: insets.trailing
    case .automatic, .bottom: insets.bottom
    }
  }

  private func edgeClearance(
    placement: FabBarPlacement, direction: LayoutDirection, host: CGRect, bar: CGRect
  ) -> CGFloat {
    switch placement {
    case .automatic, .bottom: host.maxY - bar.minY
    case .leading: direction == .leftToRight ? bar.maxX - host.minX : host.maxX - bar.minX
    case .trailing: direction == .leftToRight ? host.maxX - bar.minX : bar.maxX - host.minX
    }
  }

  private func foregroundClearance(
    placement: FabBarPlacement, direction: LayoutDirection, host: CGRect, foreground: CGRect
  ) -> CGFloat {
    switch placement {
    case .automatic, .bottom: host.maxY - foreground.maxY
    case .leading: direction == .leftToRight ? foreground.minX - host.minX : host.maxX - foreground.maxX
    case .trailing: direction == .leftToRight ? host.maxX - foreground.maxX : foreground.minX - host.minX
    }
  }

  private func layout(_ window: UIWindow, _ content: UIView) {
    window.setNeedsLayout()
    window.layoutIfNeeded()
    content.setNeedsLayout()
    content.layoutIfNeeded()
  }

  private func waitUntil(timeout: TimeInterval = 3, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
      if condition() { return true }
      RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
    } while Date() < deadline
    return condition()
  }

  private func findSubview<T: UIView>(of type: T.Type, in root: UIView) -> T? {
    if let match = root as? T { return match }
    for subview in root.subviews {
      if let match = findSubview(of: type, in: subview) { return match }
    }
    return nil
  }
}

@MainActor
@available(iOS 26.0, *)
private final class FabBarClearanceRecord {
  weak var host: UIView?
  weak var foreground: UIView?
  var insets = EdgeInsets()
  var barFrame = CGRect.zero
  var placement = FabBarPlacement.automatic
}

@available(iOS 26.0, *)
private struct FabBarClearanceContent: View {
  let record: FabBarClearanceRecord
  @Environment(\.fabBarSafeAreaInsets) private var insets
  @Environment(\.fabBarFrame) private var barFrame
  @Environment(\.fabBarPlacement) private var placement

  var body: some View {
    Color.clear
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background {
        FabBarClearanceMarker { record.foreground = $0 }
      }
      .fabBarSafeAreaPadding()
      .background {
        FabBarClearanceMarker {
          record.host = $0
          record.insets = insets
          record.barFrame = barFrame
          record.placement = placement
        }
      }
  }
}

private struct FabBarClearanceMarker: UIViewRepresentable {
  let onUpdate: (UIView) -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.isUserInteractionEnabled = false
    return view
  }

  func updateUIView(_ view: UIView, context: Context) { onUpdate(view) }
}
