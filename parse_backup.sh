#!/bin/bash
# parse_backup.sh - Extract credentials from ADB backup files

BACKUP_DIR="android_extract_*/backup"

echo "[*] Looking for backup files..."
for ab_file in $BACKUP_DIR/*.ab; do
    [ -f "$ab_file" ] || continue
    echo "[+] Processing: $ab_file"
    
    BASENAME=$(basename "$ab_file" .ab)
    OUT="$BACKUP_DIR/extracted_$BASENAME"
    mkdir -p "$OUT"
    
    # Unpack with ABE
    java -jar "$HOME/abe.jar" unpack "$ab_file" "$OUT/backup.tar" 2>/dev/null
    
    if [ -f "$OUT/backup.tar" ]; then
        echo "    Backup extracted. Size: $(stat -c%s "$OUT/backup.tar") bytes"
        mkdir -p "$OUT/tar_contents"
        tar -xf "$OUT/backup.tar" -C "$OUT/tar_contents" 2>/dev/null
        
        # Search for credential files
        echo "    Searching for credentials..."
        find "$OUT/tar_contents" -type f \( -name "*.xml" -o -name "*.db" -o -name "*.txt" \) 2>/dev/null | while read file; do
            if grep -q -i "password\|@gmail\|@google\|token\|auth\|account" "$file" 2>/dev/null; then
                echo "    [+] Credentials found in: $(echo $file | sed 's|.*tar_contents/||')"
                grep -i "password\|@gmail\|@google\|token\|auth\|account" "$file" 2>/dev/null | head -5
            fi
        done
    fi
done
