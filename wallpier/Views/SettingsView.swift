//
//  SettingsView.swift
//  wallpier
//
//  Settings window coordinator - manages settings tabs
//

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: SettingsTab = .general

    enum SettingsTab: String, CaseIterable {
        case general = "General"
        case display = "Display"
        case system = "System"
        case advanced = "Advanced"
        case about = "About"

        var icon: String {
            switch self {
            case .general: return "gear"
            case .display: return "display"
            case .system: return "macwindow"
            case .advanced: return "cpu"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            DisplaySettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Display", systemImage: "display")
                }
                .tag(SettingsTab.display)

            SystemSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("System", systemImage: "macwindow")
                }
                .tag(SettingsTab.system)

            AdvancedSettingsView(viewModel: viewModel)
                .tabItem {
                    Label("Advanced", systemImage: "cpu")
                }
                .tag(SettingsTab.advanced)

            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .frame(width: 550, height: 400)
        .padding()
        .overlay(
            // Toast notification overlay
            ToastView(
                isPresented: $viewModel.showToast,
                message: viewModel.toastMessage
            )
        )
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    viewModel.cancelChanges()
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    viewModel.saveSettings()
                    dismiss()
                }
                .disabled(viewModel.validationErrors.isEmpty == false)
            }
        }
    }
}

// Note: Settings tab views extracted to separate files:
// - GeneralSettingsView -> Views/Settings/GeneralSettingsView.swift
// - DisplaySettingsView -> Views/Settings/DisplaySettingsView.swift
// - SystemSettingsView -> Views/Settings/SystemSettingsView.swift
// - AdvancedSettingsView -> Views/Settings/AdvancedSettingsView.swift
// - AboutSettingsView -> Views/Settings/AboutSettingsView.swift
// - ToastView -> Views/Shared/ToastView.swift

#Preview {
    SettingsView(viewModel: SettingsViewModel(settings: WallpaperSettings()))
}
