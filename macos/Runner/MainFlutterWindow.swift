import Cocoa
import FlutterMacOS
import PDFKit

func engLog(_ msg: String) {
    #if DEBUG
    let logFile = NSHomeDirectory() + "/engreader_debug.log"
    let line = "\(Date()): \(msg)\n"
    if let handle = FileHandle(forWritingAtPath: logFile) {
        handle.seekToEndOfFile()
        handle.write(line.data(using: .utf8)!)
        handle.closeFile()
    } else {
        FileManager.default.createFile(atPath: logFile, contents: line.data(using: .utf8))
    }
    #endif
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    engLog("awakeFromNib start")
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let messenger = flutterViewController.engine.binaryMessenger

    // Register PDF platform view
    let pdfViewFactory = MacPDFPlatformViewFactory(messenger: messenger)
    flutterViewController.engine.registrar(forPlugin: "PDFPlatformView").register(pdfViewFactory, withId: "com.engreader/pdfview")
    engLog("pdfViewFactory registered")

    // Register method channel
    let channel = FlutterMethodChannel(name: "com.engreader/pdfkit", binaryMessenger: messenger)
    let pdfHandler = MacPDFMethodHandler(channel: channel)
    channel.setMethodCallHandler(pdfHandler.handle)
    engLog("method channel registered")

    super.awakeFromNib()

    // Full-content window style (titlebar blends with content)
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = true
  }
}

// MARK: - PDF Platform View Factory

class MacPDFPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    private var activePlatformViews: [Int64: MacPDFPlatformView] = [:]
    static var shared: MacPDFPlatformViewFactory?

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
        MacPDFPlatformViewFactory.shared = self
    }

    func setHighlightsOnActiveView(pageHighlights: [Int: [[String: Any]]]) {
        engLog("setHighlightsOnActiveView: activePlatformViews.count=\(activePlatformViews.count)")
        if let view = activePlatformViews.values.first {
            view.setHighlights(pageHighlights: pageHighlights)
        } else {
            engLog("setHighlightsOnActiveView: NO active view found!")
        }
    }

    func create(
        withViewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> NSView {
        engLog("MacPDFPlatformViewFactory.create called, viewId=\(viewId), clearing \(activePlatformViews.count) old views")
        // Clear old views to ensure setHighlightsOnActiveView targets the new one.
        activePlatformViews.removeAll()
        let platformView = MacPDFPlatformView(
            viewId: viewId,
            args: args as? [String: Any],
            messenger: messenger
        )
        activePlatformViews[viewId] = platformView
        engLog("MacPDFPlatformView created and retained, viewId=\(viewId)")
        return platformView.view()
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Native annotate popover

class AutoGrowingTextView: NSTextView {
    var onTextChange: (() -> Void)?

    override func didChangeText() {
        super.didChangeText()
        onTextChange?()
    }
}

class AnnotatePopoverViewController: NSViewController {
    var text: String = ""
    var onAnnotate: (() -> Void)?
    var onAsk: ((String) -> Void)?
    private var typeLabel: NSTextField?
    private var textLabel: NSTextField?
    private var askTextView: AutoGrowingTextView?
    private var askContainer: NSView?
    private var mainContainer: NSView?
    private var askHeightConstraint: NSLayoutConstraint?
    private var isAskExpanded = false
    private var submitBtn: NSButton?

    override func loadView() {
        let isWord = !text.contains(" ") || text.split(separator: " ").count <= 2
        let typeText = isWord ? "单词" : "句子"
        let preview = text.count > 50
            ? String(text.prefix(50)) + "…"
            : text

        let outerContainer = NSView()
        outerContainer.translatesAutoresizingMaskIntoConstraints = false

        // Main row
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        self.mainContainer = container

        let tLabel = NSTextField(labelWithString: typeText)
        tLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        tLabel.textColor = isWord
            ? NSColor.systemBlue
            : NSColor.systemPurple
        tLabel.translatesAutoresizingMaskIntoConstraints = false
        self.typeLabel = tLabel

        let txLabel = NSTextField(labelWithString: preview)
        txLabel.font = NSFont.systemFont(ofSize: 13)
        txLabel.lineBreakMode = .byTruncatingTail
        txLabel.maximumNumberOfLines = 1
        txLabel.translatesAutoresizingMaskIntoConstraints = false
        txLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        txLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        self.textLabel = txLabel

        let annotateBtn = NSButton(title: "批注", target: self, action: #selector(annotateClicked))
        annotateBtn.bezelStyle = .rounded
        annotateBtn.keyEquivalent = "\r"
        annotateBtn.translatesAutoresizingMaskIntoConstraints = false

        let askBtn = NSButton(title: "提问", target: self, action: #selector(askClicked))
        askBtn.bezelStyle = .rounded
        askBtn.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(tLabel)
        container.addSubview(txLabel)
        container.addSubview(annotateBtn)
        container.addSubview(askBtn)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),

            tLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            tLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            txLabel.leadingAnchor.constraint(equalTo: tLabel.trailingAnchor, constant: 8),
            txLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            txLabel.trailingAnchor.constraint(lessThanOrEqualTo: annotateBtn.leadingAnchor, constant: -12),

            annotateBtn.trailingAnchor.constraint(equalTo: askBtn.leadingAnchor, constant: -6),
            annotateBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            askBtn.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            askBtn.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        // Ask input row (collapsed by default, height = 0)
        let askRow = NSView()
        askRow.translatesAutoresizingMaskIntoConstraints = false
        askRow.clipsToBounds = true
        self.askContainer = askRow

        // Input container with rounded border (Cursor-like style)
        let inputWrapper = NSView()
        inputWrapper.translatesAutoresizingMaskIntoConstraints = false
        inputWrapper.wantsLayer = true
        inputWrapper.layer?.borderWidth = 1
        inputWrapper.layer?.borderColor = NSColor.separatorColor.cgColor
        inputWrapper.layer?.cornerRadius = 8

        // Auto-growing text view (no scroll view, no scrollbar)
        let textView = AutoGrowingTextView()
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.drawsBackground = false
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.onTextChange = { [weak self] in
            self?.adjustInputHeight()
        }
        self.askTextView = textView

        // Arrow-up submit button (perfect circle using a wrapper view)
        let sendWrapper = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        sendWrapper.translatesAutoresizingMaskIntoConstraints = false
        sendWrapper.wantsLayer = true
        sendWrapper.layer?.cornerRadius = 10
        sendWrapper.layer?.masksToBounds = true
        sendWrapper.layer?.backgroundColor = NSColor.controlAccentColor.cgColor

        let sendBtn = NSButton(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
        sendBtn.translatesAutoresizingMaskIntoConstraints = false
        sendBtn.isBordered = false
        sendBtn.bezelStyle = .inline
        sendBtn.wantsLayer = true
        sendBtn.layer?.backgroundColor = .clear
        sendBtn.target = self
        sendBtn.action = #selector(askSubmitted)
        if #available(macOS 11.0, *) {
            let arrowImage = NSImage(systemSymbolName: "arrow.up", accessibilityDescription: "发送")
            let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
            sendBtn.image = arrowImage?.withSymbolConfiguration(config)
        } else {
            sendBtn.title = "↑"
            sendBtn.font = NSFont.systemFont(ofSize: 10, weight: .bold)
        }
        sendBtn.contentTintColor = .white
        sendBtn.imagePosition = .imageOnly
        sendWrapper.addSubview(sendBtn)

        NSLayoutConstraint.activate([
            sendBtn.centerXAnchor.constraint(equalTo: sendWrapper.centerXAnchor),
            sendBtn.centerYAnchor.constraint(equalTo: sendWrapper.centerYAnchor),
            sendBtn.widthAnchor.constraint(equalToConstant: 20),
            sendBtn.heightAnchor.constraint(equalToConstant: 20),
        ])
        self.submitBtn = sendBtn

        inputWrapper.addSubview(textView)
        inputWrapper.addSubview(sendWrapper)

        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: inputWrapper.leadingAnchor, constant: 8),
            textView.topAnchor.constraint(equalTo: inputWrapper.topAnchor, constant: 6),
            textView.bottomAnchor.constraint(equalTo: inputWrapper.bottomAnchor, constant: -6),
            textView.trailingAnchor.constraint(equalTo: sendWrapper.leadingAnchor, constant: -8),

            sendWrapper.trailingAnchor.constraint(equalTo: inputWrapper.trailingAnchor, constant: -8),
            sendWrapper.bottomAnchor.constraint(equalTo: inputWrapper.bottomAnchor, constant: -8),
            sendWrapper.widthAnchor.constraint(equalToConstant: 20),
            sendWrapper.heightAnchor.constraint(equalToConstant: 20),
        ])

        askRow.addSubview(inputWrapper)

        let heightConstraint = askRow.heightAnchor.constraint(equalToConstant: 0)
        self.askHeightConstraint = heightConstraint

        NSLayoutConstraint.activate([
            heightConstraint,

            inputWrapper.leadingAnchor.constraint(equalTo: askRow.leadingAnchor, constant: 12),
            inputWrapper.topAnchor.constraint(equalTo: askRow.topAnchor, constant: 4),
            inputWrapper.bottomAnchor.constraint(equalTo: askRow.bottomAnchor, constant: -8),
            inputWrapper.trailingAnchor.constraint(equalTo: askRow.trailingAnchor, constant: -12),
        ])

        outerContainer.addSubview(container)
        outerContainer.addSubview(askRow)

        NSLayoutConstraint.activate([
            outerContainer.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),
            outerContainer.widthAnchor.constraint(lessThanOrEqualToConstant: 500),

            container.topAnchor.constraint(equalTo: outerContainer.topAnchor),
            container.leadingAnchor.constraint(equalTo: outerContainer.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: outerContainer.trailingAnchor),

            askRow.topAnchor.constraint(equalTo: container.bottomAnchor),
            askRow.leadingAnchor.constraint(equalTo: outerContainer.leadingAnchor),
            askRow.trailingAnchor.constraint(equalTo: outerContainer.trailingAnchor),
            askRow.bottomAnchor.constraint(equalTo: outerContainer.bottomAnchor),
        ])

        self.view = outerContainer
    }

    private func adjustInputHeight() {
        guard let textView = askTextView, isAskExpanded else { return }
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let usedRect = textView.layoutManager?.usedRect(for: textView.textContainer!) ?? .zero
        let textHeight = usedRect.height + textView.textContainerInset.height * 2
        let minHeight: CGFloat = 48
        let maxHeight: CGFloat = 160
        let newHeight = min(max(textHeight + 24, minHeight), maxHeight)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.allowsImplicitAnimation = true
            self.askHeightConstraint?.constant = newHeight
            self.view.layoutSubtreeIfNeeded()
        })
    }

    func updateText(_ newText: String) {
        text = newText
        let isWord = !newText.contains(" ") || newText.split(separator: " ").count <= 2
        let typeText = isWord ? "单词" : "句子"
        let preview = newText.count > 50
            ? String(newText.prefix(50)) + "…"
            : newText
        typeLabel?.stringValue = typeText
        typeLabel?.textColor = isWord ? NSColor.systemBlue : NSColor.systemPurple
        textLabel?.stringValue = preview
        // Collapse ask row when text changes
        if isAskExpanded {
            collapseAskRow()
        }
        askTextView?.string = ""
    }

    private func collapseAskRow() {
        isAskExpanded = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            self.askHeightConstraint?.constant = 0
            self.view.layoutSubtreeIfNeeded()
        })
    }

    private func expandAskRow() {
        isAskExpanded = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            self.askHeightConstraint?.constant = 48
            self.view.layoutSubtreeIfNeeded()
        }) {
            self.view.window?.makeFirstResponder(self.askTextView)
        }
    }

    @objc private func annotateClicked() {
        onAnnotate?()
    }

    @objc private func askClicked() {
        if isAskExpanded {
            collapseAskRow()
        } else {
            expandAskRow()
        }
    }

    @objc private func askSubmitted() {
        let question = askTextView?.string.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !question.isEmpty {
            onAsk?(question)
        }
    }
}

