[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$TranscriptPath,

  [Parameter(Mandatory = $true)]
  [string]$OutputPath
)

$ErrorActionPreference = "Stop"

$transcript = (Resolve-Path -LiteralPath $TranscriptPath).Path
$outputParent = Split-Path -Parent $OutputPath
if (-not $outputParent) {
  $outputParent = (Get-Location).Path
}
if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
  throw "Output directory does not exist: $outputParent"
}
$output = [System.IO.Path]::GetFullPath((Join-Path $outputParent (Split-Path -Leaf $OutputPath)))

$codex = Get-Command codex -ErrorAction Stop
$prompt = @"
Clean the complete YouTube caption transcript at:
$transcript

Return only the complete cleaned Markdown transcript as your final response. Do not summarize, omit material, or invent claims. Correct obvious caption errors, punctuation, capitalization, and paragraph breaks. Add concise topic headings at meaningful transitions, with useful source timestamps in headings when available. Preserve the speaker's meaning and quoted wording. Do not include a preface, postscript, QA report, or fenced code block.
"@

& $codex.Source exec `
  --model "gpt-5.6-luna" `
  --sandbox "read-only" `
  --ephemeral `
  --output-last-message $output `
  $prompt

if ($LASTEXITCODE -ne 0) {
  throw "GPT-5.6 Luna transcript-cleaning worker failed with exit code $LASTEXITCODE. No fallback model was used."
}
if (-not (Test-Path -LiteralPath $output -PathType Leaf)) {
  throw "GPT-5.6 Luna did not create the cleaned transcript: $output"
}
if ((Get-Item -LiteralPath $output).Length -eq 0) {
  throw "GPT-5.6 Luna created an empty cleaned transcript: $output"
}

Write-Output $output
