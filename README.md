# mcm-dotfiles

Personal dev-container bootstrap for the MovieCollectionManager isolated dev container
(feature 038, US3). Kept **out of the MCM repo** by design (FR-009): the committed
`.devcontainer/` carries zero personal tools, plugins, or credentials — this repo supplies them
per-developer.

## What it does

`install.sh` runs automatically as the Dev Containers post-create personalization pass and, once,
idempotently:

1. Builds **RTK** (Rust Token Killer) from source into the persisted `~/.claude/tools` volume and
   runs `rtk init -g`.
2. Registers 6 Claude Code marketplaces and installs 15 personal plugins/skills (guarded — skips
   anything already present on the persisted `~/.claude` volume).
3. Leaves service logins (Claude / gh / Expo) to the persisted `~/.claude` volume.

It fails loud (non-zero) if a required source is unreachable through the container's egress
firewall, and no-ops cleanly outside the dev container.

## Wire it in

VS Code **User** settings (not the committed devcontainer.json):

```json
"dotfiles.repository": "<this-repo-url>"
```

Then Rebuild the container. Verify with `bash .devcontainer/verify/verify-personal-layer.sh`
inside the container.

## Customize

- `RTK_GIT_URL` (top of `install.sh`) — the RTK source repo to build from.
- `PERSONAL_PLUGINS` / `PERSONAL_MARKETPLACES` arrays — your plugin set.
