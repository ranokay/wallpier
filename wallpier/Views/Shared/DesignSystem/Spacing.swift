//
//  Spacing.swift
//  wallpier
//
//  Design System - Spacing Constants
//

import SwiftUI

/// Centralized spacing system for consistent layouts
enum Spacing {
    // MARK: - Standard Spacing Scale

    /// Extra small spacing (4pt)
    static let xs: CGFloat = 4

    /// Small spacing (8pt)
    static let sm: CGFloat = 8

    /// Medium spacing (12pt)
    static let md: CGFloat = 12

    /// Large spacing (16pt)
    static let lg: CGFloat = 16

    /// Extra large spacing (20pt)
    static let xl: CGFloat = 20

    /// Double extra large spacing (24pt)
    static let xxl: CGFloat = 24

    /// Triple extra large spacing (32pt)
    static let xxxl: CGFloat = 32

    // MARK: - Component-Specific Spacing

    /// Sidebar width
    static let sidebarWidth: CGFloat = 260

    /// Content padding
    static let contentPadding: CGFloat = 24

    /// Card padding
    static let cardPadding: CGFloat = 16

    /// Section spacing
    static let sectionSpacing: CGFloat = 20

    /// Item spacing in lists
    static let listItemSpacing: CGFloat = 12

    /// Button spacing
    static let buttonSpacing: CGFloat = 8

    // MARK: - Corner Radius

    /// Small corner radius (6pt)
    static let cornerRadiusSmall: CGFloat = 6

    /// Medium corner radius (8pt)
    static let cornerRadiusMedium: CGFloat = 8

    /// Large corner radius (12pt)
    static let cornerRadiusLarge: CGFloat = 12

    /// Extra large corner radius (16pt)
    static let cornerRadiusXLarge: CGFloat = 16
}

// MARK: - Edge Insets Extensions

extension EdgeInsets {
    /// Standard content insets
    static let contentInsets = EdgeInsets(
        top: Spacing.contentPadding,
        leading: Spacing.contentPadding,
        bottom: Spacing.contentPadding,
        trailing: Spacing.contentPadding
    )

    /// Standard card insets
    static let cardInsets = EdgeInsets(
        top: Spacing.cardPadding,
        leading: Spacing.cardPadding,
        bottom: Spacing.cardPadding,
        trailing: Spacing.cardPadding
    )

    /// Compact insets for dense layouts
    static let compactInsets = EdgeInsets(
        top: Spacing.sm,
        leading: Spacing.sm,
        bottom: Spacing.sm,
        trailing: Spacing.sm
    )
}
