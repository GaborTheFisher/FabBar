import SwiftUI

/// A customizable iOS 26 glass tab bar with a floating action button.
///
/// FabBar provides a native-looking iOS 26 tab bar where you control what goes in it,
/// including a FAB that morphs with the glass effect.
///
/// ## Usage
///
/// The recommended way to use FabBar is with the `.fabBar()` modifier:
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
/// .fabBar(
///     selection: $selectedTab,
///     tabs: [
///         FabBarTab(value: .home, title: "Home", systemImage: "house.fill"),
///         FabBarTab(value: .explore, title: "Explore", systemImage: "compass"),
///         FabBarTab(value: .profile, title: "Profile", systemImage: "person.fill"),
///     ],
///     action: FabBarAction(systemImage: "plus", accessibilityLabel: "Add Item") {
///         // Handle tap
///     }
/// )
/// ```
///
/// For more control over positioning, you can use the `FabBar` view directly.

/// Coarse density presets for the bar.
///
/// Density is a plain parameter — the package never reads size classes or
/// window geometry itself. Hosts that adapt to compact window heights pass
/// `.compact`; the bar then uses an inline, content-hugging tab presentation.
/// The regular presentation keeps the familiar stacked, available-width tab
/// strip.
@available(iOS 26.0, *)
public enum FabBarDensity: Sendable, Equatable {
  /// The standard 62pt bar.
  case regular
  /// A 52pt, content-hugging bar for compact-height windows. Each tab places
  /// its label at the trailing edge of its icon.
  case compact

  var barHeight: CGFloat {
    switch self {
    case .regular: Constants.barHeight
    case .compact: Constants.compactBarHeight
    }
  }

  var tabItemLayout: FabBarTabItemLayout {
    switch self {
    case .regular: .stacked
    case .compact: .inline
    }
  }

  var hugsContentHorizontally: Bool {
    self == .compact
  }
}

@available(iOS 26.0, *)
public struct FabBar<Value: Hashable>: View {
  /// The currently selected tab.
  @Binding public var selection: Value

  /// The tabs to display.
  public let tabs: [FabBarTab<Value>]

  /// The floating action button configuration.
  public var action: FabBarAction

  public var secondaryActions: [FabBarAction]

  /// Whether tapping the primary button may reveal `secondaryActions`.
  ///
  /// Update this value when the same bar should act directly in some app
  /// states and expose its secondary menu in others. Disabling the menu also
  /// collapses it if it is currently visible.
  public var isSecondaryActionMenuEnabled: Bool

  /// Increment this value to collapse any expanded secondary actions.
  public var collapseTrigger: Int

  /// The coarse density preset the host selected.
  public var density: FabBarDensity

  /// Creates a FabBar with the specified configuration.
  ///
  /// - Parameters:
  ///   - selection: A binding to the currently selected tab.
  ///   - tabs: The tabs to display.
  ///   - action: The floating action button configuration.
  ///   - secondaryActions: Optional actions shown when tapping the floating action button.
  ///   - isSecondaryActionMenuEnabled: Whether tapping may reveal secondary actions.
  ///   - collapseTrigger: Increment to collapse any expanded secondary actions.
  ///   - density: Coarse density preset; pass `.compact` for compact-height windows.
  public init(
    selection: Binding<Value>,
    tabs: [FabBarTab<Value>],
    action: FabBarAction,
    secondaryActions: [FabBarAction] = [],
    isSecondaryActionMenuEnabled: Bool = true,
    collapseTrigger: Int = 0,
    density: FabBarDensity = .regular
  ) {
    self._selection = selection
    self.tabs = tabs
    self.action = action
    self.secondaryActions = secondaryActions
    self.isSecondaryActionMenuEnabled = isSecondaryActionMenuEnabled
    self.collapseTrigger = collapseTrigger
    self.density = density
  }

