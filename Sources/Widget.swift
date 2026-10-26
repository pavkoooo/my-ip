import AppKit
import QuartzCore

/// Borderless, non-activating panel that stays above normal windows and below the menu bar.
final class WidgetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 148, height: 34),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovable = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
        isRestorable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        title = "My IP"
        animationBehavior = .none
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        applyWindowLevel()
    }

    func applyWindowLevel() {
        // Prefer the slot just under the menu-bar window. A fullscreen game on this
        // Mac uses the status-item level, which is above the menu bar, so a panel
        // left at menu-1 is fully covered. Sit one level above that, still under
        // pop-up menus. The frame stays inside visibleFrame, so the menu bar itself
        // is never covered.
        let menu = Int(CGWindowLevelForKey(.mainMenuWindow))
        let normal = Int(CGWindowLevelForKey(.normalWindow))
        let status = Int(CGWindowLevelForKey(.statusWindow))
        let popUp = Int(CGWindowLevelForKey(.popUpMenuWindow))
        let aboveFullscreen = min(popUp - 1, status + 1)
        level = NSWindow.Level(rawValue: max(normal + 1, max(menu - 1, aboveFullscreen)))
    }
}

/// Compact glass pill. The globe toggles LAN/WAN; the address copies; right-click opens the menu.
final class WidgetView: NSView {
    var onCopy: (() -> Void)?
    var onToggle: (() -> Void)?
    var onMenu: ((NSEvent) -> Void)?

    private let effect = NSVisualEffectView()
    private let border = NSView()
    private let stack = NSStackView()
    private let symbol = NSImageView()
    let caption = NSTextField(labelWithString: "")
    let address = NSTextField(labelWithString: "—")
    private let quitButton = NSButton()
    private var captionWidth: NSLayoutConstraint!
    private var addressWidth: NSLayoutConstraint!
    private var tracking: NSTrackingArea?
    private var hovered = false
    private(set) var trailingPadding: CGFloat = 12

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.appearance = NSAppearance(named: .darkAqua)
        effect.wantsLayer = true
        effect.translatesAutoresizingMaskIntoConstraints = false

        border.wantsLayer = true
        border.translatesAutoresizingMaskIntoConstraints = false

        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        symbol.image = NSImage(systemSymbolName: "globe", accessibilityDescription: "Toggle LAN and WAN")?
            .withSymbolConfiguration(symbolConfig)
        symbol.image?.isTemplate = true
        symbol.contentTintColor = NSColor.white.withAlphaComponent(0.55)
        symbol.imageScaling = .scaleProportionallyDown
        symbol.translatesAutoresizingMaskIntoConstraints = false
        symbol.setContentHuggingPriority(.required, for: .horizontal)

        styleCaption()
        caption.translatesAutoresizingMaskIntoConstraints = false
        caption.setContentHuggingPriority(.required, for: .horizontal)
        caption.setContentCompressionResistancePriority(.required, for: .horizontal)
        caption.maximumNumberOfLines = 1
        caption.lineBreakMode = .byClipping
        caption.cell?.wraps = false
        caption.cell?.isScrollable = true
        caption.cell?.usesSingleLineMode = true
        caption.wantsLayer = true

        address.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
        address.textColor = NSColor.white.withAlphaComponent(0.38)
        address.alignment = .left
        address.translatesAutoresizingMaskIntoConstraints = false
        address.setContentHuggingPriority(.required, for: .horizontal)
        address.setContentCompressionResistancePriority(.required, for: .horizontal)
        address.maximumNumberOfLines = 1
        address.lineBreakMode = .byClipping
        address.cell?.wraps = false
        address.cell?.isScrollable = true
        address.cell?.usesSingleLineMode = true
        address.wantsLayer = true

        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setContentHuggingPriority(.required, for: .horizontal)
        stack.addArrangedSubview(symbol)
        stack.addArrangedSubview(caption)
        stack.addArrangedSubview(address)
        stack.setCustomSpacing(5, after: symbol)
        stack.setCustomSpacing(7, after: caption)

        quitButton.isBordered = false
        quitButton.imagePosition = .imageOnly
        quitButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Quit")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold))
        quitButton.image?.isTemplate = true
        quitButton.contentTintColor = NSColor.white.withAlphaComponent(0.8)
        quitButton.target = self
        quitButton.action = #selector(quitClicked)
        quitButton.toolTip = "Quit"
        quitButton.alphaValue = 0
        quitButton.isHidden = true
        quitButton.translatesAutoresizingMaskIntoConstraints = false
        quitButton.refusesFirstResponder = true

