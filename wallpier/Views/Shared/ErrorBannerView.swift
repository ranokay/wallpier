import SwiftUI

/// Banner view for displaying errors to the user
struct ErrorBannerView: View {
    let error: PresentedError
    let onDismiss: () -> Void
    let onRetry: (() async -> Void)?

    @State private var isRetrying = false

    var body: some View {
        HStack(spacing: Spacing.lg) {
            // Icon
            Image(systemName: error.severity.iconName)
                .font(.title2)
                .foregroundStyle(error.severity.color)

            // Content
            VStack(alignment: .leading, spacing: Spacing.sm) {
                // Title with error code
                HStack(spacing: Spacing.xs) {
                    Text(error.title)
                        .font(Typography.bodyMedium)

                    if let errorCode = error.errorCode {
                        Text("[\\(errorCode)]")
                            .font(Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Message
                Text(error.message)
                    .font(Typography.body)
                    .foregroundStyle(.secondary)

                // Recovery suggestion
                if let suggestion = error.recoverySuggestion {
                    Text(suggestion)
                        .font(Typography.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, Spacing.xs)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: Spacing.sm) {
                // Retry button
                if error.canRetry, let onRetry = onRetry {
                    Button {
                        handleRetry(onRetry)
                    } label: {
                        if isRetrying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.primary)
                    .disabled(isRetrying)
                }

                // Dismiss button
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.lg)
        .background(backgroundForSeverity)
        .cornerRadius(Spacing.cornerRadiusMedium)
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .padding(.horizontal, Spacing.lg)
    }

    private var backgroundForSeverity: some View {
        Group {
            switch error.severity {
            case .error:
                Color.red.opacity(0.1)
            case .warning:
                Color.orange.opacity(0.1)
            case .info:
                Color.blue.opacity(0.1)
            }
        }
    }

    private func handleRetry(_ retryAction: @escaping () async -> Void) {
        isRetrying = true
        Task {
            await retryAction()
            isRetrying = false
        }
    }
}

// MARK: - Error Overlay Modifier

/// View modifier that displays error banner overlay
struct ErrorOverlayModifier: ViewModifier {
    @ObservedObject var errorPresenter: ErrorPresenter
    let onRetry: (() async -> Void)?

    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content

            if errorPresenter.showError, let error = errorPresenter.currentError {
                ErrorBannerView(
                    error: error,
                    onDismiss: {
                        errorPresenter.dismiss()
                    },
                    onRetry: onRetry
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: errorPresenter.showError)
                .zIndex(1000)
                .padding(.top, Spacing.lg)
            }
        }
    }
}

extension View {
    /// Adds error banner overlay to the view
    func errorBanner(
        presenter: ErrorPresenter,
        onRetry: (() async -> Void)? = nil
    ) -> some View {
        modifier(ErrorOverlayModifier(errorPresenter: presenter, onRetry: onRetry))
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: Spacing.xxl) {
        ErrorBannerView(
            error: PresentedError(
                title: "Wallpaper Error",
                message: "Failed to set wallpaper for the selected image.",
                recoverySuggestion: "Try selecting a different image or restart the application.",
                severity: .error,
                errorCode: "W008",
                canRetry: true
            ),
            onDismiss: {},
            onRetry: {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        )

        ErrorBannerView(
            error: PresentedError(
                title: "Warning",
                message: "Cache is nearing capacity.",
                recoverySuggestion: "Consider clearing the cache in Settings > Advanced.",
                severity: .warning,
                errorCode: "C002"
            ),
            onDismiss: {},
            onRetry: nil
        )

        ErrorBannerView(
            error: PresentedError(
                title: "Info",
                message: "Folder scan completed successfully.",
                severity: .info
            ),
            onDismiss: {},
            onRetry: nil
        )
    }
    .padding()
}
