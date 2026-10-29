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
        if result != noErr { status = "Akses perangkat USB gagal (\(result)). Coba buka ulang aplikasi." }
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
            status = "Menghubungkan ke \(device.localizedName)…"
            queue.async {
                do {
                    self.sessionToken = UUID()
                    self.receivedFrame = false
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
        guard !receivedFrame, CMSampleBufferGetImageBuffer(sampleBuffer) != nil else { return }
        receivedFrame = true
        let message = audioReady ? "Gambar iPhone masuk • aktifkan Suara iPhone bila siap." : "Gambar iPhone masuk • perangkat belum menyediakan audio."
        DispatchQueue.main.async { self.status = message }
    }

    func showOutput() {
        if outputWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 430, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "USB Mirror — iPhone"
            window.backgroundColor = .black
            window.isReleasedWhenClosed = false
            window.contentView = PreviewView(session: session)
            window.minSize = NSSize(width: 240, height: 240)
            window.center()
            outputWindow = window
        }
        outputWindow?.makeKeyAndOrderFront(nil)
    }
}

final class PreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
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
        preview.frame = bounds
        CATransaction.commit()
    }
}

struct Controls: View {
    @ObservedObject var model: Mirror
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 14) {
                Image(systemName: "iphone.and.arrow.forward").font(.system(size: 34)).foregroundStyle(.mint)
                VStack(alignment: .leading, spacing: 4) {
                    Text("USB Mirror").font(.system(size: 28, weight: .semibold))
                    Text("iPhone → Mac → OBS").foregroundStyle(.secondary)
                }
                Spacer()
                Text("USB").font(.caption.bold()).padding(8).background(.mint.opacity(0.12), in: Capsule())
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("PERANGKAT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                HStack {
                    Picker("iPhone", selection: $model.selected) {
                        if model.devices.isEmpty { Text("Belum ada iPhone").tag("") }
                        ForEach(model.devices, id: \.uniqueID) { device in Text(device.localizedName).tag(device.uniqueID) }
                    }.labelsHidden().disabled(model.running || model.busy)
                    Button("Cari ulang") { model.refresh() }.disabled(model.busy)
                }
                Text(model.status).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button(model.running ? "Hentikan" : "Mulai mirroring") {
                    if model.running { model.stop() } else { model.start() }
                }.buttonStyle(.borderedProminent).tint(.teal).disabled(model.busy)
                Button("Tampilkan layar") { model.showOutput() }
                if model.busy { ProgressView().controlSize(.small) }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Toggle("Suara iPhone", isOn: $model.soundEnabled)
                        .onChange(of: model.soundEnabled) { model.updateVolume() }
                        .disabled(!model.running)
                    Spacer()
                    Text("\(Int(model.volume * 100))%").monospacedDigit().foregroundStyle(.secondary)
                }
                Slider(value: $model.volume, in: 0...1).onChange(of: model.volume) { model.updateVolume() }
                Text("Suara awalnya mati. Aktifkan setelah gambar muncul, lalu naikkan volume perlahan. Matikan sakelar bila terdengar kresek.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                Label("Siapkan untuk live", systemImage: "dot.radiowaves.left.and.right").font(.headline)
                Text("1. Sambungkan USB, buka kunci iPhone, lalu pilih Percayai.\n2. Klik Mulai mirroring.\n3. Di OBS, tambahkan macOS Screen Capture dan pilih jendela USB Mirror — iPhone.\n4. Aktifkan capture audio; bila perlu gunakan macOS Audio Capture untuk aplikasi USB Mirror.")
                    .font(.callout).lineSpacing(5).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Gunakan headphone agar suara tidak masuk ulang melalui mikrofon. Uji rekaman pendek sebelum live.").font(.caption).foregroundStyle(.secondary)
            }
            Text("Koneksi langsung USB • latensi bergantung perangkat dan OBS").font(.caption2).foregroundStyle(.tertiary)
        }.padding(28).frame(width: 480)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: Mirror!
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = Mirror()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 740), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "USB Mirror — Kontrol"
        window.contentView = NSHostingView(rootView: Controls(model: model))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Keluar USB Mirror", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
