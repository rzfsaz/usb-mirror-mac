import Cocoa
import SwiftUI
@preconcurrency import AVFoundation
import CoreMediaIO

final class Mirror: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    let queue = DispatchQueue(label: "USBMirror.capture", qos: .userInteractive)
    let audio = AVCaptureAudioPreviewOutput()
    let video = AVCaptureVideoDataOutput()
    private var discovery: AVCaptureDevice.DiscoverySession!
    private var scanTimer: Timer?
    private var sessionToken = UUID()
    private var receivedFrame = false
    private var audioReady = false
    private var lastFrameSize = CGSize.zero
    private var sourceSize = CGSize.zero
    @Published var orientationLabel = "Menunggu gambar"
    @Published var language = AppLanguage.initial {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "appLanguage")
            updateAppLanguage()
        }
    }
    @Published var theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "system") ?? .system {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: "appTheme") }
    }
    @Published var statusArgument = ""
    func text(_ key: String) -> String { L10n.text(key, language: language) }
    var statusText: String {
        let translated = text(status)
        return translated.contains("%@") ? String(format: translated, statusArgument) : translated
    }
    func updateAppLanguage() {
        for window in NSApp.windows where window.title != "USB Mirror — iPhone" {
            if window.contentView is NSHostingView<Controls> { window.title = text("USB Mirror — Kontrol") }
        }
        NSApp.mainMenu?.items.first?.submenu?.items.first?.title = text("Keluar USB Mirror")
    }
    @Published var rotation = 0
    @Published var autoFit = true
    @Published var devices: [AVCaptureDevice] = []
    @Published var selected = ""
    @Published var status = "Sambungkan iPhone menggunakan kabel USB."
    @Published var running = false
    @Published var busy = false
    @Published var volume: Double = 0.25
    @Published var soundEnabled = false
    private var observers: [NSObjectProtocol] = []
    private var outputWindow: NSWindow?
    private var currentID = ""

    override init() {
        super.init()
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices), mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal), mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var enabled: UInt32 = 1
        let result = CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout.size(ofValue: enabled)), &enabled)
        if result != noErr { statusArgument = String(result); status = "Akses perangkat USB gagal (%@). Coba buka ulang aplikasi." }
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self = self else { return }
                if name == AVCaptureDevice.wasDisconnectedNotification, let device = notification.object as? AVCaptureDevice, device.uniqueID == self.currentID {
                    self.stop(message: "iPhone terputus. Sambungkan kembali, lalu klik Mulai.")
                }
                self.refresh()
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] notification in
            let error = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError
            self?.stop(message: error?.localizedDescription ?? "Sesi terhenti. Coba sambungkan ulang iPhone.")
        })
        observers.append(NotificationCenter.default.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] _ in
            self?.stop(message: "Mirroring terganggu. Buka kunci iPhone lalu klik Mulai kembali.")
        })
        discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .muxed, position: .unspecified)
        refresh()
        scanTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func refresh() {
        // USB screen devices advertise muxed video + audio. Excludes Continuity Camera.
        guard let discovery = discovery else { return }
        let found = discovery.devices.filter { $0.isConnected && $0.hasMediaType(.muxed) }
        let changed = devices.map(\.uniqueID) != found.map(\.uniqueID)
        devices = found
        if changed && !busy && !running {
            status = devices.isEmpty ? "Menunggu layar iPhone lewat USB. Buka kunci dan pilih Percayai; pencarian otomatis aktif." : "iPhone USB ditemukan. Klik Mulai mirroring. Suara awalnya mati."
        }
        if !devices.contains(where: { $0.uniqueID == selected }) { selected = devices.first?.uniqueID ?? "" }
    }

    func start() {
        guard !busy, !running else { return }
        busy = true
        status = "Memeriksa izin kamera dan audio…"
        Task { @MainActor in
            let camera = await AVCaptureDevice.requestAccess(for: .video)
            let microphone = await AVCaptureDevice.requestAccess(for: .audio)
            guard camera && microphone else {
                busy = false
                status = "Izinkan Kamera dan Mikrofon untuk USB Mirror di Pengaturan Sistem → Privasi & Keamanan, lalu buka ulang aplikasi."
                return
            }
            refresh()
            guard let device = devices.first(where: { $0.uniqueID == selected }) else {
                busy = false
                status = "iPhone belum ditemukan. Buka kunci iPhone, pilih Trust/Percayai, lalu klik Cari ulang."
                return
            }
            currentID = device.uniqueID
            showOutput()
            let desiredVolume: Float = 0
            soundEnabled = false
            statusArgument = device.localizedName
            status = "Menghubungkan ke %@…"
            queue.async {
                do {
                    self.sessionToken = UUID()
                    self.receivedFrame = false
                    self.lastFrameSize = .zero
                    self.audioReady = false
                    self.session.beginConfiguration()
                    for input in self.session.inputs { self.session.removeInput(input) }
                    for output in self.session.outputs { self.session.removeOutput(output) }
                    let input: AVCaptureDeviceInput
                    do { input = try AVCaptureDeviceInput(device: device) }
                    catch { self.session.commitConfiguration(); throw error }
                    guard self.session.canAddInput(input) else {
                        self.session.commitConfiguration()
                        throw NSError(domain: "USBMirror", code: 1, userInfo: [NSLocalizedDescriptionKey: "iPhone sedang digunakan aplikasi lain. Tutup sesi QuickTime atau aplikasi mirroring lain."])
                    }
                    self.session.addInput(input)
                    if self.session.canSetSessionPreset(.high) { self.session.sessionPreset = .high }
                    self.video.alwaysDiscardsLateVideoFrames = true
                    self.video.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(self.video) else {
                        self.session.commitConfiguration()
                        throw NSError(domain: "USBMirror", code: 2, userInfo: [NSLocalizedDescriptionKey: "Tidak bisa membaca gambar iPhone. Tutup aplikasi lain yang menggunakan iPhone."])
                    }
                    self.session.addOutput(self.video)
                    let hasAudio = input.ports.contains { $0.mediaType == .audio }
                    var audioReady = false
                    if hasAudio && self.session.canAddOutput(self.audio) {
                        self.audio.volume = desiredVolume
                        self.session.addOutput(self.audio)
                        audioReady = true
                    }
                    self.audioReady = audioReady
                    self.session.commitConfiguration()
                    self.session.startRunning()
                    let active = self.session.isRunning
                    let message = !active ? "Gagal memulai. Buka kunci iPhone dan periksa kabel USB." : "Menunggu gambar pertama dari iPhone…"
                    let token = self.sessionToken
                    self.queue.asyncAfter(deadline: .now() + 12) {
                        guard self.sessionToken == token, self.session.isRunning, !self.receivedFrame else { return }
                        DispatchQueue.main.async { self.stop(message: "Tidak ada gambar dari iPhone. Buka kunci, pilih Percayai, lalu coba lagi.") }
                    }
                    DispatchQueue.main.async {
                        self.busy = false
                        self.running = active
                        self.status = message
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.busy = false
                        self.running = false
                        self.status = error.localizedDescription
                    }
                }
            }
        }
    }

    func stop(message: String = "Mirroring dihentikan.") {
        busy = true
        soundEnabled = false
        queue.async {
            self.sessionToken = UUID()
            self.audio.volume = 0
            self.session.stopRunning()
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            for output in self.session.outputs { self.session.removeOutput(output) }
            self.session.commitConfiguration()
            DispatchQueue.main.async {
                self.running = false
                self.busy = false
                self.currentID = ""
                self.status = message
            }
        }
    }

    func updateVolume() {
        let value = soundEnabled ? Float(volume) : 0
        queue.async { self.audio.volume = value }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        if !receivedFrame {
            receivedFrame = true
            let message = audioReady ? "Gambar masuk. Audio siap diaktifkan." : "Gambar masuk. Audio belum tersedia."
            DispatchQueue.main.async { self.status = message }
        }
        // iPhone screen capture changes presentation dimensions when its UI rotates.
        guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else { return }
        let size = CMVideoFormatDescriptionGetPresentationDimensions(format, usePixelAspectRatio: true, useCleanAperture: true)
        guard size.width > 0, size.height > 0, size != lastFrameSize else { return }
        lastFrameSize = size
        DispatchQueue.main.async {
            self.sourceSize = size
            self.updateOrientation()
        }
    }

    func updateOrientation() {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return }
        let size = rotation % 2 == 0 ? sourceSize : CGSize(width: sourceSize.height, height: sourceSize.width)
        orientationLabel = size.width > size.height ? "Landscape" : "Portrait"
        (outputWindow?.contentView as? PreviewView)?.setRotation(rotation)
        guard autoFit, let window = outputWindow, !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame.insetBy(dx: 24, dy: 24)
        let chrome = window.frame.height - (window.contentView?.bounds.height ?? window.frame.height)
        guard let fitted = MirrorGeometry.fittedSize(source: size, available: CGSize(width: visible.width, height: visible.height - chrome)) else { return }
        let oldFrame = window.frame
        window.contentAspectRatio = size
        var frame = window.frameRect(forContentRect: CGRect(origin: .zero, size: fitted))
        frame.origin = CGPoint(x: oldFrame.midX - frame.width / 2, y: oldFrame.midY - frame.height / 2)
        frame.origin.x = max(visible.minX, min(frame.origin.x, visible.maxX - frame.width))
        frame.origin.y = max(visible.minY, min(frame.origin.y, visible.maxY - frame.height))
        window.setFrame(frame, display: true)
    }

    func rotateManually() {
        rotation = (rotation + 1) % 4
        updateOrientation()
    }

    func showOutput() {
        if outputWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "USB Mirror — iPhone"
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.contentView = PreviewView(session: session)
            window.contentMinSize = NSSize(width: 160, height: 160)
            window.center()
            outputWindow = window
        }
        outputWindow?.makeKeyAndOrderFront(nil)
        updateOrientation()
    }
}

