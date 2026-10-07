<#
.SYNOPSIS
  Installs the Roblox + Claude Code team setup: the skills, the /setup standard, the team CLAUDE.md block and the
  robloxMeshTools kit, then checks the toolchain and smoke-tests headless Blender.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File install.ps1 -ProjectsDir "D:\Roblox"
  powershell -ExecutionPolicy Bypass -File install.ps1 -Persona jarvis
#>
param(
    [string]$ProjectsDir = (Join-Path $HOME "RobloxProjects"),
    [string]$Persona = "",
    [string]$ClaudeHome = (Join-Path $HOME ".claude"),
    [switch]$SkipMeshTools,
    [switch]$SkipSmokeTest
)

$ErrorActionPreference = "Stop"
$Repo = $PSScriptRoot
$MeshToolsCommit = "01b74d5c25f799b7622b9a74e57266a83398bcfb"
$BeginMarker = "<!-- roblox-claude-setup:begin -->"
$EndMarker = "<!-- roblox-claude-setup:end -->"
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$Problems = New-Object System.Collections.Generic.List[string]

function Say([string]$Text) { Write-Host "  $Text" }
function Step([string]$Text) { Write-Host ""; Write-Host "== $Text" -ForegroundColor Cyan }

Step "Toolchain"
$node = Get-Command node -ErrorAction SilentlyContinue
if ($node) {
    $nodeVersion = (& node --version).TrimStart("v")
    if ([int]($nodeVersion.Split(".")[0]) -lt 18) { $Problems.Add("Node $nodeVersion is older than 18: install Node 18+ from https://nodejs.org") }
    Say "node $nodeVersion"
} else { $Problems.Add("Node is not installed: install Node 18+ from https://nodejs.org") }

if (Get-Command git -ErrorAction SilentlyContinue) { Say (& git --version) } else { $Problems.Add("git is not installed: https://git-scm.com") }
if (Get-Command claude -ErrorAction SilentlyContinue) { Say "claude found" } else { $Problems.Add("Claude Code CLI not on PATH: https://code.claude.com (the desktop app works too)") }

$blender = $env:BLENDER
if (-not $blender) {
    $foundation = Join-Path ${env:ProgramFiles} "Blender Foundation"
    if (Test-Path $foundation) {
        $newest = Get-ChildItem $foundation -Directory | Sort-Object { [version](($_.Name -replace "[^0-9.]", "") + ".0") } -Descending | Select-Object -First 1
        if ($newest -and (Test-Path (Join-Path $newest.FullName "blender.exe"))) { $blender = Join-Path $newest.FullName "blender.exe" }
    }
}
if ($blender) { Say "blender $blender" } else { $Problems.Add("Blender 4.1+ not found: install it from https://www.blender.org (or set the BLENDER env var to blender.exe)") }

Step "Skills -> $ClaudeHome\skills"
$skillsTarget = Join-Path $ClaudeHome "skills"
$backup = Join-Path $ClaudeHome "backups\roblox-claude-setup-$Stamp"
New-Item -ItemType Directory -Force -Path $skillsTarget | Out-Null
foreach ($skill in Get-ChildItem (Join-Path $Repo "skills") -Directory) {
    $target = Join-Path $skillsTarget $skill.Name
    if (Test-Path $target) {
        New-Item -ItemType Directory -Force -Path $backup | Out-Null
        Move-Item $target (Join-Path $backup $skill.Name)
    }
    Copy-Item $skill.FullName $target -Recurse
    Say "/$($skill.Name)"
}
$oldCache = Join-Path $backup "assetshot\cache"
if (Test-Path $oldCache) { Move-Item $oldCache (Join-Path $skillsTarget "assetshot\cache"); Say "kept the existing /assetshot cache" }
$oldKit = Join-Path $backup "importmeshtools\vendor\robloxMeshTools"
if (Test-Path $backup) { Say "previous versions backed up to $backup" }

Step "robloxMeshTools (MrChickenRocket/robloxMeshTools @ $($MeshToolsCommit.Substring(0, 7)))"
$kitTarget = Join-Path $skillsTarget "importmeshtools\vendor\robloxMeshTools"
New-Item -ItemType Directory -Force -Path (Split-Path $kitTarget) | Out-Null
if ($SkipMeshTools) {
    if (Test-Path $oldKit) {
        Move-Item $oldKit $kitTarget
        Say "skipped the download (-SkipMeshTools); kept your existing copy"
    } else { Say "skipped (-SkipMeshTools); /blenderassets push needs it at $kitTarget" }
} else {
    try {
        $zip = Join-Path $env:TEMP "robloxMeshTools-$MeshToolsCommit.zip"
        $unpack = Join-Path $env:TEMP "robloxMeshTools-$Stamp"
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing "https://github.com/MrChickenRocket/robloxMeshTools/archive/$MeshToolsCommit.zip" -OutFile $zip
        Expand-Archive $zip -DestinationPath $unpack -Force
        New-Item -ItemType Directory -Force -Path (Split-Path $kitTarget) | Out-Null
        if (Test-Path $kitTarget) { Remove-Item $kitTarget -Recurse -Force -Confirm:$false }
        Move-Item (Get-ChildItem $unpack -Directory | Select-Object -First 1).FullName $kitTarget
        Set-Content -Encoding utf8 -Path (Join-Path $kitTarget "VENDORED.md") -Value "# Vendored copy`n`n- Upstream: https://github.com/MrChickenRocket/robloxMeshTools`n- Commit: $MeshToolsCommit`n- Fetched: $Stamp by install.ps1`n`nDo not edit these files; upstream updates replace this folder wholesale."
        Remove-Item $zip, $unpack -Recurse -Force -Confirm:$false
        Say "fetched into $kitTarget"
    } catch {
        if (Test-Path $oldKit) {
            Move-Item $oldKit $kitTarget
            Say "download failed; restored your previous copy"
        } else { $Problems.Add("Could not download robloxMeshTools ($($_.Exception.Message)); re-run install.ps1 when online") }
    }
}

