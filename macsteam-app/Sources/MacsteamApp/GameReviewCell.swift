// Import review game row
import AppKit

final class GameReviewCell: NSTableCellView {
    static let artInset: CGFloat = 8
    static let artAspect: CGFloat = 460.0 / 215.0

    static func reuseID(for rowHeight: CGFloat) -> NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier("GameReviewCell-\(Int(rowHeight))")
    }

    private let tileHeight: CGFloat
    private let tileWidth: CGFloat

    private let tile = NSView()
    private let glyph = NSImageView()
    private let artView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let summaryLabel = NSTextField(labelWithString: "")
    private let markerLabel = NSTextField(labelWithString: "")

    private let removeButton = NSButton()
    private var hoverArea: NSTrackingArea?
    var onRemove: (() -> Void)?

    init(identifier: NSUserInterfaceItemIdentifier, rowHeight: CGFloat) {
        self.tileHeight = rowHeight - 2 * Self.artInset
        self.tileWidth = (self.tileHeight * Self.artAspect).rounded()
        super.init(frame: .zero)
        self.identifier = identifier
        build()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        tile.wantsLayer = true
        tile.layer?.cornerRadius = 6
        tile.layer?.masksToBounds = true
        tile.translatesAutoresizingMaskIntoConstraints = false
        tile.setContentHuggingPriority(.required, for: .horizontal)

        glyph.image = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil)
        glyph.symbolConfiguration = .init(pointSize: 18, weight: .regular)
        glyph.contentTintColor = Colors.secondaryText
        glyph.translatesAutoresizingMaskIntoConstraints = false
        glyph.setAccessibilityElement(false)

        artView.imageScaling = .scaleProportionallyUpOrDown
        artView.translatesAutoresizingMaskIntoConstraints = false
        artView.isHidden = true
        artView.setAccessibilityElement(false)

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        summaryLabel.font = Typography.body
        summaryLabel.textColor = Colors.secondaryText
        summaryLabel.lineBreakMode = .byTruncatingTail
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        markerLabel.font = .systemFont(ofSize: 11, weight: .medium)
        markerLabel.textColor = Colors.secondaryText
        markerLabel.alignment = .right
        markerLabel.translatesAutoresizingMaskIntoConstraints = false
        markerLabel.setContentHuggingPriority(.required, for: .horizontal)
        markerLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        removeButton.isBordered = false
        removeButton.bezelStyle = .regularSquare
        removeButton.imagePosition = .imageOnly
        removeButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: L10n.text("Remove game"))
        removeButton.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        removeButton.contentTintColor = Colors.quiet
        removeButton.target = self
        removeButton.action = #selector(removeClicked)
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        removeButton.setContentHuggingPriority(.required, for: .horizontal)
        removeButton.alphaValue = 0
        removeButton.toolTip = L10n.text("Remove game from the review")
        removeButton.setAccessibilityLabel(L10n.text("Remove game"))

        let text = NSStackView(views: [titleLabel, summaryLabel])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        text.translatesAutoresizingMaskIntoConstraints = false

        tile.addSubview(glyph)
        tile.addSubview(artView)
        addSubview(tile)
        addSubview(text)
        addSubview(markerLabel)
        addSubview(removeButton)

        NSLayoutConstraint.activate([
            tile.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            tile.centerYAnchor.constraint(equalTo: centerYAnchor),
            tile.widthAnchor.constraint(equalToConstant: tileWidth),
            tile.heightAnchor.constraint(equalToConstant: tileHeight),

            glyph.centerXAnchor.constraint(equalTo: tile.centerXAnchor),
            glyph.centerYAnchor.constraint(equalTo: tile.centerYAnchor),

            artView.leadingAnchor.constraint(equalTo: tile.leadingAnchor),
            artView.trailingAnchor.constraint(equalTo: tile.trailingAnchor),
            artView.topAnchor.constraint(equalTo: tile.topAnchor),
            artView.bottomAnchor.constraint(equalTo: tile.bottomAnchor),

            text.leadingAnchor.constraint(equalTo: tile.trailingAnchor, constant: 14),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.trailingAnchor.constraint(lessThanOrEqualTo: markerLabel.leadingAnchor, constant: -8),

            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            markerLabel.trailingAnchor.constraint(equalTo: removeButton.leadingAnchor, constant: -8),
            markerLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        applyTileColor()
    }

    private func applyTileColor() {
        effectiveAppearance.performAsCurrentDrawingAppearance { [weak self] in
            self?.tile.layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyTileColor()
    }

    func configure(appID: Int?,
                   title: String,
                   summary: String,
                   importable: Bool,
                   cachedName: String?,
                   cachedImage: NSImage?) {
        setArt(cachedImage)

        let shown = (cachedName?.isEmpty == false) ? cachedName! : title
        titleLabel.stringValue = shown
        titleLabel.textColor = importable ? .labelColor : .secondaryLabelColor
        glyph.contentTintColor = importable ? Colors.secondaryText : Colors.quiet
        summaryLabel.stringValue = summary

        markerLabel.stringValue = importable ? "" : L10n.text("Can’t import")
        markerLabel.textColor = importable ? Colors.secondaryText : .secondaryLabelColor

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(importable ? L10n.format("%1$@. %2$@.", shown, summary) : L10n.format("%1$@. %2$@. Can’t import.", shown, summary))
    }

    func setName(_ name: String) {
        guard !name.isEmpty else { return }
        titleLabel.stringValue = name
        setAccessibilityLabel(name)
    }

    func setArt(_ image: NSImage?) {
        artView.image = image
        artView.isHidden = (image == nil)
        glyph.isHidden = (image != nil)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        setArt(nil)
        onRemove = nil
        removeButton.alphaValue = 0
    }

    @objc private func removeClicked() {
        onRemove?()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = hoverArea { removeTrackingArea(existing) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { revealRemove(true) }
    override func mouseExited(with event: NSEvent) { revealRemove(false) }

    private func revealRemove(_ shown: Bool) {
        let target: CGFloat = shown ? 1 : 0
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            removeButton.alphaValue = target
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            removeButton.animator().alphaValue = target
        }
    }
}
