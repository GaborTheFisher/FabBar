# FabBar

A custom Liquid Glass navigation bar with a separate, tinted primary action and adaptive bottom or side placement.

![FabBar Screenshot](Assets/fabbar-screenshot.png)

## Why FabBar?

Many apps have a primary action that users perform frequently: composing a social media post, logging a meal, creating a task. Placing this action at the bottom of the screen keeps it in the thumb zone and always visible, reducing friction for the most common user flow.

With iOS 26's tab bar, developers can declare a tab with `role: .search` and abuse it as a primary action, but this approach has several issues:

- You're lying to the system, it's not actually a search tab
- VoiceOver reads it as a tab, not a button
- Requires listening for tab changes and undoing them in SwiftUI, which is prone to race conditions
- No ability to tint, so it looks like a search tab rather than a primary action

Developers have another option: placing a custom floating action button above the tab bar. Typically, this is placed on the right side of the screen. However, with iOS 26's centered tab bar, this creates an awkward layout. With fewer than four tabs, there's negative space on either side of the bar, and placing a FAB on the trailing edge creates unbalanced empty space below it. And there's no way to customize the native tab bar's placement or sizing to work around this.

FabBar provides one solution: recreate the tab bar entirely for full control.

## How It Works

FabBar provides a SwiftUI API but uses UIKit internally.

