param([Parameter(Mandatory=$true)][string]$StatusFile,[Parameter(Mandatory=$true)][int]$OwnerProcessId)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()
$form=New-Object Windows.Forms.Form
$form.Text='安装提示 - 支付宝校园跑'
$form.ClientSize=New-Object Drawing.Size(390,160)
$form.StartPosition='Manual'
$work=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$form.Location=New-Object Drawing.Point(($work.Right-410),($work.Top+20))
$form.TopMost=$true
$form.FormBorderStyle='FixedToolWindow'
$form.Font=New-Object Drawing.Font('Microsoft YaHei UI',10)
$label=New-Object Windows.Forms.Label
$label.Location=New-Object Drawing.Point(14,12)
$label.Size=New-Object Drawing.Size(362,105)
$label.Text='安装程序正在启动，请稍候。'
$form.Controls.Add($label)
$close=New-Object Windows.Forms.Button
$close.Text='收起提示';$close.Location=New-Object Drawing.Point(270,120);$close.Size=New-Object Drawing.Size(105,30)
$close.Add_Click({$form.Close()});$form.Controls.Add($close)
$timer=New-Object Windows.Forms.Timer
$timer.Interval=700
$timer.Add_Tick({
 try { if([IO.File]::Exists($StatusFile)){$label.Text=[IO.File]::ReadAllText($StatusFile,[Text.Encoding]::UTF8)} } catch {}
 if(-not (Get-Process -Id $OwnerProcessId -ErrorAction SilentlyContinue)){$timer.Stop();$form.Close()}
})
$form.Add_Shown({$timer.Start()})
try{[void]$form.ShowDialog()}finally{$timer.Dispose();$form.Dispose()}
