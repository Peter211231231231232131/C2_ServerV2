$ProgressPreference = 'SilentlyContinue'
$ErrorActionPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$InformationPreference = 'SilentlyContinue'

function Get-SysInfo {
    $info = @{}

    # --- System & OS Info ---
    $computerInfo = Get-ComputerInfo
    $info['OS Name'] = $computerInfo.OsName
    $info['OS Version'] = $computerInfo.OsVersion
    $info['OS Architecture'] = $computerInfo.OsArchitecture
    $info['Windows Version'] = $computerInfo.WindowsVersion
    $info['Build'] = $computerInfo.WindowsBuildLabEx
    $info['Time Zone'] = $computerInfo.TimeZone

    # --- RAM Fix ---
    if ($computerInfo.TotalPhysicalMemory) {
        $info['Total RAM (GB)'] = [math]::Round($computerInfo.TotalPhysicalMemory / 1GB, 2)
    } else {
        $mem = Get-CimInstance Win32_ComputerSystem | Select-Object -ExpandProperty TotalPhysicalMemory
        $info['Total RAM (GB)'] = [math]::Round($mem / 1GB, 2)
    }

    # --- CPU Info ---
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $info['CPU'] = $cpu.Name
    $info['CPU Cores'] = $cpu.NumberOfCores
    $info['CPU Logical Processors'] = $cpu.NumberOfLogicalProcessors

    # --- SMART IP LOGIC (Hardware-Based) ---
    $activeRoute = Get-NetRoute -DestinationPrefix 0.0.0.0/0 | Sort-Object RouteMetric | Select-Object -First 1
    
    if ($activeRoute) {
        $info['Router IP'] = $activeRoute.NextHop
        $primary = Get-NetIPAddress -InterfaceIndex $activeRoute.InterfaceIndex -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress
        $info['Primary Local IP'] = ($primary -join ", ")
        
        $virtual = Get-NetIPAddress -AddressFamily IPv4 | Where-Object { 
            $_.IPAddress -notlike "127*" -and $_.InterfaceIndex -ne $activeRoute.InterfaceIndex 
        } | Select-Object -ExpandProperty IPAddress
        $info['Virtual/Other IPs'] = ($virtual -join ", ")
    } else {
        $info['Router IP'] = "Not Found"
        $info['Primary Local IP'] = "Not Found"
        $info['Virtual/Other IPs'] = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127*" } | Select-Object -ExpandProperty IPAddress) -join ", "
    }

    # --- Dual Public IP Logic (v4 and v6) ---
    try {
        $info['Public IPv4'] = (Invoke-WebRequest -Uri "http://ipv4.icanhazip.com" -UseBasicParsing -TimeoutSec 5).Content.Trim()
    } catch {
        $info['Public IPv4'] = "Not Available"
    }

    try {
        $info['Public IPv6'] = (Invoke-WebRequest -Uri "http://ipv6.icanhazip.com" -UseBasicParsing -TimeoutSec 5).Content.Trim()
    } catch {
        $info['Public IPv6'] = "Not Available"
    }

    # --- Tables ---
    $disks = Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3" | Select-Object DeviceID, @{Name="Size(GB)"; Expression={[math]::Round($_.Size/1GB,2)}}, @{Name="Free(GB)"; Expression={[math]::Round($_.FreeSpace/1GB,2)}}, @{Name="Used(GB)"; Expression={[math]::Round(($_.Size - $_.FreeSpace)/1GB,2)}}
    $info['Disks'] = "`n" + ($disks | Format-Table -AutoSize | Out-String)

    $adapters = Get-NetAdapter -Physical | Select-Object Name, Status, LinkSpeed
    $info['Network Adapters'] = "`n" + ($adapters | Format-Table -AutoSize | Out-String)

    # --- Identity & Uptime ---
    $info['User'] = whoami
    $info['Hostname'] = hostname
    $os = Get-CimInstance Win32_OperatingSystem
    $uptime = (Get-Date) - $os.LastBootUpTime
    $info['Uptime'] = "$($uptime.Days) days, $($uptime.Hours) hours, $($uptime.Minutes) minutes"

    # --- Final Output ---
    $output = ""
    foreach ($key in $info.Keys) { $output += "$key`: $($info[$key])`n" }
    $output
}

Get-SysInfo
