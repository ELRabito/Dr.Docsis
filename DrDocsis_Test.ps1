<#
.SYNOPSIS
    Robust Network Analysis Tool (iPerf3 Wrapper)
    Designed for deep-dive diagnostics on DOCSIS (Cable), DSL, and Fiber lines.
    ! USE A WIRED CONNECTION FOR THE TEST !

.DESCRIPTION
    This script identifies hidden line issues by comparing different traffic types:
    
    1. TCP-Single-Stream (S): Detects L1/L2 issues. Highly sensitive to Ingress, 
       Jitter, and Packet Reordering. 
       
    2. TCP-Multi-Stream (M): Runs 10 parallel streams (-P 10). This validates the 
       brute-force capacity of the segment and peering.
       
    DIAGNOSTIC KEY: If Multi-Stream is fast but Single-Stream is slow, there is 
    a high probability of a physical line fault (DOCSIS Noise/Reordering).

    3. UDP Stress (1474B): Tests for fragmentation issues and MTU bottlenecks. 
       Essential for identifying faulty hardware or misconfigured nodes.
       
    4. Multi-Target Rotation: Eliminates peering bias by cycling through high-quality 
       international servers.

.METHODOLOGY
    - "All-or-Nothing" Run Logic: Only complete test cycles (DL-S/DL-M/UL/UDP) are 
      saved to ensure a statistically valid data set for ISP dispute or BNetzA reports.
    - Automatic cleanup of failed/busy server logs.
#>
param(
    [Parameter(Position=0)]
    [double]$contractDownMbit = $(Read-Host "Enter Contracted Download (Mbit/s)"),

    [Parameter(Position=1)]
    [double]$contractUpMbit = $(Read-Host "Enter Contracted Upload (Mbit/s)"),

    [Parameter(Position=2)]
    [double]$slaPercent = $(Read-Host "Enter SLA Threshold % (e.g. 90)")
)
# Include iPerf3 Server List/Config
. .\iPerf3_Host_Config.ps1 

# --- PATH CONFIGURATION ---
$logPath = ".\Logs_Current"
if (-not (Test-Path $logPath)) { New-Item -ItemType Directory -Path $logPath -Force | Out-Null }

# --- FIXED PARAMETERS ---
$duration = 30           # iPerf standard for steady state
$pauseBetweenRuns = 60   # Cool-down
$retryPause = 60         # Wait on busy
$debugKeepLogs = $false  # TOGGLE: Set to $true to keep logs even if a run fails/is incomplete

$dlMbit = $contractDownMbit * ($slaPercent / 100)
$upMbit = $contractUpMbit * ($slaPercent / 100)
$dlBandwidth = "$([math]::Round($dlMbit))M"
$upBandwidth = "$([math]::Round($upMbit))M"
$targetIndex = 0

Clear-Host
Write-Host "==========================================================================================" -ForegroundColor Cyan
Write-Host "--- DR. DOCSIS TEST - Powered by iPerf3 ---" -ForegroundColor Cyan
Write-Host "Target SLA Bandwidth: $dlBandwidth Down / $upBandwidth Up ($slaPercent% of Contract)" -ForegroundColor Yellow
Write-Host "==========================================================================================" -ForegroundColor Cyan
Write-Host "    TEST METHODOLOGY & DIAGNOSTIC PARAMETERS:" -ForegroundColor DarkGreen
Write-Host "    * TCP-S: Single-stream test detects L1/L2 congestion (Highly Ingress-sensitive)." -ForegroundColor Gray
Write-Host "    * TCP-M: Multi-stream (-P 10) validates available server/node capacity." -ForegroundColor Gray
Write-Host "    * UDP-STRESS: 1474B payload forces packet fragmentation." -ForegroundColor Gray
Write-Host "==========================================================================================" -ForegroundColor Cyan
Write-Host "Logging to: $logPath" -ForegroundColor DarkGray

if (-not (Test-Path ".\iperf3.exe")) {
    Write-Host "ERROR: iperf3.exe not found!" -ForegroundColor Red
    break
}