Step "CLAUDE.md"
New-Item -ItemType Directory -Force -Path $ProjectsDir | Out-Null
$block = Get-Content -Raw -Encoding utf8 (Join-Path $Repo "claude\CLAUDE.md")
$block = $block.Replace("<projects>", $ProjectsDir)
if ($Persona) {
    $personaFile = Join-Path $Repo "claude\personas\$Persona.md"
    if (-not (Test-Path $personaFile)) { throw "No persona named $Persona in claude\personas" }
    $block = (Get-Content -Raw -Encoding utf8 $personaFile) + "`n" + $block
    Say "persona: $Persona"
}
$claudeMd = Join-Path $ClaudeHome "CLAUDE.md"
$existing = ""
if (Test-Path $claudeMd) { $existing = Get-Content -Raw -Encoding utf8 $claudeMd }
$registered = ""
$begin = $existing.IndexOf($BeginMarker)
$end = $existing.IndexOf($EndMarker)
if ($begin -ge 0 -and $end -gt $begin) {
    $oldBlock = $existing.Substring($begin, $end - $begin)
    $listAt = $oldBlock.IndexOf("Known project update logs:")
    if ($listAt -ge 0) { $registered = $oldBlock.Substring($listAt + "Known project update logs:".Length).Trim() }
    $existing = $existing.Substring(0, $begin) + $existing.Substring($end + $EndMarker.Length)
}
if ($registered) { $block = $block.TrimEnd() + "`n" + $registered + "`n" }
$merged = $existing.TrimEnd()
if ($merged) { $merged += "`n`n" }
$merged += "$BeginMarker`n$($block.TrimEnd())`n$EndMarker`n"
if (Test-Path $claudeMd) { Copy-Item $claudeMd "$claudeMd.bak-$Stamp" }
[IO.File]::WriteAllText($claudeMd, $merged, (New-Object Text.UTF8Encoding($false)))
Say "team block written to $claudeMd (between the roblox-claude-setup markers; anything else you had is kept)"
Say "projects folder: $ProjectsDir"

if (-not $SkipSmokeTest -and $node -and $blender) {
    Step "Smoke build (headless Blender)"
    $out = Join-Path $env:TEMP "roblox-claude-setup-smoke"
    $env:BLENDER = $blender
    $result = & node (Join-Path $skillsTarget "blenderassets\blend.js") build (Join-Path $skillsTarget "blenderassets\examples\pumpkin_crate.py") --out $out 2>&1 | Out-String
    if ($result -match "built PumpkinCrate" -and $result -notmatch "(?m)^\s*(warn|error)") { Say "built PumpkinCrate: Blender works" }
    else { $Problems.Add("Smoke build failed:`n$result") }
}

Step "Next, by hand"
Say "1. Studio MCP plugin: download it from https://github.com/boshyxd/robloxstudio-mcp/releases (upstream is archived;"
Say "   the maintained fork is https://github.com/Chrrxs/robloxstudio-mcp) into %LOCALAPPDATA%\Roblox\Plugins,"
Say "   and turn on Game Settings > Security > Allow HTTP Requests in each place."
Say "2. Add the server to Claude Code:  claude mcp add robloxstudio -- npx -y robloxstudio-mcp@latest"
Say "3. Optional: merge claude\settings.example.json into $ClaudeHome\settings.json (allows the skill scripts, denies playtests)."
Say "4. Optional, for /create-devproduct, /create-gamepass, /upload-images: put ROBLOX_OPEN_CLOUD_API_KEY=... in $ClaudeHome\.env"
Say "5. Open baseplate\RunnerBaseplate.rbxl in Studio, publish it as a new experience, then in Claude Code: /setup <ProjectName>"

if ($Problems.Count) {
    Step "Needs attention"
    foreach ($problem in $Problems) { Write-Host "  - $problem" -ForegroundColor Yellow }
    exit 1
}
Write-Host ""
Write-Host "Installed." -ForegroundColor Green
