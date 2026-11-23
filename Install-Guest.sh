#!/system/bin/sh
set -e
[ "$(id -u)" = 0 ] || { echo ROOT_REQUIRED; exit 10; }
magisk_bin=$(command -v magisk || true)
if [ -z "$magisk_bin" ] && [ -x /debug_ramdisk/magisk ]; then magisk_bin=/debug_ramdisk/magisk; fi
[ -n "$magisk_bin" ] || { echo MAGISK_MISSING; exit 11; }
prop=/data/adb/modules/zygisk_vector/module.prop
if [ ! -f "$prop" ]; then
  "$magisk_bin" --install-module /data/local/tmp/campus-vector-3080.zip
  "$magisk_bin" --sqlite "INSERT OR REPLACE INTO settings (key,value) VALUES ('zygisk',1);"
  echo FRAMEWORK_RESTART_REQUIRED
  exit 0
fi
grep -qx 'versionCode=3080' "$prop" || { echo VECTOR_VERSION_MISMATCH; exit 12; }
zygisk=$("$magisk_bin" --sqlite "SELECT value FROM settings WHERE key='zygisk';")
if [ "$zygisk" != value=1 ] || [ -f /data/adb/modules/zygisk_vector/disable ]; then
  echo FRAMEWORK_DISABLED
  exit 13
fi
[ ! -f /data/adb/modules/zygisk_vector/remove ] || { echo VECTOR_REMOVING; exit 14; }
echo FRAMEWORK_READY
