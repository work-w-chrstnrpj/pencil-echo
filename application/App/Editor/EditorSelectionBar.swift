import Observation
import SwiftUI

/// What the SwiftUI shell needs from the UIKit editor (ticket 024). The controller
/// writes it; the navigation bar, View menu and selection bar read it.
@MainActor
@Observable
final class EditorChromeState {
    var selectMode = false
    var hasSelection = false
    /// One editable text, Markdown, formula or graph object is selected.
    var canEditSelection = false
    var isEditable = true
    /// Selection bounds in the editor view's coordinates; nil without a selection or while dragging.
    var selectionRect: CGRect?
    var viewportFrame: CGRect = .zero
    var pageIndex = 0
    var pageCount = 1
    var pageStyle: BackgroundStyle = .blank
    /// A short notice for the glass card, such as "A notebook keeps at least one page."
    var notice: String?
}

/// Floating glass bar above a lasso selection: Edit, Ask about selection, Delete.
struct EditorSelectionBar: View {
    let chrome: EditorChromeState
    /// Space the tool picker covers at the bottom of the editor, in points.
    let bottomClearance: CGFloat
    let canAsk: Bool
    let onEdit: () -> Void
    let onAsk: () -> Void
    let onDelete: () -> Void

    static let height: CGFloat = 52
    static let gap: CGFloat = 12

    var body: some View {
        GeometryReader { proxy in
            if let rect = chrome.selectionRect, chrome.hasSelection {
                bar
                    .fixedSize()
                    .position(Self.position(for: rect, in: proxy.size, bottomClearance: bottomClearance))
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.2), value: chrome.selectionRect)
    }

    private var bar: some View {
        GlassEffectContainer {
            HStack(spacing: 4) {
                if chrome.canEditSelection {
                    Button("Edit", systemImage: "character.cursor.ibeam", action: onEdit)
                        .accessibilityIdentifier("selection-edit")
                }
                Button("Ask AI", systemImage: "sparkles", action: onAsk)
                    .disabled(!canAsk)
                    .accessibilityHint("Asks AI about the selected work")
                    .accessibilityIdentifier("selection-ask")
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    .accessibilityIdentifier("selection-delete")
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.glass)
            .controlSize(.regular)
            .disabled(!chrome.isEditable)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Selection actions")
    }

    /// Centered above the selection, or below it when there's no room above; always on
    /// screen and never under the tool picker.
    static func position(for rect: CGRect, in size: CGSize, bottomClearance: CGFloat) -> CGPoint {
        let half = height / 2
        let minY = half + gap
        let maxY = max(minY, size.height - bottomClearance - half - gap)
        var y = rect.minY - gap - half
        if y < minY { y = rect.maxY + gap + half }
        y = min(max(y, minY), maxY)
        let x = min(max(rect.midX, 160), max(160, size.width - 160))
        return CGPoint(x: x, y: y)
    }
}
