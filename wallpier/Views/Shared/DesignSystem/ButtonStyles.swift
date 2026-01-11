//
//  ButtonStyles.swift
//  wallpier
//
//  Design System - Custom Button Styles
//

import SwiftUI

// MARK: - Primary Button Style

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.bodyMedium)
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                    .fill(isEnabled ? AppColors.primary : AppColors.contentDisabled)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Animations.fastEaseOut, value: configuration.isPressed)
            .opacity(isEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Secondary Button Style

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body)
            .foregroundColor(isEnabled ? AppColors.contentPrimary : AppColors.contentDisabled)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                    .strokeBorder(AppColors.border, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                            .fill(configuration.isPressed ? AppColors.pressed : AppColors.backgroundSecondary)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(Animations.fastEaseOut, value: configuration.isPressed)
            .opacity(isEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Danger Button Style

struct DangerButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.bodyMedium)
            .foregroundColor(.white)
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                    .fill(isEnabled ? AppColors.error : AppColors.contentDisabled)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Animations.fastEaseOut, value: configuration.isPressed)
            .opacity(isEnabled ? 1.0 : 0.6)
    }
}

// MARK: - Toolbar Button Style

struct ToolbarButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.body)
            .foregroundColor(isEnabled ? AppColors.contentPrimary : AppColors.contentDisabled)
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Spacing.cornerRadiusSmall)
                    .fill(configuration.isPressed ? AppColors.pressed : (isHovered ? AppColors.hover : Color.clear))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(Animations.fastEaseOut, value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Button Style Extensions

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

extension ButtonStyle where Self == DangerButtonStyle {
    static var danger: DangerButtonStyle { DangerButtonStyle() }
}

extension ButtonStyle where Self == ToolbarButtonStyle {
    static var toolbar: ToolbarButtonStyle { ToolbarButtonStyle() }
}
