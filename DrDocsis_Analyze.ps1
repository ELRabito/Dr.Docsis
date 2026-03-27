param(
    [Parameter(Position=0)]
    [double]$contractDown = $(Read-Host "Enter Contracted Download Speed (Mbit/s)"), 
    
    [Parameter(Position=1)]
    [double]$contractUp = $(Read-Host "Enter Contracted Upload Speed (Mbit/s)"), 
    
    [Parameter(Position=2)]
    [double]$legalLimitInput = $(Read-Host "Enter Guaranteed Service Level Threshold (%)"),

    [switch]$History,
    [switch]$Archive,
    [switch]$Select
)

# --- PATH CONFIGURATION ---
$historyDir = ".\Logs_History"
$currentDir = ".\Logs_Current"

if (-not (Test-Path $currentDir)) { New-Item -ItemType Directory -Path $currentDir -Force | Out-Null }
if (-not (Test-Path $historyDir)) { New-Item -ItemType Directory -Path $historyDir -Force | Out-Null }

$legalLimit = $legalLimitInput / 100
$searchDir = $currentDir
$contextMode = "CURRENT SESSION"

# --- INTERACTIVE HISTORY SELECTOR ---
if ($History -or $Select) {
    $subDirs = Get-ChildItem -Path $historyDir -Directory | Sort-Object CreationTime -Descending
    
    if ($subDirs.Count -eq 0) {
        Write-Host "No historical audits found. Scanning root directory..." -ForegroundColor Yellow
        $searchDir = $historyDir
        $contextMode = "HISTORY SCAN (Root)"
    } else {
        Clear-Host
        Write-Host "==============================================================================================================" -ForegroundColor Cyan
        Write-Host "    DR. DOCSIS - CASE FILE SELECTOR" -ForegroundColor Cyan
        Write-Host "==============================================================================================================" -ForegroundColor Cyan
        Write-Host "0) [ALL LOGS] - Scan all directories recursively" -ForegroundColor Gray
        
        for ($i = 0; $i -lt $subDirs.Count; $i++) {
            $folderName = $subDirs[$i].Name
            $color = "White"
            if ($folderName -match "SLA-(\d+)pct") {
                $slaVal = [int]$matches[1]
                if ($slaVal -lt 30) { $color = "Red" } elseif ($slaVal -lt 75) { $color = "Yellow" } else { $color = "Green" }
            }
            Write-Host ("$($i + 1)) $folderName") -ForegroundColor $color
        }
        
        $choice = Read-Host "`nSelect an audit (0-$($subDirs.Count))"
        
        if ($choice -eq "0" -or $choice -eq "") {
            $searchDir = $historyDir
            $contextMode = "HISTORY SCAN (Full Recursive)"
        } elseif ($choice -match '^\d+$' -and [int]$choice -le $subDirs.Count) {
            $selectedFolder = $subDirs[[int]$choice - 1]
            $searchDir = $selectedFolder.FullName
            $contextMode = "CASE FILE: $($selectedFolder.Name)"
        }
    }
}

# --- HELPER FUNCTIONS ---
function Get-ProgressBar($val, $max) {
    if ($max -eq 0) { return "--------------------" }
    $pct = [math]::Min(($val / $max * 20), 20)
    if ($pct -lt 0) { $pct = 0 }
    return ("#" * [int]$pct) + ("-" * (20 - [int]$pct))
}

function Get-Median($values) {
    if (-not $values) { return 0 }
    $sorted = $values | Sort-Object
    $count = $sorted.Count
    if ($count -eq 0) { return 0 }
    if ($count % 2 -eq 1) {
        return $sorted[[math]::Floor($count / 2)]
    } else {
        return ($sorted[($count / 2) - 1] + $sorted[($count / 2)]) / 2
    }
}

