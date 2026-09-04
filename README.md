# Otomasi Instalasi TrendAI Vision One Endpoint Security Agent

## Kenapa tidak pakai role dari Ansible Galaxy?
Trend Micro **tidak mempublikasikan role/collection resmi di Galaxy** untuk instalasi
agent Vision One (berbeda dengan produk Deep Security lama yang sempat punya role
`deep-security.deep-security-agent`, dan sekarang repo itu sudah di-*retire*).

Pendekatan resmi Trend Micro sekarang: generate **Deployment Script** dari console,
lalu jalankan script itu di endpoint. Playbook ini mengotomasi proses "download &
jalankan script" itu di banyak host sekaligus, memakai collection resmi dari Galaxy
(`ansible.windows`, `ansible.posix`) untuk eksekusi lintas OS-nya.

## Flow lengkap

1. **Generate deployment script di console**
   Trend Vision One console → **Endpoint Security → Endpoint Inventory → Agent
   Installer tab → Deployment Script** → pilih OS (Windows/Linux/Mac) → copy link
   script. Link ini sudah mengandung token aktivasi tenant kamu.

2. **Simpan URL script dengan aman**
   Karena URL mengandung token, JANGAN taruh plaintext di git. Encrypt dengan
   Ansible Vault:
   ```bash
   ansible-vault encrypt_string --vault-id vault@prompt \
     'https://files.trendmicro.com/.../deploy_linux.sh?token=XXXX' \
     --name 'vision_one_linux_script_url'
   ```
   Tempel hasilnya ke `group_vars/vision_one_linux.yml` /
   `group_vars/vision_one_windows.yml` (sudah ada contoh placeholder di kedua file,
   **ganti dengan hasil generate kamu sendiri**).

3. **Install collection dari Galaxy**
   ```bash
   ansible-galaxy collection install -r requirements.yml
   ```

4. **Sesuaikan inventory**
   Edit `inventory/hosts.ini` — masukkan host Linux ke group `vision_one_linux`
   dan host Windows ke `vision_one_windows`. Pastikan WinRM sudah aktif untuk
   target Windows.

5. **Jalankan playbook**
   ```bash
    ansible-playbook -i inventory/hosts.ini playbook.yml --ask-vault-pass
   ```

   Yang terjadi di tiap host:
   - Cek apakah agent sudah terpasang & service jalan → kalau sudah, **skip** (idempotent).
   - Download deployment script ke folder temp.
   - Jalankan script (install + auto-activate ke tenant Vision One kamu).
   - Hapus script installer setelah dipakai (karena mengandung token).
   - Verifikasi ulang service agent benar-benar `running`, dan playbook akan
     **gagal (assert)** kalau ternyata tidak jalan — supaya kelihatan di CI/CD
     kalau ada host yang gagal ter-provision.

6. **Verifikasi akhir di console**
   Endpoint Inventory di Vision One akan menampilkan host baru dengan status
   "Managed / Online" beberapa menit setelah script selesai jalan.

## Penjelasan task dengan command

Playbook menjalankan langkah berikut pada setiap server. Nama task di bawah ini
sesuai dengan nama di `playbook.yml`.

### Linux

| Task | Yang dilakukan | Padanan command |
|---|---|---|
| Cek apakah agent sudah terinstall & service jalan | Membaca daftar service Linux. | `systemctl list-units --type=service` |
| Set flag jika agent sudah aktif | Menyimpan jawaban `true` atau `false` ke variabel `vision_one_already_installed`. | Cek `systemctl is-active ds_agent` |
| Download deployment script ke server Linux | Mengunduh script dari URL Vault. | `curl -o /tmp/tm_vision_one_deploy.sh URL` |
| Jalankan deployment script | Menjalankan script instalasi dan aktivasi. | `/tmp/tm_vision_one_deploy.sh` |
| Tampilkan output instalasi | Menampilkan hasil command sebelumnya. | Output dari command instalasi |
| Bersihkan script installer setelah dipakai | Menghapus script yang berisi token. | `rm /tmp/tm_vision_one_deploy.sh` |
| Verifikasi ulang service agent berjalan | Membaca status service lagi setelah instalasi. | `systemctl is-active ds_agent` |
| Assert service agent aktif | Menggagalkan playbook jika service belum `running`. | `test "$(systemctl is-active ds_agent)" = running` |

### Windows

| Task | Yang dilakukan | Padanan PowerShell |
|---|---|---|
| Cek service tmlisten | Membaca status service SEP pertama. | `Get-Service tmlisten` |
| Cek service ntrtscan | Membaca status service SEP kedua. | `Get-Service ntrtscan` |
| Tentukan apakah agent Windows sudah terpasang | `set_fact` menyimpan `true` hanya jika kedua service ditemukan dan berstatus `started`. | `((Get-Service tmlisten).Status -eq 'Running') -and ((Get-Service ntrtscan).Status -eq 'Running')` |
| Download deployment script (PowerShell) dari Vision One | Mengunduh script ke Windows target. | `Invoke-WebRequest -Uri URL -OutFile C:\Windows\Temp\tm_vision_one_deploy.ps1` |
| Jalankan deployment script PowerShell | Menjalankan file `.ps1` dengan execution policy sementara. | `powershell.exe -ExecutionPolicy Bypass -File C:\Windows\Temp\tm_vision_one_deploy.ps1` |
| Tampilkan output instalasi | Menampilkan output PowerShell. | Output dari command instalasi |
| Bersihkan script installer setelah dipakai | Menghapus script yang berisi token. | `Remove-Item C:\Windows\Temp\tm_vision_one_deploy.ps1` |
| Verifikasi ulang service tmlisten | Membaca status service setelah instalasi. | `Get-Service tmlisten` |
| Verifikasi ulang service ntrtscan | Membaca status service setelah instalasi. | `Get-Service ntrtscan` |
| Pastikan service tmlisten aktif | Menggagalkan playbook jika `tmlisten` belum aktif. | `if ((Get-Service tmlisten).Status -ne 'Running') { exit 1 }` |
| Pastikan service ntrtscan aktif | Menggagalkan playbook jika `ntrtscan` belum aktif. | `if ((Get-Service ntrtscan).Status -ne 'Running') { exit 1 }` |

### Arti keyword Ansible

- `register`: menyimpan hasil task ke variabel agar bisa dipakai task berikutnya.
- `set_fact`: membuat variabel baru selama playbook berjalan. Di sini variabelnya
   hanya jawaban sederhana: agent sudah aktif atau belum.
- `when`: menjalankan task hanya jika kondisi terpenuhi. Script tidak dijalankan
   jika agent sudah aktif.
- `assert`: memeriksa hasil akhir dan membuat playbook gagal jika kondisi salah.
- `win_shell`: menjalankan command PowerShell di server Windows.

## Catatan penting
- `vision_one_service_name_linux` / `vision_one_service_names_windows` di `group_vars` **perlu kamu
  konfirmasi ke tim security/Trend Micro support** sesuai versi agent yang dipakai
  tenant kamu — nama service bisa berbeda antar versi/edisi (Standard Endpoint
  Protection vs Server & Workload Protection).
- Kalau endpoint tidak punya akses internet langsung, set `vision_one_use_proxy: true`
  dan isi `vision_one_proxy_url`.
- File `.vault_pass.txt` di contoh ini hanya untuk demo — di production simpan
  vault password di secret manager (Ansible Automation Platform Vault, HashiCorp
  Vault, dsb), jangan commit ke repo.
