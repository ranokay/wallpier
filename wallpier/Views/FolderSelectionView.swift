//
//  FolderSelectionView.swift
//  wallpier
//
//  Created by Yuuta on 28.06.2025.
//

import SwiftUI
import UniformTypeIdentifiers

struct FolderSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedURL: URL?
    @State private var isScanning = false
    @State private var foundImages: [ImageFile] = []
    @State private var scanProgress = 0
    @State private var errorMessage: String?
    @State private var showingFilePicker = false

    let onFolderSelected: (URL) -> Void
    let initialURL: URL?

    init(initialURL: URL? = nil, onFolderSelected: @escaping (URL) -> Void) {
        self.initialURL = initialURL
        self.onFolderSelected = onFolderSelected
        self._selectedURL = State(initialValue: initialURL)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)

                    Text("Select Wallpaper Folder")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("Choose a folder containing images to use as wallpapers")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)

                // Folder Selection Area
                VStack(spacing: 16) {
                    // Current Selection Display
                    if let selectedURL = selectedURL {
                        FolderDisplayCard(url: selectedURL)
                    } else {
                        PlaceholderCard()
                    }

                    // Browse Button
                    Button(action: openFilePicker) {
                        HStack {
                            Image(systemName: "folder")
                            Text(selectedURL == nil ? "Choose Folder..." : "Change Folder...")
                        }
                        .frame(minWidth: 200)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // Scanning Progress
                if isScanning {
                    VStack(spacing: 12) {
                        ProgressView("Scanning folder...")
                            .progressViewStyle(LinearProgressViewStyle())

                        Text("Found \(scanProgress) files...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }

                // Results Preview
                if !foundImages.isEmpty && !isScanning {
                    ImagePreviewSection(images: foundImages)
                }

                // Error Display
                if let errorMessage = errorMessage {
                    ErrorMessageView(message: errorMessage) {
                        self.errorMessage = nil
                    }
                }

                Spacer()
            }
            .padding()
            .frame(minWidth: 500, minHeight: 400)
            .navigationTitle("Folder Selection")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Select") {
                        if let url = selectedURL {
                            onFolderSelected(url)
                            dismiss()
                        }
                    }
                    .disabled(selectedURL == nil || foundImages.isEmpty)
                }
            }
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            handleFileSelection(result)
        }
        .task {
            if let initialURL = initialURL {
                await scanFolder(initialURL)
            }
        }
    }

    // MARK: - Actions

    private func openFilePicker() {
        showingFilePicker = true
    }

    private func handleFileSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                selectedURL = url
                errorMessage = nil
                Task {
                    await scanFolder(url)
                }
            }
        case .failure(let error):
            errorMessage = "Failed to select folder: \(error.localizedDescription)"
        }
    }

    private func scanFolder(_ url: URL) async {
        isScanning = true
        scanProgress = 0
        foundImages = []
        errorMessage = nil

        do {
            let scanner = ImageScannerService()
            let images = try await scanner.scanDirectoryRecursively(url) { progress in
                Task { @MainActor in
                    scanProgress = progress
                }
            }

            await MainActor.run {
                foundImages = images
                isScanning = false

                if images.isEmpty {
                    errorMessage = "No supported image files found in the selected folder"
                }
            }
        } catch {
            await MainActor.run {
                isScanning = false
                errorMessage = "Failed to scan folder: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Supporting Views

struct FolderDisplayCard: View {
    let url: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                        .lineLimit(1)

                    Text(url.path)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                Spacer()
            }

            // Folder Info
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                HStack {
                    if let modificationDate = attributes[.modificationDate] as? Date {
                        Label(modificationDate.formatted(date: .abbreviated, time: .omitted),
                              systemImage: "calendar")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Label("Accessible", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
        )
    }
}

struct PlaceholderCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 36))
                .foregroundColor(.secondary)

            Text("No folder selected")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Click \"Choose Folder...\" to select a folder containing wallpaper images")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5]))
        )
    }
}

struct ImagePreviewSection: View {
    let images: [ImageFile]
    @State private var selectedImageIndex = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Found Images")
                    .font(.headline)

                Spacer()

                Text("\(images.count) images")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            if !images.isEmpty {
                // Image Grid Preview (first few images)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                    ForEach(Array(images.prefix(8).enumerated()), id: \.offset) { index, image in
                        ImageThumbnailView(imageFile: image)
                            .aspectRatio(1, contentMode: .fit)
                            .cornerRadius(6)
                            .onTapGesture {
                                selectedImageIndex = index
                            }
                    }
                }
                .frame(height: 120)

                // Image Statistics
                VStack(alignment: .leading, spacing: 4) {
                    Text("Total size: \(images.formattedTotalSize)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    let extensions = Set(images.map { $0.pathExtension.lowercased() })
                    Text("Types: \(extensions.sorted().joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
}

struct ImageThumbnailView: View {
    let imageFile: ImageFile
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail = thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.secondary.opacity(0.3))
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundColor(.secondary)
                    }
            }
        }
        .clipped()
        .task {
            await loadThumbnail()
        }
    }

    private func loadThumbnail() async {
        thumbnail = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                if let image = NSImage(contentsOf: imageFile.url) {
                    // Create a smaller thumbnail for performance
                    let thumbnailSize = NSSize(width: 60, height: 60)
                    let thumbnail = NSImage(size: thumbnailSize)
                    thumbnail.lockFocus()
                    image.draw(in: NSRect(origin: .zero, size: thumbnailSize),
                              from: NSRect(origin: .zero, size: image.size),
                              operation: .copy,
                              fraction: 1.0)
                    thumbnail.unlockFocus()

                    DispatchQueue.main.async {
                        continuation.resume(returning: thumbnail)
                    }
                } else {
                    DispatchQueue.main.async {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }
}

struct ErrorMessageView: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)

            Text(message)
                .font(.subheadline)

            Spacer()

            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
    }
}

#Preview {
    FolderSelectionView { _ in }
}