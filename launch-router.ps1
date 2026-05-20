$ErrorActionPreference = 'Stop'

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$envFile = Join-Path $root 'router.env.local.cmd'
$watchdogPath = Join-Path $root 'launch-router.watchdog.ps1'
$configPath = Join-Path $root 'config.route.toml'
$setupConfigPath = Join-Path $root '.weixin-setup.toml'
$qrImagePath = Join-Path $root 'weixin-qr.png'
$dataDir = Join-Path $root '.router-data'
$processStatePath = Join-Path $dataDir 'launch-router.pids'
$setupOutPath = Join-Path $root 'weixin-setup.out.log'
$setupErrPath = Join-Path $root 'weixin-setup.err.log'
$routeOutPath = Join-Path $root 'cc-connect-route.out.log'
$routeErrPath = Join-Path $root 'cc-connect-route.err.log'

function Set-ConsoleUtf8 {
  try {
    chcp.com 65001 > $null
  } catch {
  }

  try {
    $utf8 = [Text.UTF8Encoding]::new($false)
    [Console]::InputEncoding = $utf8
    [Console]::OutputEncoding = $utf8
    $script:OutputEncoding = $utf8
  } catch {
  }
}

function Add-ProcessPathItem {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path $Path)) {
    return
  }

  $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
  $currentPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
  $items = @($fullPath)

  if (-not [string]::IsNullOrWhiteSpace($currentPath)) {
    $items += ($currentPath -split ';' | Where-Object {
      if ([string]::IsNullOrWhiteSpace($_)) {
        return $false
      }

      try {
        return ([IO.Path]::GetFullPath($_).TrimEnd('\') -ne $fullPath)
      } catch {
        return $true
      }
    })
  }

  [Environment]::SetEnvironmentVariable('PATH', ($items -join ';'), 'Process')
}

function Assert-UnderDataDir {
  param([string]$Path)

  $fullPath = [IO.Path]::GetFullPath($Path)
  $dataRoot = [IO.Path]::GetFullPath($dataDir).TrimEnd('\') + '\'
  if (-not $fullPath.StartsWith($dataRoot, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to modify a path outside the launcher data directory: $fullPath"
  }
}

function Remove-ItemUnderDataDir {
  param(
    [string]$Path,
    [switch]$Recurse
  )

  if (-not (Test-Path $Path)) {
    return
  }

  Assert-UnderDataDir $Path
  if ($Recurse) {
    Remove-Item -LiteralPath $Path -Recurse -Force
  } else {
    Remove-Item -LiteralPath $Path -Force
  }
}

function Enable-Tls12 {
  try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
  } catch {
  }
}

function Get-NodeMajorVersion {
  param([string]$NodePath = 'node')

  try {
    $versionText = (& $NodePath --version 2>$null | Select-Object -First 1).Trim()
    $match = [regex]::Match($versionText, '^v?(\d+)\.')
    if ($match.Success) {
      return [int]$match.Groups[1].Value
    }
  } catch {
  }

  return 0
}

function Get-NodeDownloadArchitecture {
  try {
    $arch = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
    switch ($arch) {
      'x64' { return 'win-x64' }
      'arm64' { return 'win-arm64' }
      'x86' { return 'win-x86' }
    }
  } catch {
  }

  $processorArch = [string]$env:PROCESSOR_ARCHITECTURE
  if ($processorArch -match 'ARM64') {
    return 'win-arm64'
  }
  if ($processorArch -match '86') {
    return 'win-x86'
  }

  return 'win-x64'
}

function Find-PortableNodeHome {
  $installRoot = Join-Path $dataDir 'nodejs'
  if (-not (Test-Path $installRoot)) {
    return ''
  }

  $candidates = Get-ChildItem -LiteralPath $installRoot -Directory -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

  foreach ($candidate in $candidates) {
    $nodePath = Join-Path $candidate.FullName 'node.exe'
    $npmPath = Join-Path $candidate.FullName 'npm.cmd'
    if ((Test-Path $nodePath) -and (Test-Path $npmPath) -and (Get-NodeMajorVersion $nodePath) -ge 18) {
      return $candidate.FullName
    }
  }

  return ''
}

function Get-NodeReleaseForDownload {
  param([string]$NodeArch)

  Enable-Tls12
  $fileTag = "$NodeArch-zip"
  $sources = @(
    @{
      Name = 'nodejs.org'
      IndexUrl = 'https://nodejs.org/dist/index.json'
      DownloadBase = 'https://nodejs.org/dist'
    },
    @{
      Name = 'npmmirror'
      IndexUrl = 'https://npmmirror.com/mirrors/node/index.json'
      DownloadBase = 'https://npmmirror.com/mirrors/node'
    }
  )
  $lastError = ''

  foreach ($source in $sources) {
    try {
      Write-Host "Checking Node.js releases from $($source.Name)..."
      $indexText = (Invoke-WebRequest -Uri $source.IndexUrl -UseBasicParsing).Content
      $releases = $indexText | ConvertFrom-Json

      foreach ($release in $releases) {
        $match = [regex]::Match([string]$release.version, '^v?(\d+)\.')
        if (-not $match.Success -or [int]$match.Groups[1].Value -lt 18) {
          continue
        }

        if ($release.lts -and $release.files -contains $fileTag) {
          $release | Add-Member -NotePropertyName DownloadBase -NotePropertyValue $source.DownloadBase -Force
          return $release
        }
      }

      foreach ($release in $releases) {
        $match = [regex]::Match([string]$release.version, '^v?(\d+)\.')
        if ($match.Success -and [int]$match.Groups[1].Value -ge 18 -and $release.files -contains $fileTag) {
          $release | Add-Member -NotePropertyName DownloadBase -NotePropertyValue $source.DownloadBase -Force
          return $release
        }
      }
    } catch {
      $lastError = $_.Exception.Message
      Write-Host "Could not check $($source.Name): $lastError"
    }
  }

  throw "No downloadable Node.js 18+ release was found for $NodeArch. $lastError"
}

function Install-PortableNode {
  $nodeArch = Get-NodeDownloadArchitecture
  $release = Get-NodeReleaseForDownload -NodeArch $nodeArch
  $version = [string]$release.version
  $installRoot = Join-Path $dataDir 'nodejs'
  $downloadsDir = Join-Path $dataDir 'downloads'
  $nodeHome = Join-Path $installRoot "$version-$nodeArch"

  if ((Test-Path (Join-Path $nodeHome 'node.exe')) -and (Get-NodeMajorVersion (Join-Path $nodeHome 'node.exe')) -ge 18) {
    Add-ProcessPathItem $nodeHome
    return $nodeHome
  }

  if (-not (Test-Path $installRoot)) {
    New-Item -ItemType Directory -Path $installRoot -Force | Out-Null
  }
  if (-not (Test-Path $downloadsDir)) {
    New-Item -ItemType Directory -Path $downloadsDir -Force | Out-Null
  }

  $zipName = "node-$version-$nodeArch.zip"
  $zipPath = Join-Path $downloadsDir $zipName
  $downloadBase = if ($release.PSObject.Properties['DownloadBase']) { [string]$release.DownloadBase } else { 'https://nodejs.org/dist' }
  $downloadUrl = "$downloadBase/$version/$zipName"

  Write-Host "Downloading Node.js $version ($nodeArch)..."
  Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing

  $tempExtractDir = Join-Path $downloadsDir "extract-$version-$nodeArch"
  Remove-ItemUnderDataDir -Path $tempExtractDir -Recurse
  New-Item -ItemType Directory -Path $tempExtractDir -Force | Out-Null

  Write-Host 'Extracting Node.js...'
  Expand-Archive -Path $zipPath -DestinationPath $tempExtractDir -Force

  $expandedHome = Get-ChildItem -LiteralPath $tempExtractDir -Directory -ErrorAction Stop | Select-Object -First 1
  if (-not $expandedHome -or -not (Test-Path (Join-Path $expandedHome.FullName 'node.exe'))) {
    throw 'Downloaded Node.js archive did not contain node.exe.'
  }

  Remove-ItemUnderDataDir -Path $nodeHome -Recurse
  Move-Item -LiteralPath $expandedHome.FullName -Destination $nodeHome
  Remove-ItemUnderDataDir -Path $tempExtractDir -Recurse

  Add-ProcessPathItem $nodeHome
  return $nodeHome
}

function Ensure-NodeRuntime {
  $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($nodeCommand -and (Get-NodeMajorVersion $nodeCommand.Source) -ge 18) {
    Write-Host "Node.js found: $($nodeCommand.Source)"
    return
  }

  $portableNodeHome = Find-PortableNodeHome
  if ($portableNodeHome) {
    Write-Host "Using bundled Node.js: $portableNodeHome"
    Add-ProcessPathItem $portableNodeHome
    return
  }

  if ($nodeCommand) {
    Write-Host 'Installed Node.js is older than 18. Downloading a project-local Node.js runtime...'
  } else {
    Write-Host 'Node.js 18+ was not found. Downloading a project-local Node.js runtime...'
  }

  $installedHome = Install-PortableNode
  Write-Host "Node.js ready: $installedHome"
}

function Get-NpmCmdPath {
  $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
  if ($npmCommand) {
    return $npmCommand.Source
  }

  $nodeCommand = Get-Command node.exe -ErrorAction SilentlyContinue
  if ($nodeCommand) {
    $candidate = Join-Path (Split-Path -Parent $nodeCommand.Source) 'npm.cmd'
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  throw 'npm.cmd was not found after preparing Node.js.'
}

function Add-NpmGlobalBinToPath {
  param([string]$NpmCmdPath)

  try {
    $prefix = (& $NpmCmdPath config get prefix 2>$null | Select-Object -First 1).Trim()
    if (-not [string]::IsNullOrWhiteSpace($prefix)) {
      Add-ProcessPathItem $prefix
    }
  } catch {
  }

  if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
    Add-ProcessPathItem (Join-Path $env:APPDATA 'npm')
  }
}

function Get-CcConnectVersion {
  param([string]$CommandPath)

  try {
    $versionOutput = (& $CommandPath --version 2>$null | Select-Object -First 1)
    $match = [regex]::Match([string]$versionOutput, 'v?(\d+\.\d+\.\d+(?:-[A-Za-z]+\.\d+)?)')
    if ($match.Success) {
      return $match.Groups[1].Value
    }
  } catch {
  }

  return ''
}

function Test-CcConnectVersionAtLeast {
  param([string]$Version)

  $match = [regex]::Match($Version, '^(\d+)\.(\d+)\.(\d+)(?:-([A-Za-z]+)\.(\d+))?$')
  if (-not $match.Success) {
    return $false
  }

  $major = [int]$match.Groups[1].Value
  $minor = [int]$match.Groups[2].Value
  $patch = [int]$match.Groups[3].Value
  $label = $match.Groups[4].Value
  $preNumber = if ($match.Groups[5].Success) { [int]$match.Groups[5].Value } else { -1 }

  if ($major -ne 1) {
    return $major -gt 1
  }
  if ($minor -ne 3) {
    return $minor -gt 3
  }
  if ($patch -ne 3) {
    return $patch -gt 3
  }
  if ([string]::IsNullOrWhiteSpace($label)) {
    return $true
  }

  return ($label.ToLowerInvariant() -eq 'beta' -and $preNumber -ge 1)
}

function Resolve-CcConnectPath {
  $ccConnectCmdPath = (Get-Command cc-connect.cmd -ErrorAction Stop).Source
  $ccConnectExeCandidate = Join-Path (Split-Path -Parent $ccConnectCmdPath) 'node_modules\cc-connect\bin\cc-connect.exe'
  if (Test-Path $ccConnectExeCandidate) {
    return $ccConnectExeCandidate
  }

  return $ccConnectCmdPath
}

function Ensure-CcConnect {
  $npmCmdPath = Get-NpmCmdPath
  Add-NpmGlobalBinToPath -NpmCmdPath $npmCmdPath

  $ccConnectCommand = Get-Command cc-connect.cmd -ErrorAction SilentlyContinue
  $needsInstall = $true
  if ($ccConnectCommand) {
    $version = Get-CcConnectVersion $ccConnectCommand.Source
    if (Test-CcConnectVersionAtLeast $version) {
      Write-Host "cc-connect found: $($ccConnectCommand.Source) ($version)"
      $needsInstall = $false
    } else {
      Write-Host "cc-connect is missing or too old ($version). Installing cc-connect@beta..."
    }
  } else {
    Write-Host 'cc-connect was not found. Installing cc-connect@beta...'
  }

  if ($needsInstall) {
    & $npmCmdPath install -g cc-connect@beta
    $installExitCode = $LASTEXITCODE
    if ($installExitCode -ne 0) {
      Write-Host "npm install failed with exit code $installExitCode. Retrying with registry.npmmirror.com..."
      & $npmCmdPath install -g cc-connect@beta --registry=https://registry.npmmirror.com
      $installExitCode = $LASTEXITCODE
    }
    if ($installExitCode -ne 0) {
      throw "npm.cmd install -g cc-connect@beta failed with exit code $installExitCode."
    }

    Add-NpmGlobalBinToPath -NpmCmdPath $npmCmdPath
    $ccConnectCommand = Get-Command cc-connect.cmd -ErrorAction SilentlyContinue
    if (-not $ccConnectCommand) {
      throw 'cc-connect installed, but cc-connect.cmd was not found on PATH.'
    }

    $version = Get-CcConnectVersion $ccConnectCommand.Source
    if (-not (Test-CcConnectVersionAtLeast $version)) {
      throw "Installed cc-connect version is still too old: $version"
    }
    Write-Host "cc-connect ready: $($ccConnectCommand.Source) ($version)"
  }

  $script:ccConnectPath = Resolve-CcConnectPath
}

function Ensure-RuntimeDependencies {
  Ensure-NodeRuntime
  Ensure-CcConnect
}

function Start-RouterWatchdog {
  if (-not (Test-Path $watchdogPath)) {
    throw "Missing watchdog script: $watchdogPath"
  }

  $args = @(
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-File',
    $watchdogPath,
    '-ParentPid',
    $PID,
    '-StatePath',
    $processStatePath
  )

  $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden -PassThru
  return $proc.Id
}

function Write-TrackedProcessIds {
  param([int[]]$Pids)

  if (-not (Test-Path $dataDir)) {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
  }

  if (-not $Pids -or $Pids.Count -eq 0) {
    Remove-Item -Force -ErrorAction SilentlyContinue $processStatePath
    return
  }

  $lines = $Pids | Where-Object { $_ -gt 0 } | Sort-Object -Unique | ForEach-Object { $_.ToString() }
  if ($lines.Count -eq 0) {
    Remove-Item -Force -ErrorAction SilentlyContinue $processStatePath
    return
  }

  Set-Content -Path $processStatePath -Value $lines -Encoding ASCII
}

function Clear-TrackedProcessIds {
  Remove-Item -Force -ErrorAction SilentlyContinue $processStatePath
}

function Stop-ExistingCcConnectForConfig {
  param([string]$ConfigFile)

  $fullConfigPath = [IO.Path]::GetFullPath($ConfigFile)
  $configPattern = [regex]::Escape($fullConfigPath)
  $currentProcessId = $PID

  $processes = Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object {
      $_.ProcessId -ne $currentProcessId -and
      $_.CommandLine -and
      $_.CommandLine -match $configPattern -and
      $_.CommandLine -match 'cc-connect'
    }

  foreach ($process in $processes) {
    try {
      Stop-Process -Id $process.ProcessId -Force -ErrorAction Stop
      Write-Host "Stopped stale cc-connect process pid $($process.ProcessId)."
    } catch {
    }
  }
}

function Show-LogTail {
  param(
    [string[]]$Paths,
    [int]$TailLines = 40
  )

  foreach ($path in $Paths) {
    if (-not (Test-Path $path)) {
      continue
    }

    Write-Host "Log: $path"
    Get-Content -Path $path -Encoding UTF8 -Tail $TailLines | ForEach-Object { Write-Host $_ }
  }
}

function Convert-SecureToText {
  param([System.Security.SecureString]$Secure)

  if (-not $Secure -or $Secure.Length -eq 0) {
    return ''
  }

  $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
  try {
    return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)
  } finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
  }
}

