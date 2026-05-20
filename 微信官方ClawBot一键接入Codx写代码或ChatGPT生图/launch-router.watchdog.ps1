param(
  [Parameter(Mandatory = $true)]
  [int]$ParentPid,
  [Parameter(Mandatory = $true)]
  [string]$StatePath,
  [string]$LogPath = ''
)

$ErrorActionPreference = 'SilentlyContinue'

function Write-Log {
  param([string]$Message)

  if ([string]::IsNullOrWhiteSpace($LogPath)) {
    return
  }

  $line = '{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'), $Message
  Add-Content -Path $LogPath -Value $line -Encoding UTF8
}

function Get-TrackedPids {
  if (-not (Test-Path $StatePath)) {
    return @()
  }

  $pids = @()
  foreach ($line in Get-Content -Path $StatePath) {
    if ($line -match '^\s*(\d+)\s*$') {
      $pids += [int]$matches[1]
    }
  }

  return $pids | Sort-Object -Unique
}

function Stop-TrackedPid {
  param([int]$ProcessId)

  if ($ProcessId -le 0) {
    return $false
  }

  Write-Log "killing pid=$ProcessId"
  $output = & taskkill.exe /F /T /PID $ProcessId 2>&1 | Out-String

  if ([string]::IsNullOrWhiteSpace($output)) {
    return $false
  }

  $trimmed = $output.Trim()
  Write-Log $trimmed

  if ($trimmed -match 'ERROR' -or $trimmed -match 'not found' -or $trimmed -match 'failed' -or $trimmed -match 'fail') {
    return $true
  }

  return $false
}

Write-Log "watchdog pid=$PID parent=$ParentPid state=$StatePath"

while (Get-Process -Id $ParentPid -ErrorAction SilentlyContinue) {
  Start-Sleep -Milliseconds 500
}

$cleanStreak = 0
for ($i = 0; $i -lt 120; $i++) {
  $trackedPids = @(Get-TrackedPids)
  Write-Log ("loop={0} tracked={1} clean_streak={2}" -f $i, $trackedPids.Count, $cleanStreak)

  if ($trackedPids.Count -eq 0) {
    $cleanStreak++
    if ($cleanStreak -ge 4) {
      break
    }
  } else {
    $cleanStreak = 0
    $remaining = @()

    foreach ($trackedPid in $trackedPids) {
      if ($trackedPid -ne $PID) {
        if (Stop-TrackedPid -ProcessId $trackedPid) {
          $remaining += $trackedPid
        }
      }
    }

    if ($remaining.Count -lt $trackedPids.Count) {
      if ($remaining.Count -eq 0) {
        Remove-Item -Force -ErrorAction SilentlyContinue $StatePath
      } else {
        Set-Content -Path $StatePath -Value ($remaining | Sort-Object -Unique | ForEach-Object { $_.ToString() }) -Encoding ASCII
      }
    }
  }

  Start-Sleep -Milliseconds 500
}

Write-Log 'watchdog exiting'
