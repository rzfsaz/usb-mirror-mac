import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case indonesian = "id", english = "en", japanese = "ja", chinese = "zh-Hans"
    var id: String { rawValue }
    var name: String {
        switch self { case .indonesian: return "Bahasa Indonesia"; case .english: return "English"; case .japanese: return "日本語"; case .chinese: return "简体中文" }
    }
    var index: Int { Self.allCases.firstIndex(of: self)! }
    static var initial: Self {
        if let saved = UserDefaults.standard.string(forKey: "appLanguage"), let language = Self(rawValue: saved) { return language }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("id") { return .indonesian }
        if preferred.hasPrefix("ja") { return .japanese }
        if preferred.hasPrefix("zh") { return .chinese }
        return .english
    }
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { switch self { case .system: return "Ikuti sistem"; case .light: return "Terang"; case .dark: return "Gelap" } }
}

enum L10n {
    // Indonesian source keys; translations are English, Japanese, Simplified Chinese.
    static let strings: [String: [String]] = [
        "Bahasa": ["Language", "言語", "语言"],
        "Tema": ["Theme", "テーマ", "主题"],
        "Ikuti sistem": ["System", "システム", "跟随系统"],
        "Terang": ["Light", "ライト", "浅色"],
        "Gelap": ["Dark", "ダーク", "深色"],
        "Layar iPhone. Siap untuk live.": ["Your iPhone. Ready to stream.", "iPhoneの画面を、配信へ。", "iPhone 画面，随时开播。"],
        "LIVE VIEW": ["LIVE VIEW", "プレビュー中", "实时预览"],
        "Perangkat": ["Device", "デバイス", "设备"],
        "Sambungkan iPhone": ["Connect your iPhone", "iPhoneを接続", "连接 iPhone"],
        "Cari ulang perangkat": ["Refresh devices", "デバイスを再検索", "刷新设备"],
        "Menghubungkan…": ["Connecting…", "接続中…", "正在连接…"],
        "Hentikan mirroring": ["Stop mirroring", "ミラーリングを停止", "停止镜像"],
        "Mulai mirroring": ["Start mirroring", "ミラーリングを開始", "开始镜像"],
        "Rotasi otomatis": ["Auto rotation", "自動回転", "自动旋转"],
        "Menunggu gambar": ["Waiting for video", "映像を待機中", "等待画面"],
        "Landscape": ["Landscape", "横向き", "横屏"],
        "Portrait": ["Portrait", "縦向き", "竖屏"],
        "Buka layar": ["Show screen", "画面を表示", "显示画面"],
        "Putar 90°": ["Rotate 90°", "90°回転", "旋转 90°"],
        "Reset": ["Reset", "リセット", "重置"],
        "Suara iPhone": ["iPhone audio", "iPhoneの音声", "iPhone 音频"],
        "Mati": ["Off", "オフ", "关闭"],
        "Panduan OBS": ["OBS guide", "OBSガイド", "OBS 指南"],
        "Siap masuk OBS": ["Set up OBS", "OBSの設定", "设置 OBS"],
        "USB Mirror — Kontrol": ["USB Mirror — Controls", "USB Mirror — コントロール", "USB Mirror — 控制"],
        "Keluar USB Mirror": ["Quit USB Mirror", "USB Mirrorを終了", "退出 USB Mirror"],
        "Sambungkan iPhone menggunakan kabel USB.": ["Connect your iPhone with a USB cable.", "USBケーブルでiPhoneを接続してください。", "请使用 USB 数据线连接 iPhone。"],
        "iPhone terputus. Sambungkan kembali, lalu klik Mulai.": ["iPhone disconnected. Reconnect and start mirroring again.", "iPhoneが切断されました。再接続してミラーリングを開始してください。", "iPhone 已断开。请重新连接并开始镜像。"],
        "Sesi terhenti. Coba sambungkan ulang iPhone.": ["The session stopped. Try reconnecting your iPhone.", "セッションが停止しました。iPhoneを再接続してください。", "会话已停止。请尝试重新连接 iPhone。"],
        "Mirroring terganggu. Buka kunci iPhone lalu klik Mulai kembali.": ["Mirroring was interrupted. Unlock your iPhone and start again.", "ミラーリングが中断されました。iPhoneのロックを解除して再開してください。", "镜像已中断。请解锁 iPhone 后重新开始。"],
        "Menunggu layar iPhone lewat USB. Buka kunci dan pilih Percayai; pencarian otomatis aktif.": ["Waiting for your iPhone. Unlock it and tap Trust; discovery is automatic.", "iPhoneを待機中です。ロックを解除し「信頼」をタップしてください。自動検索中です。", "正在等待 iPhone。请解锁并点击“信任”；设备会自动被发现。"],
        "iPhone USB ditemukan. Klik Mulai mirroring. Suara awalnya mati.": ["iPhone connected. Start mirroring when ready. Audio starts muted.", "iPhoneが見つかりました。ミラーリングを開始できます。音声は最初はオフです。", "已发现 iPhone。点击开始镜像。音频默认关闭。"],
        "Memeriksa izin kamera dan audio…": ["Checking camera and audio permissions…", "カメラと音声の権限を確認中…", "正在检查摄像头和音频权限…"],
        "Izinkan Kamera dan Mikrofon untuk USB Mirror di Pengaturan Sistem → Privasi & Keamanan, lalu buka ulang aplikasi.": ["Allow Camera and Microphone for USB Mirror in System Settings → Privacy & Security, then reopen the app.", "システム設定 → プライバシーとセキュリティでUSB Mirrorのカメラとマイクを許可し、アプリを再起動してください。", "请在系统设置 → 隐私与安全性中允许 USB Mirror 访问摄像头和麦克风，然后重新打开应用。"],
        "iPhone belum ditemukan. Buka kunci iPhone, pilih Trust/Percayai, lalu klik Cari ulang.": ["iPhone not found. Unlock it, tap Trust, and refresh devices.", "iPhoneが見つかりません。ロックを解除して「信頼」をタップし、再検索してください。", "未找到 iPhone。请解锁、点击“信任”，然后刷新设备。"],
        "iPhone sedang digunakan aplikasi lain. Tutup sesi QuickTime atau aplikasi mirroring lain.": ["iPhone is in use. Close QuickTime capture or other mirroring apps.", "iPhoneは使用中です。QuickTimeの収録や他のミラーリングアプリを終了してください。", "iPhone 正被其他应用使用。请关闭 QuickTime 采集或其他镜像应用。"],
        "Tidak bisa membaca gambar iPhone. Tutup aplikasi lain yang menggunakan iPhone.": ["Cannot read iPhone video. Close other apps using the iPhone.", "iPhoneの映像を読み取れません。iPhoneを使用している他のアプリを終了してください。", "无法读取 iPhone 画面。请关闭正在使用 iPhone 的其他应用。"],
        "Gagal memulai. Buka kunci iPhone dan periksa kabel USB.": ["Could not start. Unlock your iPhone and check the USB cable.", "開始できません。iPhoneのロックを解除し、USBケーブルを確認してください。", "无法启动。请解锁 iPhone 并检查 USB 数据线。"],
        "Menunggu gambar pertama dari iPhone…": ["Waiting for the first iPhone frame…", "iPhoneの最初の映像を待機中…", "正在等待 iPhone 的首帧画面…"],
        "Tidak ada gambar dari iPhone. Buka kunci, pilih Percayai, lalu coba lagi.": ["No video received. Unlock your iPhone, tap Trust, and try again.", "映像を受信できません。iPhoneのロックを解除して「信頼」をタップし、再試行してください。", "未收到画面。请解锁 iPhone、点击“信任”，然后重试。"],
        "Mirroring dihentikan.": ["Mirroring stopped.", "ミラーリングを停止しました。", "镜像已停止。"],
        "Gambar masuk. Audio siap diaktifkan.": ["Video connected. Audio is ready to enable.", "映像を受信中。音声を有効にできます。", "已接收画面，可开启音频。"],
        "Gambar masuk. Audio belum tersedia.": ["Video connected. Audio is not available yet.", "映像を受信中。音声はまだ利用できません。", "已接收画面，音频暂不可用。"],
        "Menghubungkan ke %@…": ["Connecting to %@…", "%@に接続中…", "正在连接 %@…"],
        "Akses perangkat USB gagal (%@). Coba buka ulang aplikasi.": ["USB access failed (%@). Try reopening the app.", "USBアクセスに失敗しました（%@）。アプリを再起動してください。", "USB 访问失败（%@）。请尝试重新打开应用。"],
        "Tambahkan macOS Screen Capture, lalu pilih jendela USB Mirror — iPhone. Aktifkan audio, atau gunakan macOS Audio Capture khusus USB Mirror.": ["Add macOS Screen Capture and select USB Mirror — iPhone. Enable audio, or use a separate macOS Audio Capture source for USB Mirror.", "macOS Screen Captureを追加し、USB Mirror — iPhoneを選択します。音声を有効にするか、USB Mirror用のmacOS Audio Captureを追加してください。", "添加 macOS Screen Capture，并选择 USB Mirror — iPhone 窗口。开启音频，或使用单独的 macOS Audio Capture 来源采集 USB Mirror 音频。"],
        "Buka game landscape di iPhone. Jendela mengikuti ukuran gambar yang dikirim iPhone. Gunakan Putar 90° jika gambar masih menyamping.": ["Open a landscape game on your iPhone. The window follows the video dimensions. Use Rotate 90° if the picture is still sideways.", "iPhoneで横向きのゲームを開くと、映像のサイズに合わせてウインドウが変わります。映像が横倒しの場合は90°回転を使ってください。", "在 iPhone 上打开横屏游戏，窗口会跟随画面尺寸调整。如果画面仍然侧转，请使用旋转 90°。"],
        "Suara awalnya mati. Gunakan headphone dan uji rekaman sebelum live.": ["Audio starts muted. Use headphones and test a recording before going live.", "音声は最初はオフです。ヘッドホンを使い、配信前に録画をテストしてください。", "音频默认关闭。建议使用耳机，并在直播前测试录制。"]
    ]
    static func text(_ key: String, language: AppLanguage) -> String {
        guard language != .indonesian, let translations = strings[key] else { return key }
        return translations[language.index - 1]
    }
}