function Escape-CmdValue {
  param([string]$Value)

  if ($null -eq $Value) {
    return ''
  }

  return $Value.Replace('%', '%%')
}

function Escape-TomlString {
  param([string]$Value)

  if ($null -eq $Value) {
    return '""'
  }

  $normalized = ([string]$Value).Replace('\', '/')
  $escaped = $normalized.Replace('"', '\"')
  return [string]::Concat([char]34, $escaped, [char]34)
}

function Write-Utf8NoBomLines {
  param(
    [string]$Path,
    [string[]]$Lines
  )

  $encoding = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllLines($Path, $Lines, $encoding)
}

function Get-ExistingValue {
  param(
    [hashtable]$Existing,
    [string]$Key,
    [string]$Fallback
  )

  if ($Existing.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$Existing[$Key])) {
    return [string]$Existing[$Key]
  }

  return $Fallback
}

function Read-Plain {
  param(
    [string]$Label,
    [string]$Default = '',
    [switch]$Required
  )

  while ($true) {
    $prompt = if ($Default) { "$Label [$Default]" } else { $Label }
    $value = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($value)) {
      $value = $Default
    }
    if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
      Write-Host 'This value is required.'
      continue
    }
    return $value.Trim()
  }
}

function Read-Secret {
  param(
    [string]$Label,
    [string]$Default = '',
    [switch]$Required
  )

  while ($true) {
    $prompt = if ($Default) { "$Label [saved]" } else { $Label }
    $secure = Read-Host $prompt -AsSecureString
    $value = Convert-SecureToText $secure
    if ([string]::IsNullOrWhiteSpace($value)) {
      $value = $Default
    }
    if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
      Write-Host 'This value is required.'
      continue
    }
    return $value.Trim()
  }
}

