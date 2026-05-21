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

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
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

    override func loadView() {
        let isWord = !text.contains(" ") || text.split(separator: " ").count <= 2
        let typeText = isWord ? "单词" : "句子"
        let preview = text.count > 50
            ? String(text.prefix(50)) + "…"
            : text

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let typeLabel = NSTextField(labelWithString: typeText)
        typeLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        typeLabel.textColor = isWord
            ? NSColor.systemBlue
            : NSColor.systemPurple
        typeLabel.translatesAutoresizingMaskIntoConstraints = false

        let textLabel = NSTextField(labelWithString: preview)
        textLabel.font = NSFont.systemFont(ofSize: 13)
        textLabel.lineBreakMode = .byTruncatingTail
        textLabel.maximumNumberOfLines = 1
        textLabel.translatesAutoresizingMaskIntoConstraints = false
        textLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let button = NSButton(title: "批注", target: self, action: #selector(annotateClicked))
        button.bezelStyle = .rounded
        button.keyEquivalent = "\r"
        button.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(typeLabel)
        container.addSubview(textLabel)
        container.addSubview(button)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 44),
            container.widthAnchor.constraint(greaterThanOrEqualToConstant: 320),
            container.widthAnchor.constraint(lessThanOrEqualToConstant: 480),

            typeLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 12),
            typeLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            textLabel.leadingAnchor.constraint(equalTo: typeLabel.trailingAnchor, constant: 8),
            textLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            textLabel.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),

            button.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -12),
            button.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        self.view = container
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

        let viewRect = pdfView.convert(pageBounds, from: page)

        // Show native popover anchored above the selection. Flutter overlays
        // are obscured by the PlatformView, so we use a native NSPopover.
        showAnnotatePopover(text: text, anchorRect: viewRect, page: pageIndex,
                            yPosition: yPosition)
    }

    private func showAnnotatePopover(text: String, anchorRect: NSRect,
                                      page: Int, yPosition: Double) {
        engLog("showAnnotatePopover: text=\(text.prefix(20)), anchorRect=\(anchorRect), pdfView.bounds=\(pdfView.bounds), pdfView.window=\(String(describing: pdfView.window))")

        annotatePopover?.close()

        let vc = AnnotatePopoverViewController()
        vc.text = text
        vc.onAnnotate = { [weak self] in
            guard let self = self else { return }
            engLog("annotate button clicked, text=\(text.prefix(20))")
            self.channel.invokeMethod("onAnnotateConfirmed", arguments: [
                "text": text,
                "page": page,
                "yPosition": yPosition,
            ] as [String: Any])
            self.annotatePopover?.close()
            self.annotatePopover = nil
            self.pdfView.clearSelection()
            self.lastNotifiedText = ""
        }

        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .transient
        popover.animates = false

        // Make sure anchor rect is valid; clamp to view bounds.
        var rect = anchorRect.intersection(pdfView.bounds)
        if rect.isEmpty {
            engLog("anchorRect intersection empty, using fallback center")
            rect = NSRect(x: pdfView.bounds.midX, y: pdfView.bounds.midY,
                          width: 1, height: 1)
        }

        engLog("showing popover at rect=\(rect)")
        popover.show(relativeTo: rect, of: pdfView, preferredEdge: .maxY)
        annotatePopover = popover
        engLog("popover shown, isShown=\(popover.isShown)")
    }

    func view() -> NSView {
        return pdfView
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

        txtAnnotatePopover?.close()

        guard let window = NSApp.mainWindow,
              let contentView = window.contentView else {
            result(nil)
            return
        }

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

        // Convert Flutter screen coordinates to NSWindow coordinates.
        // Flutter origin = top-left; AppKit origin = bottom-left.
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
