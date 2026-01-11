//
//  ToastView.swift
//  wallpier
//
//  Toast notification component for success messages
//

import SwiftUI

struct ToastView: View {
    @Binding var isPresented: Bool
    let message: String

    var body: some View {
        VStack {
            Spacer()

            if isPresented {
                HStack(spacing: Spacing.md) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .medium))

                    Text(message)
                        .foregroundColor(.white)
                        .font(.system(size: 14, weight: .medium))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Spacing.cornerRadiusMedium)
                        .fill(AppColors.success)
                        .shadow(color: AppColors.shadowMedium, radius: 4, x: 0, y: 2)
                )
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .animation(Animations.smoothSpring, value: isPresented)
            }
        }
        .padding(.bottom, Spacing.sectionSpacing)
        .allowsHitTesting(false) // Allow clicks to pass through
    }
}
