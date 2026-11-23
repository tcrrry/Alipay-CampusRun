function Install-Alipay64([string]$apkPath){
 $installed=Invoke-Device @('shell','dumpsys','package','com.eg.android.AlipayGphone')
 $versionLine=$installed | Select-String '^\s*versionCode=(\d+)\b' | Select-Object -First 1
 if($versionLine -and [long]$versionLine.Matches[0].Groups[1].Value -gt 212470){
  Write-Host '保留已安装的较新支付宝版本。'
 }else{
  $result=Invoke-Device @('install','-r','--abi','arm64-v8a',$apkPath)
  if(!($result -match '^Success$')){throw '支付宝更新失败，请保留安装窗口的 ADB 报错。'}
  $installed=Invoke-Device @('shell','dumpsys','package','com.eg.android.AlipayGphone')
 }
 if(!($installed -match '^\s*primaryCpuAbi=arm64-v8a\s*$')){throw '支付宝未以 arm64-v8a 运行，请运行 04 采集版本与 ABI。'}
}