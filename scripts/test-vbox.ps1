[CmdletBinding()]
param(
    [string]$VmName = "MiniLinux-128MB",
    [string]$IsoPath = "",
    [string]$VdiPath = "",
    [int]$MemoryMB = 128,
    [int]$SshPort = 2222,
    [switch]$Recreate,
    [switch]$Headless
)

$ErrorActionPreference = "Stop"

function Find-VBoxManage {
    $cmd = Get-Command "VBoxManage.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $candidates = @(
        "C:\Program Files\Oracle\VirtualBox\VBoxManage.exe",
        "D:\Program Files\Oracle\VirtualBox\VBoxManage.exe"
    )
    if ($env:VBOX_MSI_INSTALL_PATH) {
        $candidates += (Join-Path $env:VBOX_MSI_INSTALL_PATH "VBoxManage.exe")
    }
    foreach ($path in $candidates) {
        if (Test-Path $path) { return $path }
    }
    throw "VBoxManage.exe tidak ditemukan. Pastikan Oracle VirtualBox sudah terinstal atau tambahkan ke PATH."
}

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $IsoPath -and -not $VdiPath) {
    $defaultIso = Join-Path $RepoRoot "out\mini-linux.iso"
    $defaultVdi = Join-Path $RepoRoot "out\mini-linux.vdi"
    if (Test-Path $defaultIso) { $IsoPath = $defaultIso }
    elseif (Test-Path $defaultVdi) { $VdiPath = $defaultVdi }
}

if ($IsoPath -and -not (Test-Path $IsoPath)) { throw "File ISO tidak ditemukan: $IsoPath" }
if ($VdiPath -and -not (Test-Path $VdiPath)) { throw "File VDI tidak ditemukan: $VdiPath" }
if (-not $IsoPath -and -not $VdiPath) {
    throw "Berikan parameter -IsoPath atau -VdiPath (atau letakkan image di .\out\mini-linux.iso / .vdi)."
}

$VBoxManage = Find-VBoxManage
Write-Host "[vbox] Menggunakan: $VBoxManage"

$existingVms = & $VBoxManage list vms
$vmExists = $existingVms -match "`"$([regex]::Escape($VmName))`""

if ($vmExists -and $Recreate) {
    Write-Host "[vbox] Menghapus VM lama '$VmName'..."
    & $VBoxManage controlvm $VmName poweroff 2>$null | Out-Null
    Start-Sleep -Seconds 1
    & $VBoxManage unregistervm $VmName --delete
    $vmExists = $false
}

if (-not $vmExists) {
    Write-Host "[vbox] Membuat VM '$VmName' (RAM: ${MemoryMB}MB, 1 vCPU, E1000 NAT, SSH :$SshPort)..."
    & $VBoxManage createvm --name $VmName --ostype "Linux_64" --register | Out-Null
    & $VBoxManage modifyvm $VmName `
        --memory $MemoryMB `
        --cpus 1 `
        --vram 16 `
        --acpi on `
        --ioapic on `
        --rtcuseutc on `
        --nic1 nat `
        --nictype1 82540EM `
        --natpf1 "ssh,tcp,127.0.0.1,$SshPort,,22" `
        --uart1 0x3F8 4 | Out-Null

    & $VBoxManage storagectl $VmName --name "SATA" --add sata --controller IntelAhci --portcount 2 --bootable on | Out-Null

    $targetVdi = ""
    if ($VdiPath) {
        $targetVdi = (Resolve-Path $VdiPath).Path
    } else {
        $vmFolder = Join-Path $env:USERPROFILE "VirtualBox VMs\$VmName"
        New-Item -ItemType Directory -Force -Path $vmFolder | Out-Null
        $targetVdi = Join-Path $vmFolder "disk-256mb.vdi"
        if (-not (Test-Path $targetVdi)) {
            Write-Host "[vbox] Membuat disk kosong 256 MB ($targetVdi) untuk uji install-to-disk..."
            & $VBoxManage createmedium disk --filename $targetVdi --size 256 --format VDI | Out-Null
        }
    }

    & $VBoxManage storageattach $VmName --storagectl "SATA" --port 0 --device 0 --type hdd --medium $targetVdi | Out-Null

    if ($IsoPath) {
        $isoFull = (Resolve-Path $IsoPath).Path
        & $VBoxManage storageattach $VmName --storagectl "SATA" --port 1 --device 0 --type dvddrive --medium $isoFull | Out-Null
        & $VBoxManage modifyvm $VmName --boot1 dvd --boot2 disk --boot3 none --boot4 none | Out-Null
    } else {
        & $VBoxManage modifyvm $VmName --boot1 disk --boot2 none --boot3 none --boot4 none | Out-Null
    }
} else {
    Write-Host "[vbox] VM '$VmName' sudah ada (gunakan -Recreate untuk membuat ulang)."
}

$startType = if ($Headless) { "headless" } else { "gui" }
Write-Host "[vbox] Menjalankan VM '$VmName' ($startType)..."
& $VBoxManage startvm $VmName --type $startType

Write-Host ""
Write-Host "VM berjalan! Tunggu ~3 detik lalu login SSH:"
Write-Host "  ssh -p $SshPort root@127.0.0.1"
Write-Host "  Password awal: minilinux"
Write-Host ""
Write-Host "Perintah verifikasi di dalam VM:"
Write-Host "  check-readiness"
Write-Host "  free -m"
Write-Host "  install-to-disk /dev/sda   (untuk instalasi ke disk VDI tanpa ISO)"
