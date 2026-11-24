import AppKit
import Foundation
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

public enum ShelfItemKind: String, Sendable {
    case file
    case image
    case text
}

public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let sizeString: String
    public let isDirectory: Bool
    public let kind: ShelfItemKind

    public init(url: URL, kind: ShelfItemKind = .file, displayName: String? = nil) {
        self.id = UUID()
        self.url = url
        self.name = displayName ?? url.lastPathComponent
        self.kind = kind

        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        self.isDirectory = isDir.boolValue

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            self.sizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        } else {
            self.sizeString = isDir.boolValue ? "Folder" : "Item"
        }
    }
}

@MainActor
public final class FileShelfManager: ObservableObject {
    public static let shared = FileShelfManager()

    @Published public private(set) var items: [ShelfItem] = []
    @Published public private(set) var thumbnails: [UUID: NSImage] = [:]
    public var onShelfEmptied: (() -> Void)?

    private lazy var shelfTempDirectory: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("com.alexey.dynamicisland.shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - Item Addition

    public func addFile(_ url: URL) {
        guard !items.contains(where: { $0.url.path == url.path }) else { return }
        let kind: ShelfItemKind = Self.isImageURL(url) ? .image : .file
        let newItem = ShelfItem(url: url, kind: kind)
        items.insert(newItem, at: 0)
        SoundManager.shared.play("chime")
        HapticEngine.perform(.generic)
        generateThumbnail(for: newItem)
    }

    public func addTextSnippet(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let fileURL = shelfTempDirectory.appendingPathComponent("Snippet-\(Int(Date().timeIntervalSince1970)).txt")
        do {
            try trimmed.write(to: fileURL, atomically: true, encoding: .utf8)
            let previewName = String(trimmed.prefix(32))
            let newItem = ShelfItem(url: fileURL, kind: .text, displayName: previewName)
            items.insert(newItem, at: 0)
            SoundManager.shared.play("chime")
            HapticEngine.perform(.generic)
            generateThumbnail(for: newItem)
        } catch {
            // Skip failed temp write cleanly
        }
    }

    public func addDroppedImage(_ image: NSImage) {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return
        }
        let fileURL = shelfTempDirectory.appendingPathComponent("Image-\(Int(Date().timeIntervalSince1970)).png")
        do {
            try pngData.write(to: fileURL)
            let newItem = ShelfItem(url: fileURL, kind: .image, displayName: fileURL.lastPathComponent)
            items.insert(newItem, at: 0)
            thumbnails[newItem.id] = image
            SoundManager.shared.play("chime")
            HapticEngine.perform(.generic)
        } catch {
            // Skip failed image write cleanly
        }
    }

    private static func isImageURL(_ url: URL) -> Bool {
        let exts = ["png", "jpg", "jpeg", "heic", "webp", "gif", "tiff", "bmp", "svg"]
        return exts.contains(url.pathExtension.lowercased())
    }

    // MARK: - QuickLook Async Thumbnailing

    private func generateThumbnail(for item: ShelfItem) {
        let itemID = item.id
        let itemURL = item.url
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        let request = QLThumbnailGenerator.Request(
            fileAt: itemURL,
            size: CGSize(width: 64, height: 64),
            scale: scale,
            representationTypes: .thumbnail
        )

        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] representation, _ in
            guard let rep = representation else { return }
            let image = rep.nsImage
            Task { @MainActor [weak self] in
                self?.thumbnails[itemID] = image
            }
        }
    }

    public func thumbnail(for item: ShelfItem) -> NSImage {
        thumbnails[item.id] ?? NSWorkspace.shared.icon(forFile: item.url.path)
    }

    // MARK: - Drag Inspection Helper

    public static func pasteboardHasSupportedDragPayload() -> Bool {
        let pb = NSPasteboard(name: .drag)
        let types = pb.types ?? []
        return types.contains(.fileURL) || types.contains(.png) || types.contains(.tiff) || types.contains(.string)
    }

    // MARK: - Shelf Actions

    public func removeFile(id: UUID) {
        items.removeAll(where: { $0.id == id })
        thumbnails.removeValue(forKey: id)
        if items.isEmpty {
            onShelfEmptied?()
        }
    }

    public func clearAll() {
        items.removeAll()
        thumbnails.removeAll()
        onShelfEmptied?()
    }

    public func openItem(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    public func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    public func copyPath(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        if item.kind == .text, let text = try? String(contentsOf: item.url, encoding: .utf8) {
            NSPasteboard.general.setString(text, forType: .string)
        } else {
            NSPasteboard.general.writeObjects([item.url as NSURL])
            NSPasteboard.general.setString(item.url.path, forType: .string)
        }
        HapticEngine.perform(.generic)
    }

    public func shareItem(_ item: ShelfItem, from view: NSView? = nil) {
        let picker = NSSharingServicePicker(items: [item.url])
        if let anchorView = view {
            picker.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minY)
        } else if let keyContent = NSApp.windows.first(where: { $0.isVisible })?.contentView {
            let rect = NSRect(x: keyContent.bounds.midX - 20, y: keyContent.bounds.minY + 20, width: 40, height: 10)
            picker.show(relativeTo: rect, of: keyContent, preferredEdge: .minY)
        } else if let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: [item.url]) {
            service.perform(withItems: [item.url])
        }
    }
}