The shipping navigation control uses public UIKit buttons, `UIGlassEffect`, and
`UIGlassContainerEffect`. A separate selection surface follows the selected
button, and changing the axis reuses the mounted buttons and primary action.
FabBar owns its placement, compression and overflow behavior; it is custom
navigation rather than a system tab bar. See [Custom chrome responsibilities](#custom-chrome-responsibilities)
for the host's qualification responsibilities.

## Requirements

- Build with the iOS 27.1 SDK or later, which declares `toolbarVerticalEdge`.
- The supported deployment minimum is iOS 26. Runtime availability guards keep
  automatic placement at the bottom before iOS 27.1; they do not make these
  declarations available to an older build SDK.

## Installation

Add FabBar as a Swift Package dependency:

```swift
dependencies: [
    .package(url: "https://github.com/ryanashcraft/FabBar.git", from: "1.0.0")
]
```

## Usage

```swift
import FabBar

enum AppTab: Hashable {
    case home, explore, profile
}

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView()
                    .fabBarSafeAreaPadding()
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Explore", systemImage: "compass", value: .explore) {
                ExploreView()
                    .fabBarSafeAreaPadding()
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
            Tab("Profile", systemImage: "person.fill", value: .profile) {
                ProfileView()
                    .fabBarSafeAreaPadding()
                    .toolbarVisibility(.hidden, for: .tabBar)
            }
        }
        .fabBar(
            selection: $selectedTab,
            tabs: [
                FabBarTab(value: .home, title: "Home", systemImage: "house.fill"),
                FabBarTab(value: .explore, title: "Explore", systemImage: "compass"),
                FabBarTab(value: .profile, title: "Profile", systemImage: "person.fill"),
            ],
            action: FabBarAction(
                systemImage: "plus",
                accessibilityLabel: "Add Item"
            ) {
                // Handle FAB tap
            }
        )
    }
}
```

The `.fabBar()` modifier handles positioning and safe area management. It keeps
tab navigation visible on iPad and other regular-width windows, where it is
centered and width-capped. If your regular-width layout provides another
visible surface for switching every tab, opt out explicitly with
`regularWidthBehavior: .hiddenWhenAlternativeNavigationIsProvided`. Use
`.fabBarSafeAreaPadding()` on scrollable content within each tab to ensure
content isn't hidden behind the bar; the padding follows the bar's measured
frame and therefore updates with its density and live window layout.

For more control over positioning, you can use the `FabBar` view directly.

### Custom Images

Use custom images from your asset catalog instead of SF Symbols:

```swift
FabBarTab(
    value: .library,
    title: "Library",
    image: "custom.library.icon",
    imageBundle: .main
)
```

### Tab Reselection

Handle when users tap an already-selected tab (useful for scroll-to-top):

```swift
FabBarTab(
    value: .home,
    title: "Home",
    systemImage: "house.fill",
    onReselect: {
        // User tapped this tab while it was already selected
        scrollToTop()
    }
)
```

### Conditional Visibility

Hide the FabBar based on app state (e.g., during selection mode):

```swift
.fabBar(
    selection: $selectedTab,
    tabs: tabs,
    action: action,
    isVisible: !isSelecting
)
```

### Collapsing Secondary Actions

Increment `collapseTrigger` to dismiss expanded secondary actions from outside the bar, for example when changing tabs:

```swift
@State private var collapseTrigger = 0

FabBar(
    selection: $selectedTab,
    tabs: tabs,
    action: action,
    secondaryActions: secondaryActions,
    collapseTrigger: collapseTrigger
)
.onChange(of: selectedTab) { _, _ in
    collapseTrigger += 1
}
```

### Conditional Secondary Actions

Keep secondary actions warm while allowing the primary button to act directly
outside the app state where the menu is relevant:

```swift
FabBar(
    selection: $selectedTab,
    tabs: tabs,
    action: action,
    secondaryActions: secondaryActions,
    isSecondaryActionMenuEnabled: selectedTab == .compose
)
```

Changing `isSecondaryActionMenuEnabled` does not rebuild the UIKit bar. Turning
it off also collapses an open secondary-action menu.

### Manual Positioning

For more control, use `FabBar` directly. The host supplies the resolved edge,
reserves the corresponding foreground clearance, and keeps its content tree
mounted as placement changes. Use `maximumLength` to supply a side rail's
available height. The recommended modifier handles these measurements.

## Adaptive bottom and side placement

FabBar keeps its separate primary action while following the system's preferred
vertical-bar edge on iOS 27.1 and later. On earlier iOS versions, automatic
placement remains at the bottom. Explicit placement is available for previews,
qualification and hosts with an independently resolved layout:

```swift
.fabBar(
    selection: $selectedTab,
    tabs: tabs,
    action: action,
    placement: .automatic // .bottom, .leading or .trailing
)
```

Bottom layouts use an icon-and-label navigation capsule next to the action.
Side layouts stack the navigation controls and keep the action at the lower end.
When a short rail cannot fit every destination, navigation becomes a chooser;
the primary action remains a separate direct control. Supply localized titles
and accessibility labels, and optional stable `accessibilityIdentifier` values
on tabs.

The modifier publishes `fabBarPlacement`, `fabBarFrame` (global coordinates),
and `fabBarSafeAreaInsets` (additional host-local clearances). Side chrome uses
the horizontal system-reserved strip when available, with a 16pt window-edge
inset. Content keeps its original safe areas; a rail that fits entirely inside
an existing strip publishes zero additional clearance. `fabBarSafeAreaPadding()`
clears only the remaining overlap. Apply it once to foreground content.
Background imagery may extend underneath the glass.
The legacy `fabBarBottomSafeAreaPadding` remains available and is zero for rails.

For a custom host, resolve the edge once and keep the content tree stable:

```swift
FabBarPlacementReader { placement in
    // Keep content and its navigation state outside placement branches.
    FabBar(selection: $selectedTab, tabs: tabs, action: action,
           placement: placement, maximumLength: availableHeight)
}
```

Leading/trailing values follow layout direction. When following the system's
preferred edge, do not mirror that result a second time. Reserve each safe-area
edge independently. The Example app's settings allow automatic/bottom/leading/
trailing placement and both densities; each tab has a local counter to check
state preservation while resizing, rotating and switching layouts.

## Example

See the [Example project](Example/FabBarExample) for a complete implementation.

## Custom chrome responsibilities

FabBar uses system glass materials but remains custom navigation chrome. Its
placement, overflow and accessibility policies belong to the package rather
than the native TabView. The native content host and navigation paths can stay
unchanged while its visible tab bar is hidden.

A side rail needs room for at least two full controls and their separation:
one navigation chooser and the primary action. Hosts should preserve that
minimum instead of shrinking hit targets. Qualify outer/inner displays, both
Split View sides, short windows, accessibility text sizes, VoiceOver, Large
Content Viewer and Reduce Transparency on the supported runtime versions.
Native tab reselection is still host-owned: use `onReselect` for scroll-to-top.

## License

MIT License. See [LICENSE](LICENSE) for details.
