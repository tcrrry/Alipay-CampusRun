param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
$adb=Join-Path $PSScriptRoot 'platform-tools\adb.exe'
$packages=Join-Path $PSScriptRoot 'packages'
$wsaName='MicrosoftCorporationII.WindowsSubsystemForAndroid'
$installRoot=Join-Path $env:LOCALAPPDATA 'CampusRun-WSA'
$wsaFolder=Join-Path $installRoot 'WSA_2407.40000.4.0_x64'
$wsaAlias=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\WsaClient.exe'
$psExe=Join-Path $PSHOME 'powershell.exe'
. (Join-Path $PSScriptRoot 'Local-Settings.ps1')
$guideStatus=Join-Path ([IO.Path]::GetTempPath()) ('CampusRun-InstallGuide-'+[guid]::NewGuid().ToString('N')+'.txt')
$diagnosticLog=Join-Path $env:LOCALAPPDATA ('CampusRun-InstallLogs\install-{0:yyyyMMdd-HHmmss}-{1}.log' -f (Get-Date),$PID)
function Write-InstallDiagnostic([string]$message){
 if($CheckOnly){return}
 try{
  [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($diagnosticLog))
  [IO.File]::AppendAllText($diagnosticLog,('{0:O} {1}{2}' -f (Get-Date),$message,[Environment]::NewLine),[Text.Encoding]::UTF8)
 }catch{}
}
function Set-InstallStep([string]$message){
 Write-Host $message
 Write-InstallDiagnostic $message
 if(!$CheckOnly){try{[IO.File]::WriteAllText($guideStatus,$message,[Text.Encoding]::UTF8)}catch{}}
}
if(!$CheckOnly){
 Set-InstallStep '安装正在准备，请等待。'
 Write-Host "安装日志：$diagnosticLog"
 try{
  $guideScript=Join-Path $PSScriptRoot 'InstallGuide.ps1'
  $startInfo=New-Object System.Diagnostics.ProcessStartInfo
  $startInfo.FileName=$psExe
  $startInfo.Arguments='-NoProfile -ExecutionPolicy Bypass -STA -File "'+$guideScript+'" -StatusFile "'+$guideStatus+'" -OwnerProcessId '+$PID
  $startInfo.UseShellExecute=$false
  $startInfo.CreateNoWindow=$true
  [System.Diagnostics.Process]::Start($startInfo) | Out-Null
 }catch{Write-Host '安装提示窗口无法打开，请留意此命令窗口。'}
}
function Invoke-Device([string[]]$Arguments,[switch]$AllowFailure){
 $ErrorActionPreference='Continue'
 $output=& $adb -s $device @Arguments 2>&1
 if($LASTEXITCODE -ne 0 -and !$AllowFailure){throw "ADB 操作失败：$($Arguments[0]) $($output -join ' ')"}
 $output | ForEach-Object {"$_"}
}
function Test-Connected {return [bool]((Invoke-Device @('get-state') -AllowFailure) -match '^device$')}
function Get-WsaAdbState {
 $ErrorActionPreference='Continue'
 $lines=& $adb devices 2>$null
 $pattern='^'+[regex]::Escape($device)+'\s+(\S+)'
 foreach($line in $lines){if($line -match $pattern){return $Matches[1]}}
 return 'absent'
}
function Wait-Wsa {
 param([string]$Phase='[3/6] WSA 首次连接',[switch]$KeepWaiting)
 $previousState=''
 $nextConnect=[DateTime]::MinValue
 for($i=0;$KeepWaiting -or $i -lt 300;$i++){
  $state=Get-WsaAdbState
  if($state -ne $previousState){
   Write-InstallDiagnostic "$Phase / $device / ADB: $state"
   if($state -eq 'unauthorized'){
    Set-InstallStep "$Phase：有 Allow 就直接允许。若没有，在 Android 开发者选项关开一次 USB 调试，勾选始终允许，再点 Allow。安装窗口保持打开。"
   }elseif($previousState -and $state -in @('absent','offline')){
    Set-InstallStep "$Phase：调试连接已断开，正在等待 WSA 恢复。"
   }
   $previousState=$state
  }
  if($state -eq 'device'){
   if((Invoke-Device @('shell','getprop','sys.boot_completed') -AllowFailure) -match '^1$'){
    Write-InstallDiagnostic "$Phase / Android boot completed"
    return
   }
  }elseif($state -in @('absent','offline') -and [DateTime]::UtcNow -ge $nextConnect){
   $nextConnect=[DateTime]::UtcNow.AddSeconds(5)
   $output=(Invoke-Device @('connect',$device) -AllowFailure) -join ' '
   Write-InstallDiagnostic "$Phase / ADB connect: $output"
  }
  if($i -gt 0 -and $i % 15 -eq 0){
   Write-Host '仍在等待 WSA 启动或授权。若没有 Allow，可在 WSA 高级设置打开 Manage developer settings，并按提示检查 USB 调试。'
  }
  Start-Sleep -Seconds 2
 }
 $state=Get-WsaAdbState
 if($state -eq 'unauthorized'){throw "$Phase：WSA 的调试连接未获授权。请检查安卓窗口和任务栏中的 Allow ADB debugging 授权框。"}
 if($state -eq 'device'){throw "$Phase：ADB 已授权，但 Android 启动未完成。"}
 throw "$Phase：WSA 未连接（ADB: $state）。请检查 WSA 开发人员模式和 settings.json 的端口。"
}
function Find-Root {
 Set-InstallStep '[4/6] 正在检查 Magisk Root。若弹出 Shell 的 Root 授权，请确认并允许。'
 while($true){
  $candidate=(Invoke-Device @('shell','command -v su') -AllowFailure | Out-String).Trim()
  if($candidate -notmatch '^/[A-Za-z0-9_./-]+$'){$candidate='/debug_ramdisk/su'}
  if((Invoke-Device @('shell',$candidate,'-c','id') -AllowFailure) -match 'uid=0\(root\)'){
   $script:rootCommand=$candidate
   return
  }
  Set-InstallStep '[4/6] 暂未取得 Root。关开 USB 调试后回到 CMD 按 Enter，再确认 Magisk 的 Shell 授权。'
  Write-Host '1. 回到 WSA 高级设置，确认 Developer mode 已开启，点 Manage developer settings。'
  Write-Host '2. 在 Android 开发者选项关闭再打开 USB 调试，然后回到这个黑色窗口按 Enter。'
  Write-Host '3. 若出现 ADB Allow，勾选始终允许并确认。若 Magisk 弹出 Shell 超级用户请求，再点允许。'
  Write-Host '   如果之前拒绝过 Shell，可在 Magisk 的「超级用户」页面改为允许。'
  [void](Read-Host 'USB 调试重新打开后即可按 Enter 重试')
  Wait-Wsa -Phase '[4/6] Root 重试' -KeepWaiting
  Set-InstallStep '[4/6] 正在重新请求 Magisk Root。若弹出 Shell 超级用户请求，请点击允许。'
 }
}
function Invoke-Root([string]$Command,[switch]$AllowFailure){Invoke-Device @('shell',$script:rootCommand,'-c',$Command) -AllowFailure:$AllowFailure}
function Restart-Wsa {
 param([string]$Phase)
 Write-InstallDiagnostic "$Phase / requesting WSA shutdown"
 $p=Start-Process -FilePath $wsaAlias -ArgumentList '/shutdown' -WindowStyle Hidden -PassThru
 try{if(!$p.WaitForExit(20000)){throw 'WSA 关闭超时，请从 WSA 设置关闭后重试。'}}finally{$p.Dispose()}
 for($i=0;$i -lt 15 -and (Test-Connected);$i++){Start-Sleep -Seconds 1}
 if(Test-Connected){throw 'WSA 没有完全关闭，请从 WSA 设置关闭后重试。'}
 Set-InstallStep "$Phase：WSA 正在重新启动。若弹出 Allow，请确认授权。"
 Start-Process -FilePath $wsaAlias -ArgumentList '/launch wsa://system' -WindowStyle Hidden
 Wait-Wsa -Phase $Phase
 Find-Root
}
try {
 if([Environment]::OSVersion.Version.Build -lt 22000 -or [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString() -ne 'X64'){throw '这个离线包仅支持 Windows 11 x64。'}
 Set-InstallStep '[1/6] 正在校验离线包，可能需要数分钟。请耐心等待下一步提示，不要关闭窗口。'
 foreach($line in Get-Content -Encoding UTF8 -LiteralPath (Join-Path $PSScriptRoot 'SHA256SUMS.txt')){
  if($line -notmatch '^([0-9a-f]{64})  (.+)$'){throw '校验清单格式错误。'}
  $expected=$Matches[1];$relative=$Matches[2]
  if([IO.Path]::IsPathRooted($relative) -or $relative -match '(?:^|[/\\])\.\.(?:$|[/\\])'){throw '校验清单含无效路径。'}
  if((Get-FileHash -LiteralPath (Join-Path $PSScriptRoot $relative)).Hash -ne $expected){throw "文件校验失败：$relative。请重新复制 ZIP。"}
 }
 if($CheckOnly){Write-Host 'SETUP_CHECK_OK';return}
 $existing=Get-AppxPackage -Name $wsaName
 if($existing -and ($existing.InstallLocation -ne $wsaFolder -or $existing.Version.ToString() -ne '2407.40000.4.0')){throw '检测到另一套 WSA。为保留原环境，一键入口不会覆盖它。请使用说明中的已有 WSA 路径。'}
 if(!$existing){
  $developer=(Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock' -Name AllowDevelopmentWithoutDevLicense -ErrorAction SilentlyContinue).AllowDevelopmentWithoutDevLicense
  if($developer -ne 1){Start-Process 'ms-settings:developers';throw '请先在 Windows 设置中开启“开发人员模式”，确认提示后，再双击 01-双击安装。'}
 }
 $cpu=Get-CimInstance Win32_Processor | Select-Object -First 1
 if($cpu.VirtualizationFirmwareEnabled -eq $false){Write-Host '提示：未检测到 BIOS/UEFI 硬件虚拟化已启用。若 WSA 无法启动，请到任务管理器的 CPU 页面检查“虚拟化”，必要时在 BIOS 中开启 Intel VT-x 或 AMD SVM。安装器无法自动修改 BIOS。' -ForegroundColor Yellow}
 $feature=Get-CimInstance Win32_OptionalFeature -Filter "Name='VirtualMachinePlatform'"
 if($feature.InstallState -ne 1){
  Set-InstallStep '需要你操作：启用 Windows 虚拟机平台，请在系统管理员权限提示中点击“是”。'
  $argsList='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Enable-Virtualization.ps1')+'"'
  $elevated=Start-Process -FilePath $psExe -ArgumentList $argsList -Verb RunAs -WindowStyle Hidden -Wait -PassThru
  if($elevated.ExitCode -notin @(0,3010)){throw '启用虚拟机平台失败。请检查 CPU 虚拟化和 Windows 功能。'}
  Write-Host '请重启 Windows，再双击 01-双击安装.cmd 继续。';return
 }
 $ownerFile=Join-Path $installRoot 'campusrun-owner.json'
 if(!$existing){
  $ownerFile=Join-Path $installRoot 'campusrun-owner.json'
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  if(Test-Path -LiteralPath $installRoot){
   $rootItem=Get-Item -LiteralPath $installRoot -Force
   if($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '安装目录是链接，已停止以保护现有文件。'}
   if(!(Test-Path -LiteralPath $ownerFile)){throw '安装目录已存在且没有本安装器标记，为避免覆盖文件已停止。'}
   $owner=Get-Content -Raw -Encoding UTF8 -LiteralPath $ownerFile | ConvertFrom-Json
   if($owner.OwnerSid -ne $identity.User.Value -or $owner.InstallLocation -ne $wsaFolder -or $owner.PackageName -ne $wsaName){throw '安装目录归属不匹配，已停止以保护现有文件。'}
  }else{
   New-Item -ItemType Directory -Path $installRoot -ErrorAction Stop | Out-Null
   @{OwnerSid=$identity.User.Value;InstallLocation=$wsaFolder;PackageName=$wsaName}|ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath $ownerFile
  }
  Set-InstallStep '[2/6] 正在解压 WSA，可能需要数分钟，请等待。接下来会请求管理员权限。'
  & "$env:SystemRoot\System32\tar.exe" -xf (Join-Path $packages 'WSA-Magisk-verified.7z') -C $installRoot
  if($LASTEXITCODE){throw 'WSA 解压失败，请检查系统盘空间。'}
  $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
  $principal=New-Object Security.Principal.WindowsPrincipal($identity)
  $registrationResult=Join-Path ([IO.Path]::GetTempPath()) ('CampusRun-WsaRegistration-'+[guid]::NewGuid().ToString('N')+'.txt')
  $arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $PSScriptRoot 'Register-Wsa.ps1')+'" -ExpectedUserSid '+$identity.User.Value+' -ResultFile "'+$registrationResult+'"'
  $launch=@{FilePath=$psExe;ArgumentList=$arguments;WindowStyle='Hidden';Wait=$true;PassThru=$true}
  if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
   Set-InstallStep '需要你操作：注册 WSA 需要管理员权限，请在 Windows 提示中点击“是”。若没看到，请查看任务栏。'
   $launch.Verb='RunAs'
  }
  try {
   try{$registration=Start-Process @launch}catch{throw "未能启动 WSA 管理员注册。请确认 UAC 提示后重试。$($_.Exception.Message)"}
   $registrationMessage=if(Test-Path -LiteralPath $registrationResult){(Get-Content -Raw -LiteralPath $registrationResult).Trim()}else{'注册程序没有返回结果。'}
   if($registration.ExitCode -ne 0 -or $registrationMessage -ne 'WSA_REGISTERED'){throw "注册 WSA 失败：$registrationMessage"}
  } finally {
   if(Test-Path -LiteralPath $registrationResult){Remove-Item -LiteralPath $registrationResult -ErrorAction SilentlyContinue}
  }
 }
 if(!(Test-Connected)){
  Start-Process 'wsa-settings:'
  Set-InstallStep '[3/6] 在 WSA 高级设置开启 Developer mode，再点 Manage developer settings，直接打开 Android 开发者选项。'
 }
 Wait-Wsa
 if((Invoke-Device @('shell','getprop','ro.build.version.sdk')) -ne '33' -or (Invoke-Device @('shell','getprop','ro.product.cpu.abi')) -ne 'x86_64'){throw '连接到的不是预期的 Android 13 x64 WSA。'}
 Find-Root
 Set-InstallStep '[4/6] 正在安装和检查 Vector，请等待。若 Magisk 弹出 Shell 的 Root 授权，请确认并允许；没有弹窗就继续等待。'
 Invoke-Device @('push',(Join-Path $packages 'Vector-v2.2-3080-Release.zip'),'/data/local/tmp/campus-vector-3080.zip') | Out-Null
 Invoke-Device @('push',(Join-Path $PSScriptRoot 'Install-Guest.sh'),'/data/local/tmp/campus-transfer-install.sh') | Out-Null
 $stage=Invoke-Root 'sh /data/local/tmp/campus-transfer-install.sh'
 if($stage -match '^FRAMEWORK_RESTART_REQUIRED$'){Restart-Wsa -Phase '[4/6] Vector 重启后验证';$stage=Invoke-Root 'sh /data/local/tmp/campus-transfer-install.sh'}
 if(!($stage -match '^FRAMEWORK_READY$')){throw 'Vector 未就绪。'}
 Set-InstallStep '[5/6] 正在安装安卓应用和检测工具，可能需要几分钟，请等待。'
 . (Join-Path $PSScriptRoot 'Install-Alipay64.ps1')
 Install-Alipay64 (Join-Path $packages 'Alipay-official-64.apk')
 foreach($apk in @('campus-run-custom.apk','sensor-probe-1.1.apk')){
  if(!((Invoke-Device @('install','-r',(Join-Path $packages $apk))) -match '^Success$')){throw "APK 安装失败：$apk"}
 }
 Invoke-Device @('shell','cmd','appops','set','lab.campus.sim','android:mock_location','allow') | Out-Null
 Invoke-Device @('shell','pm','grant','lab.campus.sensors','android.permission.ACTIVITY_RECOGNITION') | Out-Null
 Set-InstallStep '[6/6] 正在配置并检查模块作用域，请等待。'
 $cli='sh /data/adb/modules/zygisk_vector/cli'
 $registered=$false
 for($i=0;$i -lt 15;$i++){
  if((Invoke-Root "$cli modules ls" -AllowFailure) -match '^lab\.campus\.sim\s'){$registered=$true;break}
  Start-Sleep -Seconds 2
 }
 if(!$registered){throw 'Vector 尚未识别校园跑模块，请确认 Vector 已激活后重试。'}
 Invoke-Root "$cli modules enable lab.campus.sim" | Out-Null
 Invoke-Root "$cli scope set lab.campus.sim com.eg.android.AlipayGphone/0 lab.campus.sensors/0" | Out-Null
 $scope=Invoke-Root "$cli scope ls lab.campus.sim"
 if(!($scope -match '^com\.eg\.android\.AlipayGphone\s+0\s*$') -or !($scope -match '^lab\.campus\.sensors\s+0\s*$')){throw '作用域验证未通过。'}
 if(!((Invoke-Root "$cli modules ls --enabled") -match '^lab\.campus\.sim\s')){throw '模块未启用。'}
 $desktop=[Environment]::GetFolderPath('DesktopDirectory')
 $launcher=Join-Path $PSScriptRoot '02-装好后启动.cmd'
 $shortcutPath=Join-Path $desktop '支付宝校园跑.lnk'
 if(!(Test-Path -LiteralPath $shortcutPath)){
  $shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
  $shortcut.TargetPath=$launcher;$shortcut.WorkingDirectory=$PSScriptRoot;$shortcut.Save()
 }
 Set-InstallStep '安装完成。请打开 02-装好后启动.cmd 或桌面快捷方式；支付宝登录和验证由本人完成。'
}catch{Set-InstallStep ('安装暂停：'+$_.Exception.Message);exit 1}
finally{if(!$CheckOnly){Start-Sleep -Seconds 2;try{[IO.File]::Delete($guideStatus)}catch{}}}
