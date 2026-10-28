import SwiftUI
import UIKit

/// The same UIKit view stays mounted when only its axis or geometry changes.
@available(iOS 26.0, *)
struct FabBarRepresentable<Value: Hashable>: UIViewRepresentable {
  var tabs: [FabBarTab<Value>]
  var action: FabBarAction
  var secondaryActions: [FabBarAction]
  var isSecondaryActionMenuEnabled: Bool
  var collapseTrigger: Int
  var placement: FabBarPlacement = .bottom
  var density: FabBarDensity = .regular
  var maximumLength: CGFloat? = nil
  @Binding var activeTab: Value

  func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

  func makeUIView(context: Context) -> GlassTabBarView {
    let control = FabBarTabControl()
    control.setTabs(descriptors, replacingIdentity: true)
    control.selectedSegmentIndex = tabs.firstIndex { $0.value == activeTab } ?? 0
    control.addTarget(context.coordinator, action: #selector(Coordinator.tabSelected(_:)), for: .valueChanged)
    let coordinator = context.coordinator
    control.onReselect = { [weak coordinator] index in
      guard let coordinator, coordinator.parent.tabs.indices.contains(index) else { return }
      coordinator.parent.tabs[index].onReselect?()
    }
    let view = GlassTabBarView(
      segmentedControl: control, tabCount: tabs.count, action: action,
      secondaryActions: secondaryActions, isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled)
    view.updateLayout(placement: placement, density: density, maximumLength: maximumLength)
    return view
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    uiView: GlassTabBarView,
    context _: Context
  ) -> CGSize? {
    guard !placement.isVertical, density.hugsContentHorizontally else { return nil }
    let preferred = uiView.intrinsicContentSize
    let availableWidth = proposal.width ?? preferred.width
    return CGSize(width: max(0, min(preferred.width, availableWidth)), height: density.barHeight)
  }

  func updateUIView(_ view: GlassTabBarView, context: Context) {
    context.coordinator.parent = self
    view.updateAction(action, secondaryActions: secondaryActions,
      isSecondaryActionMenuEnabled: isSecondaryActionMenuEnabled)
    let values = tabs.map(\.value)
    let replacesIdentity = values != context.coordinator.previousTabValues
    if replacesIdentity {
      view.collapseSecondaryActions()
      context.coordinator.previousTabValues = values
    }
    view.segmentedControl.setTabs(descriptors, replacingIdentity: replacesIdentity)
    view.updateTabCount(tabs.count)
    view.segmentedControl.selectedSegmentIndex = tabs.firstIndex { $0.value == activeTab } ?? 0
    view.updateLayout(placement: placement, density: density, maximumLength: maximumLength)
    if collapseTrigger != context.coordinator.previousCollapseTrigger {
      context.coordinator.previousCollapseTrigger = collapseTrigger
      view.collapseSecondaryActions()
    }
    if view.tintAdjustmentMode == .normal {
      view.segmentedControl.activeTintColor = view.tintColor
    }
  }

  private var descriptors: [FabBarTabDescriptor] {
    tabs.map { tab in
      let image = tab.image.flatMap { UIImage(named: $0, in: tab.imageBundle, compatibleWith: nil) }
        ?? tab.systemImage.flatMap { UIImage(systemName: $0) }
      return FabBarTabDescriptor(title: tab.resolvedTitle,
        image: image?.withRenderingMode(.alwaysTemplate), accessibilityIdentifier: tab.accessibilityIdentifier)
    }
  }

  static func dismantleUIView(_ view: GlassTabBarView, coordinator: Coordinator) {
    view.prepareForRemoval()
  }

  @MainActor
  final class Coordinator: NSObject {
    var parent: FabBarRepresentable<Value>
    var previousTabValues: [Value]
    var previousCollapseTrigger: Int
    init(parent: FabBarRepresentable<Value>) {
      self.parent = parent
      previousTabValues = parent.tabs.map(\.value)
      previousCollapseTrigger = parent.collapseTrigger
    }
    @objc func tabSelected(_ control: FabBarTabControl) {
      let index = control.selectedSegmentIndex
      if parent.tabs.indices.contains(index) { parent.activeTab = parent.tabs[index].value }
    }
  }
}
