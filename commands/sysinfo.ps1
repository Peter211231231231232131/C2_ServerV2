$ProgressPreference = 'SilentlyContinue'
param($args)
function Get-SysInfo {
    $info = @{}

    $computerInfo = Get-ComputerInfo -Property OsName, OsVersion, OsArchitecture, WindowsVersion, WindowsBuildLabEx, TimeZone, TotalPhysicalMemory
    $info['OS Name'] = $computerInfo.OsName
    $info['OS Version'] = $computerInfo.OsVersion
    $info['OS Architecture'] = $computerInfo.OsArchitecture
    $info['Windows Version'] = $computerInfo.WindowsVersion
    $info['Build'] = $computerInfo.WindowsBuildLabEx
    $info['Time Zone'] = $computerInfo.TimeZone
    $info['Total RAM (GB)'] = [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)

    $cpu = Get-CimInstance Win32_Processor
    $info['CPU'] = $cpu.Name
    $info['CPU Cores'] = $cpu.NumberOfCores
    $info['CPU Logical Processors'] = $cpu.NumberOfLogicalProcessors

    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, @{Name="Size(GB)"; Expression={[math]::Round($_.Size/1GB,2)}}, @{Name="Free(GB)"; Expression={[math]::Round($_.FreeSpace/1GB,2)}}, @{Name="Used(GB)"; Expression={[math]::Round(($_.Size - $_.FreeSpace)/1GB,2)}}
    $diskOutput = $disks | Format-Table -AutoSize | Out-String
    $info['Disks'] = "`n$diskOutput"

    $adapters = Get-NetAdapter -Physical | Select-Object Name, Status, LinkSpeed
    $adapterOutput = $adapters | Format-Table -AutoSize | Out-String
    $info['Network Adapters'] = "`n$adapterOutput"

    $info['User'] = whoami
    $info['Hostname'] = hostname

    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    $info['Uptime'] = "$($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"

    $output = ""
    foreach ($key in $info.Keys) {
        $output += "$key`: $($info[$key])`n"
    }
    $output
}

Get-SysInfo