# USB Mirror untuk iPhone 16 + OBS

Aplikasi lokal untuk Mac Apple Silicon, macOS 14 atau lebih baru. Buka **USB Mirror.app**. Source dan build.command disertakan agar aplikasi bisa diperiksa dan dibangun ulang dengan Xcode.

## Menghubungkan
1. Gunakan kabel USB-C yang mendukung data; sambungkan iPhone langsung ke Mac.
2. Buka kunci iPhone dan pilih **Trust / Percayai** bila diminta.
3. Di USB Mirror, klik **Cari ulang**, pilih iPhone lalu **Mulai mirroring**.
4. Izinkan akses Kamera dan Mikrofon jika macOS meminta. Izin ini digunakan untuk perangkat tangkapan USB; aplikasi memilih sumber iPhone, bukan mikrofon Mac.
5. Tunggu status **Gambar iPhone masuk**. Suara awalnya mati; aktifkan sakelar **Suara iPhone** setelah gambar tampil. Volume awal 25%.
6. Jendela **USB Mirror — iPhone** menampilkan layar tanpa kontrol aplikasi. Ukuran jendela dapat diubah; rasio gambar dipertahankan dengan area hitam jika diperlukan.
7. Suara diputar ke output audio default Mac. Gunakan headphone. Volume aplikasi 0 membisukan output, termasuk yang ditangkap OBS.

## OBS
1. Tambahkan sumber **macOS Screen Capture**.
2. Pilih metode Window Capture, lalu jendela **USB Mirror — iPhone**. Jangan pilih jendela Kontrol.
3. Aktifkan capture audio jika tersedia dan periksa indikator mixer OBS sambil memutar suara di iPhone.
4. Jika audio belum masuk, tambahkan **macOS Audio Capture**, pilih capture aplikasi, lalu **USB Mirror**. Matikan audio pada sumber layar jika menggunakan sumber audio terpisah agar suara tidak dobel.
5. Pastikan OBS memiliki izin Screen & System Audio Recording di Pengaturan Sistem → Privasi & Keamanan.
6. Rekam percobaan 20–30 detik dengan gerakan dan suara. Periksa gambar, suara, dan sinkronisasi sebelum live.

Petunjuk OBS: https://obsproject.com/kb/macos-desktop-audio-capture-guide

## Jika belum terdeteksi
- Pastikan kabel mendukung data, iPhone terbuka, dan sudah mempercayai Mac.
- Tutup sesi QuickTime atau aplikasi lain yang sedang memakai iPhone.
- Cabut dan sambungkan kembali, lalu klik Cari ulang. Klik Mulai setelah tersambung kembali.
- Bila izin ditolak, aktifkan Kamera dan Mikrofon untuk USB Mirror di Pengaturan Sistem, lalu tutup dan buka ulang aplikasi.
- Jika gambar muncul tanpa suara, sambungkan ulang perangkat dan mulai lagi. Audio harus diuji langsung pada perangkat.

## Batasan
Ini versi awal dengan jalur tangkapan USB AVFoundation/CoreMediaIO dan pemutaran suara native macOS. Tidak merekam atau mengunggah apa pun. Tidak memasang driver, tidak menyediakan virtual camera, dan tidak mengontrol sentuhan iPhone dari Mac.

Tidak ada jaminan delay nol, frame rate tertentu, atau sinkronisasi sempurna. Delay dipengaruhi iPhone, kabel, tangkapan macOS, dan pengaturan OBS. Aplikasi ini tidak mengukur delay. Konten yang dilindungi dapat tidak tampil atau tidak bersuara.

Build dan pembukaan aplikasi dapat diperiksa tanpa iPhone, tetapi mirroring, audio, orientasi, reconnect, dan hasil capture OBS memerlukan pengujian dengan iPhone tersambung. Aplikasi ditandatangani lokal, bukan distribusi Developer ID/notarized.

## Perbaikan deteksi USB
Versi ini memantau perangkat setiap detik karena sumber layar iPhone dapat baru muncul setelah pencarian awal. Status berhasil menunggu frame gambar pertama. Jika dalam 12 detik tidak ada gambar, sesi dihentikan. Audio mulai dalam keadaan mati.

Jika kresek juga muncul ketika aplikasi ditutup, jangan anggap itu masalah yang sudah diselesaikan oleh sakelar mute. Cabut kabel untuk menghentikan gangguan, lalu periksa kabel data dan koneksi langsung tanpa hub. Penyebab dan audio akhir masih perlu diuji.
