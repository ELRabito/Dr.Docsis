<#
.SYNOPSIS
    Dr. Docsis Breakpoint Analyzer (Triple Validation)
    - Naming: TYPE_HOST_BITRATE_DATE-TIME.txt
    - Dynamic Step Size (5M Clean / 10M Loss)
    - Multi-Host Validation (3 Cycles)
    - Dynamic Start Point (20% of Contract)
    - Safety Integrity Check for Final Verdict
#>
param(
    [Parameter(Position=0)]
    [double]$contractUpMbit = $(Read-Host "Enter Max Upload for Test (e.g. 50)")
)

# Robust Console Clear
if ($Host.Name -eq "ConsoleHost") { [System.Console]::Clear() } else { Clear-Host }

if (Test-Path ".\iPerf3_Host_Config.ps1") { . .\iPerf3_Host_Config.ps1 } else { Write-Error "Config not found!"; break }

# Path Configuration
$baseLogPath = ".\Logs_Breakpoint"
$sessionTimestamp = Get-Date -Format "yyyy-MM-dd_HHmm"
$sessionPath = Join-Path $baseLogPath "Audit_$($sessionTimestamp)_TRIPLE_CHECK"
if (-not (Test-Path $sessionPath)) { New-Item -ItemType Directory -Path $sessionPath -Force | Out-Null }

# Test Parameters
$retryPause = 30
$duration = 12
$successfulCycles = 0
$usedHosts = @()
$breakpoints = @()

# Calculation for Dynamic Start (20% of contract, minimum 5M)
$startBW = [Math]::Max(5, [Math]::Floor($contractUpMbit * 0.2))

Write-Host "===================================================================================" -ForegroundColor Cyan
Write-Host "    DR. DOCSIS BREAKPOINT ANALYZER - Triple Host Stress Test - Powered by iPerf3" -ForegroundColor Cyan
Write-Host "    Session: $sessionTimestamp | Goal: 3 Validated Cycles" -ForegroundColor Yellow
Write-Host "===================================================================================" -ForegroundColor Cyan
Write-Host "    TEST METHODOLOGY & BREAKPOINT DETECTION:" -ForegroundColor DarkGreen
Write-Host "    * STEP-UP: Iterative bandwidth scaling to find physical limits." -ForegroundColor Gray
Write-Host "    * UDP-STRESS: Using 1474B payload to trigger packet fragmentation." -ForegroundColor Gray
Write-Host "    * BREAKPOINT: First instance of >0.1% loss defines the line's ceiling." -ForegroundColor Gray
Write-Host "    * DYNAMIC: 5M increments until loss, then 10M stress steps." -ForegroundColor Gray
Write-Host "===================================================================================" -ForegroundColor Cyan
Write-Host "    Dynamic Start Point: $startBW Mbit/s" -ForegroundColor Gray

