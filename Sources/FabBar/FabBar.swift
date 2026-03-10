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

@available(iOS 26.0, *)
public struct FabBar<Value: Hashable>: View {
  /// The currently selected tab.
  @Binding public var selection: Value

  /// The tabs to display.
  public let tabs: [FabBarTab<Value>]

  /// The floating action button configuration.
  public var action: FabBarAction

  public var secondaryActions: [FabBarAction]

  /// Creates a FabBar with the specified configuration.
  ///
  /// - Parameters:
  ///   - selection: A binding to the currently selected tab.
  ///   - tabs: The tabs to display.
  ///   - action: The floating action button configuration.
  public init(
    selection: Binding<Value>,
    tabs: [FabBarTab<Value>],
    action: FabBarAction,
    secondaryActions: [FabBarAction] = []
  ) {
    self._selection = selection
    self.tabs = tabs
    self.action = action
    self.secondaryActions = secondaryActions
  }

  public var body: some View {
    if tabs.isEmpty {
      Color.clear
        .frame(height: Constants.barHeight)
        .onAppear {
          fabBarLogger.warning("FabBar initialized with empty tabs array - nothing will be displayed")
        }
    } else {
      FabBarRepresentable(
        tabs: tabs,
        action: action,
        secondaryActions: secondaryActions,
        activeTab: $selection
      )
      .frame(height: Constants.barHeight)
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
