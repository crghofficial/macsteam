// Import drop targets and delete-key table
import AppKit

@MainActor
final class DeletingTableView: NSTableView {
    var onDeleteKey: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if deleteKeyCodes.contains(event.keyCode) { onDeleteKey?(); return }
        super.keyDown(with: event)
    }
}

@MainActor
private func draggedImportURLs(in sender: NSDraggingInfo) -> [URL] {
    let urls = sender.draggingPasteboard.readObjects(
        forClasses: [NSURL.self],
        options: [.urlReadingFileURLsOnly: true]) as? [URL]
    return urls?.filter {
        ["zip", "lua"].contains($0.pathExtension.lowercased()) || $0.hasDirectoryPath
    } ?? []
}

class ImportDropView: NSView {
    var onDrop: (([URL]) -> Void)?
    var isEnabled = true

    var isTargeted = false

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isEnabled, !draggedImportURLs(in: sender).isEmpty else { return [] }
        isTargeted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isTargeted = false
        let sources = draggedImportURLs(in: sender)
        guard isEnabled, !sources.isEmpty else { return false }
        onDrop?(sources)
        return true
    }
}

// MARK: - Empty-state well

final class DropZoneView: ImportDropView {
    var onActivate: (() -> Void)?

    override var isEnabled: Bool {
        didSet {
            alphaValue = isEnabled ? 1 : 0.5
            if !isEnabled, window?.firstResponder === self { window?.makeFirstResponder(nil) }
        }
    }

    private let glyph = NSImageView()
    private let label = NSTextField(labelWithString: L10n.text("Drop Zips, Folders, or .lua Files Here"))
    private let borderLayer = CAShapeLayer()

    override var isTargeted: Bool { didSet { applyAppearance() } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        focusRingType = .exterior

        borderLayer.fillColor = nil
        borderLayer.lineWidth = 1
        borderLayer.lineDashPattern = [6, 4]
        layer?.addSublayer(borderLayer)

        glyph.image = NSImage(systemSymbolName: "arrow.down.doc",
                              accessibilityDescription: L10n.text("Drop files"))
        glyph.symbolConfiguration = .init(pointSize: 26, weight: .regular)
        glyph.translatesAutoresizingMaskIntoConstraints = false

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = Typography.sectionHeader
        label.alignment = .center

        let stack = NSStackView(views: [glyph, label])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 2
        stack.setCustomSpacing(6, after: glyph)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        registerForDraggedTypes([.fileURL])

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(L10n.text("Choose files to import"))
        setAccessibilityHelp(L10n.text("Drop unlock zips or lua files here, or activate to browse."))
        glyph.setAccessibilityElement(false)

        applyAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: keyboard + focus

    override var acceptsFirstResponder: Bool { isEnabled }
    override var canBecomeKeyView: Bool { isEnabled }

    override func becomeFirstResponder() -> Bool { needsDisplay = true; return super.becomeFirstResponder() }
    override func resignFirstResponder() -> Bool { needsDisplay = true; return super.resignFirstResponder() }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: Metrics.cornerRadius, yRadius: Metrics.cornerRadius).fill()
    }
    override var focusRingMaskBounds: NSRect { bounds }

    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers
        if isEnabled, key == " " || key == "\r" {
            activate()
        } else {
            super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if isEnabled { activate() } else { super.mouseDown(with: event) }
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        activate()
        return true
    }

    private func activate() {
        window?.makeFirstResponder(self)
        onActivate?()
    }

    override func layout() {
        super.layout()
        let inset = borderLayer.lineWidth / 2
        let rect = bounds.insetBy(dx: inset, dy: inset)
        borderLayer.frame = bounds
        borderLayer.path = CGPath(roundedRect: rect,
                                  cornerWidth: Metrics.cornerRadius,
                                  cornerHeight: Metrics.cornerRadius,
                                  transform: nil)
    }

    private func applyAppearance() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [self] in
            let accent = NSColor.controlAccentColor
            borderLayer.strokeColor = (isTargeted ? accent : NSColor.clear).cgColor
            layer?.backgroundColor = isTargeted
                ? accent.withAlphaComponent(0.08).cgColor
                : NSColor.clear.cgColor
            glyph.contentTintColor = isTargeted ? accent : .secondaryLabelColor
            label.textColor = isTargeted ? .labelColor : .secondaryLabelColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyAppearance()
    }
}

// MARK: - Loaded-state list drop target

final class PaneDropView: ImportDropView {
    override var isTargeted: Bool { didSet { needsDisplay = true } }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = Metrics.cornerRadius
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateLayer() {
        let accent = NSColor.controlAccentColor
        layer?.backgroundColor = isTargeted ? accent.withAlphaComponent(0.08).cgColor : NSColor.clear.cgColor
    }
}
