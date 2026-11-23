param([string]$PackagePath,[switch]$NoAdb,[switch]$NonInteractive,[string]$OutputDirectory)
$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath('DesktopDirectory')
if($OutputDirectory){$desktop=$OutputDirectory}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$report = Join-Path ([IO.Path]::GetTempPath()) ("CampusRun-Diagnostic-$stamp")
[void][IO.Directory]::CreateDirectory($report)
$utf8 = [Text.UTF8Encoding]::new($false)
$wsaName = 'MicrosoftCorporationII.WindowsSubsystemForAndroid'
$package = 'com.eg.android.AlipayGphone'

function Save-Report([string]$Name,$Lines){
 $body = $Lines | Out-String -Width 250
 if($env:USERPROFILE){$body = $body -replace [regex]::Escape($env:USERPROFILE),'<USERPROFILE>'}
 $body = $body -replace '(?i)([A-Z]:\\Users\\)[^\\\r\n]+(?=\\)','$1<USER>'
 $body = $body -replace '(?im)^.*(?:authorization:|bearer\s|cookie:|access[_-]?token|refresh[_-]?token|password=|手机号).*$','<已隐藏可能敏感的日志行>'
 [IO.File]::WriteAllText((Join-Path $report $Name),$body,$utf8)
}
function Section([string]$Name,[scriptblock]$Read){
 try { Save-Report $Name (& $Read) }
 catch { Save-Report $Name ('无法读取：'+$_.Exception.Message) }
}
function Invoke-DiagnosticAdb([string[]]$Arguments){
 $ErrorActionPreference='Continue'
 $output=& $adb -P $diagnosticPort @Arguments 2>&1
 $code=$LASTEXITCODE
 if($code -ne 0){'ADB exit code: '+$code}
 $output | ForEach-Object {"$_"}
}

$chooseFolder = !$NonInteractive -and !$PackagePath
if(!$PackagePath -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'Uninstall.ps1') -PathType Leaf) -and
   (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'SHA256SUMS.txt') -PathType Leaf)){
 $PackagePath=$PSScriptRoot
 if(!$NonInteractive){
  $choice=Read-Host '默认检查当前解压目录。若报错来自另一个旧解压目录，输入 1 选择旧目录，否则直接回车'
  $chooseFolder=$choice -eq '1'
 }
}
if($chooseFolder){
 Add-Type -AssemblyName System.Windows.Forms
 $picker=New-Object System.Windows.Forms.FolderBrowserDialog
 $picker.Description='请选择出现 03 一键卸载报错的解压目录。点取消会保留默认目录。'
 $picker.ShowNewFolderButton=$false
 try {if($picker.ShowDialog() -eq 'OK'){$PackagePath=$picker.SelectedPath}}
 finally {$picker.Dispose()}
}

if(!$NonInteractive){
 Write-Host '请在另一个窗口重试刚才失败的操作。若错误或黑屏已经出现，请保留现场。'
 [void](Read-Host '问题出现后回到这里按 Enter 开始采集')
 Write-Host '正在采集，请保留此窗口直到显示诊断 ZIP 路径。'
}

