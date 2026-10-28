import AppKit
import Foundation
import SwiftUI

public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let url: URL
    public let name: String
    public let sizeString: String
    public let isDirectory: Bool

    public init(url: URL) {
        self.id = UUID()
        self.url = url
        self.name = url.lastPathComponent
        
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

    private init() {}

    public func addFile(_ url: URL) {
        // Prevent duplicates
        guard !items.contains(where: { $0.url.path == url.path }) else { return }
        let newItem = ShelfItem(url: url)
        items.insert(newItem, at: 0)
        SoundManager.shared.play("chime")
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    public func removeFile(id: UUID) {
        items.removeAll(where: { $0.id == id })
    }

    public func clearAll() {
        items.removeAll()
    }

    public func openItem(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    public func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    public func copyPath(_ item: ShelfItem) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(item.url.path, forType: .string)
        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
    }

    public func airDrop(_ item: ShelfItem) {
        if let service = NSSharingService(named: .sendViaAirDrop) {
            if service.canPerform(withItems: [item.url]) {
                service.perform(withItems: [item.url])
            }
        }
    }
}