        addSubview(effect)
        addSubview(stack)
        addSubview(border)
        addSubview(quitButton)

        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor),
            effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor),
            effect.bottomAnchor.constraint(equalTo: bottomAnchor),

            border.leadingAnchor.constraint(equalTo: leadingAnchor),
            border.trailingAnchor.constraint(equalTo: trailingAnchor),
            border.topAnchor.constraint(equalTo: topAnchor),
            border.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),

            symbol.widthAnchor.constraint(equalToConstant: 13),
            symbol.heightAnchor.constraint(equalToConstant: 13),

            quitButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            quitButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            quitButton.widthAnchor.constraint(equalToConstant: 14),
            quitButton.heightAnchor.constraint(equalToConstant: 14),
        ])

        captionWidth = caption.widthAnchor.constraint(equalToConstant: 18)
        addressWidth = address.widthAnchor.constraint(equalToConstant: 24)
        captionWidth.isActive = true
        addressWidth.isActive = true
        updateTextWidths()
        applyChrome()
    }

    required init?(coder: NSCoder) { nil }

    override var isOpaque: Bool { false }

    override func layout() {
        super.layout()
        applyChrome()
        updateTrackingAreas()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        applyChrome()
        let scale = window?.backingScaleFactor ?? 2
        address.layer?.contentsScale = scale
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        if hovered, !quitButton.isHidden {
            let inButton = quitButton.convert(local, from: self)
            if quitButton.bounds.insetBy(dx: -3, dy: -4).contains(inButton) {
                return quitButton
            }
        }
        return self
    }

    override func mouseEntered(with event: NSEvent) {
        setHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window else { return }
            let outside = window.mouseLocationOutsideOfEventStream
            let local = self.convert(outside, from: nil)
            if self.bounds.contains(local) { return }
            self.setHovered(false)
        }
    }

    override func mouseDown(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.08
            animator().alphaValue = 0.72
        }
    }

    override func mouseUp(with event: NSEvent) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            animator().alphaValue = 1
        }
        let local = convert(event.locationInWindow, from: nil)
        guard bounds.contains(local) else { return }
        if toggleRect().contains(local) {
            onToggle?()
            return
        }
        if copyRect().contains(local) {
            onCopy?()
        }
    }

    /// The globe, including its left padding, but not the LAN/WAN label.
    private func toggleRect() -> NSRect {
        let symbolFrame = symbol.convert(symbol.bounds, to: self)
        return NSRect(x: 0, y: 0, width: symbolFrame.maxX + 3, height: bounds.height)
    }

    /// The address text, stretched to the pill height so the glyphs are easy to hit.
    private func copyRect() -> NSRect {
        let addressFrame = address.convert(address.bounds, to: self)
        let limit = hovered && !quitButton.isHidden ? quitButton.frame.minX : bounds.maxX
        return NSRect(x: addressFrame.minX - 2, y: 0, width: max(0, limit - (addressFrame.minX - 2)), height: bounds.height)
    }

    override func rightMouseDown(with event: NSEvent) {
        onMenu?(event)
    }

    func contentWidth() -> CGFloat {
        updateTextWidths()
        // Symbol 13, then the custom gaps after the symbol and the caption.
        return 13 + 5 + captionWidth.constant + 7 + addressWidth.constant
    }

    private func updateTextWidths() {
        captionWidth.constant = Self.singleLineWidth(of: caption)
        addressWidth.constant = Self.singleLineWidth(of: address)
    }

    private static func singleLineWidth(of field: NSTextField) -> CGFloat {
        guard let cell = field.cell else { return 8 }
        cell.wraps = false
        cell.isScrollable = true
        cell.usesSingleLineMode = true
        let measured = cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: 4000, height: 40))
        return max(8, ceil(measured.width) + 2)
    }

    func setHovered(_ hovered: Bool) {
        guard hovered != self.hovered else { return }
        self.hovered = hovered
        trailingPadding = hovered ? 26 : 12
        if hovered { quitButton.isHidden = false }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            self.quitButton.animator().alphaValue = hovered ? 0.9 : 0
        }, completionHandler: { [weak self] in
            guard let self, !self.hovered else { return }
            self.quitButton.isHidden = true
        })
    }

    func flash() {
        guard let layer = border.layer else { return }
        let rest = NSColor.white.withAlphaComponent(0.22).cgColor
        let hot = NSColor.white.withAlphaComponent(0.92).cgColor
        let animation = CABasicAnimation(keyPath: "borderColor")
        animation.fromValue = hot
        animation.toValue = rest
        animation.duration = 0.65
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.borderColor = rest
        layer.add(animation, forKey: "flash")
    }

    func crossfadeAddress(to text: String, font: NSFont, color: NSColor) {
        if let layer = address.layer {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.2
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "crossfade")
        }
        address.font = font
        address.textColor = color
        address.stringValue = text
        updateTextWidths()
    }

    func setCaption(_ text: String) {
        guard caption.attributedStringValue.string != text else { return }
        if let layer = caption.layer {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.18
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: "crossfade")
        }
        caption.attributedStringValue = Self.captionString(text)
        updateTextWidths()
    }

    private func styleCaption() {
        caption.attributedStringValue = Self.captionString("LAN")
    }

    private static func captionString(_ text: String) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white.withAlphaComponent(0.45),
                .kern: 0.6,
            ]
        )
    }

    private func applyChrome() {
        let radius: CGFloat = 14
        let effectMask = (effect.layer?.mask as? CAShapeLayer) ?? CAShapeLayer()
        effectMask.path = CGPath(
            roundedRect: effect.bounds,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )
        effect.layer?.mask = effectMask

        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        border.layer?.cornerRadius = radius
        border.layer?.borderWidth = 1 / max(scale, 1)
        border.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        border.layer?.backgroundColor = NSColor.clear.cgColor
        border.layer?.masksToBounds = false
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }
}

