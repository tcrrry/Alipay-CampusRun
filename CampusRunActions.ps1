param([ValidateSet('Start','Stop','Status','Watch','OpenAlipay','RecoverAlipay')][string]$Action='Status',[switch]$Once)
$ErrorActionPreference='Stop'
$adb=Join-Path $PSScriptRoot 'platform-tools\adb.exe'
. (Join-Path $PSScriptRoot 'Local-Settings.ps1')
$wsa=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\WsaClient.exe'
function Report([string]$message,[string]$state){[pscustomobject]@{Message=$message;State=$state}}
function InvokeAdb([string[]]$AdbArguments,[switch]$AllowFailure){
 $ErrorActionPreference='Continue'
 $output=& $adb @AdbArguments 2>$null
 if($LASTEXITCODE -ne 0 -and !$AllowFailure){throw '连接操作失败，请重连 WSA 后重试。'}
 return $output
}
function IsConnected {return [bool]((InvokeAdb @('devices')) -match ('^'+[regex]::Escape($device)+'\s+device$'))}
function IsUnauthorized {return [bool]((InvokeAdb @('devices') -AllowFailure) -match ('^'+[regex]::Escape($device)+'\s+unauthorized(?:\s|$)'))}
function IsRunning {return [bool]((InvokeAdb @('-s',$device,'shell','content','call','--uri','content://lab.campus.sim.state','--method','state')) -match 'enabled=true')}
function InvokeRoot([string]$Command,[switch]$AllowFailure){
 if(!$script:rootExecutable){
  $candidate=(InvokeAdb @('-s',$device,'shell','command -v su') -AllowFailure | Out-String).Trim()
  if($candidate -match '^/[A-Za-z0-9_./-]+$'){$script:rootExecutable=$candidate}
  else{
   $candidate=(InvokeAdb @('-s',$device,'shell','ls','/debug_ramdisk/su') -AllowFailure | Out-String).Trim()
   if($candidate -eq '/debug_ramdisk/su'){$script:rootExecutable=$candidate}else{throw '未找到 Root 命令，请检查 Magisk 是否正常运行。'}
  }
 }
 InvokeAdb @('-s',$device,'shell',$script:rootExecutable,'-c',$Command) -AllowFailure:$AllowFailure
}
function CheckFramework {
 InvokeAdb @('-s',$device,'push',(Join-Path $PSScriptRoot 'campus-preflight.sh'),'/data/local/tmp/campus-preflight.sh') | Out-Null
 $check=(InvokeRoot 'sh /data/local/tmp/campus-preflight.sh' -AllowFailure | Out-String)
 if($check -match 'ZYGISK_DISABLED'){throw 'Zygisk 已关闭。请在 Magisk 启用 Zygisk 并重启 WSA，再点击开始。'}
 if($check -match 'VECTOR_DISABLED'){throw 'Vector 已被禁用或标记卸载。请在 Magisk 恢复 Vector 并重启 WSA，再点击开始。'}
 if($check -notmatch 'FRAMEWORK_CONFIG_OK'){throw '框架检查未通过，请检查 Root、Vector 和校园跑模块是否仍已安装。'}
}
function HasLiveModule {
 $appProcess=((InvokeAdb @('-s',$device,'shell','pidof','com.eg.android.AlipayGphone') -AllowFailure | Out-String).Trim() -split '\s+')[0]
 if($appProcess -notmatch '^\d+$'){return $false}
 $events=InvokeAdb @('-s',$device,'logcat','-d','-t','500','--pid',$appProcess,'-s','CadenceDiagnostic:I') -AllowFailure
 return [bool]($events -match 'motion event state:')
}
function StopSimulation {
 if(!(IsConnected)){InvokeAdb @('connect',$device) -AllowFailure | Out-Null;if(!(IsConnected)){throw 'WSA 无法连接，未能确认停止。请关闭 WSA，或重连后点击停止。'}}
 if(IsConnected){InvokeRoot 'am stopservice -n lab.campus.sim/.RouteService' -AllowFailure | Out-Null;InvokeAdb @('-s',$device,'shell','content','call','--uri','content://lab.campus.sim.state','--method','stop') | Out-Null;if(IsRunning){throw '模拟尚未停止，请重试。'}}
}
function RestoreDisplaySettings {
 # Keep each monitor's native metrics. A global phone-size override clips desktop-positioned windows.
 $displays=InvokeAdb @('-s',$device,'shell','dumpsys','window','displays')
 $displayIds=@(0)
 foreach($line in $displays){if($line -match 'Display: mDisplayId=(\d+)'){$displayIds+=[int]$Matches[1]}}
 foreach($displayId in @($displayIds | Select-Object -Unique)){
  $size=InvokeAdb @('-s',$device,'shell','wm','size','-d',"$displayId")
  $density=InvokeAdb @('-s',$device,'shell','wm','density','-d',"$displayId")
  if($size -match 'Override size:'){InvokeAdb @('-s',$device,'shell','wm','size','reset','-d',"$displayId") | Out-Null}
  if($density -match 'Override density:'){InvokeAdb @('-s',$device,'shell','wm','density','reset','-d',"$displayId") | Out-Null}
  $metrics=@(InvokeAdb @('-s',$device,'shell','wm','size','-d',"$displayId")) + @(InvokeAdb @('-s',$device,'shell','wm','density','-d',"$displayId"))
  if($metrics -match 'Override (size|density):'){throw '显示区域仍存在强制缩放，请稍后重试显示修复。'}
 }
}
function OpenAlipay {
 if(IsConnected){RestoreDisplaySettings}
 Start-Process -FilePath $wsa -ArgumentList '/launch wsa://com.eg.android.AlipayGphone' -WindowStyle Hidden
}
function LastRunEnd {return (@(InvokeAdb @('-s',$device,'logcat','-d','-t','400','-s','CadenceDiagnostic:I')) | Where-Object {$_ -match 'native API: stopSportDetect$'} | Select-Object -Last 1)}
function LastSportEvent {return (@(InvokeAdb @('-s',$device,'logcat','-d','-t','2500','-s','CadenceDiagnostic:I')) | Where-Object {$_ -match 'native API: (start|stop)SportDetect$'} | Select-Object -Last 1)}
function ConnectWsa {
 if(!(IsConnected)){
  Start-Process -FilePath $wsa -ArgumentList '/launch wsa://system' -WindowStyle Hidden
  $ready=$false
  $deadline=[DateTime]::UtcNow.AddMinutes(3)
  $unauthorizedSince=$null;$noticeShown=$false;$retriedUnauthorized=$false
  while([DateTime]::UtcNow -lt $deadline){
   InvokeAdb @('connect',$device) -AllowFailure | Out-Null
   if(IsConnected){$ready=$true;break}
   if(IsUnauthorized){
    if(!$unauthorizedSince){$unauthorizedSince=[DateTime]::UtcNow}
    if(!$noticeShown){
     $noticeShown=$true
     Report '等待 ADB 授权。若没有 Allow，在 WSA 高级设置打开 Manage developer settings，关开 USB 调试。' 'Starting'
     try {Start-Process 'wsa-settings:'} catch {}
    }
    if(!$retriedUnauthorized -and ([DateTime]::UtcNow-$unauthorizedSince).TotalSeconds -ge 20){
     $retriedUnauthorized=$true
     Report '正在重新连接调试通道，请留意安卓授权弹窗；如果仍未出现，请按教程关闭再开启 USB 调试。' 'Starting'
     InvokeAdb @('disconnect',$device) -AllowFailure | Out-Null
    }
   }else{$unauthorizedSince=$null}
   Start-Sleep -Seconds 2
  }
  if(!$ready){if(IsUnauthorized){throw 'WSA 调试仍未授权。请按教程第 10-12 页关闭再开启 USB 调试，允许电脑调试后，返回 02 重新点击开始。'};throw 'WSA 连接失败，请确认 WSA 开发人员模式已开启，打开 WSA 的文件并等待启动后重试。'}
 }
 for($attempt=0;$attempt -lt 30;$attempt++){
  if((InvokeAdb @('-s',$device,'shell','getprop','sys.boot_completed') -AllowFailure) -match '^1$'){return}
  Start-Sleep -Seconds 2
 }
 throw 'WSA 尚未完成启动，请稍后再点击开始。'
}
function FreshWsaSession {
 StopSimulation
 $shutdown=Start-Process -FilePath $wsa -ArgumentList '/shutdown' -WindowStyle Hidden -PassThru
 try{if(!$shutdown.WaitForExit(20000)){throw 'WSA 关闭超时，未强制结束进程，请稍后重试。'}}finally{$shutdown.Dispose()}
 $closed=$false
 for($attempt=0;$attempt -lt 15;$attempt++){if(!(IsConnected)){$closed=$true;break};Start-Sleep -Seconds 1}
 if(!$closed){throw 'WSA 仍在运行，未能清理旧图形会话。'}
 $script:rootExecutable=$null
 ConnectWsa
}
function LastGraphicsError {
 return (@(InvokeAdb @('-s',$device,'logcat','-d','-t','500','-s','EGL_emulation:E','OpenGLRenderer:F')) | Where-Object {$_ -match 'EGL_BAD_ALLOC|error 0x3003|drawRenderNode called on a context with no surface'} | Select-Object -Last 1)
}
function WatchRun($baseline){
 $graphicsBaseline=LastGraphicsError
 while($true){
  Start-Sleep -Seconds 3
  if(!(IsConnected)){Report 'WSA 已断开，当前状态无法确认；重连后请先检查或停止模拟。' 'Disconnected';return}
  if(!(IsRunning)){Report '模拟已停止。' 'Stopped';return}
  $latest=LastRunEnd
  if($latest -and $latest -ne $baseline){StopSimulation;Report '检测到跑步结束，已自动停止模拟。' 'Stopped';return}
  $graphicsError=LastGraphicsError
  if($graphicsError -and $graphicsError -ne $graphicsBaseline){
   $graphicsBaseline=$graphicsError
   Report '检测到图形异常。请结束当前跑步后点击黑屏重开支付宝。' 'GraphicsError'
  }
 }
}
try {
 switch($Action){
  'Status' {if(!(IsConnected)){Report 'WSA 尚未连接，点击开始可自动连接。' 'Offline'}elseif(IsRunning){CheckFramework;if(HasLiveModule){Report '模拟正在运行，支付宝模块已加载。' 'Running'}else{Report '模拟服务已运行，但尚未确认支付宝模块。请点击开始进行检查。' 'Unchecked'}}else{Report '模拟已停止。' 'Stopped'};return}
  'Stop' {StopSimulation;Report '模拟已停止。' 'Stopped';return}
  'Watch' {WatchRun (LastRunEnd);return}
  'OpenAlipay' {OpenAlipay;Report '已打开支付宝。' 'Info';return}
 }
 $recover=$Action -eq 'RecoverAlipay'
 Report '正在连接 WSA…' 'Starting'
 ConnectWsa
 $sportEvent=LastSportEvent
 if($sportEvent -match 'native API: startSportDetect$'){
  $script:preserveExistingRun=$true
  if(!(IsRunning)){throw '检测到校园跑正在计时，但模拟服务已停止；请先结束本次跑步再修复。'}
  Report '检测到校园跑正在计时，保留当前会话，不执行重启。' 'Running'
  if(!$Once){WatchRun (LastRunEnd)}
  return
 }
 $resumeSimulation=$recover -and (IsRunning)
 if($resumeSimulation){
  CheckFramework
  $baseline=LastRunEnd
 }else{
  Report '正在准备框架和定位服务…' 'Starting'
  InvokeAdb @('-s',$device,'push',(Join-Path $PSScriptRoot 'campus-prepare.sh'),'/data/local/tmp/campus-prepare.sh') | Out-Null
  $prepared=InvokeRoot 'sh /data/local/tmp/campus-prepare.sh'
  if($prepared -notmatch 'FRAMEWORK_(READY|RESTORED)'){throw '校园跑框架准备失败，请检查 Magisk 和 Vector。'}
  if($prepared -match 'FRAMEWORK_RESTORED'){FreshWsaSession}
  Report '正在检查框架和运动权限…' 'Starting'
  CheckFramework
  InvokeAdb @('-s',$device,'shell','cmd','appops','set','lab.campus.sim','android:mock_location','allow') | Out-Null
  $mockLocationStatus=InvokeAdb @('-s',$device,'shell','cmd','appops','get','lab.campus.sim','android:mock_location')
  if(!($mockLocationStatus -match '^MOCK_LOCATION:\s+allow(?:;|\s|$)')){throw '路线定位权限未生效，请重新运行 01 安装并查看提示。'}
  InvokeAdb @('-s',$device,'shell','pm','grant','com.eg.android.AlipayGphone','android.permission.ACTIVITY_RECOGNITION') | Out-Null
  InvokeAdb @('-s',$device,'shell','cmd','appops','set','com.eg.android.AlipayGphone','ACTIVITY_RECOGNITION','allow') | Out-Null
  $baseline=LastRunEnd
  $configPath=Join-Path $env:TEMP 'campus-run-config.json'
  if(!(Test-Path -LiteralPath $configPath)){throw '未找到路线配置，请先在控制窗口绘制地图路线或选择 GPX。'}
  InvokeAdb @('-s',$device,'push',$configPath,'/data/local/tmp/campus-run-config.json') | Out-Null
  InvokeAdb @('-s',$device,'shell','chmod','644','/data/local/tmp/campus-run-config.json') | Out-Null
  $script:simulationStartedByThisAction=$true
  InvokeRoot 'am start-foreground-service -n lab.campus.sim/.RouteService' | Out-Null
  Start-Sleep -Milliseconds 500
  if(!(IsRunning)){throw '模拟未能启动，请打开原控制程序查看提示。'}
 }
 Report '正在打开支付宝并检查模拟定位…' 'Starting'
 InvokeAdb @('-s',$device,'shell','am','force-stop','com.eg.android.AlipayGphone') | Out-Null
 OpenAlipay
 InvokeAdb @('-s',$device,'shell','am','broadcast','-a','lab.campus.sim.HIDE_PANEL','-p','lab.campus.sim') -AllowFailure | Out-Null
 Report '正在确认支付宝模块已加载…' 'Starting'
 $moduleReady=$false
 for($attempt=0;$attempt -lt 60;$attempt++){
  if(HasLiveModule){$moduleReady=$true;break}
  Start-Sleep -Seconds 1
 }
 if(!$moduleReady){throw '支付宝模块未确认加载。可重试黑屏重开；如果仍失败，请检查 Vector 作用域是否包含支付宝。'}
 if(!(IsRunning)){throw '模拟服务已停止，请重新点击开始。'}
 Report '已就绪：支付宝模块已加载，显示和运动权限已配置。进入校园跑，按提示验证后开始。' 'Running'
 if($Once){return}
 WatchRun $baseline
}catch{
 if($script:simulationStartedByThisAction -and !$script:preserveExistingRun){try{StopSimulation}catch{}}
 Report $_.Exception.Message 'Error'
}
