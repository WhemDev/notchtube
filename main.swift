import Cocoa
import WebKit
import Network

// MARK: - Minimal localhost HTTP server

class LocalServer {
    private var listener: NWListener?
    private(set) var port: UInt16 = 0
    private var html: String = ""
    private let readyCallback: (UInt16) -> Void

    init(onReady: @escaping (UInt16) -> Void) {
        self.readyCallback = onReady
    }

    func start() {
        guard let l = try? NWListener(using: .tcp, on: .any) else { return }
        listener = l

        l.stateUpdateHandler = { [weak self] state in
            if case .ready = state, let port = self?.listener?.port?.rawValue {
                self?.port = port
                DispatchQueue.main.async { self?.readyCallback(port) }
            }
        }

        l.newConnectionHandler = { [weak self] conn in
            conn.start(queue: .global(qos: .userInteractive))
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { _, _, _, _ in
                guard let body = self?.html, let data = body.data(using: .utf8) else {
                    conn.cancel(); return
                }
                let header = "HTTP/1.1 200 OK\r\nContent-Type: text/html;charset=utf-8\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n"
                conn.send(content: header.data(using: .utf8)! + data, completion: .contentProcessed { _ in
                    conn.cancel()
                })
            }
        }

        l.start(queue: .global(qos: .userInteractive))
    }

    func serve(_ content: String) { html = content }
    func stop() { listener?.cancel() }
}

// MARK: - Floating Panel

class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - App

class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {

    private var panel: FloatingPanel!
    private var containerView: NSView!
    private var webView: WKWebView!
    private var urlField: NSTextField!
    private var closeButton: NSButton!
    private var statusItem: NSStatusItem!
    private var server: LocalServer!

    private let controlBarHeight: CGFloat = 34
    private var currentWidth: CGFloat = 320
    private let minWidth: CGFloat = 200
    private let maxWidth: CGFloat = 600
    private let widthStep: CGFloat = 40

    private var videoHeight: CGFloat { floor(currentWidth * 9 / 16) }
    private var totalHeight: CGFloat { videoHeight + controlBarHeight }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupEditMenu()

        server = LocalServer { [weak self] port in
            NSLog("NotchPlayer server ready on port %d", port)
            _ = self
        }
        server.start()

