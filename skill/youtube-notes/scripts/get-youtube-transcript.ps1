param(
  [Parameter(Mandatory = $true)]
  [string]$Url,

  [string]$WorkDir = ".",
  [string]$SubLangs = "en-orig,en",
  [switch]$ForceWhisper,
  [string]$WhisperModel = "large-v3-turbo",
  [int]$Threads = 16
)

$ErrorActionPreference = "Stop"
$runningOnWindows = $env:OS -eq "Windows_NT"
if (-not (Test-Path -LiteralPath $WorkDir)) {
  New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
}
$workspace = (Resolve-Path -LiteralPath $WorkDir).Path
$store = Join-Path $workspace "youtube-notes"
$tools = Join-Path $workspace ".youtube-tools"
$incoming = Join-Path $store (".incoming-" + [guid]::NewGuid().ToString("N"))

New-Item -ItemType Directory -Force -Path $store, $tools, $incoming | Out-Null

function Get-SafeName {
  param([Parameter(Mandatory = $true)][string]$Value, [int]$MaxLength = 80)

  $safe = $Value.ToLowerInvariant() -replace "[^a-z0-9]+", "-"
  $safe = $safe.Trim("-")
  if (-not $safe) { $safe = "youtube-video" }
  if ($safe.Length -gt $MaxLength) {
    $safe = $safe.Substring(0, $MaxLength).Trim("-")
  }
  return $safe
}

function Download-File {
  param([Parameter(Mandatory = $true)][string]$Uri, [Parameter(Mandatory = $true)][string]$OutFile)

  if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
    & curl.exe -L --fail --retry 5 --retry-all-errors -o $OutFile $Uri
    if ($LASTEXITCODE -eq 0) { return }
  }
  Invoke-WebRequest -Uri $Uri -OutFile $OutFile
}

function Resolve-Tool {
  param([Parameter(Mandatory = $true)][string]$Name, [string[]]$Fallbacks = @())

  $command = Get-Command $Name -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }
  foreach ($candidate in $Fallbacks) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) { return $candidate }
  }
  return $null
}

function Format-Time {
  param([double]$Seconds)

  $time = [TimeSpan]::FromSeconds([math]::Floor($Seconds))
  if ($time.Hours -gt 0) {
    return "{0:00}:{1:00}:{2:00}" -f $time.Hours, $time.Minutes, $time.Seconds
  }
  return "{0:00}:{1:00}" -f $time.Minutes, $time.Seconds
}

$ytDlp = Resolve-Tool -Name "yt-dlp" -Fallbacks @((Join-Path $tools "yt-dlp.exe"))
if (-not $ytDlp) {
  if (-not $runningOnWindows) {
    throw "yt-dlp is required on PATH on non-Windows systems. Install it with the platform package manager, then retry."
  }
  $ytDlp = Join-Path $tools "yt-dlp.exe"
  Download-File -Uri "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe" -OutFile $ytDlp
}

$nodeFallbacks = @()
if ($env:USERPROFILE) {
  $nodeFallbacks += Join-Path $env:USERPROFILE ".cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe"
}
$node = Resolve-Tool -Name "node" -Fallbacks $nodeFallbacks

$outputTemplate = Join-Path $incoming "source.%(id)s.%(ext)s"
$metadataArgs = @("--skip-download", "--write-info-json", "--output", $outputTemplate)
if (-not $ForceWhisper) {
  $metadataArgs += @("--write-subs", "--write-auto-subs", "--sub-langs", $SubLangs, "--sub-format", "json3")
}
if ($node) {
  $metadataArgs = @("--js-runtimes", "node:$node") + $metadataArgs
}
$metadataArgs += $Url

& $ytDlp @metadataArgs
if ($LASTEXITCODE -ne 0) { throw "yt-dlp could not fetch YouTube metadata or captions." }

$infoFile = Get-ChildItem -LiteralPath $incoming -Filter "*.info.json" -File | Select-Object -First 1
if (-not $infoFile) { throw "YouTube metadata was not written." }