function Read-Decimal {
  param(
    [string]$Label,
    [string]$Default = '',
    [switch]$Required
  )

  while ($true) {
    $value = Read-Plain $Label $Default -Required:$Required
    if ([string]::IsNullOrWhiteSpace($value)) {
      return ''
    }

    [double]$parsed = 0
    if ([double]::TryParse(
      $value,
      [System.Globalization.NumberStyles]::Float,
      [System.Globalization.CultureInfo]::InvariantCulture,
      [ref]$parsed
    )) {
      return $parsed.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }

    Write-Host 'Please enter a valid number.'
  }
}

function Read-PositiveInteger {
  param(
    [string]$Label,
    [string]$Default = '',
    [switch]$Required
  )

  while ($true) {
    $value = Read-Plain $Label $Default -Required:$Required
    if ([string]::IsNullOrWhiteSpace($value)) {
      return ''
    }

    [int]$parsed = 0
    if ([int]::TryParse($value, [ref]$parsed) -and $parsed -gt 0) {
      return $parsed.ToString()
    }

    Write-Host 'Please enter a positive integer.'
  }
}

function Read-MenuChoice {
  param(
    [string]$Label,
    [array]$Options,
    [string]$Default = '',
    [scriptblock]$CustomHandler = $null
  )

  $presetValues = @()
  $defaultIndex = 0
  for ($i = 0; $i -lt $Options.Count; $i++) {
    $optionValue = [string]$Options[$i].Value
    $presetValues += $optionValue
    if ($optionValue -eq $Default) {
      $defaultIndex = $i + 1
    }
  }

  while ($true) {
    Write-Host $Label
    for ($i = 0; $i -lt $Options.Count; $i++) {
      $option = $Options[$i]
      Write-Host ('  {0}. {1}' -f ($i + 1), [string]$option.Label)
    }

    $prompt = if ($defaultIndex -gt 0) {
      "$Label [$defaultIndex]"
    } elseif (-not [string]::IsNullOrWhiteSpace($Default)) {
      "$Label [saved]"
    } else {
      $Label
    }

    $input = Read-Host $prompt
    if ([string]::IsNullOrWhiteSpace($input)) {
      return $Default
    }

    if ($input -match '^\d+$') {
      $index = [int]$input
      if ($index -ge 1 -and $index -le $Options.Count) {
        $selected = $Options[$index - 1]
        if ([string]$selected.Value -eq '__custom__') {
          $customDefault = if ($presetValues -contains $Default) { '' } else { $Default }
          if ($null -ne $CustomHandler) {
            return & $CustomHandler $customDefault
          }
          return Read-Plain "$Label (custom)" $customDefault -Required
        }
        return [string]$selected.Value
      }
    }

    Write-Host 'Please choose one of the listed numbers.'
  }
}