# --- HELPER FUNCTION ---
function Run-IperfTest {
    param($ArgString, $LogFile, $Label)
    
    $paddedLabel = " > $($Label)...".PadRight(40, ".")
    Write-Host $paddedLabel -NoNewline
    
    # Force close iPerf3 in case of process hangs
    Get-Process iperf3 -ErrorAction SilentlyContinue | Stop-Process -Force
    
    # Redirect standard output/error to temp files to keep console clean from MTU warnings
    $argList = $ArgString.Split(" ") + @("--logfile", $LogFile)
    $tempOut = "$env:TEMP\iperf_stdout.tmp"
    $tempErr = "$env:TEMP\iperf_stderr.tmp"
    
    try {
        $p = Start-Process -FilePath ".\iperf3.exe" -ArgumentList $argList -PassThru -NoNewWindow -ErrorAction Stop `
             -RedirectStandardOutput $tempOut -RedirectStandardError $tempErr
        
        # Wait for run end (duration + 20 seconds)
        $completed = $p.WaitForExit(($duration + 20) * 1000)
        
        if (-not $completed) {
            Write-Host " TIMEOUT (Force Kill)" -ForegroundColor Magenta
            $p | Stop-Process -Force
            return $false
        }
    } catch {
        Write-Host " ERROR: Execution failed!" -ForegroundColor Red
        return $false
    }
    
    Start-Sleep -Seconds 2
    
    if (Test-Path $LogFile) {
        $content = Get-Content $LogFile -Raw
        
        # Detect server busy state
        if ($content -match "busy") {
            Write-Host " BUSY (Server)" -ForegroundColor Yellow
            return $false
        }

        # General Error check
        if ($content -match "Usage:" -or $content -match "error" -or (Get-Item $LogFile).Length -lt 500) {
            Write-Host " FAILED" -ForegroundColor Red
            return $false
        }
        Write-Host " SUCCESS" -ForegroundColor Green
        return $true
    }
    Write-Host " ERROR (No Log)" -ForegroundColor Red
    return $false
}

# --- MAIN LOOP ---
while($true) {
    $currentTarget = $targets[$targetIndex]
    $server = $currentTarget.Host
    $port = $currentTarget.Ports | Get-Random
    $now = Get-Date -Format "HH-mm-ss"

    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Target: [$($currentTarget.Country)] $server (Port $port)" -ForegroundColor Yellow

    $logDown  = Join-Path $logPath "LOG_DOWN_TCP_S_$($server)_$now.txt"
    $logMulti = Join-Path $logPath "LOG_DOWN_TCP_M_$($server)_$now.txt"
    $logUp    = Join-Path $logPath "LOG_UP_TCP_S_$($server)_$now.txt"
    $logFrag  = Join-Path $logPath "LOG_UDP_FRAG_$($server)_$now.txt"
    $currentLogs = @($logDown, $logMulti, $logUp, $logFrag)

    $runValid = $true

    # 1. Download (Single-Stream)
    if (-not (Run-IperfTest "-c $server -p $port -t $duration -R --get-server-output" $logDown "DL (TCP-Single)")) {
        $runValid = $false
    }

    # 2. Download (Multi-Stream)
    if ($runValid -and -not (Run-IperfTest "-c $server -p $port -t $duration -R -P 10 --get-server-output" $logMulti "DL (TCP-Multi-10)")) {
        $runValid = $false
    }

    # 3. Upload (Single-Stream)
    if ($runValid -and -not (Run-IperfTest "-c $server -p $port -t $duration --get-server-output" $logUp "UL (TCP-Single)")) {
        $runValid = $false
    }

    # 4. UDP Stress (The Fragmentation Test)
    if ($runValid -and -not (Run-IperfTest "-c $server -p $port -u -b $upBandwidth -l 1474 -t $duration --get-server-output" $logFrag "UL (UDP-Frag)")) {
        $runValid = $false
    }
    
    # Cleanup and Wait
    if (-not $runValid) {
        if (-not $debugKeepLogs) {
            Write-Host "Run incomplete. Deleting fragment logs..." -ForegroundColor DarkGray
            foreach ($f in $currentLogs) { if (Test-Path $f) { Remove-Item $f -Force } }
        } else {
            Write-Host "Run incomplete. DEBUG: Keeping logs as requested." -ForegroundColor Magenta
        }
        
        Write-Host "Retrying in $retryPause s..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $retryPause
    } else {
        # Countdown for the next run
        for ($i = $pauseBetweenRuns; $i -gt 0; $i--) {
            Write-Host "`rCycle complete. Next test in $i s...    " -ForegroundColor DarkGray -NoNewline
            Start-Sleep -Seconds 1
        }
        Write-Host ("`r" + (" " * 60) + "`r") -NoNewline
    }

    # Next Server from iPerf3_Host_Config.ps1
    $targetIndex = ($targetIndex + 1) % $targets.Count
}