// MARK: - Custom PDFView with logging and event acceptance

class LoggingPDFView: PDFView {
    override var acceptsFirstResponder: Bool { return true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        engLog("PDFView mouseDown")
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    var onMouseUp: (() -> Void)?

    override func mouseUp(with event: NSEvent) {
        engLog("PDFView mouseUp, currentSelection=\(currentSelection?.string?.prefix(30) ?? "nil"), onMouseUp=\(onMouseUp != nil ? "set" : "nil")")
        super.mouseUp(with: event)
        if let cb = onMouseUp {
            engLog("calling onMouseUp callback")
            cb()
        } else {
            engLog("onMouseUp is nil!")
        }
    }

    override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
    }
}

// MARK: - PDF Platform View

class MacPDFPlatformView: NSObject {
    private let pdfView: LoggingPDFView
    private let channel: FlutterMethodChannel
    private var selectionPollTimer: Timer?
    private var lastNotifiedText: String = ""
    private var eventMonitor: Any?
    private var annotatePopover: NSPopover?

    init(viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
        pdfView = LoggingPDFView()
        channel = FlutterMethodChannel(name: "com.engreader/pdfkit", binaryMessenger: messenger)
        super.init()

        // Workaround: Flutter macOS AppKitView does not forward mouse events to
        // embedded NSView. Install a local NSEvent monitor and forward mouse
        // events that fall within the pdfView's window region.
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            return self?.routeMouseEvent(event) ?? event
        }

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

