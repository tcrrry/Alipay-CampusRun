param([switch]$SmokeTest)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
Add-Type 'using System;using System.Runtime.InteropServices;public class CampusWindowVisible{[DllImport("user32.dll")]public static extern bool ShowWindow(IntPtr h,int command);}' 
$actions=Join-Path $PSScriptRoot 'CampusRunActions.ps1'
$script:jobs=New-Object System.Collections.ArrayList
$form=New-Object System.Windows.Forms.Form
$form.Text='支付宝校园跑'
$form.ClientSize=New-Object System.Drawing.Size(560,550)
$form.StartPosition='CenterScreen'
$form.FormBorderStyle='FixedSingle'
$form.MaximizeBox=$false
$form.Font=New-Object System.Drawing.Font('Microsoft YaHei UI',10)
$title=New-Object System.Windows.Forms.Label
$title.Text='自定义路线与运动参数'
$title.Location=New-Object System.Drawing.Point(24,22)
$title.Size=New-Object System.Drawing.Size(510,32)
$title.Font=New-Object System.Drawing.Font('Microsoft YaHei UI',14,[System.Drawing.FontStyle]::Bold)
$form.Controls.Add($title)
$config=New-Object System.Windows.Forms.Label
$config.Text='配速（每公里）                           步频（步/分钟）'
$config.Location=New-Object System.Drawing.Point(24,64)
$config.Size=New-Object System.Drawing.Size(510,28)
$form.Controls.Add($config)
$paceMinutes=New-Object System.Windows.Forms.NumericUpDown
$paceMinutes.Location=New-Object System.Drawing.Point(24,95);$paceMinutes.Size=New-Object System.Drawing.Size(65,28);$paceMinutes.Minimum=2;$paceMinutes.Maximum=30;$paceMinutes.Value=6
$form.Controls.Add($paceMinutes)
$minuteLabel=New-Object System.Windows.Forms.Label;$minuteLabel.Text='分';$minuteLabel.Location=New-Object System.Drawing.Point(92,98);$minuteLabel.Size=New-Object System.Drawing.Size(25,25);$form.Controls.Add($minuteLabel)
$paceSeconds=New-Object System.Windows.Forms.NumericUpDown
$paceSeconds.Location=New-Object System.Drawing.Point(118,95);$paceSeconds.Size=New-Object System.Drawing.Size(65,28);$paceSeconds.Minimum=0;$paceSeconds.Maximum=59;$paceSeconds.Value=0
$form.Controls.Add($paceSeconds)
$secondLabel=New-Object System.Windows.Forms.Label;$secondLabel.Text='秒 / 公里';$secondLabel.Location=New-Object System.Drawing.Point(185,98);$secondLabel.Size=New-Object System.Drawing.Size(90,25);$form.Controls.Add($secondLabel)
$cadence=New-Object System.Windows.Forms.NumericUpDown
$cadence.Location=New-Object System.Drawing.Point(290,95);$cadence.Size=New-Object System.Drawing.Size(200,28);$cadence.Minimum=40;$cadence.Maximum=300;$cadence.Value=170
$form.Controls.Add($cadence)
$route=New-Object System.Windows.Forms.TextBox
$route.Location=New-Object System.Drawing.Point(24,140);$route.Size=New-Object System.Drawing.Size(268,28);$route.ReadOnly=$true
$form.Controls.Add($route)
$script:mapRoute=$null
$script:savedMapRoute=$null
$routeMemoryPath=Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'AlipayCampusRun\last-map-route.json'
$paceMemoryPath=Join-Path (Split-Path -Parent $routeMemoryPath) 'last-pace-seconds.txt'
$cadenceMemoryPath=Join-Path (Split-Path -Parent $routeMemoryPath) 'last-cadence.txt'
$browse=New-Object System.Windows.Forms.Button
$browse.Text='选择 GPX';$browse.Location=New-Object System.Drawing.Point(422,137);$browse.Size=New-Object System.Drawing.Size(114,32)
$browse.Add_Click({$d=New-Object System.Windows.Forms.OpenFileDialog;$d.Filter='GPX 文件 (*.gpx)|*.gpx';if($d.ShowDialog() -eq 'OK'){$script:mapRoute=$null;$route.Text=$d.FileName};$d.Dispose()})
$form.Controls.Add($browse)
$drawRoute=New-Object System.Windows.Forms.Button
$drawRoute.Text='地图画路线';$drawRoute.Location=New-Object System.Drawing.Point(300,137);$drawRoute.Size=New-Object System.Drawing.Size(114,32)
function InitializeRouteMap {
 if(-not ('CampusRouteMap' -as [type])){
  Add-Type -Path @((Join-Path $PSScriptRoot 'RouteMap.cs'),(Join-Path $PSScriptRoot 'PlaceSearch.cs')) -ReferencedAssemblies 'System.dll','System.Core.dll','System.Drawing.dll','System.Windows.Forms.dll','System.Web.Extensions.dll'
  [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::SystemDefault
 }
}
$drawRoute.Add_Click({
 try {
  InitializeRouteMap
  $editor=New-Object System.Windows.Forms.Form
  try {
   $editor.Text='地图画路线'
   $editor.ClientSize=New-Object System.Drawing.Size(850,610)
   $editor.MinimumSize=New-Object System.Drawing.Size(760,430)
   $editor.StartPosition='CenterParent'
   $editor.Font=$form.Font
   $map=New-Object CampusRouteMap
   $map.Dock='Fill'
   if($script:savedMapRoute){$map.SetPoints($script:savedMapRoute)}
   $editor.Controls.Add($map)
   $toolbar=New-Object System.Windows.Forms.FlowLayoutPanel
   $toolbar.Dock='Top';$toolbar.Height=68;$toolbar.Padding=New-Object System.Windows.Forms.Padding(5,3,0,0)
   $editor.Controls.Add($toolbar)
   $coordinates=New-Object System.Windows.Forms.TextBox
   $coordinates.Width=165;$coordinates.AccessibleName='纬度, 经度';$coordinates.Text='35.0, 105.0'
   $toolbar.Controls.Add($coordinates)
   $jump=New-Object System.Windows.Forms.Button;$jump.Text='定位';$jump.AutoSize=$true
   $jump.Add_Click({
    $values=$coordinates.Text -split '[,，]';$lat=0.0;$lon=0.0
    $style=[Globalization.NumberStyles]::Float;$culture=[Globalization.CultureInfo]::InvariantCulture
    if($values.Count -ne 2 -or ![double]::TryParse($values[0],$style,$culture,[ref]$lat) -or ![double]::TryParse($values[1],$style,$culture,[ref]$lon) -or [double]::IsNaN($lat) -or [double]::IsNaN($lon) -or [math]::Abs($lat) -gt 85 -or [math]::Abs($lon) -gt 180){
     [void][System.Windows.Forms.MessageBox]::Show($editor,'请输入 WGS84 坐标：纬度, 经度，例如 34.75, 113.63。','坐标格式');return
    }
    $map.MoveTo($lat,$lon,17)
   })
   $toolbar.Controls.Add($jump)
   $undo=New-Object System.Windows.Forms.Button;$undo.Text='撤销一点';$undo.AutoSize=$true
   $undo.Add_Click({$map.Undo()});$toolbar.Controls.Add($undo)
   $clear=New-Object System.Windows.Forms.Button;$clear.Text='清空画板';$clear.AutoSize=$true
   $clear.Add_Click({$map.SetPoints($null)});$toolbar.Controls.Add($clear)
   $use=New-Object System.Windows.Forms.Button;$use.Text='闭合并使用';$use.AutoSize=$true
   $use.Enabled=$map.PointCount -ge 3
   $use.Add_Click({$editor.DialogResult='OK'})
   $toolbar.Controls.Add($use)
   $retry=New-Object System.Windows.Forms.Button;$retry.Text='重试底图';$retry.AutoSize=$true
   $retry.Add_Click({$map.RetryTiles()});$toolbar.Controls.Add($retry)
   $toolbar.SetFlowBreak($retry,$true)
   $source=New-Object System.Windows.Forms.ComboBox
   $source.DropDownStyle='DropDownList';$source.Width=170;$source.AccessibleName='底图来源'
   [void]$source.Items.Add('底图：OSM 德国')
   [void]$source.Items.Add('底图：OSM 标准')
   $source.SelectedIndex=0
   $source.Add_SelectedIndexChanged({$map.UseGermanTiles($source.SelectedIndex -eq 0)})
   $toolbar.Controls.Add($source)
   $placeButton=New-Object System.Windows.Forms.Button;$placeButton.Text='搜索地名';$placeButton.AutoSize=$true
   $placeButton.Add_Click({$placeDialog=New-Object CampusPlaceSearch($map);try{[void]$placeDialog.ShowDialog($editor)}finally{$placeDialog.Dispose()}})
   $toolbar.Controls.Add($placeButton)
   $map.Add_RouteChanged({$use.Enabled=$map.PointCount -ge 3})
   $help=New-Object System.Windows.Forms.Label
   $help.Text='滚轮放大 · 右键拖动 · 放大后左键加点 · 底图需要联网      © OpenStreetMap contributors'
   $help.Dock='Bottom';$help.Height=28;$help.TextAlign='MiddleCenter';$editor.Controls.Add($help)
   if($editor.ShowDialog($form) -eq 'OK'){
    $drawn=$map.GetPoints()
    SaveMapRoute -file $routeMemoryPath -mapPoints $drawn
    $script:savedMapRoute=$drawn
    $script:mapRoute=$drawn
    $route.Text="地图路线（$($drawn.Count) 点，已保存）"
   }
  } finally {$editor.Dispose()}
 } catch {[void][System.Windows.Forms.MessageBox]::Show($form,$_.Exception.Message,'无法打开地图')}
})
$form.Controls.Add($drawRoute)
$note=New-Object System.Windows.Forms.Label
$note.Text="1. 选择路线，设置配速和步频，再点击开始。`r`n2. 参数在启动模拟时生效，运行时修改不会实时应用。`r`n3. 要更改参数，请先结束当前跑步并停止，再修改后重新开始。`r`n4. 启动需要等待，身份验证和支付密码请本人操作。"
$note.Location=New-Object System.Drawing.Point(24,180)
$note.Size=New-Object System.Drawing.Size(510,110)
$form.Controls.Add($note)
$status=New-Object System.Windows.Forms.Label
$status.Text='正在检查状态…'
$status.Location=New-Object System.Drawing.Point(24,400)
$status.Size=New-Object System.Drawing.Size(510,56)
$form.Controls.Add($status)
$foot=New-Object System.Windows.Forms.Label
$foot.Text='结束跑步或关闭此窗口后停止模拟。身份验证由本人完成。'
$foot.Location=New-Object System.Drawing.Point(24,490)
$foot.Size=New-Object System.Drawing.Size(510,30)
$foot.ForeColor=[System.Drawing.Color]::DimGray
$foot.Font=New-Object System.Drawing.Font('Microsoft YaHei UI',9)
$form.Controls.Add($foot)
function GetRoutePoints([string]$path,[double[][]]$mapPoints){
   $usingMap=$null -ne $mapPoints
   if($usingMap){
    $nodes=$mapPoints
   } else {
    if(!$path){throw '请先在地图上绘制路线，或选择 GPX 文件。'}
    $settings=New-Object System.Xml.XmlReaderSettings;$settings.DtdProcessing=[System.Xml.DtdProcessing]::Prohibit;$settings.XmlResolver=$null
    $reader=[System.Xml.XmlReader]::Create($path,$settings)
    try {$doc=New-Object System.Xml.XmlDocument;$doc.XmlResolver=$null;$doc.Load($reader)} finally {$reader.Dispose()}
    $segments=@($doc.SelectNodes("//*[local-name()='trkseg' or local-name()='rte']"));if($segments.Count -ne 1){throw '请使用只包含一段轨迹或一条路线的 GPX。'}
    $nodes=@($segments[0].SelectNodes(".//*[local-name()='trkpt' or local-name()='rtept']"));if($nodes.Count -lt 2 -or $nodes.Count -gt 10000){throw '路线必须包含 2 至 10000 个轨迹点。'}
   }
   $points=New-Object System.Collections.ArrayList
   foreach($n in $nodes){$lat=0.0;$lon=0.0;$style=[System.Globalization.NumberStyles]::Float;$culture=[System.Globalization.CultureInfo]::InvariantCulture
    if($usingMap){$lat=[double]$n[0];$lon=[double]$n[1]}
    elseif(![double]::TryParse($n.GetAttribute('lat'),$style,$culture,[ref]$lat) -or ![double]::TryParse($n.GetAttribute('lon'),$style,$culture,[ref]$lon)){throw 'GPX 存在无效坐标。'}
    if([double]::IsNaN($lat) -or [double]::IsInfinity($lat) -or [double]::IsNaN($lon) -or [double]::IsInfinity($lon) -or [math]::Abs($lat) -gt 90 -or [math]::Abs($lon) -gt 180){throw '路线存在无效坐标。'}
    if($points.Count -gt 0 -and $points[$points.Count-1][0] -eq $lat -and $points[$points.Count-1][1] -eq $lon){continue}
    if($points.Count -gt 0){
     $previous=$points[$points.Count-1];$dy=($lat-$previous[0])*111320;$dx=($lon-$previous[1])*111320*[math]::Cos(($lat+$previous[0])*[math]::PI/360)
     if([math]::Sqrt($dx*$dx+$dy*$dy) -lt 0.02){throw '路线中有间距小于 2 厘米的相邻点，请简化路线后重试。'}
    }
    [void]$points.Add(@($lat,$lon))
   }
   if($points.Count -lt 2){throw '路线有效点不足。'}
   $first=$points[0];$last=$points[$points.Count-1];$dy=($first[0]-$last[0])*111320;$dx=($first[1]-$last[1])*111320*[math]::Cos($first[0]*[math]::PI/180)
   $gap=[math]::Sqrt($dx*$dx+$dy*$dy)
   if($usingMap){
    if($points.Count -lt 3){throw '地图路线至少需要三个有效点。'}
    if($gap -ge 0.02){[void]$points.Add($first)}
    elseif($gap -gt 0){$points[$points.Count-1]=$first}
   } elseif($gap -gt 20){throw '路线首尾相距超过 20 米，请使用闭合路线，避免循环时位置跳跃。'}
   return ,($points.ToArray())
}
function SaveMapRoute([string]$file,[double[][]]$mapPoints){
 [void](GetRoutePoints -mapPoints $mapPoints)
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($file))
 $temporary="$file.$([guid]::NewGuid().ToString('N')).tmp"
 try {
  $json=@{points=$mapPoints}|ConvertTo-Json -Depth 4 -Compress
  [IO.File]::WriteAllText($temporary,$json,(New-Object Text.UTF8Encoding($false)))
  if([IO.File]::Exists($file)){[IO.File]::Replace($temporary,$file,[NullString]::Value)}
  else {[IO.File]::Move($temporary,$file)}
 } finally {[IO.File]::Delete($temporary)}
}
function ReadMapRoute([string]$file){
 $saved=[IO.File]::ReadAllText($file)|ConvertFrom-Json
 if($saved.points.Count -lt 3 -or $saved.points.Count -gt 9999){throw '已保存路线的点数无效。'}
 foreach($point in $saved.points){if($point.Count -ne 2 -or $null -eq $point[0] -or $null -eq $point[1]){throw '已保存路线的坐标无效。'}}
 $restored=[double[][]]$saved.points
 [void](GetRoutePoints -mapPoints $restored)
 return ,$restored
}
function ReadSavedNumber([string]$path,[int]$default,[int]$minimum,[int]$maximum){
 if(![IO.File]::Exists($path)){return $default}
 $value=0
 if([int]::TryParse([IO.File]::ReadAllText($path),[ref]$value) -and $value -ge $minimum -and $value -le $maximum){return $value}
 return $default
}
function SaveNumber([string]$path,[int]$value){
 [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
 $temporary=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 try {
  [IO.File]::WriteAllText($temporary,$value.ToString([Globalization.CultureInfo]::InvariantCulture))
  if([IO.File]::Exists($path)){[IO.File]::Replace($temporary,$path,[NullString]::Value)}
  else{[IO.File]::Move($temporary,$path)}
 }finally{[IO.File]::Delete($temporary)}
}
function SavePace {
 $total=[int]$paceMinutes.Value*60+[int]$paceSeconds.Value
 if($total -le 1800){
  try {SaveNumber $paceMemoryPath $total}
  catch {$status.Text='配速未能保存，请检查本机用户目录的写入权限。'}
 }
}
function OpenIriun {
 $roots=@($env:ProgramFiles,${env:ProgramFiles(x86)},(Join-Path $env:LOCALAPPDATA 'Programs'))
 $registryPaths=@('HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*')
 $folders=@(Get-ItemProperty $registryPaths -ErrorAction SilentlyContinue |
  Where-Object {$_.DisplayName -like 'Iriun Webcam*' -and $_.InstallLocation} |
  ForEach-Object {$_.InstallLocation.Trim('"')})
 $folders+=@($roots | Where-Object {$_} | ForEach-Object {Join-Path $_ 'Iriun Webcam'})
 foreach($folder in $folders){
  foreach($name in 'IriunWebcam.exe','webcam.exe'){
   $exe=Join-Path $folder $name
   if(Test-Path -LiteralPath $exe -PathType Leaf){Start-Process -FilePath $exe;return}
  }
 }
 Start-Process 'https://iriun.com/'
 $status.Text='已打开 Iriun 官网。请安装 Windows 端和手机端，然后连接手机摄像头。'
}
function LaunchAction([string]$name){
 if($name -eq 'RecoverAlipay' -and @($script:jobs | Where-Object {$_.CampusAction -notin @('Status','Watch') -and $_.State -in @('Running','NotStarted')}).Count){
  $status.Text='请先等待当前操作结束。完成后可点击黑屏重开。'
  return
 }
 if($name -in @('Start','RecoverAlipay')){
  try {
   $points=GetRoutePoints -path $route.Text -mapPoints $script:mapRoute
   if($paceMinutes.Value -eq 30 -and $paceSeconds.Value -gt 0){throw '配速范围为每公里 2 分至 30 分。'}
   $seconds=[double]$paceMinutes.Value*60+[double]$paceSeconds.Value
   $payload=@{speed_kmh=3600.0/$seconds;cadence=[int]$cadence.Value;route=$points}|ConvertTo-Json -Depth 5 -Compress
   [IO.File]::WriteAllText((Join-Path $env:TEMP 'campus-run-config.json'),$payload,(New-Object Text.UTF8Encoding($false)))
  } catch {[System.Windows.Forms.MessageBox]::Show($_.Exception.Message,'路线配置错误')|Out-Null;return}
 }

 if($name -in @('Start','Stop','RecoverAlipay')){
  foreach($job in @($script:jobs)){if($job.CampusAction -in @('Start','Watch')){Stop-Job $job -ErrorAction SilentlyContinue;Remove-Job $job -Force -ErrorAction SilentlyContinue;[void]$script:jobs.Remove($job)}}
 }
 if($name -in @('Start','Stop','RecoverAlipay')){$start.Enabled=$false;$stop.Enabled=$false}
 # -FilePath runs the file contents as a scriptblock, losing PSScriptRoot in Windows PowerShell 5.1.
 # Invoke the actual file inside the job so helper paths resolve against its own directory.
 $job=Start-Job -ScriptBlock {
  param($entryPath,$actionName)
  & $entryPath -Action $actionName
 } -ArgumentList $actions,$name
 $job | Add-Member NoteProperty CampusAction $name
 [void]$script:jobs.Add($job)
}
$start=New-Object System.Windows.Forms.Button
$start.Text='开始模拟并打开支付宝'
$start.Location=New-Object System.Drawing.Point(24,320)
$start.Size=New-Object System.Drawing.Size(300,52)
$start.BackColor=[System.Drawing.Color]::FromArgb(22,119,255)
$start.ForeColor=[System.Drawing.Color]::White
$start.FlatStyle='Flat'
$start.Add_Click({LaunchAction 'Start'})
$form.Controls.Add($start)
$stop=New-Object System.Windows.Forms.Button
$stop.Text='停止模拟'
$stop.Location=New-Object System.Drawing.Point(338,320)
$stop.Size=New-Object System.Drawing.Size(198,52)
$stop.Add_Click({LaunchAction 'Stop'})
$form.Controls.Add($stop)
$supportButtons=@(
 @{Text='WSA 设置';X=24;Click={try{Start-Process 'wsa-settings:'}catch{$status.Text='无法打开 WSA 设置，请确认 01 已安装完成。'}}},
 @{Text='黑屏重开支付宝';X=198;Click={LaunchAction 'RecoverAlipay'}},
 @{Text='Iriun 手机摄像头';X=372;Click={try{OpenIriun}catch{$status.Text='无法打开 Iriun，请从 iriun.com 安装后重试。'}}}
)
foreach($entry in $supportButtons){
 $button=New-Object System.Windows.Forms.Button
 $button.Text=$entry.Text
 $button.Location=New-Object System.Drawing.Point($entry.X,458)
 $button.Size=New-Object System.Drawing.Size(164,28)
 $button.Add_Click($entry.Click)
 $form.Controls.Add($button)
}
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=500
$timer.Add_Tick({
 foreach($job in @($script:jobs)){
  foreach($result in @(Receive-Job $job -ErrorAction SilentlyContinue)){
   if($result.Message){$status.Text=$result.Message;if($result.State -eq 'Running'){$start.Enabled=$false;$stop.Enabled=$true;if($job.CampusAction -eq 'Status'){LaunchAction 'Watch'}elseif($job.CampusAction -in @('Start','RecoverAlipay')){$job.CampusAction='Watch'}}elseif($result.State -eq 'Starting'){$start.Enabled=$false;$stop.Enabled=$false}else{$start.Enabled=$true;$stop.Enabled=$true}}
  }
  if($job.State -in @('Completed','Failed','Stopped')){
   if($job.State -eq 'Failed'){$status.Text='控制任务失败，请关闭并重开此窗口。';$start.Enabled=$true;$stop.Enabled=$true}
   Remove-Job $job -Force -ErrorAction SilentlyContinue
   [void]$script:jobs.Remove($job)
  }
 }
})
$form.Add_Shown({[void][CampusWindowVisible]::ShowWindow($form.Handle,5);$form.Activate();LaunchAction 'Status';$timer.Start()})
$form.Add_FormClosing({
 $timer.Stop()
 foreach($job in @($script:jobs)){Stop-Job $job -ErrorAction SilentlyContinue;Remove-Job $job -Force -ErrorAction SilentlyContinue}
 & $actions -Action Stop | Out-Null
})
if($SmokeTest){
 try {
  if($PSVersionTable.PSEdition -eq 'Desktop'){
   InitializeRouteMap
   $mapSmoke=New-Object CampusRouteMap
   try {
    $mapSmoke.SetPoints([double[][]]@(@(34.75,113.63),@(34.7503,113.63),@(34.7503,113.6303)))
    $sample=GetRoutePoints -mapPoints ($mapSmoke.GetPoints())
    $sampleJson=@{route=$sample}|ConvertTo-Json -Depth 5 -Compress|ConvertFrom-Json
    if($sampleJson.route.Count -ne 4 -or $sampleJson.route[3][0] -ne $sampleJson.route[0][0] -or $sampleJson.route[3][1] -ne $sampleJson.route[0][1]){throw '地图路线闭合检查失败。'}
    $memoryTest=Join-Path ([IO.Path]::GetTempPath()) ("CampusRun-RouteTest-$([guid]::NewGuid()).json")
    try {
     SaveMapRoute -file $memoryTest -mapPoints ($mapSmoke.GetPoints())
     SaveMapRoute -file $memoryTest -mapPoints ($mapSmoke.GetPoints())
     $restored=ReadMapRoute -file $memoryTest
     if($restored.Count -ne 3 -or $restored[2][1] -ne 113.6303){throw '地图路线保存和恢复检查失败。'}
     'MAP_MEMORY_OK'
    } finally {[IO.File]::Delete($memoryTest)}
   } finally {$mapSmoke.Dispose()}
   'MAP_SMOKE_OK'
  }
  'GUI_SMOKE_OK'
 } finally {$timer.Dispose();$form.Dispose()}
 exit
}
try {
 $savedPace=ReadSavedNumber $paceMemoryPath 360 120 1800
 $paceMinutes.Value=[math]::Floor($savedPace/60)
 $paceSeconds.Value=$savedPace%60
} catch {}
try {$cadence.Value=ReadSavedNumber $cadenceMemoryPath 170 40 300} catch {}
$paceMinutes.Add_ValueChanged({SavePace})
$paceSeconds.Add_ValueChanged({SavePace})
$cadence.Add_ValueChanged({
 try {SaveNumber $cadenceMemoryPath ([int]$cadence.Value)}
 catch {$status.Text='步频未能保存。请检查本机用户目录的写入权限。'}
})
if([IO.File]::Exists($routeMemoryPath)){
 try {
  $script:savedMapRoute=ReadMapRoute -file $routeMemoryPath
  $script:mapRoute=$script:savedMapRoute
  $route.Text="地图路线（$($script:mapRoute.Count) 点，已恢复）"
 } catch {$route.Text='';$note.Text="上次保存的路线无法读取，请重新绘制或选择 GPX。`r`n$($note.Text)"}
}
try{[void]$form.ShowDialog()}finally{$timer.Dispose();$form.Dispose()}
