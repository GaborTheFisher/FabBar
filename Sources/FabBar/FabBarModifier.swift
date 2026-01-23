import SwiftUI

/// View modifier that positions a FabBar at the bottom of the view.
///
/// This modifier handles all the layout details:
/// - Wraps in `.safeAreaBar(edge: .bottom)`
/// - Applies appropriate padding
/// - Ignores bottom safe area for manual positioning
/// - Hides automatically on regular horizontal size class (iPad)
@available(iOS 26.0, *)
struct FabBarModifier<Value: Hashable>: ViewModifier {
    @Binding var selection: Value
    let tabs: [FabBarTab<Value>]
    let action: FabBarAction
    let isVisible: Bool

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        content
            .safeAreaBar(edge: .bottom) {
                if horizontalSizeClass == .compact && isVisible {
                    FabBar(selection: $selection, tabs: tabs, action: action)
                        .padding(.horizontal, Constants.horizontalPadding)
                        .padding(.bottom, Constants.bottomPadding)
                }
            }
            .ignoresSafeArea(.container, edges: .bottom)
    }
}

@available(iOS 26.0, *)
public extension View {
    /// Adds a FabBar to the bottom of the view.
    ///
    /// This is the recommended way to use FabBar. It handles positioning,
    /// safe area management, and automatically hides on iPad.
    ///
    /// ```swift
    /// TabView(selection: $selectedTab) {
    ///     Tab(value: .home) {
    ///         HomeView()
    ///             .fabBarSafeAreaPadding()
    ///             .toolbarVisibility(.hidden, for: .tabBar)
    ///     }
    ///     // more tabs...
    /// }
    /// .fabBar(selection: $selectedTab, tabs: tabs, action: action)
    /// ```
    ///
    /// - Parameters:
    ///   - selection: A binding to the currently selected tab.
    ///   - tabs: The tabs to display.
    ///   - action: The floating action button configuration.
    ///   - isVisible: Whether the FabBar is visible. Defaults to `true`.
    func fabBar<Value: Hashable>(
        selection: Binding<Value>,
        tabs: [FabBarTab<Value>],
        action: FabBarAction,
        isVisible: Bool = true
    ) -> some View {
        modifier(FabBarModifier(selection: selection, tabs: tabs, action: action, isVisible: isVisible))
    }
}
