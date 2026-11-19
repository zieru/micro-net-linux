# Mini-Linux 128 MB RAM (Zero-Initramfs + WireGuard + VLESS REALITY Ready)

Distribusi Linux x86_64 ultra-minimalis berbasis **Linux Kernel 6.6 LTS (`tinyconfig`)**, **BusyBox statis (`musl`)**, dan **Dropbear SSH statis (`musl`)** tanpa `initramfs`, dirancang agar menyisakan **>115 MB RAM bebas** pada VPS/VM berkapasitas **128 MB RAM**.

## Rincian Pemakaian RAM (Target 128 MB)

| Komponen | Estimasi RAM | Keterangan |
| :--- | :--- | :--- |
| **Linux Kernel 6.6 (`tinyconfig`)** | ~4.2 – 6.0 MB | `SLUB_TINY`, `NR_CPUS=4`, tanpa `initramfs`, tanpa loadable modules. |
| **Userland (BusyBox + Dropbear SSH)** | ~1.5 – 2.0 MB | Static `musl-libc`, `Ed25519` + `ChaCha20-Poly1305`, batas `tmpfs` ketat. |
| **WireGuard `wg` + CA Bundle + `ntpd`** | ~0.0 – 0.4 MB | Kernel-native `wireguard` + `wg` statis (~80 KB di disk). |
| **Sisa RAM Bebas (OS Idle)** | **~118 – 122 MB** | Siap untuk `xray-core` (VLESS REALITY) + TCP socket buffer BBR. |

## Fitur Utama

- **Dual-Mode Zero Initramfs (`.img`, `.vdi`, dan Custom `.iso`)**:
  - **`mini-linux.iso`**: Boot langsung me-mount `ISO9660 + Rock Ridge` (`root=/dev/sr0`) **tanpa initramfs**, memakai overlay RAM tipis untuk `/etc` & `/root`.
  - **`install-to-disk /dev/vda`** (atau `/dev/sda`): Menginstal OS ke hard disk VPS/VM sebagai partisi `ext2` murni + `EXTLINUX`, sehingga Custom ISO dapat dilepas permanen.
- **Kompatibel VirtualBox & Cloud VPS (KVM/QEMU)**: Driver *built-in* untuk `VirtIO-Blk/SCSI`, `VirtIO-Net`, `ATA PIIX`, `SATA AHCI`, dan `Intel E1000`.
- **Dukungan WireGuard Native**: `CONFIG_WIREGUARD=y` + biner statis `/usr/bin/wg` + skrip service POSIX `/etc/init.d/S40wireguard` (tanpa perlu `bash`).
- **Prasyarat Lengkap VLESS REALITY & Go Runtime**:
  - Syscall Go & GC: `CONFIG_ADVISE_SYSCALLS=y`, `FUTEX`, `EPOLL`, `EVENTFD`, `TIMERFD`, `SIGNALFD`, `INOTIFY_USER`.
  - Jaringan & Firewall: `TCP BBR` + `FQ` (default), `TUN/TAP`, `nftables` + `iptables` (`TPROXY`, `SOCKET`, `MASQUERADE`, `IP_MULTIPLE_TABLES`).
  - Jam & TLS: `RTC_DRV_CMOS` + `ntpd` (sync waktu akurat untuk validasi timestamp REALITY), `HW_RANDOM_VIRTIO`, akselerasi CPU `AES-NI`/`ChaCha20`/`Curve25519`, dan `/etc/ssl/certs/ca-certificates.crt`.

---

## Cara Build Image

### Opsi 1: Otomatis via GitHub Actions (Tanpa WSL/Docker di Windows)
1. Push repositori ini ke GitHub.
2. Workflow [build-mini-linux.yml](.github/workflows/build-mini-linux.yml) otomatis berjalan dan menghasilkan artifact `mini-linux-128mb-x86_64` berisi:
   - `mini-linux.iso` (untuk test di VirtualBox & upload Custom ISO ke VPS)
   - `mini-linux.img` (raw disk image 64 MB)
   - `mini-linux.vdi` (disk image siap pakai VirtualBox)
   - `bzImage` & `SHA256SUMS.txt`

### Opsi 2: Build Lokal di Linux / WSL2 (Ubuntu 24.04)
```bash
sudo apt-get update && sudo apt-get install -y \
  build-essential bc bison flex libelf-dev libssl-dev \
  musl-tools linux-libc-dev syslinux extlinux isolinux \
  syslinux-common xorriso e2fsprogs fdisk qemu-utils \
  ca-certificates curl xz-utils bzip2

chmod +x scripts/*.sh
bash scripts/build-all.sh
```

---

## Pengujian di VirtualBox (128 MB RAM)

Letakkan `mini-linux.iso` hasil build ke folder `out\mini-linux.iso`, lalu jalankan di PowerShell Windows:

```powershell
.\scripts\test-vbox.ps1 -IsoPath .\out\mini-linux.iso -Recreate
```

Login melalui SSH dari Windows:
```powershell
ssh -p 2222 root@127.0.0.1
# Password awal: minilinux
```

Di dalam VM, jalankan pemeriksaan kesiapan:
```sh
check-readiness
free -m
```

Untuk menginstal ke disk virtual VirtualBox agar boot tanpa ISO:
```sh
install-to-disk /dev/sda
# Setelah selesai, lepas ISO di VirtualBox lalu reboot
```

---

## Deploy ke Cloud VPS (Custom ISO)

1. Upload `out/mini-linux.iso` sebagai **Custom ISO** di panel VPS, set RAM `128 MB`, lalu boot.
2. Buka VNC/Console atau SSH (jika DHCP VPS langsung aktif), lalu instal permanen ke disk VPS:
   ```sh
   install-to-disk /dev/vda
   ```
3. Unmount/eject ISO dari panel VPS dan reboot.
4. Untuk konfigurasi IP statis, salin `/etc/network.conf.example` ke `/etc/network.conf` lalu jalankan `/etc/init.d/S20network restart`.
5. Untuk mengaktifkan WireGuard, buat `/etc/wireguard/wg0.conf` (lihat `/etc/wireguard/wg0.conf.example`) lalu jalankan `/etc/init.d/S40wireguard restart`.

## Catatan Tahap Berikutnya (`xray-core` + `x-ui-agent`)
Saat nanti menambahkan biner Go (`xray-core`) ke OS 128 MB ini:
- Kompilasi statis dengan `CGO_ENABLED=0 GOARCH=amd64`.
- Jalankan dengan batas memori Go runtime agar aman dari OOM saat lonjakan trafik:
  ```sh
  GOMEMLIMIT=40MiB GOGC=40 /usr/local/bin/xray run -c /etc/xray/config.json
  ```
