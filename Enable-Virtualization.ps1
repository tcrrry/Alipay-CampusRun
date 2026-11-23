$ErrorActionPreference='Stop'
try {
 $result=Enable-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -All -NoRestart
 if($result.RestartNeeded){exit 3010}
 exit 0
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
