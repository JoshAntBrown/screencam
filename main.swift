import AppKit
import Carbon.HIToolbox
import AVFoundation
import ScreenCaptureKit

// MARK: - Floating webcam bubble

final class CameraBubble: NSPanel {
    private let session = AVCaptureSession()
    private let preview: AVCaptureVideoPreviewLayer

    init(diameter: CGFloat) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        let screen = NSScreen.main!.visibleFrame
        let rect = NSRect(x: screen.maxX - diameter - 40, y: screen.minY + 40, width: diameter, height: diameter)
        super.init(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true

        let view = NSView(frame: NSRect(origin: .zero, size: rect.size))
        view.wantsLayer = true
        view.layer!.cornerRadius = diameter / 2
        view.layer!.masksToBounds = true
        view.layer!.borderWidth = 3
        view.layer!.borderColor = NSColor.white.withAlphaComponent(0.9).cgColor
        view.layer!.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        preview.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer!.insertSublayer(preview, at: 0)
        view.autoresizingMask = [.width, .height]
        contentView = view
    }

    override var canBecomeKey: Bool { false }

    func startCamera() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            guard granted else { return }
            DispatchQueue.main.async { self.configureSession() }
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(input)
        session.commitConfiguration()
        if let conn = preview.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = false
            conn.isVideoMirrored = true
        }
        DispatchQueue.global(qos: .userInitiated).async { self.session.startRunning() }
    }

    func setDiameter(_ d: CGFloat) {
        var f = frame
        f.origin.x += (f.width - d) / 2
        f.origin.y += (f.height - d) / 2
        f.size = NSSize(width: d, height: d)
        setFrame(f, display: true, animate: true)
        contentView?.layer?.cornerRadius = d / 2
    }
}

// MARK: - Screen + mic recorder

final class Recorder: NSObject, SCStreamOutput, SCStreamDelegate, SCRecordingOutputDelegate {
    private var stream: SCStream?
    private var output: SCRecordingOutput?
    private(set) var fileURL: URL?
    var onFinish: ((URL?, Error?) -> Void)?
    private let sampleQueue = DispatchQueue(label: "screencam.samples")

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        // Record the display the mouse is on (fall back to the first one).
        let mouse = NSEvent.mouseLocation
        let nsScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main!
        let screenID = nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == screenID }) ?? content.displays.first else {
            throw NSError(domain: "ScreenCam", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let scale = nsScreen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true
        config.queueDepth = 6
        config.captureMicrophone = true
        config.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID

        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0]
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let url = movies.appendingPathComponent("ScreenCam \(stamp.string(from: Date())).mov")

        let recConfig = SCRecordingOutputConfiguration()
        recConfig.outputURL = url
        recConfig.outputFileType = .mov
        recConfig.videoCodecType = .h264

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        // No-op outputs so ScreenCaptureKit has somewhere to deliver buffers.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: sampleQueue)
        let output = SCRecordingOutput(configuration: recConfig, delegate: self)
        try stream.addRecordingOutput(output)
        try await stream.startCapture()

        self.stream = stream
        self.output = output
        self.fileURL = url
    }

    func stop() async {
        guard let stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {}

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { self.onFinish?(self.fileURL, error) }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        DispatchQueue.main.async { self.onFinish?(self.fileURL, nil) }
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        DispatchQueue.main.async { self.onFinish?(self.fileURL, error) }
    }
}

// MARK: - App / menu bar

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var bubble: CameraBubble!
    private let recorder = Recorder()
    private var recording = false
    private var startedAt: Date?
    private var timer: Timer?
    private var toggleItem: NSMenuItem!
    private var bubbleItem: NSMenuItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        bubble = CameraBubble(diameter: 220)
        bubble.orderFrontRegardless()
        bubble.startCamera()

        // Ask for mic up front so the first recording doesn't stall on a prompt.
        AVCaptureDevice.requestAccess(for: .audio) { _ in }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusIcon()

        let menu = NSMenu()
        toggleItem = NSMenuItem(title: "Start Recording", action: #selector(toggleRecording), keyEquivalent: "r")
        toggleItem.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        bubbleItem = NSMenuItem(title: "Hide Webcam", action: #selector(toggleBubble), keyEquivalent: "")
        menu.addItem(bubbleItem)
        let sizes = NSMenu()
        for (name, d) in [("Small", 150), ("Medium", 220), ("Large", 320), ("Huge", 440)] {
            let item = NSMenuItem(title: name, action: #selector(setSize(_:)), keyEquivalent: "")
            item.tag = d
            sizes.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Webcam Size", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizes
        menu.addItem(sizeItem)
        menu.addItem(NSMenuItem(title: "Open Recordings Folder", action: #selector(openFolder), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ScreenCam", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        recorder.onFinish = { [weak self] url, error in self?.finished(url: url, error: error) }
        registerHotKey()
    }

    // Global ⌃⌥⌘R, works whichever app is frontmost (no Accessibility permission needed).
    private var hotKeyRef: EventHotKeyRef?
    private func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            MainActor.assumeIsolated { delegate.toggleRecording() }
            return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x5343_414D), id: 1) // 'SCAM'
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey | cmdKey), id,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    private func updateStatusIcon() {
        guard let button = statusItem.button else { return }
        if recording, let startedAt {
            let s = Int(Date().timeIntervalSince(startedAt))
            let red = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: "Recording")?
                .withSymbolConfiguration(red)
            image?.isTemplate = false
            button.image = image
            button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            button.title = String(format: " %d:%02d", s / 60, s % 60)
        } else {
            button.image = NSImage(systemSymbolName: "video.circle", accessibilityDescription: "ScreenCam")
            button.image?.isTemplate = true
            button.title = ""
        }
        button.imagePosition = .imageLeading
    }

    @objc func toggleRecording() {
        guard toggleItem.isEnabled else { return }
        if recording {
            toggleItem.isEnabled = false
            Task { await recorder.stop() }
        } else {
            toggleItem.isEnabled = false
            Task { @MainActor in
                do {
                    try await recorder.start()
                    recording = true
                    startedAt = Date()
                    toggleItem.title = "Stop Recording"
                    timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.updateStatusIcon() } }
                } catch {
                    alert("Couldn't start recording", error.localizedDescription +
                          "\n\nMake sure ScreenCam is allowed under System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch it.")
                }
                toggleItem.isEnabled = true
                updateStatusIcon()
            }
        }
    }

    private func finished(url: URL?, error: Error?) {
        guard recording else { return }
        recording = false
        timer?.invalidate()
        toggleItem.title = "Start Recording"
        toggleItem.isEnabled = true
        updateStatusIcon()
        if let error { alert("Recording stopped with an error", error.localizedDescription) }
        if let url, FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    @objc private func toggleBubble() {
        if bubble.isVisible { bubble.orderOut(nil); bubbleItem.title = "Show Webcam" }
        else { bubble.orderFrontRegardless(); bubbleItem.title = "Hide Webcam" }
    }

    @objc private func setSize(_ sender: NSMenuItem) { bubble.setDiameter(CGFloat(sender.tag)) }

    @objc private func openFolder() {
        NSWorkspace.shared.open(FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0])
    }

    @objc private func quit() {
        if recording {
            Task { @MainActor in await recorder.stop(); try? await Task.sleep(for: .milliseconds(500)); NSApp.terminate(nil) }
        } else { NSApp.terminate(nil) }
    }

    private func alert(_ title: String, _ text: String) {
        NSApp.activate()
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.runModal()
    }
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