        pdfView.onMouseUp = { [weak self] in
            self?.pollSelection()
        }

        if let path = args?["path"] as? String {
            loadDocument(at: path)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handlePageChange),
            name: .PDFViewPageChanged,
            object: pdfView
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChange),
            name: .PDFViewSelectionChanged,
            object: pdfView
        )

        // Fallback: poll current selection periodically.
        // PDFViewSelectionChanged is unreliable in some macOS versions/configs.
        selectionPollTimer = Timer.scheduledTimer(
            withTimeInterval: 0.3, repeats: true
        ) { [weak self] _ in
            self?.pollSelection()
        }
    }

    private func pollSelection() {
        let raw = pdfView.currentSelection?.string ?? ""
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text != lastNotifiedText {
            engLog("poll: selection changed, text=\(text.prefix(30))")
            lastNotifiedText = text
            if !text.isEmpty {
                notifyTextSelected()
            }
        }
    }

    private func notifyTextSelected() {
        guard let selection = pdfView.currentSelection,
              let rawText = selection.string,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let page = selection.pages.first,
              let pageIndex = pdfView.document?.index(for: page) else {
            return
        }
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)

        let pageBounds = selection.bounds(for: page)
        let pageHeight = page.bounds(for: .mediaBox).height
        let yPosition = Double(pageBounds.midY / pageHeight)

        // Get character range within the page text.
        var charStart: Int = -1
        var charEnd: Int = -1
        if let pageText = page.string as NSString? {
            let range = pageText.range(of: text, options: [.caseInsensitive])
            if range.location != NSNotFound {
                charStart = range.location
                charEnd = range.location + range.length
            }
        }

        let viewRect = pdfView.convert(pageBounds, from: page)

        showAnnotatePopover(text: text, anchorRect: viewRect, page: pageIndex,
                            yPosition: yPosition, charStart: charStart, charEnd: charEnd)
    }

    private func showAnnotatePopover(text: String, anchorRect: NSRect,
                                      page: Int, yPosition: Double,
                                      charStart: Int = -1, charEnd: Int = -1) {
        // If popover is already showing, just update text and callback in-place.
        if let existingPopover = annotatePopover, existingPopover.isShown,
           let vc = existingPopover.contentViewController as? AnnotatePopoverViewController {
            vc.updateText(text)
            vc.onAnnotate = { [weak self] in
                guard let self = self else { return }
                var args: [String: Any] = [
                    "text": text,
                    "page": page,
                    "yPosition": yPosition,
                ]
                if charStart >= 0 && charEnd >= 0 {
                    args["charStart"] = charStart
                    args["charEnd"] = charEnd
                }
                self.channel.invokeMethod("onAnnotateConfirmed", arguments: args)
                self.annotatePopover?.close()
                self.annotatePopover = nil
                self.pdfView.clearSelection()
                self.lastNotifiedText = ""
            }
            vc.onAsk = { [weak self] question in
                guard let self = self else { return }
                var args: [String: Any] = [
                    "text": text,
                    "question": question,
                    "page": page,
                    "yPosition": yPosition,
                ]
                if charStart >= 0 && charEnd >= 0 {
                    args["charStart"] = charStart
                    args["charEnd"] = charEnd
                }
                self.channel.invokeMethod("onAskConfirmed", arguments: args)
                self.annotatePopover?.close()
                self.annotatePopover = nil
                self.pdfView.clearSelection()
                self.lastNotifiedText = ""
            }
            return
        }

        annotatePopover?.close()

        let vc = AnnotatePopoverViewController()
        vc.text = text
        vc.onAnnotate = { [weak self] in
            guard let self = self else { return }
            var args: [String: Any] = [
                "text": text,
                "page": page,
                "yPosition": yPosition,
            ]
            if charStart >= 0 && charEnd >= 0 {
                args["charStart"] = charStart
                args["charEnd"] = charEnd
            }
            self.channel.invokeMethod("onAnnotateConfirmed", arguments: args)
            self.annotatePopover?.close()
            self.annotatePopover = nil
            self.pdfView.clearSelection()
            self.lastNotifiedText = ""
        }
        vc.onAsk = { [weak self] question in
            guard let self = self else { return }
            var args: [String: Any] = [
                "text": text,
                "question": question,
                "page": page,
                "yPosition": yPosition,
            ]
            if charStart >= 0 && charEnd >= 0 {
                args["charStart"] = charStart
                args["charEnd"] = charEnd
            }
            self.channel.invokeMethod("onAskConfirmed", arguments: args)
            self.annotatePopover?.close()
            self.annotatePopover = nil
            self.pdfView.clearSelection()
            self.lastNotifiedText = ""
        }

        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = false

        var rect = anchorRect.intersection(pdfView.bounds)
        if rect.isEmpty {
            rect = NSRect(x: pdfView.bounds.midX, y: pdfView.bounds.midY,
                          width: 1, height: 1)
        }

        popover.show(relativeTo: rect, of: pdfView, preferredEdge: .maxY)
        annotatePopover = popover
    }

    func view() -> NSView {
        return pdfView
    }

    func setHighlights(pageHighlights: [Int: [[String: Any]]]) {
        guard let document = pdfView.document else {
            engLog("setHighlights: NO document, skipping")
            return
        }

        engLog("setHighlights called: \(pageHighlights.count) pages, doc.pageCount=\(document.pageCount)")

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations where annotation.type == "Highlight" {
                page.removeAnnotation(annotation)
            }
        }

        if pageHighlights.isEmpty {
            engLog("setHighlights: empty, cleared all")
            return
        }

        var totalAdded = 0
        for (pageIndex, items) in pageHighlights {
            guard let page = document.page(at: pageIndex) else {
                engLog("setHighlights: page \(pageIndex) not found")
                continue
            }
            guard let pageText = page.string else {
                engLog("setHighlights: page \(pageIndex) has no text")
                continue
            }
            let nsPageText = pageText as NSString

            for item in items {
                let text = item["text"] as? String ?? ""
                let charStart = item["charStart"] as? Int ?? -1
                let charEnd = item["charEnd"] as? Int ?? -1

                if charStart >= 0 && charEnd > charStart && charEnd <= nsPageText.length {
                    let range = NSRange(location: charStart, length: charEnd - charStart)
                    if let selection = page.selection(for: range) {
                        let bounds = selection.bounds(for: page)
                        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                        annotation.color = NSColor.yellow.withAlphaComponent(0.35)
                        page.addAnnotation(annotation)
                        totalAdded += 1
                        engLog("setHighlights: page \(pageIndex) charRange \(charStart)-\(charEnd) -> OK bounds=\(bounds)")
                    } else {
                        engLog("setHighlights: page \(pageIndex) charRange \(charStart)-\(charEnd) -> selection FAILED")
                    }
                } else if !text.isEmpty {
                    let range = nsPageText.range(of: text, options: [.caseInsensitive])
                    if range.location != NSNotFound {
                        if let selection = page.selection(for: range) {
                            let bounds = selection.bounds(for: page)
                            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                            annotation.color = NSColor.yellow.withAlphaComponent(0.35)
                            page.addAnnotation(annotation)
                            totalAdded += 1
                            engLog("setHighlights: page \(pageIndex) textSearch '\(text.prefix(20))' -> OK")
                        } else {
                            engLog("setHighlights: page \(pageIndex) textSearch '\(text.prefix(20))' -> selection FAILED")
                        }
                    } else {
                        engLog("setHighlights: page \(pageIndex) textSearch '\(text.prefix(20))' -> NOT FOUND in pageText(\(nsPageText.length) chars)")
                    }
                }
            }
        }
        engLog("setHighlights done: added \(totalAdded) annotations")
    }

    private func loadDocument(at path: String) {
        let url = URL(fileURLWithPath: path)
        if let document = PDFDocument(url: url) {
            pdfView.document = document
            channel.invokeMethod("onDocumentLoaded", arguments: [
                "pageCount": document.pageCount
            ])
        } else {
            engLog("Failed to load PDF at: \(path)")
        }
    }

    @objc private func handleSelectionChange(_ notification: Notification) {
        let raw = pdfView.currentSelection?.string ?? ""
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text != lastNotifiedText {
            lastNotifiedText = text
            if !text.isEmpty {
                notifyTextSelected()
            }
        }
    }

    @objc private func handlePageChange(_ notification: Notification) {
        if let currentPage = pdfView.currentPage,
           let pageIndex = pdfView.document?.index(for: currentPage) {
            channel.invokeMethod("onPageChanged", arguments: pageIndex)
        }
    }

    private func routeMouseEvent(_ event: NSEvent) -> NSEvent? {
        engLog("routeMouseEvent type=\(event.type.rawValue)")
        guard let window = pdfView.window else {
            engLog("pdfView has no window")
            return event
        }
        guard event.window === window else {
            return event
        }
        let pointInWindow = event.locationInWindow
        let pointInView = pdfView.convert(pointInWindow, from: nil)
        guard pdfView.bounds.contains(pointInView) else {
            return event
        }

        engLog("forwarding event to pdfView, point=\(pointInView)")
        switch event.type {
        case .leftMouseDown:
            window.makeFirstResponder(pdfView)
            pdfView.mouseDown(with: event)
        case .leftMouseDragged:
            pdfView.mouseDragged(with: event)
        case .leftMouseUp:
            pdfView.mouseUp(with: event)
        default:
            return event
        }
        return nil
    }

    deinit {
        selectionPollTimer?.invalidate()
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - PDF Method Handler

class MacPDFMethodHandler {
    private let channel: FlutterMethodChannel
    private var document: PDFDocument?
    private var txtAnnotatePopover: NSPopover?

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "loadPdf":
            handleLoadPdf(call, result: result)
        case "goToPage":
            handleGoToPage(call, result: result)
        case "getPageText":
            handleGetPageText(call, result: result)
        case "showAnnotatePopover":
            handleShowAnnotatePopover(call, result: result)
        case "setHighlights":
            if let args = call.arguments as? [String: Any],
               let pageHighlights = args["pageHighlights"] as? [String: [[String: Any]]] {
                var mapped: [Int: [[String: Any]]] = [:]
                for (key, value) in pageHighlights {
                    if let pageIndex = Int(key) {
                        mapped[pageIndex] = value
                    }
                }
                MacPDFPlatformViewFactory.shared?.setHighlightsOnActiveView(pageHighlights: mapped)
            }
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func handleShowAnnotatePopover(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let text = args["text"] as? String,
              let yPosition = args["yPosition"] as? Double,
              let screenX = args["screenX"] as? Double,
              let screenY = args["screenY"] as? Double else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing args", details: nil))
            return
        }

        guard let window = NSApp.mainWindow,
              let contentView = window.contentView else {
            result(nil)
            return
        }

        // If popover is already showing, just update text and callback in-place.
        if let existingPopover = txtAnnotatePopover, existingPopover.isShown,
           let vc = existingPopover.contentViewController as? AnnotatePopoverViewController {
            vc.updateText(text)
            vc.onAnnotate = { [weak self] in
                guard let self = self else { return }
                self.channel.invokeMethod("onAnnotateConfirmed", arguments: [
                    "text": text,
                    "yPosition": yPosition,
                ] as [String: Any])
                self.txtAnnotatePopover?.close()
                self.txtAnnotatePopover = nil
            }
            vc.onAsk = { [weak self] question in
                guard let self = self else { return }
                self.channel.invokeMethod("onAskConfirmed", arguments: [
                    "text": text,
                    "question": question,
                    "yPosition": yPosition,
                ] as [String: Any])
                self.txtAnnotatePopover?.close()
                self.txtAnnotatePopover = nil
            }
            result(nil)
            return
        }

        txtAnnotatePopover?.close()

        let vc = AnnotatePopoverViewController()
        vc.text = text
        vc.onAnnotate = { [weak self] in
            guard let self = self else { return }
            self.channel.invokeMethod("onAnnotateConfirmed", arguments: [
                "text": text,
                "yPosition": yPosition,
            ] as [String: Any])
            self.txtAnnotatePopover?.close()
            self.txtAnnotatePopover = nil
        }
        vc.onAsk = { [weak self] question in
            guard let self = self else { return }
            self.channel.invokeMethod("onAskConfirmed", arguments: [
                "text": text,
                "question": question,
                "yPosition": yPosition,
            ] as [String: Any])
            self.txtAnnotatePopover?.close()
            self.txtAnnotatePopover = nil
        }

        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = false

        let windowHeight = contentView.bounds.height
        let localX = screenX
        let localY = windowHeight - screenY
        let rect = NSRect(x: localX, y: localY, width: 1, height: 1)

        popover.show(relativeTo: rect, of: contentView, preferredEdge: .maxY)
        txtAnnotatePopover = popover
        result(nil)
    }

    private func handleLoadPdf(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let path = args["path"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Missing path", details: nil))
            return
        }

        let url = URL(fileURLWithPath: path)
        guard let doc = PDFDocument(url: url) else {
            result(FlutterError(code: "LOAD_ERROR", message: "Cannot load PDF", details: nil))
            return
        }

        document = doc
        result(["pageCount": doc.pageCount])
    }

    private func handleGoToPage(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let _ = args["page"] as? Int else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid page", details: nil))
            return
        }
        result(nil)
    }

    private func handleGetPageText(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let page = args["page"] as? Int,
              let doc = document,
              let pdfPage = doc.page(at: page) else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid page", details: nil))
            return
        }

        let text = pdfPage.string ?? ""
        result(text)
    }
}
