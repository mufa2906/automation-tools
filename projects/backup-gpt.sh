#!/usr/bin/env bash
# Backup tool with logging, retention, exclude, lock, checksum, and optional Git push
# Author: June + GPT-Tech
# Usage example:
#   ./backup.sh -s /home/june/projects -d /mnt/backups -n projects -k 7 \
#     -e "*.log" -e "node_modules" --compress gz --git --check-space 1024 -v

set -Eeuo pipefail
IFS=$'\n\t'

# ========== Defaults ==========
KEEP="${KEEP:-7}"                 # jumlah backup yang disimpan
COMPRESS="${COMPRESS:-gz}"        # gz | zst
CHECK_SPACE_MB="${CHECK_SPACE_MB:-512}" # minimal free space (MB) di destinasi
LOG_FILE="${LOG_FILE:-$HOME/.local/var/log/backup_tool.log}"
LOCK_FILE="${LOCK_FILE:-/tmp/backup_tool.lock}"
VERBOSE="${VERBOSE:-0}"
GIT_PUSH="${GIT_PUSH:-0}"
NAME="${NAME:-}"                  # default diisi nama folder SRC kalau kosong
EXCLUDES=()                       # diisi via -e/--exclude

# ========== Helpers ==========
usage() {
  cat <<EOF
Backup directory menjadi arsip terkompresi dengan fitur:
- Logging + rotasi sederhana, lock agar tidak tumpang tindih
- Retention: simpan N backup terbaru
- Exclude file/folder (bisa diulang beberapa kali)
- Cek free space sebelum backup
- Checksum SHA256
- Opsional auto-commit & push Git di SRC

Wajib: -s/--src <dir> -d/--dest <dir>
Opsional:
  -n, --name <nama>           Nama prefix file backup (default: nama folder SRC)
  -k, --keep <N>              Simpan N backup terbaru (default: ${KEEP})
  -e, --exclude <pattern>     Pola exclude (bisa diulang), contoh: "*.log" atau "node_modules"
      --compress <gz|zst>     Metode kompresi (default: ${COMPRESS})
      --check-space <MB>      Minimal free space destinasi (default: ${CHECK_SPACE_MB} MB)
      --log <file>            Lokasi file log (default: ${LOG_FILE})
      --git                   Auto commit & push jika SRC repo Git
  -v, --verbose               Output lebih detil
  -h, --help                  Bantuan

Contoh:
  $(basename "$0") -s /srv/app -d /backups -n app -k 10 -e "node_modules" -e "*.cache" --compress zst --git -v
EOF
}

log_init() {
  mkdir -p "$(dirname "$LOG_FILE")"
  touch "$LOG_FILE"
}

log_rotate_if_big() {
  # rotasi jika >10MB
  if [[ -f "$LOG_FILE" ]]; then
    local size
    size=$(wc -c < "$LOG_FILE" || echo 0)
    if (( size > 10*1024*1024 )); then
      mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d%H%M%S)"
      : > "$LOG_FILE"
    fi
  fi
}

_log() {
  local level="$1"; shift
  local msg="$*"
  local ts
  ts="$(date +'%Y-%m-%d %H:%M:%S')"
  local line="[$ts] [$level] $msg"
  echo "$line" | tee -a "$LOG_FILE" >/dev/null
  # Untuk cron: tetap tulis ke stdout saat verbose
  if [[ "${VERBOSE}" == "1" ]]; then echo "$line"; fi
}

info(){ _log INFO "$*"; }
warn(){ _log WARN "$*"; }
error(){ _log ERROR "$*"; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { error "Perintah '$1' tidak ditemukan. Install dulu."; exit 127; }
}

cleanup_on_error() {
  local exit_code=$?
  error "Backup GAGAL dengan exit code ${exit_code}"
  exit "${exit_code}"
}

trap cleanup_on_error ERR