while ($successfulCycles -lt 3) {
    # Cleanup previous instances
    Get-Process iperf3 -ErrorAction SilentlyContinue | Stop-Process -Force

    $target = $targets | Where-Object { $usedHosts -notcontains $_.Host } | Get-Random
    if (-not $target) { $usedHosts = @(); $target = $targets | Get-Random }
    
    $server = $target.Host
    $port = $target.Ports | Get-Random
    $currentSessionLogs = @()
    $isAllValid = $true
    $currentBW = $startBW
    $hasDetectedLoss = $false
    $firstLossAt = 0

    Write-Host "`n>>> CYCLE $($successfulCycles + 1) START: [$($target.Country)] $server" -ForegroundColor Cyan

    while ($currentBW -le $contractUpMbit) {
        $logFile = Join-Path $sessionPath "TEMP_C$($successfulCycles)_$($currentBW)M.txt"
        $currentSessionLogs += $logFile
        
        Write-Host "    Testing $($currentBW) Mbit/s ".PadRight(30) -NoNewline -ForegroundColor Yellow
        Write-Host "................ " -NoNewline -ForegroundColor DarkGray

        $args = "-c $server -p $port -u -b $($currentBW)M -l 1474 -t $duration --get-server-output --logfile $logFile"
        $p = Start-Process -FilePath ".\iperf3.exe" -ArgumentList $args -PassThru -NoNewWindow
        
        # Timeout safety (Duration + 10s buffer)
        if (-not $p.WaitForExit(($duration + 10) * 1000)) {
            $p | Stop-Process -Force
            Write-Host " TIMEOUT (Killed)" -ForegroundColor Red
            $isAllValid = $false
            break
        }

        if (Test-Path $logFile) {
            $content = Get-Content $logFile -Raw
            
			# Detect server busy state
            if ($content -match "busy") {
                Write-Host " BUSY (Server)" -ForegroundColor Yellow
                $isAllValid = $false
                break
            }

            if ($content -match "(\d+)/(\d+)\s+\(([\d\.]+)%\)") {
                $loss = [double]$matches[3]
                $color = "Green"; if ($loss -gt 0.1) { $color = "Yellow" }; if ($loss -gt 15) { $color = "Red" }
                Write-Host " LOSS: $loss%" -ForegroundColor $color
                
                if ($loss -gt 0.1 -and -not $hasDetectedLoss) {
                    $hasDetectedLoss = $true
                    $firstLossAt = $currentBW
                    Write-Host "         (!) Point of Failure detected at $($currentBW)M" -ForegroundColor Gray
                }
            } else {
                Write-Host " ERROR (Log Content)" -ForegroundColor Red
                $isAllValid = $false; break 
            }
        } else { $isAllValid = $false; break }

        # Adjust step size
        if ($hasDetectedLoss) { $currentBW += 10 } else { $currentBW += 5 }
        Start-Sleep -Seconds 1
    }

    if ($isAllValid) {
        Write-Host "    [OK] Cycle complete." -ForegroundColor Green
        $breakpoints += $firstLossAt
        foreach ($f in $currentSessionLogs) {
            if (Test-Path $f) { 
                $bwMatch = [regex]::Match($f, "(\d+)M\.txt").Groups[1].Value
                $fileTime = Get-Date -Format "HH-mm-ss"
                $finalName = "LOG_UP_UDP_$($server)_$($bwMatch)M_$($fileTime).txt"
                Rename-Item -Path $f -NewName $finalName -Force 
            }
        }
        $usedHosts += $server
        $successfulCycles++
    } else {
        Write-Host "    [FAILED] Server busy or Timeout. Cleaning up logs..." -ForegroundColor Red
        foreach ($f in $currentSessionLogs) { if (Test-Path $f) { Remove-Item $f -Force } }
        Write-Host "    Waiting $retryPause s for retry with different host..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $retryPause
    }
}

# FINAL ANALYSIS REPORT
Write-Host "===================================================================================" -ForegroundColor Cyan
Write-Host "    DR. DOCSIS FINAL VERDICT" -ForegroundColor White

if ($breakpoints.Count -lt 3) {
    Write-Warning "Incomplete data set ($($breakpoints.Count)/3 cycles). Cannot compute average."
    exit
}

$avgBreakpoint = ($breakpoints[0] + $breakpoints[1] + $breakpoints[2]) / 3
Write-Host "    Average Breakpoint: $([Math]::Round($avgBreakpoint, 2)) Mbit/s" -ForegroundColor Yellow

if ($avgBreakpoint -gt 0 -and $avgBreakpoint -lt ($contractUpMbit * 0.5)) {
    Write-Host "    VERDICT: Critical segment congestion or massive ingress." -ForegroundColor Red
} elseif ($avgBreakpoint -eq 0) {
    Write-Host "    VERDICT: No breakpoint found. Line stable." -ForegroundColor Green
} else {
    Write-Host "    VERDICT: Line within tolerance, peak losses possible." -ForegroundColor Green
}
Write-Host "    Logs in: $sessionPath" -ForegroundColor DarkGray
Write-Host "===================================================================================" -ForegroundColor Cyan
