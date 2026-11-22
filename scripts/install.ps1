$ErrorActionPreference = 'Stop'

function Fail([string]$Message) {
  Write-Error "crit setup: $Message"
  exit 1
}

function Invoke-Native([string]$File, [string[]]$Arguments) {
  & $File @Arguments
  if ($LASTEXITCODE -ne 0) { Fail "$File $($Arguments -join ' ') failed ($LASTEXITCODE)" }
}

if (-not (Get-Command node -ErrorAction SilentlyContinue)) { Fail 'Install Node.js 24 or newer, then run setup again.' }
node -e 'if (Number(process.versions.node.split(".")[0]) < 24) process.exit(1)'
if ($LASTEXITCODE -ne 0) { Fail 'Node.js 24 or newer is required. Upgrade Node, then run setup again.' }
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Fail 'npm is required (it ships with Node.js).' }
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Fail 'git is required.' }

$installPrefix = if ($env:CRIT_INSTALL_PREFIX) { $env:CRIT_INSTALL_PREFIX } else { Join-Path $env:LOCALAPPDATA 'crit' }
if (-not [System.IO.Path]::IsPathRooted($installPrefix)) { Fail 'CRIT_INSTALL_PREFIX must be an absolute path.' }

$setupTmp = Join-Path ([System.IO.Path]::GetTempPath()) ("crit-setup-" + [System.Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $setupTmp | Out-Null

try {
  $sourceRoot = ''
  if ($PSScriptRoot) {
    $candidate = Split-Path -Parent $PSScriptRoot
    if (Test-Path (Join-Path $candidate 'apps\cli\package.json')) { $sourceRoot = $candidate }
  }
  if (-not $sourceRoot) {
    $installRepo = if ($env:CRIT_INSTALL_REPO) { $env:CRIT_INSTALL_REPO } else { 'essensus-io/crit' }
    $installRef = if ($env:CRIT_INSTALL_REF) { $env:CRIT_INSTALL_REF } else { 'main' }
    Write-Host "Fetching $installRepo ($installRef)..."
    $installUrl = if ($installRepo -match '://|^git@|^[A-Za-z]:[\\/]|^/') { $installRepo } else { "git@github.com:$($installRepo -replace '\.git$','').git" }
    $sourceRoot = Join-Path $setupTmp 'source'
    Invoke-Native git @('clone', '--depth', '1', '--branch', $installRef, $installUrl, $sourceRoot)
  }

  Set-Location $sourceRoot
  $packageManager = node -p 'require("./package.json").packageManager'
  if ($packageManager -notlike 'pnpm@*') { Fail 'Expected a pinned pnpm version in package.json.' }
  Write-Host 'Installing build dependencies and building crit...'
  Invoke-Native npm @('exec', '--yes', "--package=$packageManager", '--', 'pnpm', 'install', '--frozen-lockfile')
  Invoke-Native npm @('exec', '--yes', "--package=$packageManager", '--', 'pnpm', 'build')

  Set-Location (Join-Path $sourceRoot 'apps\cli')
  Invoke-Native npm @('pack', '--pack-destination', $setupTmp, '--silent')
  $packages = @(Get-ChildItem -Path $setupTmp -Filter '*.tgz')
  if ($packages.Count -ne 1) { Fail 'Expected one CLI package.' }
  Write-Host "Installing crit into $installPrefix..."
  Invoke-Native npm @('install', '--global', '--prefix', $installPrefix, '--omit=dev', '--no-audit', '--no-fund', $packages[0].FullName)
  Invoke-Native (Join-Path $installPrefix 'crit.cmd') @('--version')

  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
  $entries = if ($userPath) { $userPath -split ';' | Where-Object { $_ } } else { @() }
  if ($entries -notcontains $installPrefix) {
    [Environment]::SetEnvironmentVariable('Path', (@($entries) + $installPrefix) -join ';', 'User')
    Write-Host "`nAdded $installPrefix to your user PATH. Open a new terminal to use crit."
  }
  Write-Host "`nSetup complete. In any repository, run:`n  crit doctor`n  crit review`n`nRerun setup to update. Your provider settings and review history are kept."
}
finally {
  Set-Location $env:USERPROFILE
  Remove-Item -Recurse -Force $setupTmp -ErrorAction SilentlyContinue
}
