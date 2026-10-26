import SwiftUI

@available(iOS 26.0, *)
public extension EnvironmentValues {
    /// Measured clearance in the host's local coordinate space. Apply it once
    /// to foreground content; decorative imagery can continue behind the bar.
    @Entry var fabBarSafeAreaInsets: EdgeInsets = EdgeInsets(
        top: 0, leading: 0, bottom: Constants.barHeight + Constants.bottomPadding, trailing: 0)

    /// The visible glass/action surface in global coordinates, excluding menus.
    @Entry var fabBarFrame: CGRect = .zero

    /// The currently resolved edge; automatic is never published here.
    @Entry var fabBarPlacement: FabBarPlacement = .bottom

    /// Compatibility value for existing bottom-only consumers. Side layouts
    /// publish zero; prefer fabBarSafeAreaInsets for new integrations.
    @Entry var fabBarBottomSafeAreaPadding: CGFloat = Constants.barHeight + Constants.bottomPadding
}

@available(iOS 26.0, *)
struct FabBarSafeAreaPaddingModifier: ViewModifier {
    @Environment(\.fabBarSafeAreaInsets) private var insets

    func body(content: Content) -> some View {
        content.safeAreaPadding(insets)
    }
}

@available(iOS 26.0, *)
public extension View {
    /// Clears the measured FabBar edge for interactive content. This works for
    /// both bottom bars and side rails without assuming symmetric safe areas.
    func fabBarSafeAreaPadding() -> some View {
        modifier(FabBarSafeAreaPaddingModifier())
    }
}