function Load-LocalEnv {
  param([string]$Path)

  $values = @{}
  if (-not (Test-Path $Path)) {
    return $values
  }

  foreach ($line in Get-Content $Path) {
    if ($line -match '^\s*set\s+"([^=]+)=(.*)"\s*$') {
      $values[$matches[1]] = $matches[2].Replace('%%', '%')
    }
  }

  return $values
}

function Write-LocalEnv {
  param(
    [string]$Path,
    [hashtable]$Values
  )

  $keys = @(
    'WEIXIN_TOKEN',
    'WEIXIN_ALLOW_FROM',
    'WEIXIN_ADMIN_FROM',
    'WEIXIN_ACCOUNT_ID',
    'ROUTER_IMAGE_API_KEY',
    'ROUTER_IMAGE_ENDPOINT',
    'ROUTER_IMAGE_PROVIDER',
    'ROUTER_IMAGE_MODEL',
    'ROUTER_IMAGE_API',
    'ROUTER_CODE_API_KEY',
    'ROUTER_CODE_ENDPOINT',
    'ROUTER_CODE_PROVIDER',
    'ROUTER_CODE_MODEL',
    'ROUTER_IMAGE_SIZE',
    'ROUTER_IMAGE_QUALITY',
    'ROUTER_CODE_TEMPERATURE',
    'ROUTER_CODE_MAX_OUTPUT_TOKENS',
    'ROUTER_CODE_REASONING_EFFORT'
  )

  $lines = @(
    '@ECHO off',
    'REM Auto-generated by launch-router.cmd. Re-run it to change values.'
  )

  foreach ($key in $keys) {
    if ($Values.ContainsKey($key)) {
      $lines += 'set "' + $key + '=' + (Escape-CmdValue $Values[$key]) + '"'
    }
  }

  Write-Utf8NoBomLines -Path $Path -Lines $lines
}

