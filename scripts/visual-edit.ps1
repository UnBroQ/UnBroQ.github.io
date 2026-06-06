param(
  [int]$Port = 1313,
  [switch]$InstallLoreStudio
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
$LogDir = Join-Path $RepoRoot ".visual-edit"
$HugoLog = Join-Path $LogDir "hugo.log"
$CmsLog = Join-Path $LogDir "decap-server.log"
$PushLog = Join-Path $LogDir "git-push-server.log"

function Test-Command($Name) {
  return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Open-Url($Url) {
  Start-Process $Url | Out-Null
}

function Repair-TailwindShim {
  $TailwindBin = Join-Path $RepoRoot "node_modules\.bin\tailwindcss"
  $TailwindCli = Join-Path $RepoRoot "node_modules\@tailwindcss\cli\dist\index.mjs"

  if ((Test-Path $TailwindBin) -and (Test-Path $TailwindCli)) {
    $ExpectedShim = "#!/usr/bin/env node`nimport(`"../@tailwindcss/cli/dist/index.mjs`");`n"
    $CurrentShim = Get-Content -Path $TailwindBin -Raw -ErrorAction SilentlyContinue

    if ($CurrentShim -ne $ExpectedShim) {
      Write-Host "Repairing Windows Tailwind CLI shim for Hugo..."
      $Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
      [System.IO.File]::WriteAllText($TailwindBin, $ExpectedShim, $Utf8NoBom)
    }
  }
}

function Start-DecapServer {
  if (-not (Test-Command "npx.cmd")) {
    Write-Warning "npx.cmd is not available. The visual CMS at /admin will open, but local saving may not work until Node.js/npm is available."
    return
  }

  $ExistingCms = Get-CimInstance Win32_Process |
    Where-Object {
      $_.CommandLine -like "*decap-server*" -and
      $_.CommandLine -like "*$RepoRoot*"
    }

  if ($ExistingCms) {
    Write-Host "Decap local CMS server already appears to be running."
    return
  }

  Write-Host "Starting Decap local CMS server on http://localhost:8081 ..."
  $Command = "Set-Location '$RepoRoot'; npx.cmd --yes decap-server *> '$CmsLog'"
  Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $Command) | Out-Null
}

function Start-GitPushServer {
  $PushServerScript = Join-Path $RepoRoot "scripts\git-push-server.ps1"

  if (-not (Test-Path $PushServerScript)) {
    Write-Warning "Git push server script was not found. The /admin push button will be disabled."
    return
  }

  $ExistingPushServer = Get-CimInstance Win32_Process |
    Where-Object {
      $_.CommandLine -like "*git-push-server.ps1*" -and
      $_.CommandLine -like "*$RepoRoot*"
    }

  if ($ExistingPushServer) {
    Write-Host "Git push server already appears to be running."
    return
  }

  Write-Host "Starting Git push server on http://127.0.0.1:8787 ..."
  $Command = "Set-Location '$RepoRoot'; powershell -NoProfile -ExecutionPolicy Bypass -File '$PushServerScript' *> '$PushLog'"
  Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $Command) | Out-Null
}

function Assert-CompatibleHugo {
  $VersionOutput = & hugo version 2>$null

  if ($VersionOutput -match "hugo v(?<major>\d+)\.(?<minor>\d+)\.") {
    $Major = [int]$Matches.major
    $Minor = [int]$Matches.minor

    if (($Major -eq 0 -and $Minor -ge 161) -or ($Major -gt 0)) {
      throw @"
This site currently fails with Hugo $($Matches[0]) on Windows because Hugo 0.161+ performs stricter Tailwind CLI script checks.

Install Hugo Extended 0.160.0 instead, then reopen PowerShell:
  winget uninstall Hugo.Hugo.Extended
  winget install Hugo.Hugo.Extended --version 0.160.0

Then verify:
  hugo version
"@
    }
  }
}

Set-Location $RepoRoot
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

Write-Host "Personal site visual editing launcher"
Write-Host "Repository: $RepoRoot"

if (-not (Test-Command "hugo")) {
  throw "Hugo is not available on PATH. Install Hugo Extended, then run this script again."
}

Assert-CompatibleHugo

if (-not (Test-Path (Join-Path $RepoRoot "node_modules"))) {
  if (Test-Command "pnpm.cmd") {
    Write-Host "Installing Node dependencies with pnpm..."
    pnpm.cmd install
  } else {
    Write-Warning "pnpm is not available. Hugo can still run, but Tailwind/Pagefind tooling may be incomplete."
  }
}

Repair-TailwindShim
Start-DecapServer
Start-GitPushServer

$ExistingHugo = Get-CimInstance Win32_Process |
  Where-Object {
    $_.CommandLine -like "*hugo server*" -and
    $_.CommandLine -like "*--port $Port*" -and
    $_.CommandLine -like "*$RepoRoot*"
  }

if ($ExistingHugo) {
  Write-Host "Hugo server already appears to be running on port $Port."
} else {
  Write-Host "Starting Hugo server on http://localhost:$Port ..."
  $Command = "Set-Location '$RepoRoot'; hugo server --disableFastRender --port $Port --bind 127.0.0.1 *> '$HugoLog'"
  Start-Process powershell -WindowStyle Hidden -ArgumentList @("-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $Command) | Out-Null
  Start-Sleep -Seconds 3
}

if (Test-Command "code") {
  if ($InstallLoreStudio) {
    Write-Host "Installing Lore Studio VS Code extension..."
    code --install-extension lore.lore-studio
  }

  Write-Host "Opening project in VS Code..."
  code $RepoRoot
} else {
  Write-Warning "VS Code command 'code' is not available on PATH. Open this folder manually in VS Code for visual editing."
}

$PreviewUrl = "http://localhost:$Port"
$AdminUrl = "http://localhost:$Port/admin/"
Write-Host "Opening preview: $PreviewUrl"
Open-Url $PreviewUrl
Write-Host "Opening visual editor: $AdminUrl"
Open-Url $AdminUrl

Write-Host ""
Write-Host "Edit visually at $AdminUrl, or edit Markdown/YAML files directly."
Write-Host "Hugo log: $HugoLog"
Write-Host "Decap CMS log: $CmsLog"
Write-Host "Git push server log: $PushLog"
