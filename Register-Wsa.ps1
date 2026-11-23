param([Parameter(Mandatory=$true)][string]$ExpectedUserSid,[Parameter(Mandatory=$true)][string]$ResultFile)
$ErrorActionPreference='Stop'
try {
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 if($identity.User.Value -ne $ExpectedUserSid){throw 'UAC 使用了另一位 Windows 用户。请让管理员在实际使用 WSA 的账户下处理安装权限，避免注册到错误账户。'}
 $principal=New-Object Security.Principal.WindowsPrincipal($identity)
 if(!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw '注册 WSA 需要管理员权限，请确认 UAC 提示。'}
 $wsaFolder=Join-Path $env:LOCALAPPDATA 'CampusRun-WSA\WSA_2407.40000.4.0_x64'
 $manifest=Join-Path $wsaFolder 'AppxManifest.xml'
 $xml=[xml](Get-Content -Raw -LiteralPath $manifest)
 $wsaName='MicrosoftCorporationII.WindowsSubsystemForAndroid'
 if($xml.Package.Identity.Name -ne $wsaName -or $xml.Package.Identity.Version -ne '2407.40000.4.0' -or $xml.Package.Identity.ProcessorArchitecture -ne 'x64'){throw '解压后的 WSA 清单与本安装包不符。'}
 $existing=Get-AppxPackage -Name $wsaName
 if($existing){
  if($existing.InstallLocation -ne $wsaFolder -or $existing.Version.ToString() -ne '2407.40000.4.0'){throw '检测到另一套 WSA，安装器不会覆盖它。'}
 }else{
  foreach($dep in $xml.Package.Dependencies.PackageDependency){
   $installed=Get-AppxPackage -Name $dep.Name | Where-Object {($_.Architecture.ToString() -in @('X64','Neutral')) -and $_.Version -ge [version]$dep.MinVersion}
   if(!$installed){Add-AppxPackage -Path (Join-Path $wsaFolder ($dep.Name+'_x64.appx'))}
  }
  Add-AppxPackage -Register $manifest
 }
 Set-Content -Encoding UTF8 -LiteralPath $ResultFile -Value 'WSA_REGISTERED'
 exit 0
}catch{
 Set-Content -Encoding UTF8 -LiteralPath $ResultFile -Value $_.Exception.Message
 exit 1
}
