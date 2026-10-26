import SwiftUI

/// Where FabBar draws its navigation capsule and separate primary action.
/// Leading and trailing are logical edges, resolved once by the host's layout
/// direction. Automatic follows the system's preferred vertical edge on iOS
/// 27.1 and later, and remains at the bottom on earlier systems.
@available(iOS 26.0, *)
public enum FabBarPlacement: String, CaseIterable, Hashable, Sendable {
  case automatic
  case bottom
  case leading
  case trailing

  public var isVertical: Bool { self == .leading || self == .trailing }

  public func resolved(preferredVerticalEdge: HorizontalEdge?) -> FabBarPlacement {
    guard self == .automatic else { return self }
    switch preferredVerticalEdge {
    case .leading: return .leading
    case .trailing: return .trailing
    case nil: return .bottom
    }
  }

  var alignment: Alignment {
    switch self {
    case .leading: return .bottomLeading
    case .trailing: return .bottomTrailing
    case .automatic, .bottom: return .bottom
    }
  }
}

/// Resolves a placement without replacing the content's structural identity as
/// the preferred edge changes. Use this when hosting FabBar directly and when
/// the surrounding layout also needs to know which edge to reserve.
@available(iOS 26.0, *)
public struct FabBarPlacementReader<Content: View>: View {
  private let placement: FabBarPlacement
  private let content: (FabBarPlacement) -> Content

  public init(
    placement: FabBarPlacement = .automatic,
    @ViewBuilder content: @escaping (FabBarPlacement) -> Content
  ) {
    self.placement = placement
    self.content = content
  }

  public var body: some View {
    if #available(iOS 27.1, *) {
      PreferredFabBarPlacementReader(placement: placement, content: content)
    } else {
      content(placement.resolved(preferredVerticalEdge: nil))
    }
  }
}

@available(iOS 27.1, *)
private struct PreferredFabBarPlacementReader<Content: View>: View {
  let placement: FabBarPlacement
  let content: (FabBarPlacement) -> Content
  @Environment(\.toolbarVerticalEdge) private var preferredEdge

  var body: some View {
    content(placement.resolved(preferredVerticalEdge: preferredEdge))
  }
}

@available(iOS 26.0, *)
enum FabBarLayoutPolicy {
  static func nominalVerticalLength(tabCount: Int, density: FabBarDensity) -> CGFloat {
    CGFloat(max(1, tabCount) + 1) * density.barHeight + Constants.fabSpacing
  }

  static func verticalLength(
    tabCount: Int,
    density: FabBarDensity,
    maximumLength: CGFloat?
  ) -> CGFloat {
    let nominal = nominalVerticalLength(tabCount: tabCount, density: density)
    guard let maximumLength, maximumLength.isFinite, maximumLength > 0,
          nominal > maximumLength else { return nominal }
    // Preserve two full hit regions: the navigation chooser and primary
    // action. The host can reserve this minimum without shrinking controls.
    return 2 * density.barHeight + Constants.fabSpacing
  }
}

#if DEBUG
@available(iOS 26.0, *)
#Preview("Placement reader") {
  FabBarPlacementReader { placement in
    Text("Resolved FabBar: \(placement.rawValue)")
      .padding()
  }
}
#endif