function Clear-WeixinRuntimeState {
  param([string]$Dir)

  $weixinDir = Join-Path $Dir 'weixin'
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $weixinDir
}

function Set-ProcessEnvValues {
  param([hashtable]$Values)

  foreach ($key in $Values.Keys) {
    [Environment]::SetEnvironmentVariable($key, [string]$Values[$key], 'Process')
  }

  $rootPath = [IO.Path]::GetFullPath($root).TrimEnd('\')
  $currentPath = [Environment]::GetEnvironmentVariable('PATH', 'Process')
  $pathItems = @($rootPath)

  if (-not [string]::IsNullOrWhiteSpace($currentPath)) {
    $pathItems += ($currentPath -split ';' | Where-Object {
      if ([string]::IsNullOrWhiteSpace($_)) {
        return $false
      }

      try {
        return ([IO.Path]::GetFullPath($_).TrimEnd('\') -ne $rootPath)
      } catch {
        return $true
      }
    })
  }

  [Environment]::SetEnvironmentVariable('PATH', ($pathItems -join ';'), 'Process')
}

function Extract-WeixinToken {
  param([string]$Dir)

  $target = Join-Path $Dir 'weixin'
  if (-not (Test-Path $target)) {
    return ''
  }

  $bufFiles = Get-ChildItem -Path $target -Recurse -Filter 'get_updates.buf' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

  foreach ($file in $bufFiles) {
    $raw = (Get-Content -Path $file.FullName -Raw).Trim()
    if (-not $raw) {
      continue
    }

    try {
      $decoded = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($raw))
    } catch {
      continue
    }

    $match = [regex]::Match($decoded, '([A-Za-z0-9._-]+@im\.[A-Za-z0-9.-]+:[A-Za-z0-9]+)')
    if ($match.Success) {
      return $match.Groups[1].Value
    }
  }

  return ''
}

function Extract-WeixinTokenFromConfig {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return ''
  }

  $text = Get-Content -Path $Path -Raw
  $match = [regex]::Match($text, 'token\s*=\s*"([^"]+)"')
  if ($match.Success -and $match.Groups[1].Value -notlike '${*') {
    return $match.Groups[1].Value
  }

  return ''
}

function Get-WeixinUserIdFromText {
  param([string]$Text)

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return ''
  }

  $match = [regex]::Match($Text, '([A-Za-z0-9._-]+@im\.wechat)')
  if ($match.Success) {
    return $match.Groups[1].Value
  }

  return ''
}

