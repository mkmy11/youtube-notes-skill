---
name: youtube-notes
description: Turn YouTube videos into polished DOCX notes or complete transcript files. Use for YouTube notes, summaries, study documents, transcript-only requests, cleaned transcripts, fast notes, Claude-created documents, forced local Whisper transcription, or presentation/demo mode. Keep transcripts and document contents out of the parent context by delegating every content-reading pass to isolated workers.
---

# YouTube Notes

Keep each video under `youtube-notes/<safe-title>-<video-id>/` in the current workspace. Return mobile-friendly deliverables from the workspace root.

## Resolve The Skill Directory

Resolve `<skill-dir>` to the absolute directory containing this `SKILL.md`. Never hard-code a user profile or assume whether the skill is installed under Codex, Claude Code, a project, or a cloned repository. Use the resolved absolute path when running bundled scripts.

## Bootstrap Dependencies

Before the first run, verify that PowerShell and network access are available. The acquisition script resolves `yt-dlp`, `ffmpeg`, and `whisper-cli` from `PATH` and downloads missing Windows binaries plus the requested Whisper model into `.youtube-tools` in the current workspace. It uses Node.js when available and also recognizes Codex's bundled Windows Node runtime. Require:

- the `codex` CLI only for the GPT-5.6 Luna cleaning launcher;
- the `claude` CLI only for the Claude DOCX launcher;
- a compatible isolated worker and DOCX creation capability for the selected authoring route.

If the current agent platform does not provide a named worker, skill, model alias, or CLI used below, adapt that integration while preserving the orchestration boundary and output contract. Keep `.youtube-tools/`, `youtube-notes/`, downloaded media, models, transcripts, logs, and generated documents out of the skill's source repository.

## Non-Negotiable Orchestration Boundary

The parent is a thin orchestrator. It may run acquisition/worker commands, pass exact paths, wait, and check `Test-Path` plus file length. It must never:

- open, print, preview, summarize, or search a raw or cleaned transcript;
- open `notes.source.md`, DOCX contents, rendered pages, contact sheets, or worker logs;
- load the `documents` skill for a delegated DOCX job;
- repeat, review, or repair a worker's cleaning, authoring, or visual QA;
- ask a worker to return document content in chat.

Worker completion messages must be path-only and concise. Unless the user explicitly requests content QA, existence and non-zero file length are the parent's complete verification gate.

## Select The Mode

- Default: acquire captions, clean with Luna, then delegate note authoring and DOCX creation together to one fresh isolated Codex worker that inherits the parent's selected model.
- `fast`: skip Luna and give the timestamped captions directly to one isolated Codex DOCX worker that inherits the parent's selected model.
- `Claude` or `Claude version`: acquire, clean with Luna unless also `fast`, then use the Claude DOCX launcher.
- `transcript only`: return `transcript.plain.txt`; do not read it or create notes.
- `clean transcript`: run Luna and return `transcript.cleaned.md`; do not read it or create notes.
- `Whisper`: force local Whisper `large-v3-turbo`. Otherwise use Whisper only when captions are missing, wrong-language, sparse, or corrupt.
- `presentation mode` or `demo mode`: force Whisper `large-v3-turbo`, clean with Luna, then use Claude Code's `haiku` alias at medium effort.

Do not invoke another YouTube skill for these variants.

## Acquire The Transcript

Run from the current workspace:

```powershell
& "<skill-dir>\scripts\get-youtube-transcript.ps1" -Url "<youtube-url>"
```

Add `-ForceWhisper -WhisperModel "large-v3-turbo"` only when Whisper is forced. The script downloads only when needed, creates the per-video folder, writes `transcript.txt`, `transcript.plain.txt`, and `video.info.json`, and prints a compact JSON result as its final line.

Use only paths from the current run. Do not open the files or reuse workspace-root/remembered paths from another run. There is no medium-sized turbo Whisper model.

## Clean With Luna

