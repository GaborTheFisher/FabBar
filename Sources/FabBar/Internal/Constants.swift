import os
import UIKit

/// Centralized constants for FabBar components.
///
/// All magic numbers are documented here with rationale for their values.
@available(iOS 26.0, *)
enum Constants {
    // MARK: - Bar Dimensions

    /// Height of the entire tab bar.
    /// Matches the standard iOS tab bar height for visual consistency.
    static let barHeight: CGFloat = 62

    /// Height of the inline bar in its compact density
    /// (`FabBarDensity.compact`). Every interior metric (FAB diameter, pill
    /// heights, capsule corners) derives from the framed height.
    static let compactBarHeight: CGFloat = 52

    /// Maximum width of the glass bar on regular-width layouts. Keeping the
    /// bar visible preserves tab navigation while preventing its controls from
    /// stretching across an entire iPad or resizable window.
    static let regularWidthMaximumBarWidth: CGFloat = 600

    /// Spacing between the segmented control and FAB.
    static let fabSpacing: CGFloat = 8

    // MARK: - Layout Padding

    /// Horizontal padding for FabBar positioning.
    static let horizontalPadding: CGFloat = 21

    /// Bottom padding for FabBar positioning.
    /// Provides clearance above the home indicator.
    static let bottomPadding: CGFloat = 21

    /// Padding inside the glass container around the segmented control.
    static let contentPadding: CGFloat = 2

    // MARK: - Icon Sizing

    /// Point size for tab bar icons (SF Symbols).
    /// Uses medium weight at large scale to match SwiftUI's .imageScale(.large).
    static let tabIconPointSize: CGFloat = 18

    /// Point size for the FAB button icon.
    static let fabIconPointSize: CGFloat = 20

    /// Fixed size for the icon image view container.
    /// Provides consistent touch target and visual alignment.
    static let iconViewSize: CGFloat = 28

    /// Gap between the icon and its trailing label in compact inline mode.
    static let inlineIconTitleSpacing: CGFloat = 6

    // MARK: - Typography

    /// Font size for tab item titles.
    /// Matches Apple HIG recommendations for tab bar labels.
    static let tabTitleFontSize: CGFloat = 10

    /// Slightly larger label used beside the icon in compact inline mode.
    static let inlineTabTitleFontSize: CGFloat = 13

    // MARK: - Segment Sizing

    /// Fixed segment width used when there are fewer than 3 tabs.
    /// With 3+ tabs, segments auto-distribute to fill the available space.
    static let fewTabsSegmentWidth: CGFloat = 98

    /// Horizontal breathing room around an inline icon-label pair.
    static let inlineSegmentHorizontalPadding: CGFloat = 10

    /// Keeps every content-sized segment at least as wide as a standard
    /// minimum touch target.
    static let minimumInlineSegmentWidth: CGFloat = 44

}

/// Logger for FabBar warnings and diagnostics.
let fabBarLogger = Logger(subsystem: "com.ryanashcraft.FabBar", category: "FabBar")
