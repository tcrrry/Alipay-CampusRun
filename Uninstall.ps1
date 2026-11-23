param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
$root=Join-Path $env:LOCALAPPDATA 'CampusRun-WSA'
$expected=Join-Path $root 'WSA_2407.40000.4.0_x64'
$marker=Join-Path $root 'campusrun-owner.json'
$name='MicrosoftCorporationII.WindowsSubsystemForAndroid'
function GetPackageUserSid($userInformation) {
 $identity=$userInformation.UserSecurityId
 if($identity -is [string]){return $identity}
 if($identity -is [Security.Principal.SecurityIdentifier]){return $identity.Value}
 return [string]$identity.Sid
}
function Get-ExtractedPackageDirectory {
 $folder=Get-Item -LiteralPath $PSScriptRoot -Force
 if($folder.Name -notin @('支付宝校园跑','CampusRun-自定义测试版')){throw '解压目录名称与原 ZIP 不一致，已保留目录。'}
 for($parent=$folder;$parent;$parent=$parent.Parent){
  if($parent.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '解压路径包含链接，已保留目录。'}
 }
 $known=@('SHA256SUMS.txt')
 $required=@('Setup.ps1','Uninstall.ps1','platform-tools/adb.exe','packages/WSA-Magisk-verified.7z')
 foreach($line in Get-Content -LiteralPath (Join-Path $folder.FullName 'SHA256SUMS.txt') -Encoding UTF8){
  if($line -notmatch '^[a-f0-9]{64}  (.+)$'){throw '无法识别包内文件清单，已保留目录。'}
  $entry=$Matches[1].Replace('\','/')
  if([IO.Path]::IsPathRooted($entry) -or $entry -match '(?:^|/)\.\.(?:/|$)' -or $entry -like '*.zip' -and $entry -notlike 'packages/*'){
   throw '包内文件清单含不安全的路径，已保留目录。'
  }
  $known+=$entry
 }
 foreach($entry in $required){
  if($entry -notin $known -or !(Test-Path -LiteralPath (Join-Path $folder.FullName $entry) -PathType Leaf)){
   throw '解压目录不完整，已保留目录。'
  }
 }
 $prefix=$folder.FullName+'\'
 $pending=New-Object 'System.Collections.Generic.Stack[System.IO.DirectoryInfo]'
 $pending.Push($folder)
 while($pending.Count){
  foreach($item in Get-ChildItem -LiteralPath ($pending.Pop().FullName) -Force){
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '解压目录包含链接，已保留目录。'}
   $relative=$item.FullName.Substring($prefix.Length).Replace('\','/')
   if($item.PSIsContainer){
    if(!($known | Where-Object {$_.StartsWith($relative+'/',[StringComparison]::OrdinalIgnoreCase)} | Select-Object -First 1)){
     throw "解压目录有额外文件夹：$relative。请移到外面再重试。"
    }
    $pending.Push($item)
   }elseif($relative -notin $known){
    throw "解压目录有额外文件：$relative。请移到外面再重试。"
   }
  }
 }
 return $folder.FullName
}
try {
 $packageDirectory=Get-ExtractedPackageDirectory
 Set-Location -LiteralPath $env:TEMP
 $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
 $installed=Get-AppxPackage -Name $name
 if($installed -and $installed.InstallLocation -ne $expected){throw '当前 WSA 不是本安装器安装的版本，已停止卸载。'}
 if($installed -or (Test-Path -LiteralPath $root)){
  if(!(Test-Path -LiteralPath $marker -PathType Leaf)){throw '没有找到本安装器的归属标记，已停止卸载。'}
  $owner=Get-Content -Raw -Encoding UTF8 -LiteralPath $marker | ConvertFrom-Json
  if($owner.OwnerSid -ne $sid -or $owner.InstallLocation -ne $expected -or $owner.PackageName -ne $name){throw '安装归属信息不匹配，已停止卸载。'}
  $item=Get-Item -LiteralPath $root -Force
  if($item.FullName -ne $root -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'WSA 安装路径异常，已停止卸载。'}
 }
 if($CheckOnly){Write-Host 'UNINSTALL_CHECK_OK';return}
 $message="卸载会关闭并移除本包安装的 WSA，安卓应用、登录状态和数据可能丢失。`r`n同时删除这个解压目录，保留外部的 ZIP：`r`n$packageDirectory`r`n`r`n确定继续吗？"
 if([Windows.Forms.MessageBox]::Show($message,'确认卸载',[Windows.Forms.MessageBoxButtons]::YesNo,[Windows.Forms.MessageBoxIcon]::Warning) -ne [Windows.Forms.DialogResult]::Yes){Write-Host '已取消。';return}
 $principal=New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
 if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw '请右键卸载入口，选择“以管理员身份运行”，然后确认 UAC。请使用安装时的同一 Windows 账户。'}
 $all=@(Get-AppxPackage -AllUsers -Name $name -ErrorAction Stop)
 foreach($pkg in $all){
  if($pkg.InstallLocation -and $pkg.InstallLocation -ne $expected){throw '检测到不同目录的 WSA，已停止卸载。'}
  foreach($u in @($pkg.PackageUserInformation)){
   if($null -eq $u -or $u.InstallState.ToString() -ne 'Installed'){continue}
   $registeredSid=GetPackageUserSid $u
   if($registeredSid -notmatch '^S-\d+(?:-\d+)+$'){throw '无法确认 WSA 的注册用户，已停止卸载。'}
   if($registeredSid -ne $sid){throw '其他 Windows 用户也注册了 WSA，已停止卸载以保护其数据。'}
  }
 }
 if($installed){
  $wsa=Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\WsaClient.exe'
  if(Test-Path -LiteralPath $wsa){$proc=Start-Process -FilePath $wsa -ArgumentList '/shutdown' -WindowStyle Hidden -Wait -PassThru;if($proc.ExitCode -ne 0){throw 'WSA 未能关闭，请先手动关闭后重试。'}}
  Remove-AppxPackage -Package $installed.PackageFullName -ErrorAction Stop
 }
 if(Get-AppxPackage -Name $name){throw 'WSA 仍处于注册状态，未删除安装目录。'}
 $remaining=@(Get-AppxPackage -AllUsers -Name $name -ErrorAction Stop | Where-Object {$_.PackageUserInformation.InstallState -contains 'Installed'})
 if($remaining.Count){throw '其他用户仍有 WSA，未删除安装目录。'}
 if(Test-Path -LiteralPath $root){
  $links=@(Get-ChildItem -LiteralPath $root -Force -Recurse -Attributes ReparsePoint -ErrorAction Stop)
  if($links.Count){throw '安装目录含链接，未自动删除目录，请人工检查。'}
  Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
 }
 foreach($shortcutName in '支付宝校园跑.lnk','校园跑控制（自定义版）.lnk'){
  $shortcut=Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) $shortcutName
  if(Test-Path -LiteralPath $shortcut){
   $target=(New-Object -ComObject WScript.Shell).CreateShortcut($shortcut).TargetPath
   if($target -eq (Join-Path $PSScriptRoot '02-装好后启动.cmd')){Remove-Item -LiteralPath $shortcut -Force}
  }
 }
 $adbPath=Join-Path $packageDirectory 'platform-tools\adb.exe'
 Get-CimInstance Win32_Process -Filter "Name='adb.exe'" | Where-Object ExecutablePath -EQ $adbPath |
  ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction Stop }
 $verifiedDirectory=Get-ExtractedPackageDirectory
 if($verifiedDirectory -ne $packageDirectory){throw '解压路径发生变化，已保留目录。'}
 Remove-Item -LiteralPath $verifiedDirectory -Recurse -Force -ErrorAction Stop
 if(Test-Path -LiteralPath $verifiedDirectory){throw '解压目录仍在使用。关闭相关窗口后重试。'}
 [Windows.Forms.MessageBox]::Show('卸载完成，已清理解压目录。原 ZIP 可用于重新安装。','卸载完成')|Out-Null
}catch{[Windows.Forms.MessageBox]::Show($_.Exception.Message,'卸载未完成',[Windows.Forms.MessageBoxButtons]::OK,[Windows.Forms.MessageBoxIcon]::Error)|Out-Null;exit 1}
