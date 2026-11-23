#!/system/bin/sh
# Called only for an explicit Start before a fresh WSA session.
set -e
[ "$(id -u)" = 0 ] || { echo ROOT_UNAVAILABLE; exit 10; }
magisk_bin=$(command -v magisk || true)
if [ -z "$magisk_bin" ] && [ -x /debug_ramdisk/magisk ]; then magisk_bin=/debug_ramdisk/magisk; fi
[ -n "$magisk_bin" ] || { echo MAGISK_MISSING; exit 15; }
[ -f /data/adb/modules/zygisk_vector/module.prop ] || { echo VECTOR_MISSING; exit 12; }
[ ! -f /data/adb/modules/zygisk_vector/remove ] || { echo VECTOR_REMOVING; exit 13; }
changed=0
zygisk=$("$magisk_bin" --sqlite "SELECT value FROM settings WHERE key='zygisk';")
case "$zygisk" in *value=1*) ;; *) "$magisk_bin" --sqlite "INSERT OR REPLACE INTO settings (key,value) VALUES ('zygisk',1);"; changed=1;; esac
if [ -f /data/adb/modules/zygisk_vector/disable ]; then
 mv /data/adb/modules/zygisk_vector/disable "/data/adb/modules/zygisk_vector/disable.before-campus-$(date +%s)"
 changed=1
fi
if [ "$changed" = 1 ]; then echo FRAMEWORK_RESTORED; else echo FRAMEWORK_READY; fi
