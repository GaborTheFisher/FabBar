import SwiftUI

/// Hosts one floating navigation/action surface without replacing the tab
/// content when the system's preferred edge changes.
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
    let placement: FabBarPlacement

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutDirection) private var layoutDirection
    @State private var renderedBarFrame: CGRect = .zero
    @State private var measuredPlacement: FabBarPlacement = .automatic
    @State private var hostGeometry = FabBarHostGeometry()

    private var showsFabBar: Bool {
        FabBarModifierLayout.showsBar(
            isVisible: isVisible,
            horizontalSizeClass: horizontalSizeClass,
            regularWidthBehavior: regularWidthBehavior
        )
    }

    func body(content: Content) -> some View {
        FabBarPlacementReader(placement: placement) { resolvedPlacement in
            content
                .background {
                    GeometryReader { _ in Color.clear }
                        .onGeometryChange(for: FabBarHostGeometry.self) {
                            FabBarHostGeometry(size: $0.size, globalFrame: $0.frame(in: .global))
                        } action: { hostGeometry = $0 }
                        .allowsHitTesting(false)
                }
                .overlay {
                    GeometryReader { geometry in
                        if showsFabBar {
                            FabBar(
                                selection: $selection,
                                tabs: tabs,
                                action: action,
                                secondaryActions: secondaryActions,
                                isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled,
                                collapseTrigger: collapseTrigger,
                                density: density,
                                placement: resolvedPlacement,
                                maximumLength: max(0, geometry.size.height - 2 * (resolvedPlacement.isVertical
                                    ? Constants.sidePadding : Constants.bottomPadding))
                            )
                            .frame(maxWidth: resolvedPlacement.isVertical || density.hugsContentHorizontally ? nil
                                : FabBarModifierLayout.maximumBarWidth(horizontalSizeClass: horizontalSizeClass))
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                                renderedBarFrame = $0
                                measuredPlacement = resolvedPlacement
                            }
                            .padding(.horizontal, resolvedPlacement.isVertical ? 0 : Constants.horizontalPadding)
                            .padding(.leading, resolvedPlacement == .leading ? Constants.sidePadding : 0)
                            .padding(.trailing, resolvedPlacement == .trailing ? Constants.sidePadding : 0)
                            .padding(.bottom, resolvedPlacement.isVertical ? Constants.sidePadding : Constants.bottomPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: resolvedPlacement.alignment)
                        }
                    }
                    // Only the side chrome expands into the system-reserved
                    // horizontal strip. Content and bottom chrome retain their
                    // original safe-area geometry.
                    .ignoresSafeArea(.container, edges: resolvedPlacement.isVertical ? .horizontal : [])
                }
                .environment(\.fabBarPlacement, resolvedPlacement)
                .environment(\.fabBarFrame,
                    showsFabBar && measuredPlacement == resolvedPlacement ? renderedBarFrame : .zero)
                .environment(\.fabBarSafeAreaInsets, clearances(for: resolvedPlacement))
                .environment(\.fabBarBottomSafeAreaPadding, clearances(for: resolvedPlacement).bottom)
                .onChange(of: showsFabBar) { _, visible in
                    if !visible { renderedBarFrame = .zero }
                }
        }
    }

    private func clearances(for placement: FabBarPlacement) -> EdgeInsets {
        guard showsFabBar else { return EdgeInsets() }
        guard measuredPlacement == placement, !renderedBarFrame.isEmpty,
              !hostGeometry.globalFrame.isEmpty else {
            return FabBarModifierLayout.fallbackInsets(placement: placement, density: density)
        }
        return FabBarModifierLayout.safeAreaInsets(
            placement: placement,
            renderedBarFrame: renderedBarFrame,
            hostFrame: hostGeometry.globalFrame,
            hostSize: hostGeometry.size,
            layoutDirection: layoutDirection
        )
    }
}

private struct FabBarHostGeometry: Equatable {
    var size: CGSize = .zero
    var globalFrame: CGRect = .zero
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

    static func fallbackInsets(placement: FabBarPlacement, density: FabBarDensity) -> EdgeInsets {
        let clearance = density.barThickness(for: placement)
            + (placement.isVertical ? Constants.sidePadding : Constants.bottomPadding)
        switch placement {
        case .leading: return EdgeInsets(top: 0, leading: clearance, bottom: 0, trailing: 0)
        case .trailing: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: clearance)
        case .automatic, .bottom: return EdgeInsets(top: 0, leading: 0, bottom: clearance, trailing: 0)
        }
    }

    static func safeAreaInsets(
        placement: FabBarPlacement,
        renderedBarFrame: CGRect,
        hostFrame: CGRect,
        hostSize: CGSize,
        layoutDirection: LayoutDirection
    ) -> EdgeInsets {
        guard !renderedBarFrame.isEmpty, !hostFrame.isEmpty,
              hostSize.width > 0, hostSize.height > 0,
              hostFrame.width.isFinite, hostFrame.height.isFinite,
              renderedBarFrame.intersects(hostFrame) else { return EdgeInsets() }
        let scaleX = hostSize.width / hostFrame.width
        let scaleY = hostSize.height / hostFrame.height
        switch placement {
        case .automatic, .bottom:
            return EdgeInsets(top: 0, leading: 0,
                bottom: min(hostSize.height, max(0, hostFrame.maxY - renderedBarFrame.minY) * scaleY), trailing: 0)
        case .leading:
            let overlap = layoutDirection == .leftToRight
                ? renderedBarFrame.maxX - hostFrame.minX
                : hostFrame.maxX - renderedBarFrame.minX
            return EdgeInsets(top: 0,
                leading: min(hostSize.width, max(0, overlap) * scaleX), bottom: 0, trailing: 0)
        case .trailing:
            let overlap = layoutDirection == .leftToRight
                ? hostFrame.maxX - renderedBarFrame.minX
                : renderedBarFrame.maxX - hostFrame.minX
            return EdgeInsets(top: 0, leading: 0, bottom: 0,
                trailing: min(hostSize.width, max(0, overlap) * scaleX))
        }
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
    /// Keep FabBar visible. Bottom bars are centered and width-capped.
    case visible

    /// Hide FabBar at regular width because the host provides another visible
    /// way to switch between every tab.
    case hiddenWhenAlternativeNavigationIsProvided
}

@available(iOS 26.0, *)
public extension View {
    /// Adds FabBar at the system-preferred edge, or an explicit placement.
    ///
    /// This is the recommended way to use FabBar. It handles positioning,
    /// safe area management, and keeps navigation visible at regular width.
    /// Bottom bars are centered and width-capped at regular width.
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
    ///   - placement: Automatic uses the system-preferred side on iOS 27.1+;
    ///     earlier systems use the bottom. Explicit sides are useful for previews.
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
        regularWidthBehavior: FabBarRegularWidthBehavior = .visible,
        placement: FabBarPlacement = .automatic
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
            regularWidthBehavior: regularWidthBehavior,
            placement: placement
        ))
    }
}
