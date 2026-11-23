#!/system/bin/sh
# Read-only framework checks. Do not override another tool's disable settings.
if [ "$(id -u)" != 0 ]; then echo ROOT_UNAVAILABLE; exit 10; fi
magisk_bin=$(command -v magisk)
if [ -z "$magisk_bin" ] && [ -x /debug_ramdisk/magisk ]; then magisk_bin=/debug_ramdisk/magisk; fi
if [ -z "$magisk_bin" ]; then echo MAGISK_MISSING; exit 15; fi
zygisk=$("$magisk_bin" --sqlite "SELECT value FROM settings WHERE key='zygisk';" 2>/dev/null)
case "$zygisk" in *value=1*) ;; *) echo ZYGISK_DISABLED; exit 11;; esac
if [ ! -f /data/adb/modules/zygisk_vector/module.prop ]; then echo VECTOR_MISSING; exit 12; fi
if [ -f /data/adb/modules/zygisk_vector/disable ] || [ -f /data/adb/modules/zygisk_vector/remove ]; then
 echo VECTOR_DISABLED; exit 13
fi
if ! pm path lab.campus.sim >/dev/null 2>&1; then echo MODULE_MISSING; exit 14; fi
echo FRAMEWORK_CONFIG_OK
