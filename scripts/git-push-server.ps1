param(
  [int]$Port = 8787
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
$Prefix = "http://127.0.0.1:$Port/"

function Send-Json($Context, [int]$StatusCode, $Data) {
  $Json = $Data | ConvertTo-Json -Depth 8
  $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)

  $Context.Response.StatusCode = $StatusCode
  $Context.Response.ContentType = "application/json; charset=utf-8"
  $Context.Response.Headers.Add("Access-Control-Allow-Origin", "*")
  $Context.Response.Headers.Add("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
  $Context.Response.Headers.Add("Access-Control-Allow-Headers", "Content-Type")
  $Context.Response.OutputStream.Write($Bytes, 0, $Bytes.Length)
  $Context.Response.OutputStream.Close()
}

function Invoke-Git($Arguments) {
  $Output = & git @Arguments 2>&1
  $ExitCode = $LASTEXITCODE

  return @{
    exitCode = $ExitCode
    output = ($Output -join "`n")
  }
}

function Get-GitStatus {
  Set-Location $RepoRoot
  $Status = Invoke-Git @("status", "--short")

  if ($Status.exitCode -ne 0) {
    throw $Status.output
  }

  return $Status.output
}

function Push-Changes {
  Set-Location $RepoRoot

  $BeforeStatus = Get-GitStatus
  if ([string]::IsNullOrWhiteSpace($BeforeStatus)) {
    return @{
      ok = $true
      pushed = $false
      message = "No local changes to push."
      status = ""
    }
  }

  $Add = Invoke-Git @("add", "-A")
  if ($Add.exitCode -ne 0) {
    throw "git add failed:`n$($Add.output)"
  }

  $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
  $Commit = Invoke-Git @("commit", "-m", "Update website content ($Timestamp)")

  if ($Commit.exitCode -ne 0) {
    throw "git commit failed:`n$($Commit.output)"
  }

  $Push = Invoke-Git @("push", "origin", "main")
  if ($Push.exitCode -ne 0) {
    throw "git push failed:`n$($Push.output)"
  }

  return @{
    ok = $true
    pushed = $true
    message = "Changes committed and pushed to origin/main."
    status = $BeforeStatus
    commit = $Commit.output
    push = $Push.output
  }
}

$Listener = [System.Net.HttpListener]::new()
$Listener.Prefixes.Add($Prefix)
$Listener.Start()

Write-Host "Git push server listening at $Prefix"
Write-Host "Repository: $RepoRoot"

try {
  while ($Listener.IsListening) {
    $Context = $Listener.GetContext()
    $Request = $Context.Request

    if ($Request.HttpMethod -eq "OPTIONS") {
      Send-Json $Context 200 @{ ok = $true }
      continue
    }

    try {
      switch ($Request.Url.AbsolutePath) {
        "/status" {
          Send-Json $Context 200 @{
            ok = $true
            status = Get-GitStatus
          }
        }
        "/push" {
          if ($Request.HttpMethod -ne "POST") {
            Send-Json $Context 405 @{ ok = $false; error = "Use POST for /push." }
            continue
          }

          Send-Json $Context 200 (Push-Changes)
        }
        default {
          Send-Json $Context 404 @{ ok = $false; error = "Unknown endpoint." }
        }
      }
    } catch {
      Send-Json $Context 500 @{
        ok = $false
        error = $_.Exception.Message
      }
    }
  }
} finally {
  $Listener.Stop()
}