# ========== Parse Args ==========
SRC=""
DEST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -s|--src) SRC="$2"; shift 2;;
    -d|--dest) DEST="$2"; shift 2;;
    -n|--name) NAME="$2"; shift 2;;
    -k|--keep) KEEP="$2"; shift 2;;
    -e|--exclude) EXCLUDES+=("$2"); shift 2;;
    --compress) COMPRESS="$2"; shift 2;;
    --check-space) CHECK_SPACE_MB="$2"; shift 2;;
    --log) LOG_FILE="$2"; shift 2;;
    --git) GIT_PUSH=1; shift;;
    -v|--verbose) VERBOSE=1; shift;;
    -h|--help) usage; exit 0;;
    --) shift; break;;
    *) error "Argumen tidak dikenal: $1"; usage; exit 2;;
  esac
done

[[ -z "${SRC}" || -z "${DEST}" ]] && { usage; exit 2; }
[[ -d "$SRC" ]] || { error "SRC tidak ada/akses gagal: $SRC"; exit 2; }
mkdir -p "$DEST"

log_init
log_rotate_if_big

# ========== Lock ==========
require_cmd flock
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  warn "Proses lain masih berjalan (lock: $LOCK_FILE). Keluar tanpa menjalankan backup."
  exit 0
fi

# ========== Dependencies ==========
require_cmd tar
require_cmd df
require_cmd du
require_cmd sha256sum

case "$COMPRESS" in
  gz)   EXT="tar.gz"; TAR_COMPRESS_ARGS=(-czf);;
  zst|zstd)
        EXT="tar.zst"
        # butuh tar yang support --zstd
        tar --help 2>&1 | grep -q -- "--zstd" || { error "tar tidak mendukung --zstd. Install tar/zstd terbaru atau pakai --compress gz"; exit 2; }
        TAR_COMPRESS_ARGS=(--zstd -cf)
        ;;
  *) error "Metode kompresi tidak dikenal: $COMPRESS (pakai gz atau zst)"; exit 2;;
esac

# ========== Validasi ruang disk ==========
# estimasi kasar: ukuran SRC + 50MB jaga-jaga
SRC_SIZE_BYTES=$(du -sb "$SRC" | awk '{print $1}')
DEST_FREE_KB=$(df -Pk "$DEST" | awk 'NR==2 {print $4}')
DEST_FREE_BYTES=$(( DEST_FREE_KB * 1024 ))
REQUIRED_BYTES=$(( SRC_SIZE_BYTES + 50*1024*1024 ))

MIN_FREE_BYTES=$(( CHECK_SPACE_MB * 1024 * 1024 ))
if (( DEST_FREE_BYTES < REQUIRED_BYTES || DEST_FREE_BYTES < MIN_FREE_BYTES )); then
  error "Free space tidak cukup di $DEST (tersedia: $((DEST_FREE_BYTES/1024/1024)) MB, butuh minimal: $((REQUIRED_BYTES/1024/1024)) MB dan threshold ${CHECK_SPACE_MB} MB)"
  exit 3
fi

# ========== Nama file & exclude ==========
BASENAME=$(basename "$SRC")
NAME="${NAME:-$BASENAME}"
STAMP="$(date +'%Y%m%d_%H%M%S')"
TARGET="${DEST}/${NAME}_${STAMP}.${EXT}"
TMP_TARGET="${TARGET}.part"