$info = Get-Content -LiteralPath $infoFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
$videoId = [string]$info.id
$safeTitle = Get-SafeName -Value ([string]$info.title)
$videoRoot = Join-Path $store ("{0}-{1}" -f $safeTitle, $videoId)
New-Item -ItemType Directory -Force -Path $videoRoot | Out-Null

Get-ChildItem -LiteralPath $incoming -File | ForEach-Object {
  Move-Item -LiteralPath $_.FullName -Destination (Join-Path $videoRoot $_.Name) -Force
}
Remove-Item -LiteralPath $incoming -Force

$metadataPath = Join-Path $videoRoot "video.info.json"
$compactInfo = [ordered]@{
  id = [string]$info.id
  title = [string]$info.title
  uploader = [string]$info.uploader
  channel = [string]$info.channel
  duration = $info.duration
  webpage_url = [string]$info.webpage_url
  upload_date = [string]$info.upload_date
  description = [string]$info.description
}
[System.IO.File]::WriteAllText(
  $metadataPath,
  ($compactInfo | ConvertTo-Json -Depth 4),
  [System.Text.UTF8Encoding]::new($false)
)
Remove-Item -LiteralPath (Join-Path $videoRoot $infoFile.Name) -Force
$timestampedPath = Join-Path $videoRoot "transcript.txt"
$plainPath = Join-Path $videoRoot "transcript.plain.txt"
$source = $null
$captionFile = $null

if (-not $ForceWhisper) {
  $captionFiles = Get-ChildItem -LiteralPath $videoRoot -Filter "*.json3" -File
  $captionFile = $captionFiles | Where-Object { $_.Name -match "\.en-orig\." } | Select-Object -First 1
  if (-not $captionFile) {
    $captionFile = $captionFiles | Where-Object { $_.Name -match "\.en\." } | Select-Object -First 1
  }
  if (-not $captionFile) {
    $captionFile = $captionFiles | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  }
}

