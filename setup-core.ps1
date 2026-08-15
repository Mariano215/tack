# setup-core.ps1  [harnessRoot]
# Windows bootstrap: record the profile-repo root, install the tokensave CLI, and
# confirm Git Bash is available (the tack switcher and apply-profile are bash
# scripts; on Windows run them from Git Bash or WSL).
param([string]$HarnessRoot = "$env:USERPROFILE\Projects")

$ErrorActionPreference = "Stop"
$coreDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$claude  = "$env:USERPROFILE\.claude"
New-Item -ItemType Directory -Force -Path $claude | Out-Null
Set-Content -Path "$claude\.harness-root" -Value $HarnessRoot
Write-Host "harness root recorded: $HarnessRoot"

# tokensave CLI (used as CLI, not MCP; do NOT run `tokensave install`).
# Best-effort chain: existing binary -> scoop -> cargo -> prebuilt release zip.
function Install-Tokensave {
  if (Get-Command tokensave -ErrorAction SilentlyContinue) { Write-Host "tokensave present"; return }

  if (Get-Command scoop -ErrorAction SilentlyContinue) {
    scoop bucket add tokensave https://github.com/aovestdipaperino/scoop-aovestdipaperino 2>$null
    scoop install tokensave
    if (Get-Command tokensave -ErrorAction SilentlyContinue) { return }
  }

  if (Get-Command cargo -ErrorAction SilentlyContinue) {
    cargo install tokensave
    if (Get-Command tokensave -ErrorAction SilentlyContinue) { Write-Host "tokensave installed via cargo"; return }
  }

  # Prebuilt release zip: resolve the latest tag, match the arch, extract to ~/.claude/bin.
  $arch = if ($env:PROCESSOR_ARCHITECTURE -match 'ARM64') { 'aarch64' } else { 'x86_64' }
  $bin  = "$claude\bin"
  try {
    $rel = Invoke-RestMethod "https://api.github.com/repos/aovestdipaperino/tokensave/releases/latest"
    $tag = $rel.tag_name
    $url = "https://github.com/aovestdipaperino/tokensave/releases/download/$tag/tokensave-$tag-$arch-windows.zip"
    $zip = Join-Path $env:TEMP "tokensave-$tag-$arch.zip"
    Invoke-WebRequest $url -OutFile $zip
    New-Item -ItemType Directory -Force -Path $bin | Out-Null
    Expand-Archive -Path $zip -DestinationPath $bin -Force
    Remove-Item $zip -Force
    # Ensure ~/.claude/bin is on the user PATH for future sessions.
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($userPath -notlike "*$bin*") {
      [Environment]::SetEnvironmentVariable("Path", "$userPath;$bin", "User")
      $env:Path = "$env:Path;$bin"
      Write-Host "added $bin to user PATH (restart shells to pick it up)"
    }
    Write-Host "tokensave installed to $bin (prebuilt $arch)"
  } catch {
    Write-Host "WARN: tokensave auto-install failed ($($_.Exception.Message))."
    Write-Host "      Install manually: cargo install tokensave, or a release zip from github.com/aovestdipaperino/tokensave/releases"
  }
}
Install-Tokensave

# claude-code profile function (plain claude, no proxy wrap).
# claude-tg (Telegram bot) is machine-local, not part of this shared setup.
function Install-ClaudeAliases {
  $marker = "# >>> tack aliases >>>"
  $endMarker = "# <<< tack aliases <<<"
  $block = @"
$marker
function claude-code { `$env:ANTHROPIC_API_KEY = ''; claude --dangerously-skip-permissions @args }
$endMarker
"@
  if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }
  $content = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
  if ($content -and $content -match [regex]::Escape($marker)) {
    $pattern = "(?s)" + [regex]::Escape($marker) + ".*?" + [regex]::Escape($endMarker)
    $content = $content -replace $pattern, $block.Trim()
    Set-Content -Path $PROFILE -Value $content
    Write-Host "tack aliases updated in $PROFILE"
  } else {
    Add-Content -Path $PROFILE -Value "`n$block"
    Write-Host "tack aliases added to $PROFILE"
  }
}
Install-ClaudeAliases

# tack on PATH, matching setup-core.sh. Without this the switcher was only
# reachable as `bash <coreDir>/bin/tack`, so `tack sync` did not exist on Windows and
# apply-profile's tack refresh landed somewhere Windows never looked.
$localBin = "$env:USERPROFILE\.local\bin"
New-Item -ItemType Directory -Force -Path $localBin | Out-Null
Copy-Item "$coreDir\bin\tack" "$localBin\tack" -Force
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$localBin*") {
  [Environment]::SetEnvironmentVariable("Path", "$userPath;$localBin", "User")
  $env:Path = "$env:Path;$localBin"
  Write-Host "added $localBin to user PATH (restart shells to pick it up)"
}
Write-Host "installed tack -> $localBin\tack"

foreach ($dep in @("bash", "jq", "git")) {
  if (-not (Get-Command $dep -ErrorAction SilentlyContinue)) {
    Write-Host "WARN: $dep not on PATH. Install Git for Windows (bash, git) and jq; tack/apply-profile need them."
  }
}
if (-not (Get-Command python3 -ErrorAction SilentlyContinue) -and -not (Get-Command python -ErrorAction SilentlyContinue)) {
  Write-Host "WARN: no python on PATH; the ghost prose hooks will skip."
}
Write-Host "done. Next (from Git Bash): tack install dev"
