import SwiftUI

/// View modifier that positions a FabBar at the bottom of the view.
///
/// This modifier handles all the layout details:
/// - Wraps in `.safeAreaBar(edge: .bottom)`
/// - Applies appropriate padding
/// - Ignores bottom safe area for manual positioning
/// - Keeps tab navigation visible and width-capped in regular-width layouts
/// - Injects padding measured from the rendered bar into the environment
@available(iOS 26.0, *)
struct FabBarModifier<Value: Hashable>: ViewModifier {
    @Binding var selection: Value
    let tabs: [FabBarTab<Value>]
    let action: FabBarAction
    let secondaryActions: [FabBarAction]
    let isSecondaryActionMenuEnabled: Bool
    let isVisible: Bool
    let collapseTrigger: Int
    let density: FabBarDensity
    let regularWidthBehavior: FabBarRegularWidthBehavior

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var bottomSafeAreaInset: CGFloat = 0
    @State private var renderedBarFrame: CGRect = .zero

    /// Whether the FabBar should be displayed.
    private var showsFabBar: Bool {
        FabBarModifierLayout.showsBar(
            isVisible: isVisible,
            horizontalSizeClass: horizontalSizeClass,
            regularWidthBehavior: regularWidthBehavior
        )
    }

    /// Regular-width bars remain available as the primary tab navigation but
    /// are capped so their controls do not stretch across the whole window.
    private var maximumBarWidth: CGFloat {
        FabBarModifierLayout.maximumBarWidth(horizontalSizeClass: horizontalSizeClass)
    }

    /// The padding to inject into the environment.
    /// This is derived from the rendered chrome frame (including its bottom
    /// spacing), rather than assuming a particular density or bar height.
    private var calculatedPadding: CGFloat {
        FabBarModifierLayout.bottomSafeAreaPadding(
            showsBar: showsFabBar,
            renderedBarFrame: renderedBarFrame,
            bottomSafeAreaInset: bottomSafeAreaInset
        )
    }

    func body(content: Content) -> some View {
        content
            .safeAreaBar(edge: .bottom) {
                if showsFabBar {
                    FabBar(
                        selection: $selection,
                        tabs: tabs,
                        action: action,
                        secondaryActions: secondaryActions,
                        isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled,
                        collapseTrigger: collapseTrigger,
                        density: density
                    )
                        .frame(maxWidth: maximumBarWidth)
                        .padding(.horizontal, Constants.horizontalPadding)
                        .padding(.bottom, Constants.bottomPadding)
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .global)
                        } action: { newValue in
                            renderedBarFrame = newValue
                        }
                }
            }
            .ignoresSafeArea(.all, edges: showsFabBar ? [.bottom] : [])
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.safeAreaInsets.bottom
            } action: { newValue in
                bottomSafeAreaInset = newValue
            }
            .environment(\.fabBarBottomSafeAreaPadding, calculatedPadding)
    }
}

@available(iOS 26.0, *)
enum FabBarModifierLayout {
    static func showsBar(
        isVisible: Bool,
        horizontalSizeClass: UserInterfaceSizeClass?,
        regularWidthBehavior: FabBarRegularWidthBehavior
    ) -> Bool {
        guard isVisible else { return false }
        guard horizontalSizeClass == .regular else { return true }
        return regularWidthBehavior == .visible
    }

    static func maximumBarWidth(horizontalSizeClass: UserInterfaceSizeClass?) -> CGFloat {
        horizontalSizeClass == .regular
            ? Constants.regularWidthMaximumBarWidth
            : .infinity
    }

    static func bottomSafeAreaPadding(
        showsBar: Bool,
        renderedBarFrame: CGRect,
        bottomSafeAreaInset: CGFloat
    ) -> CGFloat {
        guard showsBar else { return 0 }
        return max(0, renderedBarFrame.height - bottomSafeAreaInset)
    }
}

/// Controls how the recommended modifier behaves in a regular-width layout.
///
/// FabBar remains visible by default because it may be the app's only tab
/// navigation. Select ``hiddenWhenAlternativeNavigationIsProvided`` only when
/// the same tabs are available through another visible navigation surface.
@available(iOS 26.0, *)
public enum FabBarRegularWidthBehavior: Sendable, Equatable {
    /// Keep FabBar visible, centered, and capped at a readable width.
    case visible

    /// Hide FabBar at regular width because the host provides another visible
    /// way to switch between every tab.
    case hiddenWhenAlternativeNavigationIsProvided
}

@available(iOS 26.0, *)
public extension View {
    /// Adds a FabBar to the bottom of the view.
    ///
    /// This is the recommended way to use FabBar. It handles positioning,
    /// safe area management, and keeps navigation visible at regular width.
    /// Regular-width bars are centered and width-capped by default.
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
    ///   - secondaryActions: Optional actions revealed by the floating action button.
    ///   - isSecondaryActionMenuEnabled: Whether tapping may reveal secondary actions.
    ///   - isVisible: Whether the FabBar is visible. Defaults to `true`.
    ///   - collapseTrigger: Increment to collapse any expanded secondary actions.
    ///   - density: Coarse density preset selected by the host.
    ///   - regularWidthBehavior: Whether to keep navigation visible at regular
    ///     width. Hide it only when the host provides another tab surface.
    func fabBar<Value: Hashable>(
        selection: Binding<Value>,
        tabs: [FabBarTab<Value>],
        action: FabBarAction,
        secondaryActions: [FabBarAction] = [],
        isSecondaryActionMenuEnabled: Bool = true,
        isVisible: Bool = true,
        collapseTrigger: Int = 0,
        density: FabBarDensity = .regular,
        regularWidthBehavior: FabBarRegularWidthBehavior = .visible
    ) -> some View {
        modifier(FabBarModifier(
            selection: selection,
            tabs: tabs,
            action: action,
            secondaryActions: secondaryActions,
            isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled,
            isVisible: isVisible,
            collapseTrigger: collapseTrigger,
            density: density,
            regularWidthBehavior: regularWidthBehavior
        ))
    }
}