# 1. READ & PARSE LOGS
$files = Get-ChildItem -Path $searchDir -Filter "LOG_*.txt" -Recurse 
$report = $files | ForEach-Object {
    $content = Get-Content $_.FullName -Raw
    $filename = $_.Name
    $hostLine = $content | Select-String -Pattern "Connecting to host (.*),"
    $hostname = if ($hostLine) { $hostLine.Matches.Groups[1].Value.Trim() } else { "Unknown" }
    
    $cwndVal = $null
    $cwndRange = ""

   if ($filename -like "*LOG_DOWN_TCP_S*") {
  
        $cwndRegex = "(?i)\d+\s+(\d+(?:\.\d+)?)\s+([KM]?)\s*Bytes"
        $allCwndMatches = $content | Select-String -Pattern $cwndRegex -AllMatches | ForEach-Object { $_.Matches }
        $allCwndValues = $allCwndMatches | ForEach-Object { 
            $val = [double]$_.Groups[1].Value
            $unit = $_.Groups[2].Value.ToUpper()
            if ($unit -eq "M") { $val * 1024 } else { $val }
        }

        if ($allCwndValues) { 
            $cwndVal = Get-Median $allCwndValues 
            $minC = ($allCwndValues | Measure-Object -Minimum).Minimum
            $maxC = ($allCwndValues | Measure-Object -Maximum).Maximum
            
            if ($maxC -ge 1024) {
                $cwndRange = "$([math]::Round($minC/1024, 1))-$([math]::Round($maxC/1024, 1))MB"
            } else {
                $cwndRange = "$([int]$minC)-$([int]$maxC)K"
            }
        }

        $stats = $content | Select-String -Pattern "(\d+\.?\d*)\s+Mbits/sec\s+receiver"
        if ($stats) {
            $bw = [double]$stats.Matches.Groups[1].Value
            [PSCustomObject]@{ 
                Time = $_.CreationTime.ToString("MM-dd HH:mm"); 
                RawTime = $_.CreationTime; 
                Type = "DL-TCP-S"; 
                Target = $hostname; 
                Val = $bw; 
                Result = "$bw".PadLeft(5); 
                Max = $contractDown; 
                Visual = "[$(Get-ProgressBar $bw $contractDown)]"; 
                IsError = ($bw -lt ($contractDown * $legalLimit)); 
                FullPath = $_.FullName; 
                Retr = $null; 
                Cwnd = $cwndVal; 
                CwndDisplay = $cwndRange 
            }
        }
    }
    elseif ($filename -like "*LOG_DOWN_TCP_M*") {
        $stats = $content | Select-String -Pattern "SUM.* (\d+\.?\d*)\s+Mbits/sec\s+receiver"
        $retrMatch = $content | Select-String -Pattern "SUM.* \d+\.?\d* Mbits/sec\s+(\d+)\s+sender"
        if ($stats) {
            $bw = [double]$stats.Matches.Groups[1].Value
            $retr = if ($retrMatch) { [int]$retrMatch.Matches.Groups[1].Value } else { 0 }
            [PSCustomObject]@{ Time = $_.CreationTime.ToString("MM-dd HH:mm"); RawTime = $_.CreationTime; Type = "DL-TCP-M"; Target = $hostname; Val = $bw; Result = "$bw".PadLeft(5); Max = $contractDown; Visual = "[$(Get-ProgressBar $bw $contractDown)]"; IsError = ($bw -lt ($contractDown * $legalLimit)); FullPath = $_.FullName; Retr = $retr; Cwnd = $null; CwndDisplay = "" }
        }
    }
    elseif ($filename -like "*LOG_UP_TCP*") {
        $stats = $content | Select-String -Pattern "(\d+\.?\d*)\s+Mbits/sec\s+receiver"
        if ($stats) {
            $bw = [double]$stats.Matches.Groups[1].Value
            [PSCustomObject]@{ Time = $_.CreationTime.ToString("MM-dd HH:mm"); RawTime = $_.CreationTime; Type = "UL-TCP-S"; Target = $hostname; Val = $bw; Result = "$bw".PadLeft(5); Max = $contractUp; Visual = "[$(Get-ProgressBar $bw $contractUp)]"; IsError = ($bw -lt ($contractUp * $legalLimit)); FullPath = $_.FullName; Retr = $null; Cwnd = $null; CwndDisplay = "" }
        }
    }
    elseif ($filename -like "*LOG_UDP_FRAG*") {
		
        $stats = $content -split "`n" | Select-String -Pattern "(\d+)/(\d+)\s+\(([\d\.]+)%\).*receiver"
        $jitterMatch = $content | Select-String -Pattern "([\d\.]+)\s+ms\s+(\d+)/(\d+)" | Select-Object -Last 1
        
        if ($stats) {
            $loss = [double]$stats.Matches.Groups[3].Value
            $jitter = if ($jitterMatch) { $jitterMatch.Matches.Groups[1].Value } else { "N/A" }
            $lossBar = ("!" * [int]([math]::Min($loss/5, 20))) + ("." * (20 - [int]([math]::Min($loss/5, 20))))
            [PSCustomObject]@{ 
                Time = $_.CreationTime.ToString("MM-dd HH:mm"); 
                RawTime = $_.CreationTime; 
                Type = "UDP-STRESS"; 
                Target = $hostname; 
                Val = $loss; 
                Result = "$loss% Loss"; 
                Max = $jitter; 
                Visual = "[$lossBar]"; 
                IsError = ($loss -gt 5); 
                FullPath = $_.FullName; 
                Retr = $null;
                Cwnd = $null;
                CwndDisplay = ""
            }
        }
    }
}

