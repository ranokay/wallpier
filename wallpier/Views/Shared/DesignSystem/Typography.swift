//
//  Typography.swift
//  wallpier
//
//  Design System - Typography System
//

import SwiftUI

/// Centralized typography system for consistent text styles
enum Typography {
    // MARK: - Font Weights

    static let regular = Font.Weight.regular
    static let medium = Font.Weight.medium
    static let semibold = Font.Weight.semibold
    static let bold = Font.Weight.bold

    // MARK: - Text Styles

    /// Large title style (28pt, bold)
    static let largeTitle = Font.system(size: 28, weight: .bold)

    /// Title style (22pt, semibold)
    static let title = Font.system(size: 22, weight: .semibold)

    /// Title 2 style (20pt, semibold)
    static let title2 = Font.system(size: 20, weight: .semibold)

    /// Title 3 style (18pt, semibold)
    static let title3 = Font.system(size: 18, weight: .semibold)

    /// Headline style (15pt, semibold)
    static let headline = Font.system(size: 15, weight: .semibold)

    /// Body style (13pt, regular)
    static let body = Font.system(size: 13, weight: .regular)

    /// Body medium style (13pt, medium)
    static let bodyMedium = Font.system(size: 13, weight: .medium)

    /// Callout style (12pt, regular)
    static let callout = Font.system(size: 12, weight: .regular)

    /// Subheadline style (11pt, regular)
    static let subheadline = Font.system(size: 11, weight: .regular)

    /// Footnote style (10pt, regular)
    static let footnote = Font.system(size: 10, weight: .regular)

    /// Caption style (10pt, regular)
    static let caption = Font.system(size: 10, weight: .regular)

    /// Caption 2 style (9pt, regular)
    static let caption2 = Font.system(size: 9, weight: .regular)
}

// MARK: - Text Style View Modifiers

extension View {
    /// Applies large title typography style
    func largeTitleStyle() -> some View {
        self.font(Typography.largeTitle)
    }

    /// Applies title typography style
    func titleStyle() -> some View {
        self.font(Typography.title)
    }

    /// Applies headline typography style
    func headlineStyle() -> some View {
        self.font(Typography.headline)
            .foregroundColor(AppColors.contentPrimary)
    }

    /// Applies body typography style
    func bodyStyle() -> some View {
        self.font(Typography.body)
            .foregroundColor(AppColors.contentPrimary)
    }

    /// Applies secondary text style
    func secondaryTextStyle() -> some View {
        self.font(Typography.body)
            .foregroundColor(AppColors.contentSecondary)
    }

    /// Applies caption typography style
    func captionStyle() -> some View {
        self.font(Typography.caption)
            .foregroundColor(AppColors.contentSecondary)
    }
}