  public var body: some View {
    if tabs.isEmpty {
      Color.clear
        .frame(height: density.barHeight)
        .onAppear {
          fabBarLogger.warning("FabBar initialized with empty tabs array - nothing will be displayed")
        }
    } else {
      FabBarRepresentable(
        tabs: tabs,
        action: action,
        secondaryActions: secondaryActions,
        isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled,
        collapseTrigger: collapseTrigger,
        density: density,
        activeTab: $selection
      )
      .frame(height: density.barHeight)
    }
  }
}

@available(iOS 26.0, *)
private enum PreviewTab: Hashable {
  case home, explore, profile
}

@available(iOS 26.0, *)
#Preview("Basic") {
  @Previewable @State var selection: PreviewTab = .home

  VStack {
    Spacer()
    FabBar(
      selection: $selection,
      tabs: [
        FabBarTab(value: PreviewTab.home, title: "Home", systemImage: "house.fill"),
        FabBarTab(value: PreviewTab.explore, title: "Explore", systemImage: "map.fill"),
        FabBarTab(value: PreviewTab.profile, title: "Profile", systemImage: "person.fill"),
      ],
      action: FabBarAction(systemImage: "plus", accessibilityLabel: "Add") {}
    )
  }
}

@available(iOS 26.0, *)
#Preview("Secondary Actions") {
  @Previewable @State var selection: PreviewTab = .home

  VStack {
    Spacer()
    FabBar(
      selection: $selection,
      tabs: [
        FabBarTab(value: PreviewTab.home, title: "Home", systemImage: "house.fill"),
        FabBarTab(value: PreviewTab.explore, title: "Explore", systemImage: "map.fill"),
        FabBarTab(value: PreviewTab.profile, title: "Profile", systemImage: "person.fill"),
      ],
      action: FabBarAction(systemImage: "plus", accessibilityLabel: "Add") {},
      secondaryActions: [
        FabBarAction(systemImage: "camera.fill", accessibilityLabel: "Camera") {},
        FabBarAction(systemImage: "photo.fill", accessibilityLabel: "Photo") {},
        FabBarAction(systemImage: "doc.fill", accessibilityLabel: "Document") {},
        FabBarAction(systemImage: "link", accessibilityLabel: "Link") {},
        FabBarAction(systemImage: "mappin", accessibilityLabel: "Location") {},
      ]
    )
  }
  .preferredColorScheme(.light)
}

@available(iOS 26.0, *)
private struct SecondaryActionLabel: View {
  let systemImage: String
  let title: String

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: systemImage)
      Text(title)
        .font(.callout.weight(.medium))
    }
    .foregroundStyle(.primary)
  }
}

@available(iOS 26.0, *)
@MainActor
private func makeSecondaryAction(
  systemImage: String,
  title: String
) -> FabBarAction {
  FabBarAction(
    systemImage: systemImage,
    accessibilityLabel: title,
    view: UIHostingController(rootView: SecondaryActionLabel(systemImage: systemImage, title: title)),
    action: {}
  )
}

@available(iOS 26.0, *)
#Preview("Custom Views") {
  @Previewable @State var selection: PreviewTab = .home

  VStack {
    Spacer()
    FabBar(
      selection: $selection,
      tabs: [
        FabBarTab(value: PreviewTab.home, title: "Home", systemImage: "house.fill"),
        FabBarTab(value: PreviewTab.explore, title: "Explore", systemImage: "map.fill"),
        FabBarTab(value: PreviewTab.profile, title: "Profile", systemImage: "person.fill"),
      ],
      action: FabBarAction(systemImage: "plus", accessibilityLabel: "Add") {},
      secondaryActions: [
        makeSecondaryAction(systemImage: "camera.fill", title: "Camera"),
        makeSecondaryAction(systemImage: "photo.fill", title: "Photo"),
        makeSecondaryAction(systemImage: "doc.fill", title: "Document"),
        makeSecondaryAction(systemImage: "link", title: "Link"),
        makeSecondaryAction(systemImage: "mappin", title: "Location"),
      ]
    )
  }
  .preferredColorScheme(.dark)
}