if ($captionFile) {
  $captionData = Get-Content -LiteralPath $captionFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
  $timestamped = New-Object System.Collections.Generic.List[string]
  $plain = New-Object System.Collections.Generic.List[string]
  $previous = $null

  foreach ($event in $captionData.events) {
    if (-not $event.segs) { continue }
    $text = ($event.segs | ForEach-Object { $_.utf8 }) -join ""
    $text = [System.Net.WebUtility]::HtmlDecode($text).Replace("`n", " ")
    $text = ($text -replace "\s+", " ").Trim()
    if (-not $text -or $text -eq $previous) { continue }
    $previous = $text
    $start = [double]$event.tStartMs / 1000
    $timestamped.Add(("[{0}] {1}" -f (Format-Time $start), $text))
    $plain.Add($text)
  }

  if ($timestamped.Count -gt 0) {
    [System.IO.File]::WriteAllLines($timestampedPath, $timestamped, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::WriteAllText($plainPath, ($plain -join " "), [System.Text.UTF8Encoding]::new($false))
    $language = if ($captionFile.Name -match "\.(?<language>[^.]+)\.json3$") { $Matches.language } else { $null }
    $manualLanguages = if ($info.subtitles) { @($info.subtitles.PSObject.Properties.Name) } else { @() }
    $source = if ($language -and $manualLanguages -contains $language) { "youtube-captions" } else { "youtube-auto-captions" }
  }
}

if (-not $source) {
  $whisperCli = Resolve-Tool -Name "whisper-cli" -Fallbacks @(
    (Get-ChildItem -LiteralPath $tools -Recurse -Filter "whisper-cli.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
  )
  if (-not $whisperCli) {
    if (-not $runningOnWindows) {
      throw "whisper-cli is required on PATH on non-Windows systems. Install whisper.cpp with the platform package manager, then retry."
    }
    $whisperZip = Join-Path $tools "whisper-bin-x64.zip"
    Download-File -Uri "https://github.com/ggml-org/whisper.cpp/releases/download/v1.9.1/whisper-bin-x64.zip" -OutFile $whisperZip
    Expand-Archive -LiteralPath $whisperZip -DestinationPath (Join-Path $tools "whisper") -Force
    $whisperCli = Get-ChildItem -LiteralPath $tools -Recurse -Filter "whisper-cli.exe" | Select-Object -First 1 -ExpandProperty FullName
  }

  $modelFile = Join-Path $tools "ggml-$WhisperModel.bin"
  if (-not (Test-Path -LiteralPath $modelFile)) {
    Download-File -Uri "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$WhisperModel.bin?download=true" -OutFile $modelFile
  }

  $ffmpeg = Resolve-Tool -Name "ffmpeg" -Fallbacks @(
    (Get-ChildItem -LiteralPath $tools -Recurse -Filter "ffmpeg.exe" -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName)
  )
  if (-not $ffmpeg) {
    if (-not $runningOnWindows) {
      throw "ffmpeg is required on PATH on non-Windows systems. Install it with the platform package manager, then retry."
    }
    $ffmpegZip = Join-Path $tools "ffmpeg.zip"
    Download-File -Uri "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-essentials.zip" -OutFile $ffmpegZip
    Expand-Archive -LiteralPath $ffmpegZip -DestinationPath (Join-Path $tools "ffmpeg") -Force
    $ffmpeg = Get-ChildItem -LiteralPath $tools -Recurse -Filter "ffmpeg.exe" | Select-Object -First 1 -ExpandProperty FullName
  }

  & $ytDlp -f "ba" --skip-unavailable-fragments --output (Join-Path $videoRoot "audio.%(ext)s") $Url
  if ($LASTEXITCODE -ne 0) { throw "yt-dlp could not download audio for Whisper." }
  $audio = Get-ChildItem -LiteralPath $videoRoot -Filter "audio.*" -File | Where-Object { $_.Extension -ne ".wav" } | Select-Object -First 1
  if (-not $audio) { throw "Downloaded audio could not be found." }

  $wav = Join-Path $videoRoot "audio.wav"
  & $ffmpeg -y -i $audio.FullName -ar 16000 -ac 1 -c:a pcm_s16le $wav
  if ($LASTEXITCODE -ne 0) { throw "ffmpeg could not prepare audio for Whisper." }

  $whisperBase = Join-Path $videoRoot "transcript"
  & $whisperCli -m $modelFile -f $wav -l en -otxt -osrt -of $whisperBase --threads $Threads
  if ($LASTEXITCODE -ne 0) { throw "Whisper transcription failed." }
  $srtPath = "$whisperBase.srt"
  if (-not (Test-Path -LiteralPath $srtPath)) { throw "Whisper did not write transcript.srt." }

  $srtText = Get-Content -LiteralPath $srtPath -Raw -Encoding UTF8
  $matches = [regex]::Matches($srtText, "(?ms)^\d+\s*\r?\n(?<start>\d{2}:\d{2}:\d{2})[,.]\d+\s+-->[^\r\n]*\r?\n(?<text>.*?)(?=\r?\n\r?\n|\z)")
  $timestamped = New-Object System.Collections.Generic.List[string]
  $plain = New-Object System.Collections.Generic.List[string]
  foreach ($match in $matches) {
    $text = ($match.Groups["text"].Value -replace "\r?\n", " " -replace "\s+", " ").Trim()
    if (-not $text) { continue }
    $timestamped.Add(("[{0}] {1}" -f $match.Groups["start"].Value, $text))
    $plain.Add($text)
  }
  if ($timestamped.Count -eq 0) { throw "Whisper produced an unreadable SRT transcript." }
  [System.IO.File]::WriteAllLines($timestampedPath, $timestamped, [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText($plainPath, ($plain -join " "), [System.Text.UTF8Encoding]::new($false))
  $source = "whisper-$WhisperModel"
}

$result = [ordered]@{
  video_id = $videoId
  title = [string]$info.title
  channel = [string]$info.uploader
  duration_seconds = $info.duration
  source = $source
  video_folder = $videoRoot
  transcript = $timestampedPath
  plain_transcript = $plainPath
  metadata = $metadataPath
}

Write-Output ($result | ConvertTo-Json -Compress)
