//
//  AboutSettingsView.swift
//  wallpier
//
//  About tab - App information and credits
//

import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.xxl) {
                Spacer(minLength: Spacing.sectionSpacing)

                // App Icon and Title
                VStack(spacing: Spacing.md) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .foregroundStyle(.linearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))

                    Text("Wallpier")
                        .font(.title)
                        .fontWeight(.bold)

                    Text("Dynamic Wallpaper Cycling for macOS")
                        .font(.subheadline)
                        .foregroundColor(AppColors.contentSecondary)
                }

                // App Info
                VStack(spacing: Spacing.sm) {
                    HStack {
                        Text("Version")
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0")
                            .secondaryTextStyle()
                    }

                    HStack {
                        Text("Build")
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .secondaryTextStyle()
                    }

                    HStack {
                        Text("Bundle ID")
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Text(Bundle.main.bundleIdentifier ?? "com.oxystack.wallpier")
                            .font(Typography.caption)
                            .foregroundColor(AppColors.contentSecondary)
                    }
                }
                .padding(Spacing.lg)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: Spacing.cornerRadiusLarge))
                .frame(maxWidth: 300)

                Spacer(minLength: Spacing.sectionSpacing)

                // Copyright
                Text("© 2025 Oxystack. All rights reserved.")
                    .captionStyle()
            }
            .frame(maxWidth: .infinity)
            .padding(Spacing.lg)
        }
    }
}