Section '01-system.txt' {
 Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,LastBootUpTime | Format-List
 Get-CimInstance Win32_Processor | Select-Object Name | Format-List
 Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,DriverDate,Status | Format-List
 Get-AppxPackage -Name $wsaName | Select-Object Name,Version,InstallLocation,Status | Format-List
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 '管理员权限：'+([Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
}
Section '02-uninstall.txt' {
 '采集时现有进程（在诊断程序发起 ADB 连接之前）：'
 Get-CimInstance Win32_Process | Where-Object {$_.Name -match '^(adb|WsaClient|WsaService|WsaSettings|vmmemWSA)\.exe$'} |
  Select-Object Name,ProcessId,ExecutablePath | Format-Table -AutoSize
 $ownerFile=Join-Path $env:LOCALAPPDATA 'CampusRun-WSA\campusrun-owner.json'
 'WSA 归属标记存在：'+(Test-Path -LiteralPath $ownerFile -PathType Leaf)
 if(Test-Path -LiteralPath $ownerFile -PathType Leaf){
  $owner=Get-Content -LiteralPath $ownerFile -Raw | ConvertFrom-Json
  '标记与当前账户一致：'+($owner.OwnerSid -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
  '标记安装目录：'+$owner.InstallLocation
 }
 if(!$PackagePath){'未选择原解压目录。';return}
 $folder=Get-Item -LiteralPath $PackagePath -Force
 '解压目录：'+$folder.FullName
 '目录名称受卸载器支持：'+($folder.Name -in @('支付宝校园跑','CampusRun-自定义测试版'))
 for($parent=$folder;$parent;$parent=$parent.Parent){
  if($parent.Attributes -band [IO.FileAttributes]::ReparsePoint){'路径含链接：'+$parent.FullName;return}
 }
 $manifest=Join-Path $folder.FullName 'SHA256SUMS.txt'
 if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){'校验清单不存在。';return}
 $known=@('SHA256SUMS.txt')
 foreach($line in Get-Content -LiteralPath $manifest -Encoding UTF8){
  if($line -match '^[a-f0-9]{64}  (.+)$'){$known+=$Matches[1].Replace('\','/')}
  else{'校验清单有格式异常。'}
 }
 foreach($name in 'Setup.ps1','Uninstall.ps1','platform-tools/adb.exe','packages/WSA-Magisk-verified.7z'){
  $path=Join-Path $folder.FullName $name
  if(!(Test-Path -LiteralPath $path -PathType Leaf)){'缺少文件：'+$name}
 }
 $pending=[Collections.Generic.Stack[IO.DirectoryInfo]]::new()
 $pending.Push($folder)
 while($pending.Count){
  foreach($item in Get-ChildItem -LiteralPath ($pending.Pop().FullName) -Force){
   $relative=$item.FullName.Substring($folder.FullName.Length+1).Replace('\','/')
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){'发现链接：'+$relative;continue}
   if($item.PSIsContainer){
    if($known | Where-Object {$_.StartsWith($relative+'/',[StringComparison]::OrdinalIgnoreCase)} | Select-Object -First 1){$pending.Push($item)}
    else{'额外文件夹：'+$relative}
   }elseif($relative -notin $known){'额外文件：'+$relative}
  }
 }
 $adbPath=Join-Path $folder.FullName 'platform-tools\adb.exe'
 $uninstaller=Join-Path $folder.FullName 'Uninstall.ps1'
 if(Test-Path -LiteralPath $uninstaller -PathType Leaf){
  '卸载脚本 SHA256：'+(Get-FileHash -LiteralPath $uninstaller).Hash
 }
 if(Test-Path -LiteralPath $adbPath -PathType Leaf){
  try{
   $probe=[IO.File]::Open($adbPath,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::None)
   $probe.Dispose()
   'adb.exe 当前可独占打开。'
  }catch{'adb.exe 独占读取失败（可能被占用或权限不足）：'+$_.Exception.Message}
 }
}
Section '03-windows-events.txt' {
 $start=(Get-Date).AddDays(-2)
 foreach($log in 'Application','Microsoft-Windows-AppXDeploymentServer/Operational'){
  $events=Get-WinEvent -FilterHashtable @{LogName=$log;StartTime=$start} -MaxEvents 1000 -ErrorAction SilentlyContinue
  "事件日志：$log"
  $events | Where-Object {$_.Message -match 'WsaClient|WsaService|WindowsSubsystemForAndroid|CampusRun-WSA|adb\.exe'} |
   Select-Object -First 18 TimeCreated,ProviderName,Id,Message | Format-List
 }
}
if(!$NonInteractive){
 $errorText=Read-Host '如果有安装、运行或卸载报错，可粘贴一行原文。直接回车可跳过'
 if($errorText){Save-Report '04-uninstall-message.txt' $errorText}
}
if(!$NoAdb){
 $adb=Join-Path $PSScriptRoot 'platform-tools\adb.exe'
 $device='127.0.0.1:58526'
 if($PackagePath){
  try{
   $settings=Get-Content -Raw -LiteralPath (Join-Path $PackagePath 'settings.json') | ConvertFrom-Json
   $endpoint=[string]$settings.AdbEndpoint
   if($endpoint -match '^127\.0\.0\.1:([0-9]{1,5})$' -and [int]$Matches[1] -in (1..65535)){$device=$endpoint}
  }catch{}
 }
 $port=[int]$device.Split(':')[1]
 $listening=Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue |
  Where-Object {$_.LocalAddress -in @('127.0.0.1','::1','0.0.0.0','::')}
 $diagnosticPort=$null
 try {
 if($listening){
  # Use our own server so diagnostic ADB cannot restart the installer's server.
  $socket=[Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback,0)
  $socket.Start()
  try {$diagnosticPort=$socket.LocalEndpoint.Port} finally {$socket.Stop()}
 }
 Section '05-adb.txt' {
  'WSA 调试地址：'+$device
  if(!$listening){'端口没有监听。请保持 WSA 已启动再采集。';return}
  $devices=@(Invoke-DiagnosticAdb @('devices'))
  $pattern='^'+[regex]::Escape($device)+'\s+(device|unauthorized|offline)\s*$'
  if(!($devices -match $pattern)){
   Invoke-DiagnosticAdb @('connect',$device)
   $devices=@(Invoke-DiagnosticAdb @('devices'))
  }
  $devices -match $pattern
  if($devices -match ('^'+[regex]::Escape($device)+'\s+unauthorized')){
   'ADB 未授权。请点 Allow，或到 WSA 高级设置开启调试后重新采集。'
  }
 }
 if($listening -and (@(Invoke-DiagnosticAdb @('devices')) -match ('^'+[regex]::Escape($device)+'\s+device\s*$'))){
  Section '06-android.txt' {
   'Android 启动完成：'
   Invoke-DiagnosticAdb @('-s',$device,'shell','getprop','sys.boot_completed')
   '支付宝版本：'
   Invoke-DiagnosticAdb @('-s',$device,'shell','dumpsys','package',$package) | Select-String 'versionName=|versionCode=|primaryCpuAbi=|secondaryCpuAbi=' | ForEach-Object Line
   'Android ABI 与 native bridge：'
   Invoke-DiagnosticAdb @('-s',$device,'shell','getprop','ro.product.cpu.abi')
   Invoke-DiagnosticAdb @('-s',$device,'shell','getprop','ro.dalvik.vm.native.bridge')
   Invoke-DiagnosticAdb @('-s',$device,'shell','sha256sum','/system/lib64/libhoudini.so','/system/lib/libhoudini.so')
   '定位服务状态：'
   Invoke-DiagnosticAdb @('-s',$device,'shell','content','call','--uri','content://lab.campus.sim.state','--method','state')
   Invoke-DiagnosticAdb @('-s',$device,'shell','dumpsys','activity','services','lab.campus.sim') |
    Select-String 'RouteService|isForeground=|startRequested=' | ForEach-Object Line
   '支付宝进程 PID：'
   Invoke-DiagnosticAdb @('-s',$device,'shell','pidof',$package)
   Invoke-DiagnosticAdb @('-s',$device,'shell','wm','size')
   Invoke-DiagnosticAdb @('-s',$device,'shell','wm','density')
  }
  Section '07-alipay-crash.txt' {
   $crash=@(Invoke-DiagnosticAdb @('-s',$device,'logcat','-b','crash','-d','-t','1500','-v','threadtime'))
   for($i=0;$i -lt $crash.Count;$i++){
    if($crash[$i] -match '(?:Process:|>>>|Cmdline:)\s*com\.eg\.android\.AlipayGphone(?=[:\s,]|$)' -and
       $crash[$i] -match '^\S+\s+\S+\s+(\d+)\s+'){
     $crashPid=$Matches[1]
     for($j=[Math]::Max(0,$i-16);$j -lt [Math]::Min($i+100,$crash.Count);$j++){
      if($crash[$j] -match ('^\S+\s+\S+\s+'+[regex]::Escape($crashPid)+'\s+')){$crash[$j]}
     }
    }
   }
  }
  Section '08-graphics.txt' {
   Invoke-DiagnosticAdb @('-s',$device,'logcat','-d','-t','1800','-v','threadtime','-s','EGL_emulation:E','OpenGLRenderer:E','SurfaceFlinger:E','ActivityManager:I') |
    Where-Object {$_ -match 'EGL_BAD|0x3003|drawRenderNode|buffer.*alloc|surface.*fail|com\.eg\.android\.AlipayGphone.*(?:died|crash)|(?:died|crash).*com\.eg\.android\.AlipayGphone'} |
    Select-Object -Last 60
  }
 }
 }finally{
  if($diagnosticPort){Invoke-DiagnosticAdb @('kill-server') | Out-Null}
 }
}
$zip=Join-Path $desktop "支付宝校园跑诊断-$stamp.zip"
Compress-Archive -Path (Join-Path $report '*') -DestinationPath $zip -ErrorAction Stop
Write-Host "诊断 ZIP：$zip"
