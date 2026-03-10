import Foundation
import SwiftUI

/// Configuration for the floating action button (FAB) in FabBar.
///
/// The FAB appears as a circular glass button next to the tab items,
/// morphing with the iOS 26 glass effect.
@available(iOS 26.0, *)
public struct FabBarAction {
  /// The SF Symbol name for the button icon.
  public let systemImage: String

  /// The accessibility label for VoiceOver users.
  public let accessibilityLabel: String

  /// The action to perform when the button is tapped.
  public let action: () -> Void

  /// An optional custom view controller to render inside the FAB instead of the default icon.
  public let customView: UIViewController?

  /// Creates a floating action button configuration.
  ///
  /// - Parameters:
  ///   - systemImage: The SF Symbol name for the button icon.
  ///   - accessibilityLabel: The accessibility label for VoiceOver users.
  ///   - action: The action to perform when the button is tapped.
  public init(
    systemImage: String,
    accessibilityLabel: String,
    action: @escaping () -> Void
  ) {
    self.systemImage = systemImage
    self.accessibilityLabel = accessibilityLabel
    self.action = action
    self.customView = nil
  }

  /// Creates a floating action button with a custom SwiftUI view.
  ///
  /// - Parameters:
  ///   - systemImage: The SF Symbol name used as a fallback icon.
  ///   - accessibilityLabel: The accessibility label for VoiceOver users.
  ///   - view: A `UIHostingController` wrapping a custom SwiftUI view to render inside the FAB.
  ///   - action: The action to perform when the button is tapped.
  public init<Content: View>(
    systemImage: String,
    accessibilityLabel: String,
    view: UIHostingController<Content>,
    action: @escaping () -> Void
  ) {
    self.systemImage = systemImage
    self.accessibilityLabel = accessibilityLabel
    self.action = action
    self.customView = view
  }
}