# 2. GENERATE OUTPUT
Clear-Host
Write-Host "==============================================================================================================" -ForegroundColor Cyan
Write-Host "    DR. DOCSIS ANALYZER - Powered by iPerf3" -ForegroundColor Cyan
Write-Host "    MODE: $contextMode" -ForegroundColor Blue
Write-Host "    Contract: $contractDown / $contractUp Mbit/s | Service Level Threshold: $legalLimitInput %" -ForegroundColor Yellow
Write-Host "==============================================================================================================" -ForegroundColor Cyan
Write-Host "    TEST METHODOLOGY & DIAGNOSTIC PARAMETERS:" -ForegroundColor DarkGreen
Write-Host "    * TCP-S: Single-stream test detects L1/L2 congestion (Highly Ingress-sensitive)." -ForegroundColor Gray
Write-Host "    * TCP-M: Multi-stream (-P 10) validates available server/node capacity." -ForegroundColor Gray
Write-Host "    * UDP-STRESS: 1474B payload forces packet fragmentation." -ForegroundColor Gray
Write-Host "==============================================================================================================" -ForegroundColor Cyan
Write-Host ""

if ($report) {
    $totalTests = $report.Count
    $failedTests = ($report | Where { $_.IsError -eq $true }).Count
    $passRate = if ($totalTests -gt 0) { [math]::Round((($totalTests - $failedTests) / $totalTests) * 100, 2) } else { 0 }

    $lastTarget = ""
    $report | Sort-Object RawTime | ForEach-Object {
        if ($lastTarget -ne "" -and $lastTarget -ne $_.Target) {
            Write-Host "------------------------------------------------------------------------------------------" -ForegroundColor DarkGray
        }
        $lastTarget = $_.Target

        $color = if ($_.IsError) { "Red" } else { "Green" }
        $displayTarget = if ($_.Target.Length -gt 20) { $_.Target.Substring(0,17) + "..." } else { $_.Target.PadRight(20) }
        
        $resStr = if ($_.Type -match "TCP") { "$($_.Result.Trim()) / $($_.Max)".PadLeft(11) } else { "$($_.Result)".PadLeft(11) }
        
        $infoStr = ""
        $infoColor = "Gray"
        if ($_.Retr -ne $null) { 
            $infoStr = "Retr: $($_.Retr)".PadRight(12)
            $infoColor = if ($_.Retr -gt 100) { "Red" } elseif ($_.Retr -gt 0) { "Yellow" } else { "Gray" }
        }
        elseif ($_.CwndDisplay -ne "") { 

            $infoStr = "CWND: $($_.CwndDisplay)".PadRight(12)
            $infoColor = if ($_.Cwnd -lt 200) { "Yellow" } else { "Gray" }
        }
        elseif ($_.Type -eq "UDP-STRESS") { 
            $infoStr = "Jit: $($_.Max)ms".PadRight(12)
        }

        Write-Host ("$($_.Time) | $displayTarget | $($_.Type.PadRight(10)) | ") -NoNewline
        Write-Host ("$($_.Visual) ") -ForegroundColor $color -NoNewline
        Write-Host ("$resStr | ") -ForegroundColor $color -NoNewline
        Write-Host $infoStr -ForegroundColor $infoColor
    }
    
    # --- STATISTICAL SUMMARY ---
	Write-Host "==============================================================================================================" -ForegroundColor Cyan
    Write-Host "    STATISTICAL SUMMARY (MEDIAN & PEAK VALUES)" -ForegroundColor Yellow
	Write-Host "==============================================================================================================" -ForegroundColor Cyan

    $medDL  = Get-Median ($report | Where { $_.Type -eq "DL-TCP-S" } | Select-Object -ExpandProperty Val)
    $medDLM = Get-Median ($report | Where { $_.Type -eq "DL-TCP-M" } | Select-Object -ExpandProperty Val)
    $medUL  = Get-Median ($report | Where { $_.Type -eq "UL-TCP-S" } | Select-Object -ExpandProperty Val)
    $medUDP = Get-Median ($report | Where { $_.Type -eq "UDP-STRESS" } | Select-Object -ExpandProperty Val)
    
    $retrValues = $report | Where { $_.Type -eq "DL-TCP-M" } | Select-Object -ExpandProperty Retr
    $medRetr = Get-Median $retrValues
    $maxRetr = if ($retrValues) { ($retrValues | Measure-Object -Maximum).Maximum } else { 0 }

    $cwndValues = $report | Where { $_.Cwnd -ne $null } | Select-Object -ExpandProperty Cwnd
    $medCwnd = if ($cwndValues) { Get-Median $cwndValues } else { $null }

    if ($medDL) {
        $color = if ($medDL -lt ($contractDown * $legalLimit)) { "Red" } else { "Green" }
        Write-Host "    Median Download (TCP Single):".PadRight(55) -NoNewline
        Write-Host ("$([math]::Round($medDL, 2)) Mb/s").PadLeft(20) -ForegroundColor $color
    }
    if ($medDLM) {
        $color = if ($medDLM -lt ($contractDown * $legalLimit)) { "Red" } else { "Green" }
        Write-Host "    Median Download (TCP Multi-10):".PadRight(55) -NoNewline
        Write-Host ("$([math]::Round($medDLM, 2)) Mb/s").PadLeft(20) -ForegroundColor $color
    }
    if ($medRetr -ne $null) {
        $color = if ($maxRetr -gt 100) { "Red" } else { "Gray" }
        Write-Host "    Retransmits (TCP Multi-10) (Median / PEAK):".PadRight(55) -NoNewline
        Write-Host ("$([int]$medRetr) / $([int]$maxRetr) PKTs").PadLeft(20) -ForegroundColor $color
    }
    if ($medCwnd -ne $null) {
        $color = if ($medCwnd -lt 500) { "Yellow" } else { "Gray" }
        Write-Host "    Median CWND (Congestion Window):".PadRight(55) -NoNewline
        Write-Host ("$([int]$medCwnd) KBytes").PadLeft(20) -ForegroundColor $color
    }
    if ($medUL) {
        $color = if ($medUL -lt ($contractUp * $legalLimit)) { "Red" } else { "Green" }
        Write-Host "    Median Upload (TCP Single):".PadRight(55) -NoNewline
        Write-Host ("$([math]::Round($medUL, 2)) Mb/s").PadLeft(20) -ForegroundColor $color
    }
    if ($medUDP -ne $null) {
        $color = if ($medUDP -gt 5) { "Red" } else { "Green" }
        Write-Host "    Median Packet Loss (UDP Stress):".PadRight(55) -NoNewline
        Write-Host ("$([math]::Round($medUDP, 2)) %").PadLeft(20) -ForegroundColor $color
    }
    
    $diagMessages = @()
    $diagColor = "Green"
    if ($maxRetr -gt 100) { 
        $diagMessages += "CRITICAL: Excessive TCP Retransmit PEAKS ($([int]$maxRetr)) - Potential Layer 1/2 instability detected."
        $diagColor = "Red"
    }
    if ($medUDP -gt 10) {
        $diagMessages += "CRITICAL: High UDP Packet Loss ($([int]$medUDP)%) - Upstream Ingress suspected."
        $diagColor = "Red"
    }
    if ($medDLM -gt ($medDL * 1.8) -and $medDL -lt ($contractDown * 0.7)) {
        $diagMessages += "CRITICAL: Heavy Stream-Drift - Single-stream performance collapsed (Jitter/Reordering)."
        $diagColor = "Red"
    }
    if ($diagMessages.Count -eq 0) { $diagMessages += "Performance within acceptable parameters" }
    
    Write-Host "`n    AUTOMATED DIAGNOSIS: " -NoNewline
    for ($i=0; $i -lt $diagMessages.Count; $i++) {
        if ($i -gt 0) { Write-Host (" " * 25) -NoNewline } 
        Write-Host $diagMessages[$i] -ForegroundColor $diagColor
    }

	Write-Host "==============================================================================================================" -ForegroundColor Cyan
    Write-Host "    COMPLIANCE & SLA AUDIT REPORT (Overall Pass Rate: $passRate%)" -ForegroundColor Yellow
	Write-Host "==============================================================================================================" -ForegroundColor Cyan
    Write-Host "    Total Measurement Points: ".PadRight(45) -NoNewline
    Write-Host "$totalTests".PadLeft(20)
    Write-Host "    Failed Requirements: ".PadRight(45) -NoNewline
    Write-Host "$failedTests".PadLeft(20) -ForegroundColor Red
    
    if ($Archive -and -not $History -and $files) {
        $dateStr = Get-Date -Format "yyyy-MM-dd_HHmm"
        $folderName = "Audit_$($dateStr)_SLA-$([int]$passRate)pct"
        $targetPath = Join-Path $historyDir $folderName
        if (-not (Test-Path $targetPath)) { New-Item -ItemType Directory -Path $targetPath -Force | Out-Null }
        
        $files | ForEach-Object {
            if (Test-Path $_.FullName) { Move-Item -Path $_.FullName -Destination $targetPath -Force }
        }
        Write-Host "`n[Archived] Logs moved to $folderName" -ForegroundColor Gray
    }
} else {
    Write-Host "No logs found in $searchDir!" -ForegroundColor Red
}