final class PreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    private var quarterTurns = 0
    func setRotation(_ turns: Int) {
        quarterTurns = turns
        needsLayout = true
    }
    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        preview.videoGravity = .resizeAspect
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { fatalError("Not used") }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let rotated = quarterTurns % 2 != 0
        preview.bounds = CGRect(origin: .zero, size: rotated ? CGSize(width: bounds.height, height: bounds.width) : bounds.size)
        preview.position = CGPoint(x: bounds.midX, y: bounds.midY)
        preview.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(quarterTurns) * .pi / 2))
        CATransaction.commit()
    }
}

struct Controls: View {
    @ObservedObject var model: Mirror
    @State private var showHelp = false
    @Environment(\.colorScheme) private var systemScheme
    private var dark: Bool { model.theme == .dark || (model.theme == .system && systemScheme == .dark) }
    private var ink: Color { dark ? Color(red: 0.91, green: 0.92, blue: 0.90) : Color(red: 0.16, green: 0.18, blue: 0.17) }
    private var muted: Color { dark ? Color(red: 0.61, green: 0.64, blue: 0.61) : Color(red: 0.45, green: 0.46, blue: 0.43) }
    private var canvas: Color { dark ? Color(red: 0.07, green: 0.08, blue: 0.075) : Color(red: 0.97, green: 0.965, blue: 0.95) }
    private var surface: Color { dark ? Color(red: 0.115, green: 0.13, blue: 0.12) : .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .center, spacing: 12) {
                Image(nsImage: NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent(dark ? "LogoDark.png" : "LogoLight.png")) ?? NSImage())
                    .resizable().scaledToFit().frame(width: 54, height: 54).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("USB Mirror").font(.system(size: 27, weight: .semibold)).tracking(-1.2)
                    Text(model.text("Layar iPhone. Siap untuk live.")).font(.system(size: 13)).foregroundStyle(muted)
                }
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(model.running ? Color(red: 0.25, green: 0.48, blue: 0.33) : muted).frame(width: 6, height: 6)
                    Text(model.running ? model.text("LIVE VIEW") : "USB").font(.system(size: 10, weight: .semibold, design: .monospaced))
                }.padding(9).background((dark ? Color(red: 0.18, green: 0.24, blue: 0.19) : Color(red: 0.91, green: 0.94, blue: 0.89)), in: RoundedRectangle(cornerRadius: 6))
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "iphone").font(.system(size: 26, weight: .medium))
                    Picker(model.text("Perangkat"), selection: $model.selected) {
                        if model.devices.isEmpty { Text(model.text("Sambungkan iPhone")).tag("") }
                        ForEach(model.devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    }.labelsHidden().disabled(model.running || model.busy)
                    Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).help(model.text("Cari ulang perangkat")).disabled(model.busy)
                }
                Text(model.statusText).font(.system(size: 12)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true).frame(minHeight: 30, alignment: .topLeading)
                Button {
                    if model.running { model.stop() } else { model.start() }
                } label: {
                    HStack(spacing: 8) {
                        if model.busy { ProgressView().controlSize(.small).tint(.white) }
                        Image(systemName: model.running ? "stop.fill" : "play.fill").font(.system(size: 11))
                        Text(model.text(model.busy ? "Menghubungkan…" : (model.running ? "Hentikan mirroring" : "Mulai mirroring"))).font(.system(size: 13, weight: .semibold))
                    }.frame(maxWidth: .infinity).padding(.vertical, 13).foregroundStyle(dark ? Color.black : Color.white)
                        .background(ink.opacity(model.busy ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).disabled(model.busy)
            }.padding(20).background(surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke((dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07))))
            VStack(spacing: 18) {
                HStack {
                    Label(model.text("Rotasi otomatis"), systemImage: "rotate.right").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(model.text(model.orientationLabel)).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                    Toggle(model.text("Rotasi otomatis"), isOn: $model.autoFit).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .onChange(of: model.autoFit) {
                            if model.autoFit { model.rotation = 0; model.updateOrientation() }
                        }
                }
                HStack(spacing: 10) {
                    Button(model.text("Buka layar")) { model.showOutput() }
                    Button(model.text("Putar 90°")) { model.rotateManually() }.disabled(!model.running)
                    if model.rotation != 0 {
                        Button(model.text("Reset")) { model.rotation = 0; model.updateOrientation() }
                    }
                    Spacer()
                }.controlSize(.small)
                Divider()
                HStack {
                    Label(model.text("Suara iPhone"), systemImage: "speaker.wave.2").font(.system(size: 13, weight: .medium))
                    Spacer()
                    Text(model.soundEnabled ? "\(Int(model.volume * 100))%" : model.text("Mati")).font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                    Toggle(model.text("Suara iPhone"), isOn: $model.soundEnabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                        .onChange(of: model.soundEnabled) { model.updateVolume() }.disabled(!model.running)
                }
                Slider(value: $model.volume, in: 0...1).controlSize(.small)
                    .onChange(of: model.volume) { model.updateVolume() }.disabled(!model.soundEnabled)
            }
            Divider()
            VStack(spacing: 12) {
                HStack {
                    Label(model.text("Bahasa"), systemImage: "globe").font(.system(size: 12))
                    Spacer()
                    Picker(model.text("Bahasa"), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                HStack {
                    Label(model.text("Tema"), systemImage: "circle.lefthalf.filled").font(.system(size: 12))
                    Spacer()
                    Picker(model.text("Tema"), selection: $model.theme) {
                        ForEach(AppTheme.allCases) { Text(model.text($0.label)).tag($0) }
                    }.labelsHidden().pickerStyle(.segmented).frame(width: 235)
                }
            }
            HStack {
                Link(destination: URL(string: "https://t.me/noutq")!) {
                    Label(model.text("Laporkan bug"), systemImage: "ladybug")
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(muted)
                    .help("Telegram · @noutq")
                Spacer()
                Button(model.text("Panduan OBS")) { showHelp.toggle() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    .popover(isPresented: $showHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(model.text("Siap masuk OBS")).font(.headline)
                            Text(model.text("Tambahkan macOS Screen Capture, lalu pilih jendela USB Mirror — iPhone. Aktifkan audio, atau gunakan macOS Audio Capture khusus USB Mirror."))
                            Text(model.text("Buka game landscape di iPhone. Jendela mengikuti ukuran gambar yang dikirim iPhone. Gunakan Putar 90° jika gambar masih menyamping."))
                            Text(model.text("Suara awalnya mati. Gunakan headphone dan uji rekaman sebelum live."))
                        }.font(.system(size: 12)).lineSpacing(4).padding(22).frame(width: 320)
                    }
            }
        }.padding(28).frame(width: 440).foregroundStyle(ink)
            .tint(Color(red: 0.31, green: 0.43, blue: 0.34))
            .background(canvas)
            .preferredColorScheme(model.theme == .system ? nil : (model.theme == .dark ? .dark : .light))
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: Mirror!
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = Mirror()
        if let icon = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("AppIcon.icns")) {
            NSApp.applicationIconImage = icon
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 680), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = model.text("USB Mirror — Kontrol")
        window.contentView = NSHostingView(rootView: Controls(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: model.text("Keluar USB Mirror"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        window.makeKeyAndOrderFront(nil)
        return true
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.regular)
let delegate = AppDelegate()
application.delegate = delegate
application.run()
