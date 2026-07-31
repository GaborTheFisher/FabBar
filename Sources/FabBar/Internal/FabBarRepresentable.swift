import SwiftUI
import UIKit

@available(iOS 26.0, *)
struct FabBarTabPresentationSignature: Equatable {
  let value: AnyHashable
  let title: String
  let systemImage: String?
  let image: String?
  let imageBundlePath: String?
}

/// A UIViewRepresentable that wraps a TabBarSegmentedControl for tab bar functionality.
/// Tab content (icon + label) is injected directly into each segment's view subtree so that
/// the glass magnification effect applies to the content. SF Symbols remain vector-based
/// and scale at any resolution, avoiding rasterization issues in accessibility popovers.
@available(iOS 26.0, *)
struct FabBarRepresentable<Value: Hashable>: UIViewRepresentable {
  var tabs: [FabBarTab<Value>]
  var action: FabBarAction
  var secondaryActions: [FabBarAction]
  var isSecondaryActionMenuEnabled: Bool
  var collapseTrigger: Int
  var density: FabBarDensity

  @Binding var activeTab: Value

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeUIView(context: Context) -> GlassTabBarView {
    let images = tabs.compactMap { _ in
      UIImage(systemName: "circle")
    }
    let control = TabBarSegmentedControl(items: images)
    control.showsLargeContentViewer = false
    let selectedIndex = tabs.firstIndex { $0.value == activeTab } ?? 0
    control.selectedSegmentIndex = selectedIndex

    let preferredCompactSegmentWidths = configureSegmentContent(on: control)
    control.selectedSegmentTintColor = segmentTintColor(for: control.traitCollection)

    control.addTarget(context.coordinator, action: #selector(context.coordinator.tabSelected(_:)), for: .valueChanged)

    // Handle reselection (tapping already-selected segment)
    let coordinator = context.coordinator
    control.onReselect = { [weak coordinator] index in
      guard let coordinator else { return }
      if index >= 0 && index < coordinator.parent.tabs.count {
        coordinator.parent.tabs[index].onReselect?()
      }
    }

    // Wrap in glass tab bar view with segmented control and FAB
    let container = GlassTabBarView(
      segmentedControl: control,
      tabCount: tabs.count,
      action: action,
      secondaryActions: secondaryActions,
      isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled,
      density: density
    )
    container.updatePreferredCompactSegmentWidths(preferredCompactSegmentWidths)

    return container
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: GlassTabBarView,
    context _: Context
  ) -> CGSize? {
    guard density.hugsContentHorizontally else { return nil }
    let preferred = uiView.intrinsicContentSize
    let availableWidth = proposal.width ?? preferred.width
    return CGSize(
      width: max(0, min(preferred.width, availableWidth)),
      height: density.barHeight
    )
  }

  func updateUIView(_ uiView: GlassTabBarView, context: Context) {
    context.coordinator.parent = self
    uiView.updatePrimaryAction(
      action.action,
      isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled
    )

    let control = uiView.segmentedControl
    control.selectedSegmentTintColor = segmentTintColor(for: uiView.traitCollection)

    // Sync segments when tabs change (count, order, or identity), or rebuild
    // their content when the host switches between stacked and inline
    // density while this representable remains mounted.
    let currentTabValues = tabs.map(\.value)
    let currentPresentationSignatures = tabPresentationSignatures
    let tabsChanged = currentTabValues != context.coordinator.previousTabValues
    let presentationChanged = currentPresentationSignatures
      != context.coordinator.previousPresentationSignatures
    let densityChanged = density != context.coordinator.previousDensity
    if tabsChanged {
      context.coordinator.previousTabValues = currentTabValues

      // Rebuild all segments — configureSegmentContent replaces all
      // injected content views anyway, so incremental patching adds
      // complexity without benefit.
      control.removeAllSegments()
      for _ in tabs {
        control.insertSegment(
          with: UIImage(systemName: "circle"),
          at: control.numberOfSegments,
          animated: false
        )
      }
      uiView.updateTabCount(tabs.count)
    }

    if tabsChanged || presentationChanged || densityChanged {
      context.coordinator.previousPresentationSignatures = currentPresentationSignatures
      context.coordinator.previousDensity = density
      let preferredCompactSegmentWidths = configureSegmentContent(on: control)
      uiView.updatePreferredCompactSegmentWidths(preferredCompactSegmentWidths)
      uiView.updateDensity(density)
    }

    let newIndex = tabs.firstIndex { $0.value == activeTab } ?? 0
    if control.selectedSegmentIndex != newIndex {
      control.selectedSegmentIndex = newIndex
    }

    if collapseTrigger != context.coordinator.previousCollapseTrigger {
      context.coordinator.previousCollapseTrigger = collapseTrigger
      uiView.collapseSecondaryActions()
    }

    // Set accent color from the view's inherited tintColor, converted to a concrete color.
    // Only update when tintAdjustmentMode is normal — when dimmed (e.g. sheet presented),
    // tintColor returns a dimmed gray which would incorrectly overwrite the accent color.
    if uiView.tintAdjustmentMode == .normal, let tint = uiView.tintColor {
      let concreteAccentColor = UIColor(cgColor: tint.cgColor)
      control.activeTintColor = concreteAccentColor
    }
  }

  static func dismantleUIView(_ uiView: GlassTabBarView, coordinator _: Coordinator) {
    uiView.prepareForRemoval()
  }

  /// Sets accessibility titles, injects content views, and configures segment widths.
  private func configureSegmentContent(on control: TabBarSegmentedControl) -> [CGFloat] {
    for (index, tab) in tabs.enumerated() {
      control.setTitle(tab.resolvedTitle, forSegmentAt: index)
    }

    // Content views use draw(_:) rendering with NSCoding support, so when the
    // accessibility popover archives/unarchives them they hide (via init(coder:)),
    // letting the native segment labels render crisply at popover scale.
    // Two views per segment: base (inactive) underneath, accent (active) on top
    // masked to the glass indicator position.
    let baseViews = tabs.map(makeContentView)
    let accentViews = tabs.map(makeContentView)
    control.configureContentViews(baseViews, accentViews: accentViews)

    // Regular density keeps the existing equal, available-width segments.
    // Compact density sizes each selection pill from its own icon-label pair,
    // which lets the complete glass bar hug localized content.
    var preferredCompactSegmentWidths: [CGFloat] = []
    for index in 0..<tabs.count {
      let width: CGFloat
      switch density.tabItemLayout {
      case .stacked:
        width = tabs.count < 3 ? Constants.fewTabsSegmentWidth : 0
      case .inline:
        width = max(
          Constants.minimumInlineSegmentWidth,
          ceil(baseViews[index].intrinsicContentSize.width)
            + Constants.inlineSegmentHorizontalPadding * 2
        )
        preferredCompactSegmentWidths.append(width)
      }
      control.setWidth(width, forSegmentAt: index)
    }
    return preferredCompactSegmentWidths
  }

  private var tabPresentationSignatures: [FabBarTabPresentationSignature] {
    tabs.map { tab in
      FabBarTabPresentationSignature(
        value: AnyHashable(tab.value),
        title: tab.resolvedTitle,
        systemImage: tab.systemImage,
        image: tab.image,
        imageBundlePath: tab.imageBundle?.bundleURL.path
      )
    }
  }

  private func makeContentView(for tab: FabBarTab<Value>) -> TabItemContentView {
    if let imageName = tab.image {
      TabItemContentView(
        title: tab.resolvedTitle,
        imageName: imageName,
        imageBundle: tab.imageBundle,
        layout: density.tabItemLayout
      )
    } else {
      TabItemContentView(
        title: tab.resolvedTitle,
        symbolName: tab.systemImage ?? "",
        layout: density.tabItemLayout
      )
    }
  }

  private func segmentTintColor(for traitCollection: UITraitCollection) -> UIColor {
    switch traitCollection.userInterfaceStyle {
    case .dark:
      return .label.withAlphaComponent(0.15)
    default:
      return .label.withAlphaComponent(0.08)
    }
  }

  @MainActor
  class Coordinator: NSObject {
    var parent: FabBarRepresentable<Value>
    var previousTabValues: [Value]
    var previousPresentationSignatures: [FabBarTabPresentationSignature]
    var previousCollapseTrigger: Int
    var previousDensity: FabBarDensity

    init(parent: FabBarRepresentable<Value>) {
      self.parent = parent
      self.previousTabValues = parent.tabs.map(\.value)
      self.previousPresentationSignatures = parent.tabPresentationSignatures
      self.previousCollapseTrigger = parent.collapseTrigger
      self.previousDensity = parent.density
    }

    @objc func tabSelected(_ control: UISegmentedControl) {
      let index = control.selectedSegmentIndex
      if index >= 0 && index < parent.tabs.count {
        parent.activeTab = parent.tabs[index].value
      }
    }
  }
}