Run when required by the selected mode:

```powershell
& "<skill-dir>\scripts\invoke-luna-transcript-cleaner.ps1" `
  -TranscriptPath "<per-video-folder>\transcript.txt" `
  -OutputPath "<per-video-folder>\transcript.cleaned.md"
```

This launcher pins GPT-5.6 Luna in a fresh ephemeral process. Do not spawn a generic Luna subagent, run another cleaning pass, or compare raw and cleaned files. Wait in intervals of at most 60 seconds, then check only that the output exists and is non-empty.

## Delegate The Entire Codex DOCX Job

For default and `fast` modes, spawn exactly one fresh `notes_docx_builder` subagent with `fork_turns="none"`. Use normal subagent model inheritance so it runs the same model selected at the start of the parent chat: if the chat starts with Sol, the DOCX worker must be Sol. Do not pin, substitute, downgrade, or launch a different model for this worker. The only model exception is an explicitly requested Claude route. The parent must not read the transcript, metadata file, notes source, document, or QA images before or after delegation.

Give the worker only:

- the exact transcript path (`transcript.cleaned.md` by default, `transcript.txt` for `fast`);
- the exact metadata path;
- the source URL and transcript-source label from acquisition output;
- the exact per-video DOCX path and workspace-root DOCX path;
- whether the transcript is cleaned or raw.

Use this task contract:

> Read the transcript and metadata at the supplied paths. You alone own content authoring, DOCX construction, and visual QA. Read and follow the installed `documents` skill completely. Make one substantive pass over the transcript and create polished, quote-rich notes organized by ideas and themes. Capture important ideas, frameworks, examples, tensions, practical steps, exact quotes, useful timestamps, and key takeaways without inventing claims. If the input is raw, silently handle obvious caption noise while authoring; do not create a separate cleaning artifact. Include title, channel, duration, URL, and transcript source. Create the DOCX at the per-video path, render and inspect every page as required by the `documents` skill, fix objective layout defects in a bounded pass, and copy the final DOCX to the workspace-root path. Keep renders and temporary files internal. Do not send notes, transcript text, document content, or a QA narrative back to the parent. Your final response must be exactly `DONE: <workspace-root-path>` or `BLOCKED: <short reason>`.

Wait for the worker. Do not inspect its intermediate work. On `DONE`, check only that both requested DOCX files exist and are non-empty, then return the workspace-root file. On `BLOCKED`, report the short reason without attempting the document work in the parent.

## Claude DOCX Route

Run the existing isolated launcher; do not open its transcript, output, or log:

```powershell
& "<skill-dir>\scripts\invoke-claude-docx.ps1" `
  -TranscriptPath "<cleaned-or-raw-transcript>" `
  -MetadataPath "<per-video-folder>\video.info.json" `
  -SourceUrl "<youtube-url>" `
  -OutputPath "<per-video-folder>\<safe-title>-claude.docx" `
  -TranscriptIsRaw:<$true-or-$false> `
  -Model "sonnet" `
  -Effort "high" `
  -TranscriptSource "<source from acquisition>"
```

For presentation/demo mode, use the verified cleaned transcript, `-Model "haiku"`, `-Effort "medium"`, and transcript source `local Whisper large-v3-turbo audio transcription`. Narrate only transcribing, cleaning, and creating the DOCX. Copy the final file to the workspace root as `<safe-title>-<video-id>-demo-haiku.docx`.

Trust the isolated Claude worker's checks. The parent verifies only existence and non-zero length. Do not add Codex render QA unless the user explicitly asks to compare or verify the Claude version.

## Return

Return concise links only to requested deliverables and identify the transcript source as YouTube original captions, YouTube auto-generated captions, or local Whisper `large-v3-turbo` audio transcription. Mention recognition uncertainty for Whisper. Do not return audio, downloads, caption JSON, metadata, logs, temporary notes sources, or QA renders unless explicitly requested.
