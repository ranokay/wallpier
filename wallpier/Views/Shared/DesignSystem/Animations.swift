//
//  Animations.swift
//  wallpier
//
//  Design System - Animation Constants
//

import SwiftUI

/// Centralized animation configurations for consistent motion
enum Animations {
    // MARK: - Duration Constants

    /// Fast animation duration (0.15s)
    static let fast: TimeInterval = 0.15

    /// Medium animation duration (0.25s)
    static let medium: TimeInterval = 0.25

    /// Slow animation duration (0.35s)
    static let slow: TimeInterval = 0.35

    // MARK: - Standard Animations

    /// Fast ease out animation
    static let fastEaseOut = Animation.easeOut(duration: fast)

    /// Medium ease in-out animation
    static let mediumEaseInOut = Animation.easeInOut(duration: medium)

    /// Slow ease out animation
    static let slowEaseOut = Animation.easeOut(duration: slow)

    /// Spring animation for bouncy effects
    static let spring = Animation.spring(response: 0.3, dampingFraction: 0.7)

    /// Smooth spring animation
    static let smoothSpring = Animation.spring(response: 0.4, dampingFraction: 0.8)

    // MARK: - Transitions

    /// Fade transition
    static let fade = AnyTransition.opacity

    /// Slide from top transition
    static let slideFromTop = AnyTransition.move(edge: .top).combined(with: .opacity)

    /// Slide from bottom transition
    static let slideFromBottom = AnyTransition.move(edge: .bottom).combined(with: .opacity)

    /// Scale transition
    static let scale = AnyTransition.scale.combined(with: .opacity)
}

// MARK: - View Extensions for Animations

extension View {
    /// Applies standard fade animation
    func animatedFade() -> some View {
        self.animation(Animations.fastEaseOut, value: UUID())
    }

    /// Applies smooth scale effect on hover
    func scaleOnHover(_ isHovered: Bool, scale: CGFloat = 1.02) -> some View {
        self.scaleEffect(isHovered ? scale : 1.0)
            .animation(Animations.smoothSpring, value: isHovered)
    }
}
