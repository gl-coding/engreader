import Flutter
import UIKit
import PDFKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let messenger = controller.binaryMessenger

    // Register PDF platform view
    let pdfViewFactory = IOSPDFPlatformViewFactory(messenger: messenger)
    registrar(forPlugin: "PDFPlatformView")!.register(pdfViewFactory, withId: "com.engreader/pdfview")

    // Register method channel
    let channel = FlutterMethodChannel(name: "com.engreader/pdfkit", binaryMessenger: messenger)
    let pdfHandler = IOSPDFMethodHandler(channel: channel)
    channel.setMethodCallHandler(pdfHandler.handle)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

// MARK: - PDF Platform View Factory

class IOSPDFPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger

    init(messenger: FlutterBinaryMessenger) {
        self.messenger = messenger
        super.init()
    }

    func create(
        withFrame frame: CGRect,
        viewIdentifier viewId: Int64,
        arguments args: Any?
    ) -> FlutterPlatformView {
        return IOSPDFPlatformView(
            frame: frame,
            viewId: viewId,
            args: args as? [String: Any],
            messenger: messenger
        )
    }

    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
        return FlutterStandardMessageCodec.sharedInstance()
    }
}

// MARK: - PDF Platform View

class IOSPDFPlatformView: NSObject, FlutterPlatformView {
    private let pdfView: PDFView
    private let channel: FlutterMethodChannel

    init(frame: CGRect, viewId: Int64, args: [String: Any]?, messenger: FlutterBinaryMessenger) {
        pdfView = PDFView(frame: frame)
        channel = FlutterMethodChannel(name: "com.engreader/pdfkit", binaryMessenger: messenger)
        super.init()

        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical

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
    }

    func view() -> UIView {
        return pdfView
    }

    private func loadDocument(at path: String) {
        let url = URL(fileURLWithPath: path)
        if let document = PDFDocument(url: url) {
            pdfView.document = document
        }
    }

    @objc private func handleSelectionChange(_ notification: Notification) {
        guard let selection = pdfView.currentSelection,
              let text = selection.string,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        if let page = selection.pages.first,
           let pageIndex = pdfView.document?.index(for: page) {
            let bounds = selection.bounds(for: page)
            let pageHeight = page.bounds(for: .mediaBox).height
            let yPosition = Double(bounds.midY / pageHeight)

            channel.invokeMethod("onTextSelected", arguments: [
                "text": text.trimmingCharacters(in: .whitespacesAndNewlines),
                "yPosition": yPosition,
                "page": pageIndex
            ] as [String: Any])
        }
    }

    @objc private func handlePageChange(_ notification: Notification) {
        if let currentPage = pdfView.currentPage,
           let pageIndex = pdfView.document?.index(for: currentPage) {
            channel.invokeMethod("onPageChanged", arguments: pageIndex)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

// MARK: - PDF Method Handler

class IOSPDFMethodHandler {
    private let channel: FlutterMethodChannel
    private var document: PDFDocument?

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
        default:
            result(FlutterMethodNotImplemented)
        }
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
