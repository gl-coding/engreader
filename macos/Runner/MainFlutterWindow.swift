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
        if let view = activePlatformViews.values.first {
            view.setHighlights(pageHighlights: pageHighlights)
        }
    }

    func create(
        withViewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> NSView {
        engLog("MacPDFPlatformViewFactory.create called, viewId=\(viewId)")
        let platformView = MacPDFPlatformView(
            viewId: viewId,
            args: args as? [String: Any],
            messenger: messenger
        )
        activePlatformViews[viewId] = platformView
        engLog("MacPDFPlatformView created and retained")
        return platformView.view()
    }

    func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - Native annotate popover

class AnnotatePopoverViewController: NSViewController {
    var text: String = ""
    var onAnnotate: (() -> Void)?
    private var typeLabel: NSTextField?
    private var textLabel: NSTextField?

    override func loadView() {
        let isWord = !text.contains(" ") || text.split(separator: " ").count <= 2
        let typeText = isWord ? "单词" : "句子"
        let preview = text.count > 50
            ? String(text.prefix(50)) + "…"
            : text

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

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

        let button = NSButton(title: "批注", target: self, action: #selector(annotateClicked))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(tLabel)
        container.addSubview(txLabel)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 480),

            tLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            tLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            txLabel.leadingAnchor.constraint(equalTo: tLabel.trailingAnchor, constant: 8),
            txLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            txLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        self.view = container
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
    }

    @objc private func annotateClicked() {
        onAnnotate?()
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
        guard let document = pdfView.document else { return }

        for i in 0..<document.pageCount {
            guard let page = document.page(at: i) else { continue }
            for annotation in page.annotations where annotation.type == "Highlight" {
                page.removeAnnotation(annotation)
            }
        }

        if pageHighlights.isEmpty { return }

        for (pageIndex, items) in pageHighlights {
            guard let page = document.page(at: pageIndex) else { continue }
            guard let pageText = page.string else { continue }
            let nsPageText = pageText as NSString

            for item in items {
                let text = item["text"] as? String ?? ""
                let charStart = item["charStart"] as? Int ?? -1
                let charEnd = item["charEnd"] as? Int ?? -1

                if charStart >= 0 && charEnd > charStart && charEnd <= nsPageText.length {
                    // Use precise character range.
                    let range = NSRange(location: charStart, length: charEnd - charStart)
                    if let selection = page.selection(for: range) {
                        let bounds = selection.bounds(for: page)
                        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                        annotation.color = NSColor.yellow.withAlphaComponent(0.35)
                        page.addAnnotation(annotation)
                    }
                } else if !text.isEmpty {
                    // Fallback: search by text on this page.
                    let range = nsPageText.range(of: text, options: [.caseInsensitive])
                    if range.location != NSNotFound {
                        if let selection = page.selection(for: range) {
                            let bounds = selection.bounds(for: page)
                            let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
                            annotation.color = NSColor.yellow.withAlphaComponent(0.35)
                            page.addAnnotation(annotation)
                        }
                    }
                }
            }
        }
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
