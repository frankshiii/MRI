# MRI-Mobile_Reading_Intelligence

MRI is a spoiler-aware EPUB reading assistant designed for small Kindle screens. Its interface and answer language follow KOReader's Chinese or English UI setting.

## Features

- Recap the current chapter, previous two chapters, or the text read so far.
- Recaps send the allowed range in one request by default. MRI falls back to at most six chunk summaries and a merge only when the service explicitly reports a context or request-size limit; cancellation, network, and authentication errors are not retried as chunks.
- Build cached people, places, and representative recurring-concept lists.
- Reference lists use automatic hybrid mode by default: title, author, reading progress, chapter memory, and three small excerpts establish the edition and spoiler boundary, while reliable model knowledge may supply candidates and aliases. An unfamiliar work automatically expands to six excerpts. A setting can restrict lists to supplied book text only.
- Use one MRI selection action that adapts to a person, place, concept, or passage.
- Create a spoiler-free book guide or, when spoilers are enabled, a complete overview including the ending.
- Attach the book, author, overall progress, current chapter, and chapter progress internally to control scope and spoilers, without echoing those positions in the answer. Book content is paraphrased by default and quoted briefly only when exact wording matters.
- Choose short, medium, or long responses; the setting is injected into every system prompt and also adjusts the output-token limit.
- Optionally show a three-line MRI quick view before the detailed explanation. It is enabled by default and adapts its labels to people, places, concepts, or passages.
- After a user-initiated AI answer, MRI can prepare the people, places, and concepts lists with one combined background request. The foreground answer appears first; caches refresh after more than five percentage points of reading, and failures go only to the activity log. This is enabled by default and can be disabled in settings.
- Sample introductions, representative mentions, and recent mentions for better long-novel MRI entries.
- Store up to 80 AI answers locally per book. Identical MRI selections, recap scopes, book overviews, and Ask This Book questions are reused while reading progress remains within five percentage points. Changing the model, endpoint, spoiler setting, response length, or interface language invalidates the entry. Follow-up chat remains session-only.
- Ask This Book clearly shows whether it uses text read so far or whole-book excerpts that may contain spoilers.
- Chinese question dialogs add Previous / Select-Space / Next candidate controls directly above the keyboard, avoiding text-box gestures when choosing Pinyin characters.
- Continue a conversation within the current reading session.
- Generate and optionally show an automatic recap after finishing a chapter.
- Benchmark one whole-text request against the current split-and-merge recap flow. The activity log records input size, estimated tokens, per-request latency, and total latency. The benchmark uses real API quota.
- Use OpenAI, Anthropic, Gemini, Qwen, DeepSeek, Kimi, or custom compatible endpoints.

MRI currently supports EPUB only. The prototype baseline is KOReader `v2025.08`; the intended release baseline is `v2026.07`.

## Installation

Copy the complete `mri.koplugin` directory into KOReader's `plugins` directory, then fully quit and restart KOReader.

MRI appears near the top of the reader's Tools menu. AI service, response length, MRI quick view, spoiler controls, and other settings are grouped under one submenu.

Answers use a sincere, natural reviewer-like voice without rhetorical lists or stacked synonyms. Ordinary answers use compact paragraphs. Lists use “-” for main entries and “•” only for supporting details that genuinely need a second level. People, places, and concept lists use blank lines instead of numbered entries. Output remains plain text without other Markdown markers.

### Configure API keys on a computer

Copy `mri.koplugin/config.example.json` to `mri.koplugin/config.json`, then edit the new `config.json` file:

```json
{
  "api_keys": {
    "openai": "sk-...",
    "anthropic": "",
    "gemini": ""
  },
  "models": {
    "openai": "gpt-4.1-mini",
    "anthropic": "claude-haiku-4-5",
    "gemini": "gemini-2.5-flash-lite"
  },
  "endpoints": {}
}
```

Enter a model name under `models` to override that provider's preset; leave it empty to keep the Kindle setting or plugin default. Keep this file when updating the plugin. Git ignores it and the release package excludes it, but it should still never be shared through screenshots, chat, or other channels.

## Privacy

- MRI sends only text before the current reading position or text explicitly selected by the user.
- Temporary conversations are cleared when the book closes.
- The latest automatic recap, three cached reference lists, up to 200 chapter memories, and up to 80 cached AI answers are stored in the book's KOReader settings.
- People, places, and concepts use up to six evenly distributed excerpts without loading an entire long novel into Kindle memory.
- Background preparation adds one AI request and runs sequentially after the foreground response; it does not launch several requests at once.
- “Start to current position” uses chapter memories and up to six distributed excerpts to keep memory and request sizes bounded.
- Spoilers are off by default. Enabling them allows MRI, Book overview, Ask this book, and the three reference lists to send excerpts from the whole book.
- API keys are stored as plain text on the device. Use a separate key with a spending limit.

## License

Copyright (C) 2026 Frank

GNU Affero General Public License v3.0 or later. See `LICENSE`.
