# YouTube Notes Agent Skill

This repository packages a reusable agent skill for turning YouTube videos into polished DOCX notes or complete transcript deliverables. The installable skill is under `skill/youtube-notes/`.

## Agent-Assisted Setup

After cloning or downloading the repository, give Codex or Claude Code this prompt:

> Set up the `youtube-notes` skill from this repository on this machine. Read `skill/youtube-notes/SKILL.md` and its bundled PowerShell scripts first. Install or configure the local dependencies appropriate for the operating system, install the complete skill in the current agent's personal skills directory, verify the skill structure and script syntax, and report any platform-specific integration that still needs adaptation. Do not process a video during installation.

## Install Locations

- Codex personal skill: `~/.codex/skills/youtube-notes/`
- Claude Code personal skill: `~/.claude/skills/youtube-notes/`
- Claude Code project skill: `.claude/skills/youtube-notes/`

Copy or link the complete `skill/youtube-notes/` directory. Do not copy only `SKILL.md`; the scripts are part of the workflow.

## Runtime Requirements

- PowerShell
- Network access to YouTube and the documented download sources
- `yt-dlp`
- `ffmpeg` when local transcription is needed
- whisper.cpp's `whisper-cli` and a compatible model when local transcription is needed
- Node.js when required by the installed `yt-dlp`/YouTube extraction path
- Codex CLI for the bundled GPT-5.6 Luna transcript-cleaning launcher
- Claude Code CLI for the bundled Claude DOCX launcher
- An isolated agent worker plus DOCX creation/visual-QA capability for the selected authoring route

On Windows, the acquisition script resolves tools from `PATH` and can download missing `yt-dlp`, ffmpeg, whisper.cpp, and the requested Whisper model into the current workspace's `.youtube-tools/` cache. On macOS or Linux, install native `yt-dlp`, `ffmpeg`, and `whisper-cli` commands on `PATH` before running the script.

## Portability

The skill contains no hard-coded user-profile paths. `SKILL.md` instructs the agent to resolve the directory containing the installed skill and invoke scripts relative to it. Dynamic environment references such as `$env:USERPROFILE` resolve locally on the current machine.

The workflow format transfers between agents, but tool names and model integrations do not automatically transfer. In particular, the Luna launcher calls Codex, while the Claude DOCX launcher calls Claude Code. An installing agent should adapt unavailable integrations while preserving the transcript-isolation boundary and output contract in `SKILL.md`.

## Repository Hygiene

Runtime tools, downloaded media, Whisper models, transcripts, logs, and generated documents are ignored by the included `.gitignore`. Review the bundled download URLs and your organization's software-installation policy before allowing automatic binary downloads.

No license has been selected. Add an appropriate license before publishing the repository publicly.
