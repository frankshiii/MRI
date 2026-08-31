# MRI project working notes

- Before device, release, installation, or synchronisation work, read `.local/MRI_PROJECT_MEMORY.md` when it exists.
- Keep that file current in the same turn whenever a Kindle fact, useful command, workflow, failure, fix, or compatibility result is verified.
- Record the instruction to keep maintaining the memory itself; do not let this habit disappear during later refactors.
- Never store API keys, tokens, passwords, complete device serial numbers, private book text, or personal documents in project memory, logs, commits, or replies.
- Back up the Kindle before KOReader upgrades. Never connect USB storage while KOReader is running, and avoid broad delete or overwrite commands on the device.
- Treat `mri.koplugin/` as the plugin source of truth. Use `scripts/check.sh` before releases and `scripts/sync_to_kindle.command` for normal device synchronisation.