function Extract-WeixinUserFromConfig {
  param([string]$Path)

  if (-not (Test-Path $Path)) {
    return ''
  }

  $text = Get-Content -Path $Path -Raw -Encoding UTF8
  foreach ($key in @('admin_from', 'allow_from')) {
    $match = [regex]::Match($text, "$key\s*=\s*`"([^`"]+)`"")
    if (-not $match.Success) {
      continue
    }

    $value = $match.Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($value) -or $value -eq '*' -or $value -like '${*') {
      continue
    }

    $userId = Get-WeixinUserIdFromText $value
    if ($userId) {
      return $userId
    }
  }

  return ''
}

function Extract-WeixinUserFromState {
  param([string]$Dir)

  foreach ($file in Get-ChildItem -Path $Dir -Recurse -Filter 'context_tokens.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) {
    try {
      $json = Get-Content -Path $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($property in $json.PSObject.Properties) {
        $userId = Get-WeixinUserIdFromText $property.Name
        if ($userId) {
          return $userId
        }
      }
    } catch {
    }
  }

  foreach ($file in Get-ChildItem -Path (Join-Path $Dir 'sessions') -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending) {
    try {
      $text = Get-Content -Path $file.FullName -Raw -Encoding UTF8
      $userId = Get-WeixinUserIdFromText $text
      if ($userId) {
        return $userId
      }
    } catch {
    }
  }

  return ''
}

function Write-WeixinSetupConfig {
  param([string]$Path)

  $tomlDataDir = Escape-TomlString $dataDir
  $tomlRoot = Escape-TomlString $root
  $tomlCmd = Escape-TomlString (Join-Path $root 'router.route.cmd')

  $lines = @(
    'language = "zh"',
    "data_dir = $tomlDataDir",
    '',
    '[log]',
    'level = "info"',
    '',
    '[[projects]]',
    'name = "test"',
    'show_context_indicator = false',
    'reply_footer = false',
    '',
    '[projects.agent]',
    'type = "codex"',
    '',
    '[projects.agent.options]',
    "work_dir = $tomlRoot",
    'mode = "full-auto"',
    "cmd = $tomlCmd"
  )

  Write-Utf8NoBomLines -Path $Path -Lines $lines
}

function Write-RouteConfig {
  param([string]$Path)

  $tomlDataDir = Escape-TomlString $dataDir
  $tomlRoot = Escape-TomlString $root
  $tomlRouteCmd = Escape-TomlString (Join-Path $root 'router.route.cmd')
  $tomlControlCmd = Escape-TomlString ((Join-Path $root 'router.control.cmd') + ' {{args:status}}')

  $lines = @(
    'language = "zh"',
    "data_dir = $tomlDataDir",
    '',
    '[log]',
    'level = "info"',
    '',
    '[[projects]]',
    'name = "test"',
    'admin_from = "${WEIXIN_ADMIN_FROM}"',
    'show_context_indicator = false',
    'reply_footer = false',
    '',
    '[projects.agent]',
    'type = "codex"',
    '',
    '[projects.agent.options]',
    "work_dir = $tomlRoot",
    'mode = "full-auto"',
    "cmd = $tomlRouteCmd",
    '',
    '[[projects.platforms]]',
    'type = "weixin"',
    '',
    '[projects.platforms.options]',
    'token = "${WEIXIN_TOKEN}"',
    'allow_from = "${WEIXIN_ALLOW_FROM}"',
    'account_id = "${WEIXIN_ACCOUNT_ID}"',
    'base_url = "https://ilinkai.weixin.qq.com"',
    '',
    '[[commands]]',
    'name = "route"',
    'description = "Show or switch the smart routing mode / \u67e5\u770b\u6216\u5207\u6362\u667a\u80fd\u8def\u7531\u6a21\u5f0f"',
    "exec = $tomlControlCmd",
    '',
    '[[aliases]]',
    'name = "\u5f53\u524d\u6a21\u5f0f"',
    'command = "/route status"',
    '',
    '[[aliases]]',
    'name = "\u56fe\u7247\u6a21\u5f0f"',
    'command = "/route image"',
    '',
    '[[aliases]]',
    'name = "\u56fe\u50cf\u6a21\u5f0f"',
    'command = "/route image"',
    '',
    '[[aliases]]',
    'name = "\u751f\u56fe\u6a21\u5f0f"',
    'command = "/route image"',
    '',
    '[[aliases]]',
    'name = "\u751f\u6210\u56fe\u7247\u6a21\u5f0f"',
    'command = "/route image"',
    '',
    '[[aliases]]',
    'name = "\u7ed8\u56fe\u6a21\u5f0f"',
    'command = "/route image"',
    '',
    '[[aliases]]',
    'name = "\u753b\u56fe\u6a21\u5f0f"',
    'command = "/route image"',
    '',
    '[[aliases]]',
    'name = "\u4ee3\u7801\u6a21\u5f0f"',
    'command = "/route code"',
    '',
    '[[aliases]]',
    'name = "\u95ee\u7b54\u6a21\u5f0f"',
    'command = "/route code"',
    '',
    '[[aliases]]',
    'name = "\u901a\u7528\u95ee\u7b54\u6a21\u5f0f"',
    'command = "/route code"',
    '',
    '[[aliases]]',
    'name = "\u81ea\u52a8\u6a21\u5f0f"',
    'command = "/route auto"',
    '',
    '[[aliases]]',
    'name = "\u667a\u80fd\u6a21\u5f0f"',
    'command = "/route auto"',
    '',
    '[[aliases]]',
    'name = "\u667a\u80fd\u8def\u7531"',
    'command = "/route auto"'
  )

  Write-Utf8NoBomLines -Path $Path -Lines $lines
}

function Invoke-WeixinSetup {
  param(
    [switch]$ForceQrLogin
  )

  Clear-TrackedProcessIds
  Remove-Item -Force -ErrorAction SilentlyContinue $setupOutPath, $setupErrPath

  $commandName = if ($ForceQrLogin) { 'new' } else { 'setup' }
  $args = @(
    'weixin',
    $commandName,
    '--config',
    $setupConfigPath,
    '--project',
    'test',
    '--qr-image',
    $qrImagePath,
    '--timeout',
    '600',
    '--set-allow-from-empty'
  )

  $process = Start-Process -FilePath $ccConnectPath -ArgumentList $args -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $setupOutPath -RedirectStandardError $setupErrPath
  if (-not $process) {
    throw 'Failed to start Weixin setup process.'
  }

  Write-TrackedProcessIds -Pids @($process.Id)

  $openedQr = $false

  while (-not $process.HasExited) {
    if (-not $openedQr -and (Test-Path $qrImagePath)) {
      try {
        $qr = Get-Item -LiteralPath $qrImagePath -ErrorAction Stop
        if ($qr.Length -gt 0) {
          Write-Host "QR image saved: $qrImagePath"
          Write-Host 'Opening QR image now. Scan the image window with Weixin.'
          Start-Process -FilePath $qrImagePath
          $openedQr = $true
        }
      } catch {
      }
    }

    Start-Sleep -Milliseconds 500
    $process.Refresh()
  }

  $process.WaitForExit()
  $exitCode = $process.ExitCode
  Clear-TrackedProcessIds

  if (-not $openedQr -and (Test-Path $qrImagePath)) {
    Write-Host "QR image saved: $qrImagePath"
    Start-Process -FilePath $qrImagePath
  }

  return $exitCode
}

function Start-WeixinQrLogin {
  param(
    [switch]$ForceRebind
  )

  Write-Host 'Starting Weixin QR login...'
  if ($ForceRebind) {
    Write-Host 'Rebinding Weixin: clearing cached bot state and forcing a fresh QR login...'
    Clear-WeixinRuntimeState $dataDir
  }
  Remove-Item -Force -ErrorAction SilentlyContinue $qrImagePath
  Remove-Item -Force -ErrorAction SilentlyContinue $setupConfigPath
  Write-WeixinSetupConfig $setupConfigPath

  try {
    $exitCode = Invoke-WeixinSetup -ForceQrLogin:$ForceRebind
    $token = Extract-WeixinTokenFromConfig $setupConfigPath
    if (-not $token) {
      $token = Extract-WeixinToken $dataDir
    }
    $adminFrom = Extract-WeixinUserFromConfig $setupConfigPath
    if (-not $adminFrom) {
      $adminFrom = Extract-WeixinUserFromState $dataDir
    }
    if (-not $token) {
      if ($exitCode -ne 0) {
        Write-Host 'Weixin setup log:'
        Show-LogTail -Paths @($setupOutPath, $setupErrPath)
      }
      throw 'Weixin login completed, but no token was found. Please send one WeChat message once, then run the launcher again.'
    }

    if ($exitCode -ne 0) {
      Write-Host "Weixin setup exited with code $exitCode, but the token was saved. Continuing..."
    }
  } finally {
    Remove-Item -Force -ErrorAction SilentlyContinue $setupConfigPath
  }

  $accountId = ($token -split ':', 2)[0]
  return @{
    WEIXIN_TOKEN = $token
    WEIXIN_ALLOW_FROM = '*'
    WEIXIN_ADMIN_FROM = $adminFrom
    WEIXIN_ACCOUNT_ID = $accountId
  }
}

function Prompt-ApiConfig {
  param([hashtable]$Existing)

  $config = @{}
  $config['ROUTER_IMAGE_API_KEY'] = Read-Secret 'Image API key' (Get-ExistingValue $Existing 'ROUTER_IMAGE_API_KEY' '') -Required
  $config['ROUTER_IMAGE_ENDPOINT'] = Read-Plain 'Image API endpoint' (Get-ExistingValue $Existing 'ROUTER_IMAGE_ENDPOINT' '') -Required
  $config['ROUTER_IMAGE_PROVIDER'] = Read-Plain 'Image provider' (Get-ExistingValue $Existing 'ROUTER_IMAGE_PROVIDER' 'openai-responses')
  $config['ROUTER_IMAGE_MODEL'] = Read-Plain 'Image model' (Get-ExistingValue $Existing 'ROUTER_IMAGE_MODEL' 'gpt-5')

  $config['ROUTER_CODE_API_KEY'] = Read-Secret 'Code API key' (Get-ExistingValue $Existing 'ROUTER_CODE_API_KEY' '') -Required
  $config['ROUTER_CODE_ENDPOINT'] = Read-Plain 'Code API endpoint' (Get-ExistingValue $Existing 'ROUTER_CODE_ENDPOINT' '') -Required
  $config['ROUTER_CODE_PROVIDER'] = Read-MenuChoice '代码提供方' @(
    @{ Label = 'OpenAI Responses (openai-responses)'; Value = 'openai-responses' },
    @{ Label = 'Anthropic (anthropic)'; Value = 'anthropic' },
    @{ Label = 'Google Gemini (gemini)'; Value = 'gemini' },
    @{ Label = 'DeepSeek (deepseek)'; Value = 'deepseek' },
    @{ Label = 'OpenRouter (openrouter)'; Value = 'openrouter' },
    @{ Label = '自定义'; Value = '__custom__' }
  ) (Get-ExistingValue $Existing 'ROUTER_CODE_PROVIDER' 'openai-responses') {
    param($Default)
    Read-Plain '自定义代码提供方' $Default -Required
  }
  $config['ROUTER_CODE_MODEL'] = Read-Plain 'Code model' (Get-ExistingValue $Existing 'ROUTER_CODE_MODEL' 'gpt-5')

  $config['ROUTER_IMAGE_SIZE'] = Read-MenuChoice '图片尺寸' @(
    @{ Label = '空白（使用接口默认）'; Value = '' },
    @{ Label = '1024x1024'; Value = '1024x1024' },
    @{ Label = '1536x1024'; Value = '1536x1024' },
    @{ Label = '1024x1536'; Value = '1024x1536' },
    @{ Label = '自定义'; Value = '__custom__' }
  ) (Get-ExistingValue $Existing 'ROUTER_IMAGE_SIZE' '') {
    param($Default)
    Read-Plain '自定义图片尺寸' $Default -Required
  }
  $config['ROUTER_IMAGE_QUALITY'] = Read-MenuChoice '图片质量' @(
    @{ Label = '低 (low)'; Value = 'low' },
    @{ Label = '中 (medium)'; Value = 'medium' },
    @{ Label = '高 (high)'; Value = 'high' }
  ) (Get-ExistingValue $Existing 'ROUTER_IMAGE_QUALITY' 'high')
  $config['ROUTER_CODE_TEMPERATURE'] = Read-MenuChoice '代码温度' @(
    @{ Label = '低 (0)'; Value = '0' },
    @{ Label = '标准 (0.2)'; Value = '0.2' },
    @{ Label = '平衡 (0.5)'; Value = '0.5' },
    @{ Label = '高 (0.8)'; Value = '0.8' },
    @{ Label = '自定义'; Value = '__custom__' }
  ) (Get-ExistingValue $Existing 'ROUTER_CODE_TEMPERATURE' '0.2') {
    param($Default)
    Read-Decimal '自定义代码温度' $Default -Required
  }
  $config['ROUTER_CODE_MAX_OUTPUT_TOKENS'] = Read-MenuChoice '最大输出长度' @(
    @{ Label = '不限制'; Value = '' },
    @{ Label = '自定义长度'; Value = '__custom__' }
  ) (Get-ExistingValue $Existing 'ROUTER_CODE_MAX_OUTPUT_TOKENS' '') {
    param($Default)
    Read-PositiveInteger '自定义最大输出长度' $Default -Required
  }

  return $config
}

function Merge-Hashtable {
  param(
    [hashtable]$Base,
    [hashtable]$Update
  )

  $merged = @{}
  foreach ($key in $Base.Keys) {
    $merged[$key] = $Base[$key]
  }
  foreach ($key in $Update.Keys) {
    $merged[$key] = $Update[$key]
  }
  return $merged
}

function Ensure-WeixinConfig {
  param(
    [hashtable]$Values,
    [switch]$ForceRebind
  )

  $current = Merge-Hashtable @{} $Values
  if ($ForceRebind -or [string]::IsNullOrWhiteSpace([string]$current['WEIXIN_TOKEN'])) {
    $weixin = Start-WeixinQrLogin -ForceRebind:$ForceRebind
    foreach ($key in $weixin.Keys) {
      $current[$key] = $weixin[$key]
    }
  } elseif ([string]::IsNullOrWhiteSpace([string]$current['WEIXIN_ACCOUNT_ID'])) {
    $current['WEIXIN_ACCOUNT_ID'] = ($current['WEIXIN_TOKEN'] -split ':', 2)[0]
  }

  if ([string]::IsNullOrWhiteSpace([string]$current['WEIXIN_ALLOW_FROM'])) {
    $current['WEIXIN_ALLOW_FROM'] = '*'
  }

  if ([string]::IsNullOrWhiteSpace([string]$current['WEIXIN_ADMIN_FROM'])) {
    $adminFrom = Extract-WeixinUserFromState $dataDir
    if (-not $adminFrom -and [string]$current['WEIXIN_ALLOW_FROM'] -ne '*') {
      $adminFrom = Get-WeixinUserIdFromText ([string]$current['WEIXIN_ALLOW_FROM'])
    }
    if ($adminFrom) {
      $current['WEIXIN_ADMIN_FROM'] = $adminFrom
    }
  }

  return $current
}

Set-ConsoleUtf8
Ensure-RuntimeDependencies
Write-RouteConfig -Path $configPath
$watchdogPid = Start-RouterWatchdog

$existing = Load-LocalEnv $envFile
$values = Merge-Hashtable @{} $existing
$forceRebind = $false
$needsApiPrompt = -not (Test-Path $envFile)

if (Test-Path $envFile) {
  Write-Host 'Saved config found.'
  $choice = Read-Host 'Enter U to use the saved config, C to change API values, or R to rebind Weixin'
  switch ($choice.Trim().ToUpperInvariant()) {
    'C' { $needsApiPrompt = $true }
    'R' { $forceRebind = $true }
    default { }
  }
}

$values = Ensure-WeixinConfig -Values $values -ForceRebind:$forceRebind

if ($needsApiPrompt) {
  $apiValues = Prompt-ApiConfig -Existing $values
  $values = Merge-Hashtable $values $apiValues
}

Write-LocalEnv -Path $envFile -Values $values
Set-ProcessEnvValues -Values $values
Write-Host "Saved local config: $envFile"

Stop-ExistingCcConnectForConfig -ConfigFile $configPath
Remove-Item -Force -ErrorAction SilentlyContinue $routeOutPath, $routeErrPath

$routeArgs = @(
  '--config',
  $configPath,
  '--force'
)

$routeProcess = Start-Process -FilePath $ccConnectPath -ArgumentList $routeArgs -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $routeOutPath -RedirectStandardError $routeErrPath
if (-not $routeProcess) {
  Clear-TrackedProcessIds
  throw 'Failed to start cc-connect route process.'
}

Write-TrackedProcessIds -Pids @($routeProcess.Id)
Write-Host "cc-connect route process started (pid $($routeProcess.Id))"

$routeProcess.WaitForExit()
$routeExitCode = $routeProcess.ExitCode
Clear-TrackedProcessIds

if ($routeExitCode -ne 0) {
  Write-Host 'cc-connect route log:'
  Show-LogTail -Paths @($routeOutPath, $routeErrPath)
}

exit $routeExitCode

