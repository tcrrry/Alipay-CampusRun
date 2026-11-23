$localSettings=Get-Content -Raw -LiteralPath (Join-Path $PSScriptRoot 'settings.json') | ConvertFrom-Json
$device=[string]$localSettings.AdbEndpoint
if($device -notmatch '^127\.0\.0\.1:[0-9]{1,5}$' -or [int]($device.Split(':')[1]) -notin (1..65535)){throw 'AdbEndpoint must be a local 127.0.0.1 address with a valid port.'}
