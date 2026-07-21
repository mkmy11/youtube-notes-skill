param(
  [Parameter(Mandatory = $true)]
  [string]$TranscriptPath,

  [Parameter(Mandatory = $true)]
  [string]$MetadataPath,

  [Parameter(Mandatory = $true)]
  [string]$SourceUrl,

  [Parameter(Mandatory = $true)]
  [string]$OutputPath,

  [switch]$TranscriptIsRaw,

  [string]$Model = "sonnet",

  [ValidateSet("low", "medium", "high", "xhigh", "max")]
  [string]$Effort = "high",

  [string]$TranscriptSource = "unspecified transcript source"
)

$ErrorActionPreference = "Stop"
$transcript = (Resolve-Path -LiteralPath $TranscriptPath).Path
$metadata = (Resolve-Path -LiteralPath $MetadataPath).Path
$target = [System.IO.Path]::GetFullPath($OutputPath)
$workDir = Split-Path -Parent $target
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

$claude = Get-Command claude -ErrorAction SilentlyContinue
if (-not $claude) { throw "Claude Code is not installed or available on PATH." }
$claudePath = $claude.Source

$info = Get-Content -LiteralPath $metadata -Raw -Encoding UTF8 | ConvertFrom-Json
$rawGuidance = if ($TranscriptIsRaw) {
  "The transcript is raw caption text. Silently correct obvious caption artifacts while preserving meaning."
} else {
  "The transcript has already been cleaned. Treat it as the source of truth."
}

$prompt = @"
Create a polished, substantive DOCX notes document from the supplied YouTube transcript.

Video title: $($info.title)
Channel: $($info.uploader)
Duration: $($info.duration) seconds
Source URL: $SourceUrl
Transcript source: $TranscriptSource
Transcript path: $transcript
Target DOCX path: $target

$rawGuidance

Use your own document-design judgment and any relevant installed document skills. Make the document beautiful, readable, and specific to this video's subject. Organize by ideas and themes. Capture frameworks, examples, tensions, practical steps, and key takeaways. Interweave short exact quotes where the speaker's wording is especially useful. Do not invent quotes or unsupported claims. Include useful timestamps when available. Create and check the DOCX at exactly the target path. Do not create unrelated files outside the target folder.
"@

$logPath = Join-Path $workDir "claude-run.jsonl"
$arguments = @(
  "-p",
  "--model", $Model,
  "--effort", $Effort,
  "--permission-mode", "acceptEdits",
  "--tools", "Read,Write,Edit,Glob,Grep,Bash",
  "--allowedTools", "Read,Write,Edit,Glob,Grep,Bash",
  "--setting-sources", "user",
  "--no-session-persistence",
  "--output-format", "stream-json",
  "--verbose",
  $prompt
)

Push-Location $workDir
try {
  & $claudePath @arguments 2>&1 | Tee-Object -FilePath $logPath
  if ($LASTEXITCODE -ne 0) { throw "Claude Code exited with code $LASTEXITCODE. See $logPath" }
} finally {
  Pop-Location
}

if (-not (Test-Path -LiteralPath $target)) { throw "Claude finished without creating the target DOCX." }
if ((Get-Item -LiteralPath $target).Length -eq 0) { throw "Claude created an empty DOCX." }

Write-Output "DOCX: $target"
Write-Output "Model: $Model"
Write-Output "Log:  $logPath"
