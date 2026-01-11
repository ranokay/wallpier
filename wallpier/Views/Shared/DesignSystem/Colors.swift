//
//  Colors.swift
//  wallpier
//
//  Design System - Color Palette
//

import SwiftUI

/// Centralized color palette for the application
enum AppColors {
    // MARK: - Semantic Colors

    /// Primary brand colors
    static let primary = Color.accentColor
    static let primaryLight = Color.accentColor.opacity(0.8)
    static let primaryDark = Color.accentColor.opacity(1.2)

    /// Background colors
    static let background = Color(NSColor.windowBackgroundColor)
    static let backgroundSecondary = Color(NSColor.controlBackgroundColor)
    static let backgroundTertiary = Color(NSColor.controlBackgroundColor).opacity(0.5)

    /// Content colors
    static let contentPrimary = Color.primary
    static let contentSecondary = Color.secondary
    static let contentTertiary = Color(NSColor.tertiaryLabelColor)
    static let contentDisabled = Color(NSColor.disabledControlTextColor)

    /// Status colors
    static let success = Color.green
    static let warning = Color.orange
    static let error = Color.red
    static let info = Color.blue

    /// Interactive states
    static let hover = Color.primary.opacity(0.1)
    static let pressed = Color.primary.opacity(0.2)
    static let selected = Color.accentColor.opacity(0.2)

    /// Borders and dividers
    static let border = Color(NSColor.separatorColor)
    static let borderLight = Color(NSColor.separatorColor).opacity(0.5)
    static let borderHeavy = Color(NSColor.separatorColor).opacity(1.5)

    // MARK: - Material Colors

    static let materialRegular = Color(NSColor.controlBackgroundColor)
    static let materialThick = Color(NSColor.windowBackgroundColor)

    // MARK: - Shadow Colors

    static let shadowLight = Color.black.opacity(0.05)
    static let shadowMedium = Color.black.opacity(0.1)
    static let shadowHeavy = Color.black.opacity(0.15)
}