        setupPanel()
        setupWebView()
        setupControlBar()
        setupStatusBarMenu()
        showPlaceholder()
        panel.orderFront(nil)
    }

    private func setupEditMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationWillTerminate(_ notification: Notification) {
        server.stop()
    }

    // MARK: - Panel

    private func setupPanel() {
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - currentWidth / 2
        let y = screen.frame.maxY - totalHeight - 4

        panel = FloatingPanel(
            contentRect: NSRect(x: x, y: y, width: currentWidth, height: totalHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isMovableByWindowBackground = false

        containerView = NSView(frame: NSRect(x: 0, y: 0, width: currentWidth, height: totalHeight))
        containerView.wantsLayer = true
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor
        containerView.layer?.borderColor = NSColor(white: 0.22, alpha: 0.9).cgColor
        containerView.layer?.borderWidth = 0.5
        panel.contentView = containerView
    }

    // MARK: - WebView

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []

        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        webView = WKWebView(
            frame: NSRect(x: 0, y: controlBarHeight, width: currentWidth, height: videoHeight),
            configuration: config
        )
        webView.uiDelegate = self
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.3 Safari/605.1.15"
        webView.allowsBackForwardNavigationGestures = false
        webView.autoresizingMask = [.width, .height]
        containerView.addSubview(webView)
    }

    private func showPlaceholder() {
        let html = """
        <html><body style="background:#0a0a0a;color:#484848;display:flex;align-items:center;\
        justify-content:center;height:100vh;margin:0;font-family:-apple-system,sans-serif;\
        font-size:13px;-webkit-user-select:none">\
        <div style="text-align:center;line-height:1.6">▶︎<br>YouTube URL yapıştırın</div>\
        </body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func loadVideo(videoId: String) {
        guard server.port > 0 else { return }
        let origin = "http://localhost:\(server.port)"
        let html = """
        <!DOCTYPE html><html><head>\
        <meta name="viewport" content="width=device-width,initial-scale=1">\
        <style>*{margin:0;padding:0;overflow:hidden}html,body{width:100%;height:100%;background:#000}\
        iframe{width:100%;height:100%;border:none;display:block}</style>\
        </head><body>\
        <iframe src="https://www.youtube.com/embed/\(videoId)?autoplay=1&controls=1&rel=0&origin=\(origin)"\
         allow="autoplay;encrypted-media;picture-in-picture" allowfullscreen></iframe>\
        </body></html>
        """
        server.serve(html)
        webView.load(URLRequest(url: URL(string: "\(origin)/")!))
    }

    // MARK: - Control Bar

    private func setupControlBar() {
        let bar = NSView(frame: NSRect(x: 0, y: 0, width: currentWidth, height: controlBarHeight))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        bar.autoresizingMask = [.width]
        bar.autoresizesSubviews = true

        bar.addSubview(makeBtn(x: 6, title: "−", action: #selector(sizeDown)))
        bar.addSubview(makeBtn(x: 30, title: "+", action: #selector(sizeUp)))

        let urlX: CGFloat = 58
        urlField = NSTextField(frame: NSRect(x: urlX, y: 5, width: currentWidth - urlX - 34, height: 24))
        urlField.placeholderString = "YouTube URL..."
        urlField.font = .systemFont(ofSize: 11)
        urlField.isBezeled = true
        urlField.bezelStyle = .roundedBezel
        urlField.focusRingType = .none
        urlField.target = self
        urlField.action = #selector(handleUrlSubmit)
        urlField.autoresizingMask = [.width]
        bar.addSubview(urlField)

        closeButton = NSButton(frame: NSRect(x: currentWidth - 30, y: 5, width: 24, height: 24))
        closeButton.title = "✕"
        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.font = .systemFont(ofSize: 14, weight: .light)
        closeButton.contentTintColor = NSColor(white: 0.45, alpha: 1)
        closeButton.target = self
        closeButton.action = #selector(hidePanel)
        closeButton.autoresizingMask = [.minXMargin]
        bar.addSubview(closeButton)

        containerView.addSubview(bar)
    }

    private func makeBtn(x: CGFloat, title: String, action: Selector) -> NSButton {
        let b = NSButton(frame: NSRect(x: x, y: 5, width: 24, height: 24))
        b.title = title
        b.bezelStyle = .inline
        b.isBordered = false
        b.font = .systemFont(ofSize: 16, weight: .medium)
        b.contentTintColor = NSColor(white: 0.55, alpha: 1)
        b.target = self
        b.action = action
        return b
    }

    // MARK: - Status Bar Menu

    private func setupStatusBarMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "▶ Notch"
        let menu = NSMenu()
        menu.addItem(withTitle: "Göster / Gizle", action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Çıkış", action: #selector(quitApp), keyEquivalent: "q")
        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func handleUrlSubmit() {
        let input = urlField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, let videoId = extractVideoId(from: input) else { return }
        loadVideo(videoId: videoId)
        panel.makeFirstResponder(nil)
    }

    @objc private func sizeDown() {
        guard currentWidth > minWidth else { return }
        currentWidth -= widthStep
        relayout()
    }

    @objc private func sizeUp() {
        guard currentWidth < maxWidth else { return }
        currentWidth += widthStep
        relayout()
    }

    private func relayout() {
        guard let screen = NSScreen.main else { return }
        let x = screen.frame.midX - currentWidth / 2
        let y = screen.frame.maxY - totalHeight - 4
        panel.setFrame(
            NSRect(x: x, y: y, width: currentWidth, height: totalHeight),
            display: true, animate: true
        )
    }

    @objc private func hidePanel() { panel.orderOut(nil) }
    @objc private func togglePanel() { panel.isVisible ? panel.orderOut(nil) : panel.orderFront(nil) }
    @objc private func quitApp() { NSApp.terminate(nil) }

    // MARK: - YouTube URL Parsing

    private func extractVideoId(from input: String) -> String? {
        guard let url = URL(string: input) else {
            return input.count == 11 ? input : nil
        }
        let host = url.host ?? ""
        if host.contains("youtu.be") {
            return url.pathComponents.dropFirst().first
        }
        if host.contains("youtube.com") {
            if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
               let v = items.first(where: { $0.name == "v" })?.value { return v }
            let p = url.pathComponents
            if p.contains("embed") || p.contains("shorts") || p.contains("live") { return p.last }
        }
        return nil
    }

    // MARK: - WKUIDelegate

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            NSWorkspace.shared.open(url)
        }
        return nil
    }
}

// MARK: - Entry Point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
