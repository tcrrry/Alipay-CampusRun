$ErrorActionPreference='Stop'
$adb=Join-Path $PSScriptRoot 'platform-tools\adb.exe'
. (Join-Path $PSScriptRoot 'Local-Settings.ps1')
function Invoke-Device([string[]]$Arguments){
 $ErrorActionPreference='Continue'
 $output=& $adb -s $device @Arguments 2>&1
 if($LASTEXITCODE -ne 0){throw "ADB command failed: $($Arguments[0]); $($output -join ' ')"}
 $output
}
if(![Environment]::Is64BitOperatingSystem -or [Environment]::OSVersion.Version.Build -lt 22000){throw 'This kit targets x64 Windows 11.'}
if(!(Test-Path -LiteralPath $adb)){throw 'Extract the entire transfer ZIP before running this installer.'}
& $adb connect $device
if((& $adb -s $device get-state) -ne 'device'){throw 'Open WSA Settings > Developer and enable Developer mode. Check the local port in settings.json.'}
if((Invoke-Device @('shell','getprop','sys.boot_completed')) -ne '1'){throw 'Wait for WSA to finish starting, then try again.'}
if((Invoke-Device @('shell','getprop','ro.build.version.sdk')) -ne '33'){throw 'This kit expects Android 13 WSA.'}
if((Invoke-Device @('shell','getprop','ro.product.cpu.abi')) -ne 'x86_64'){throw 'This kit expects x86_64 WSA.'}
$su=(& $adb -s $device shell 'command -v su' 2>$null | Out-String).Trim()
if($su -notmatch '^/[A-Za-z0-9_./-]+$'){$su='/debug_ramdisk/su'}
if((Invoke-Device @('shell',$su,'-c','id')) -notmatch 'uid=0\(root\)'){throw 'Grant root to Android shell in Magisk, then retry.'}
$packages=Join-Path $PSScriptRoot 'packages'
Invoke-Device @('push',(Join-Path $packages 'Vector-v2.2-3080-Release.zip'),'/data/local/tmp/campus-vector-3080.zip') | Out-Null
Invoke-Device @('push',(Join-Path $PSScriptRoot 'Install-Guest.sh'),'/data/local/tmp/campus-transfer-install.sh') | Out-Null
$state=Invoke-Device @('shell',$su,'-c','sh /data/local/tmp/campus-transfer-install.sh')
if($state -match 'FRAMEWORK_RESTART_REQUIRED'){
 Write-Host 'Vector installed. Turn WSA off from its Settings, open Settings > Files to start it again, then rerun 99-手动安装（备用）.cmd.'
 return
}
if($state -notmatch 'FRAMEWORK_READY'){throw 'Framework did not report ready.'}
. (Join-Path $PSScriptRoot 'Install-Alipay64.ps1')
Install-Alipay64 (Join-Path $PSScriptRoot 'packages\Alipay-official-64.apk')
 foreach($apk in @('campus-run-custom.apk','sensor-probe-1.1.apk')){
 $result=Invoke-Device @('install','-r',(Join-Path $packages $apk))
 if(!($result -match '^Success$')){throw "APK installation failed: $apk"}
}
Invoke-Device @('shell','cmd','appops','set','lab.campus.sim','android:mock_location','allow') | Out-Null
Invoke-Device @('shell','pm','grant','lab.campus.sensors','android.permission.ACTIVITY_RECOGNITION') | Out-Null
Write-Host 'Apps installed. In Vector Manager enable lab.campus.sim and select only Alipay and Sensor Probe in its scope. Restart WSA, then open 02-装好后启动.cmd.'