# Build opsi exclude untuk tar
EXCLUDE_ARGS=()
if (( ${#EXCLUDES[@]} )); then
  for pat in "${EXCLUDES[@]}"; do
    EXCLUDE_ARGS+=( --exclude="$pat" )
  done
fi

info "Mulai backup"
info "SRC: $SRC"
info "DEST: $DEST"
info "FILE: $TARGET"
info "COMPRESS: $COMPRESS"
(( ${#EXCLUDES[@]} )) && info "EXCLUDES: ${EXCLUDES[*]}"
info "KEEP terakhir: $KEEP"
info "Free space: $((DEST_FREE_BYTES/1024/1024)) MB"

# ========== Proses backup ==========
# Gunakan -C agar path di arsip rapi (tanpa direktori absolut)
if [[ "$COMPRESS" == "gz" ]]; then
  tar "${TAR_COMPRESS_ARGS[@]}" "$TMP_TARGET" "${EXCLUDE_ARGS[@]}" -C "$SRC" .
else
  # zstd
  tar "${TAR_COMPRESS_ARGS[@]}" "$TMP_TARGET" "${EXCLUDE_ARGS[@]}" -C "$SRC" .
fi

# Pastikan file sementara jadi final atomically
mv "$TMP_TARGET" "$TARGET"

# ========== Checksum ==========
sha256sum "$TARGET" > "${TARGET}.sha256"

info "Backup selesai: $TARGET"
info "Checksum: ${TARGET}.sha256"

# ========== Retention: simpan N terbaru ==========
# Urutkan berdasarkan waktu file (terbaru dulu), hapus yang lewat N.
mapfile -t backups < <(ls -1t "${DEST}/${NAME}_"*.${EXT} 2>/dev/null || true)
if (( ${#backups[@]} > KEEP )); then
  to_delete=( "${backups[@]:$KEEP}" )
  if (( ${#to_delete[@]} )); then
    info "Retention: hapus ${#to_delete[@]} file lama"
    for f in "${to_delete[@]}"; do
      rm -f -- "$f" "$f.sha256" || warn "Gagal hapus $f"
    done
  fi
fi

# ========== Optional: Git auto-commit & push ==========
if [[ "$GIT_PUSH" == "1" ]]; then
  if [[ -d "$SRC/.git" ]]; then
    require_cmd git
    info "Git: add/commit/push di $SRC"
    git -C "$SRC" add -A
    # commit mungkin kosong; jangan fail hard
    if ! git -C "$SRC" commit -m "Auto backup $(date +'%Y-%m-%d %H:%M:%S')" 2>/dev/null; then
      info "Git: tidak ada perubahan untuk di-commit"
    fi
    if ! git -C "$SRC" push; then
      warn "Git: push gagal. Cek credential/network."
    fi
  else
    warn "Git: SRC bukan repo Git, lewati push"
  fi
fi

info "SUKSES"
exit 0


: '
cara run codenya
~/tools/backup.sh \
  -s /home/june/projects \
  -d /mnt/backups \
  -n projects \
  -k 10 \
  -e "node_modules" -e "*.log" -e ".venv" \
  --compress zst \
  --check-space 1024 \
  --git \
  -v

settingan crontab
crontab -e
# GANTI path sesuai punyamu. Pakai path absolut!
0 21 * * * /home/june/tools/backup.sh -s /home/june/projects -d /mnt/backups -n projects -k 10 -e "node_modules" --compress gz --check-space 512 >> /home/june/.local/var/log/backup_cron.out 2>&1

Penjelasan Desain & Baris Penting (biar paham “kenapa”)
set -Eeuo pipefail → bikin script fail-fast dan error di pipeline ikut terdeteksi.

Logging rapi:

log_init, log_rotate_if_big → simpan log ke ~/.local/var/log/backup_tool.log, auto-rotate kalau >10MB.

Fungsi info/warn/error nulis ke log dan (kalau -v) juga ke stdout.

Locking (anti dobel jalan):

flock pada LOCK_FILE di FD 9 → kalau proses lama belum selesai, proses baru keluar dengan aman.

Cek dependency: require_cmd tar/df/du/sha256sum/git → fail cepat kalau belum terpasang.

Cek free space:

Hitung du -sb ukuran SRC, bandingkan dengan free space df -Pk.

Tambah buffer 50MB + threshold --check-space (default 512MB) → menghindari disk full.

Exclude:

Tar pakai --exclude="pattern" untuk skip folder/file berat seperti node_modules, .venv, *.log.

Kompresi:

gz (universal), zst/zstd (lebih cepat & rasio bagus, butuh tar yang support --zstd).

Format nama file: <name>_YYYYmmdd_HHMMSS.tar.gz|tar.zst.

Atomic write:

Tulis ke *.part dulu lalu mv → mencegah backup “setengah jadi” kalau listrik mati.

Checksum:

sha256sum file > file.sha256 → buat verifikasi integritas backup.

Retention:

Simpan N terbaru (default 7). Sisanya dihapus (termasuk .sha256-nya).

Git opsional (--git):

Kalau SRC repo Git: git add/commit/push. Commit kosong tidak dianggap error.

Gunakan .gitignore untuk hindari commit secrets, venv, build artifact, dll.
'
