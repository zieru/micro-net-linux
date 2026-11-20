# Mini-Linux 128 MB RAM (Zero-Initramfs + `x-ui-agent-rs` + TinySSH + `nftables`)

[![Build Mini-Linux 128MB](https://github.com/zieru/micro-net-linux/actions/workflows/build-mini-linux.yml/badge.svg)](https://github.com/zieru/micro-net-linux/actions/workflows/build-mini-linux.yml)

Distribusi Linux `x86_64` ultra-minimalis berbasis **Linux Kernel 6.6 LTS (`tinyconfig`)**, **BusyBox statis (`musl`)**, **TinySSH (`musl`, public-key only)**, dan **`x-ui-agent-rs` (Rust static `musl` dengan embedded `shoes` proxy)** tanpa `initramfs`, dirancang untuk VPS/VM **128 MB RAM** dengan output khusus **ISO-only (`mini-linux-v0.1.x.iso`)**.

---

## Fitur Utama

- **Zero-Initramfs + `ext4` Full-Disk Installer (`install-to-disk`)**:
  - **Live ISO (`ISO9660`)**: Boot langsung tanpa `initramfs` dengan overlay RAM tipis untuk `/etc` & `/root`.
  - **Disk Install (`ext4`)**: `install-to-disk /dev/vda` (atau `/dev/sda`) mempartisi ulang seluruh disk menjadi `ext4` + `EXTLINUX` (`e2fsck`/`resize2fs`), membuat `/swapfile` fleksibel (0–512 MB+), dialog jaringan dual-stack, password root **SHA-512**, dan setup SSH key via **Web Drop**.
- **`x-ui-agent-rs` (Embedded `shoes` Proxy + Hardened Remote Shell)**:
  - Menggantikan Go `xray-core` dengan single-binary Rust (`12 MB` statis `musl`, single-threaded Tokio runtime).
  - Auto-generate sertifikat **TLS 1.3 (ECDSA P-256)** pada boot pertama (`:2053` selalu HTTPS), mendukung *cert pinning*, *hot-reload* TLS/token, otentikasi shell **Ed25519 + anti-replay**, dan *rate-limiting* Bearer token.
- **TinySSH (`musl`, Public-Key Only) + Web Drop (`add-ssh-key`)**:
  - Login SSH hanya menerima kunci modern (**Ed25519** / `ecdsa-sha2-nistp256`), tanpa password login.
  - Dilengkapi **`add-ssh-key` (Web Drop)** berbasis BusyBox `httpd` + PIN acak 6 digit agar Anda bisa mengirim SSH public key dari browser PC/HP tanpa perlu *copy-paste* di konsol VNC.
- **Firewall Kernel `nftables` (`S15firewall`)**:
  - Berjalan murni di kernel (`0 MB` RAM daemon tambahan), otomatis mendeteksi port kustom dari `/etc/tinyssh/tinyssh.conf` dan `/etc/x-ui-agent/agent.conf`.
  - Mendukung mode **`TRUSTED_IPS`** (*allowlist*) atau **auto-ban dinamis** (`5` koneksi baru/menit -> ban `10` menit untuk IPv4 & IPv6).
- **Dual-Stack IPv4/IPv6 & `netui` TUI**:
  - Jalankan **`netui`** untuk mengatur IPv4 (`dhcp` / `static` / `off`) dan IPv6 (`slaac` / `static` / `off`) secara independen.
- **OOM Resilience & Auto-Recovery**:
  - **Kernel `zram` 32 MB (`LZ4`)** aktif otomatis di Live ISO maupun disk install.
  - **`oom_score_adj = -900`** melindungi TinySSH agar akses SSH darurat tetap hidup saat RAM kritis.
  - **Auto-respawn supervisor** di `/etc/init.d/S50x-ui-agent` menghidupkan ulang `x-ui-agent-rs` dalam 2 detik bila terhenti/terbunuh OOM.
- **Utilitas Bawaan**: `htop` (statis `musl`), WireGuard kernel-native (`wg`), `ntpd`, `check-readiness`, `save-config`.

---

## Cara Build Image (ISO-Only `0.1.x`)

Versi rilis diatur di file [`VERSION`](VERSION) (saat ini `0.1.4`). Output build hanya menghasilkan **`out/mini-linux-v<VERSION>.iso`**.

### Opsi 1: Otomatis via GitHub Actions
1. Jalankan workflow [build-mini-linux.yml](.github/workflows/build-mini-linux.yml) melalui tab **Actions** (atau push tag `v0.1.x`).
2. Centang `create_release` pada `workflow_dispatch` jika ingin otomatis membuat GitHub Release dengan aset tunggal `mini-linux-v<VERSION>.iso`.

### Opsi 2: Build Lokal di Linux / WSL2 (Ubuntu 24.04)
```bash
sudo apt-get update && sudo apt-get install -y \
  build-essential bc bison flex libelf-dev libssl-dev pkg-config \
  musl-tools linux-libc-dev syslinux extlinux isolinux \
  syslinux-common xorriso e2fsprogs fdisk \
  ca-certificates curl xz-utils bzip2

chmod +x scripts/*.sh
bash scripts/build-all.sh
```

---

## Deploy ke Cloud VPS & VirtualBox

1. Unduh `mini-linux-v0.1.x.iso` dari [GitHub Releases](https://github.com/zieru/micro-net-linux/releases) lalu mount sebagai **Custom ISO** (RAM `128 MB`), kemudian boot.
2. Di konsol VNC, jalankan installer permanen ke disk:
   ```sh
   install-to-disk /dev/vda   # atau /dev/sda di VirtualBox
   ```
   Ikuti dialog interaktif untuk:
   - Ukuran `/swapfile` (default `256 MB`),
   - Konfigurasi jaringan (`DHCP` / `Static` IPv4 & IPv6),
   - Password root baru (hash **SHA-512**),
   - Penambahan SSH public key via **Web Drop** (`1) Web Drop`) — buka URL + masukkan PIN 6 digit dari browser PC/HP Anda.
3. Lepas/eject Custom ISO dari panel VPS lalu `reboot`.

---

## Manajemen Layanan & Konfigurasi

| Layanan / Fitur | File Konfigurasi | Terapkan Perubahan |
| :--- | :--- | :--- |
| **Network (IPv4/IPv6)** | `/etc/network.conf` (atau jalankan `netui`) | `/etc/init.d/S20network restart` |
| **Firewall & Auto-Ban** | `/etc/firewall.conf` | `/etc/init.d/S15firewall restart` |
| **TinySSH (Port Kustom)** | `/etc/tinyssh/tinyssh.conf` | `/etc/init.d/S55tinyssh restart && /etc/init.d/S15firewall restart` |
| **`x-ui-agent-rs` (`:2053`)** | `/etc/x-ui-agent/agent.conf` | `/etc/init.d/S50x-ui-agent restart` |
| **Tambah SSH Key Kapan Saja** | `/root/.ssh/authorized_keys` | Jalankan `add-ssh-key` |
| **WireGuard** | `/etc/wireguard/wg0.conf` | `/etc/init.d/S40wireguard restart` |

Koneksi SSH ke VPS (hanya mendukung kunci **Ed25519**, tanpa password):
```bash
ssh -i ~/.ssh/id_ed25519 root@<IP_VPS>
```

Pemeriksaan cepat di dalam VM:
```sh
check-readiness
free -m
cat /proc/swaps
nft list table inet minilinux_fw
```
