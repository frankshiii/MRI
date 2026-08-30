# MRI for KOReader

[简体中文](README.md) | English

[![CI](https://github.com/frankshiii/MRI/actions/workflows/ci.yml/badge.svg)](https://github.com/frankshiii/MRI/actions/workflows/ci.yml)
[![License: AGPL-3.0-or-later](https://img.shields.io/badge/License-AGPL--3.0--or--later-blue.svg)](LICENSE)

MRI is an AI reading companion for EPUB books on small-screen Kindle devices running KOReader. It helps readers recall characters and earlier chapters, organise places and concepts, and ask questions within the current reading boundary.

The project is in early testing. Its prototype baseline is KOReader `v2025.08`, with `v2026.07` as the intended release baseline. PDF is not currently supported.

## Features

- Use one MRI action on selected text; it adapts to a person, place, concept, or passage.
- Recap the current chapter, the previous two chapters, or everything read so far, with spoiler protection enabled by default.
- Build people, places, and concept lists. Hybrid mode can use model knowledge for familiar books and expands book excerpts for less familiar works.
- Cache repeated questions and MRI entries separately for each book.
- Connect to OpenAI, Anthropic, Gemini, Qwen, DeepSeek, Kimi, and custom compatible endpoints.
- Configure API keys, model names, and endpoints from a computer.

## Installation

Download the ZIP from [Releases](https://github.com/frankshiii/MRI/releases). After extracting it, confirm that the directory is named `mri.koplugin`, then copy it to:

```text
koreader/plugins/mri.koplugin
```

Fully quit and restart KOReader.

To configure API keys on a computer, copy `mri.koplugin/config.example.json` to `mri.koplugin/config.json`, then enter your own settings. Git ignores `config.json`, and release packages exclude it.

On macOS, developers can double-click `同步 MRI 到 Kindle.command` to sync the current source to a connected Kindle. The script migrates an old `aireader.koplugin` directory to `mri.koplugin`; MRI also migrates legacy settings and per-book caches.

See the [detailed English documentation](mri.koplugin/README.en.md) for feature and privacy details. The [Chinese documentation](mri.koplugin/README.md) is also available.

## Development and releases

```bash
./scripts/check.sh
./scripts/package.sh dev
```

CI runs on every push and pull request. Pushing a tag such as `v0.1.0` triggers the release workflow, validates the source, builds the installation ZIP, and creates a GitHub Release. See the [CI/CD guide](docs/CI-CD.md) for the full workflow.

## KOReader contrib

KOReader's `contrib` repository includes third-party plugins as Git submodules. MRI will apply after testing on the target KOReader release and a physical Kindle. The `main` branch keeps development files around a nested `mri.koplugin` directory, while a dedicated `koreader-contrib` branch will expose `_meta.lua` at its root. See the [KOReader contrib guide](docs/KOREADER-CONTRIB.md) for preparation and submission steps.

## Contributing

Issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md) first.

## License

Copyright (C) 2026 Frank

Licensed under the GNU Affero General Public License v3.0 or later. See [LICENSE](LICENSE).