final class WidgetController: NSObject {
    private enum Mode { case lan, wan }

    private let panel = WidgetPanel()
    private let widget = WidgetView(frame: NSRect(x: 0, y: 0, width: 148, height: 34))
    private let lanService = IPService()
    private let wanService = PublicIPService()
    private var mode: Mode = .lan
    private var lanAddress: String?
    private var wanAddress: String?
    private var displayedIP: String?
    private var didShow = false
    private var copiedUntil = Date.distantPast

    private var modeLabel: String { mode == .lan ? "LAN" : "WAN" }
    private var visibleAddress: String? { mode == .lan ? lanAddress : wanAddress }
    private var statusURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("status.json")
    }
    private var logURL: URL {
        Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("widget.log")
    }

    func start() {
        panel.contentView = widget
        widget.onCopy = { [weak self] in self?.copyIP() }
        widget.onToggle = { [weak self] in self?.toggleMode() }
        widget.onMenu = { [weak self] event in self?.showMenu(event) }

        lanService.onIP = { [weak self] ip in
            self?.store(ip, for: .lan)
        }
        lanService.onUnreachable = { [weak self] in
            self?.store(nil, for: .lan)
        }
        wanService.onIP = { [weak self] ip in
            self?.store(ip, for: .wan)
        }
        wanService.onUnreachable = { [weak self] in
            self?.store(nil, for: .wan)
        }

        let center = NotificationCenter.default
        center.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.applyPlacement(animated: false)
        }
        center.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.panel.applyWindowLevel()
        }

        // The globe toggle is memory-only. Every launch starts on LAN.
        mode = .lan
        render(address: "—", dimmed: true, animate: false)
        lanService.start()
        wanService.start()
        log("started policy=\(NSApp.activationPolicy().rawValue) level=\(panel.level.rawValue) screens=\(NSScreen.screens.count)")

        DispatchQueue.main.async { [weak self] in
            self?.applyPlacement(animated: false)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.applyPlacement(animated: false)
        }
    }

    private func store(_ ip: String?, for updated: Mode) {
        let previous = updated == .lan ? lanAddress : wanAddress
        if updated == .lan {
            lanAddress = ip
        } else {
            wanAddress = ip
        }
        guard updated == mode else {
            writeStatus(shown: widget.address.stringValue)
            return
        }
        let changed = previous != ip
        if Date() < copiedUntil, !changed {
            writeStatus(shown: "Copied")
            return
        }
        presentVisible(animateChange: changed)
        log("\(modeLabel) \(ip ?? "—") changed=\(changed)")
    }

    private func toggleMode() {
        copiedUntil = .distantPast
        mode = mode == .lan ? .wan : .lan
        presentVisible(animateChange: true)
        log("toggle \(modeLabel)")
        if mode == .lan {
            lanService.refresh()
        } else {
            wanService.refresh()
        }
    }

    private func presentVisible(animateChange: Bool) {
        let address = visibleAddress
        displayedIP = address
        widget.setCaption(modeLabel)
        let text = address ?? "—"
        if animateChange {
            widget.flash()
        }
        widget.crossfadeAddress(
            to: text,
            font: .monospacedSystemFont(ofSize: 13, weight: .medium),
            color: NSColor.white.withAlphaComponent(address == nil ? 0.38 : 0.94)
        )
        widget.setAccessibilityLabel(address.map { "\(modeLabel) \($0)" } ?? "\(modeLabel) unavailable")
        applyPlacement(animated: didShow && animateChange)
        writeStatus(shown: text)
    }

    private func render(address: String, dimmed: Bool, animate: Bool) {
        widget.crossfadeAddress(
            to: address,
            font: address == "Copied"
                ? .systemFont(ofSize: 13, weight: .medium)
                : .monospacedSystemFont(ofSize: 13, weight: .medium),
            color: NSColor.white.withAlphaComponent(dimmed ? 0.38 : 0.94)
        )
        if address == "—" {
            widget.setAccessibilityLabel("\(modeLabel) unavailable")
        }
        applyPlacement(animated: animate)
        writeStatus(shown: address)
    }

    private func copyIP() {
        guard let ip = displayedIP else { return }
        let board = NSPasteboard.general
        board.clearContents()
        board.setString(ip, forType: .string)
        copiedUntil = Date().addingTimeInterval(0.9)
        widget.flash()
        render(address: "Copied", dimmed: false, animate: true)
        log("copied")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, let ip = self.displayedIP else { return }
            guard Date() >= self.copiedUntil else { return }
            self.widget.crossfadeAddress(
                to: ip,
                font: .monospacedSystemFont(ofSize: 13, weight: .medium),
                color: NSColor.white.withAlphaComponent(0.94)
            )
            self.applyPlacement(animated: true)
            self.writeStatus(shown: ip)
        }
    }

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let copy = NSMenuItem(title: "Copy IP", action: #selector(copyFromMenu(_:)), keyEquivalent: "")
        copy.target = self
        copy.isEnabled = displayedIP != nil
        menu.addItem(copy)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        NSMenu.popUpContextMenu(menu, with: event, for: widget)
    }

    @objc private func copyFromMenu(_ sender: Any?) {
        copyIP()
    }

    private func applyPlacement(animated: Bool) {
        panel.applyWindowLevel()
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        guard let screen = NSScreen.screens.first else {
            log("no screen")
            return
        }
        let width = max(72, ceil(12 + widget.contentWidth() + widget.trailingPadding))
        let height: CGFloat = 34
        let size = NSSize(width: width, height: height)
        let visible = screen.visibleFrame
        let inset: CGFloat = 12
        var origin = NSPoint(
            x: (visible.maxX - size.width - inset).rounded(),
            y: (visible.maxY - size.height - inset).rounded()
        )
        if origin.x < visible.minX { origin.x = visible.minX.rounded() }
        if origin.y < visible.minY { origin.y = visible.minY.rounded() }
        if origin.x + size.width > visible.maxX {
            origin.x = (visible.maxX - size.width).rounded()
        }
        if origin.y + size.height > visible.maxY {
            origin.y = (visible.maxY - size.height).rounded()
        }
        let frame = NSRect(origin: origin, size: size)
        if !didShow {
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            didShow = true
        } else if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                self.panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        panel.invalidateShadow()
        panel.invalidateCursorRects(for: widget)
    }

    private func writeStatus(shown: String) {
        let frame = panel.frame
        let screen = NSScreen.screens.first
        let screenHeight = screen?.frame.height ?? 0
        let screenOriginY = screen?.frame.origin.y ?? 0
        let captureX = frame.minX - (screen?.frame.origin.x ?? 0)
        let captureY = (screenOriginY + screenHeight) - frame.maxY
        let payload: [String: Any] = [
            "mode": modeLabel,
            "lan": lanAddress ?? "",
            "wan": wanAddress ?? "",
            "ip": displayedIP ?? "",
            "shown": shown,
            "visible": panel.isVisible,
            "level": panel.level.rawValue,
            "x": frame.minX,
            "y": frame.minY,
            "width": frame.width,
            "height": frame.height,
            "captureX": captureX,
            "captureY": captureY,
            "screenWidth": screen?.frame.width ?? 0,
            "screenHeight": screenHeight,
            "visibleMaxX": screen?.visibleFrame.maxX ?? 0,
            "visibleMaxY": screen?.visibleFrame.maxY ?? 0,
            "pid": ProcessInfo.processInfo.processIdentifier,
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: statusURL, options: .atomic)
    }

    private func log(_ message: String) {
        let line = "\(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        if let existing = try? Data(contentsOf: logURL) {
            var combined = existing
            combined.append(data)
            try? combined.write(to: logURL)
        } else {
            try? data.write(to: logURL)
        }
        fputs(line, stderr)
    }
}
