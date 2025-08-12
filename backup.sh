#!/bin/bash
SRC="$1" # source folder
DEST="$2" # destination folder

DATE=$(date +'%Y-%m-%d_%H-%M-%S')
TARFILE="$DEST/backup_$DATE.tar.gz"

mkdir -p "$DEST"
tar -czf "$TARFILE" -C "$SRC" .

echo "Backup selesai: $TARFILE"

cd ~/projects
git add .
git commit -m "Auto backup $(date +'%Y-%m-%d %H:%M:%S')"
git push origin main
