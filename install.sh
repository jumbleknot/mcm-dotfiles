#!/usr/bin/env bash
# install.sh — PERSONAL dev-container dotfiles bootstrap (MCM feature 038, US3 / T025).
#
# ⚠️ THIS FILE BELONGS IN YOUR OUT-OF-REPO PERSONAL DOTFILES REPOSITORY — NOT in the
# MovieCollectionManager repo (FR-009: the committed .devcontainer/ carries ZERO personal tools,
# plugins, or credentials). Wire it in per-developer via the VS Code user setting
# `dotfiles.repository` (or the CLI `--dotfiles-repository`). The Dev Containers runner auto-runs
# an `install.sh` at the root of that repo as a post-create personalization pass.
#
# Establishes ONCE and reuses on every open (idempotent, login-preserving — FR-008):
#   1. RTK (Rust Token Killer) — built from source into the PERSISTED ~/.claude volume, then
#      `rtk init -g`. Installed to ~/.claude/tools (NOT ~/.cargo/bin) so it survives recreation
#      and does not shadow the baked cargo utilities (research D3/D7).
#   2. Personal Claude Code marketplaces + plugins/skills — added/installed only if not already
#      present (the ~/.claude volume persists them, so this no-ops after first setup).
#   3. Service logins (Claude / gh / Expo) — left to the persisted ~/.claude volume; never scripted.
#
# FAIL-LOUD on a blocked/unreachable source (FR-015): a network/firewall failure exits NON-ZERO
# naming the unreachable source, rather than silently half-configuring the personal layer.
# Safe to run repeatedly. Never blocks container start on an absent optional step (FR-014).

set -uo pipefail

log()  { printf '[dotfiles] %s\n' "$1"; }
die()  { printf '[dotfiles] ERROR: %s\n' "$1" >&2; exit 1; }

# --- 0. sanity: only meaningful inside the dev container ----------------------------------
if [ "${MCM_DEVCONTAINER:-}" != "1" ]; then
  log "not inside the MCM dev container (MCM_DEVCONTAINER != 1) — skipping personal bootstrap."
  exit 0
fi

CLAUDE_DIR="${HOME}/.claude"
RTK_ROOT="${CLAUDE_DIR}/tools"                 # persisted volume → RTK survives recreate
RTK_BIN="${RTK_ROOT}/bin"
mkdir -p "${RTK_BIN}"

# Ensure the persisted RTK bin dir is on PATH for THIS run and future shells.
export PATH="${RTK_BIN}:${PATH}"
if ! grep -qs 'RTK persisted bin (feature 038)' "${HOME}/.bashrc" 2>/dev/null; then
  {
    echo ''
    echo '# RTK persisted bin (feature 038) — installed to the ~/.claude volume so it survives recreate.'
    echo "export PATH=\"${RTK_BIN}:\$PATH\""
  } >> "${HOME}/.bashrc"
fi

# --- 1. RTK (Rust Token Killer) — cargo install --git into the persisted volume -----------
RTK_GIT_URL="${RTK_GIT_URL:-https://github.com/rtk-ai/rtk.git}"
if command -v rtk >/dev/null 2>&1 && [ -x "${RTK_BIN}/rtk" ]; then
  log "RTK already installed ($(command -v rtk)) — skipping build (FR-008 idempotent)."
else
  command -v cargo >/dev/null 2>&1 || die "cargo not found — the toolchain image is required for RTK (FR-015)."
  log "building RTK from ${RTK_GIT_URL} into ${RTK_ROOT} (one-time; cached by the cargo volumes)…"
  if ! cargo install --git "${RTK_GIT_URL}" --root "${RTK_ROOT}" rtk; then
    die "RTK build failed — is crates.io / ${RTK_GIT_URL} reachable through the egress firewall? (FR-015)"
  fi
  log "RTK built → ${RTK_BIN}/rtk"
fi

# Activate the RTK Claude Code hook (idempotent; writes into the persisted ~/.claude).
if command -v rtk >/dev/null 2>&1; then
  rtk init -g >/dev/null 2>&1 || log "WARN: 'rtk init -g' returned non-zero (already initialized?)."
  log "RTK active — verify with: rtk gain"
fi

# --- 2. Personal Claude Code marketplaces + plugins (guarded — persist in ~/.claude) ------
# Marketplaces to register (GitHub owner/repo). All GitHub-hosted → reachable through the 038
# egress allowlist. Re-adding an existing marketplace is tolerated (idempotent).
PERSONAL_MARKETPLACES=(
  "anthropics/claude-plugins-official"
  "callstackincubator/agent-skills"
  "nrwl/nx-ai-agents-config"
  "actionbook/rust-skills"
  "langchain-ai/langsmith-claude-code-plugins"
  "Codeblockz/langchain-community-plugin"
)

# All 15 plugins as name@marketplace (exact refs mirrored from the host workstation set).
PERSONAL_PLUGINS=(
  "superpowers@claude-plugins-official"
  "expo@claude-plugins-official"
  "frontend-design@claude-plugins-official"
  "code-review@claude-plugins-official"
  "context7@claude-plugins-official"
  "security-guidance@claude-plugins-official"
  "rust-analyzer-lsp@claude-plugins-official"
  "pyright-lsp@claude-plugins-official"
  "pydantic-ai@claude-plugins-official"
  "react-native-best-practices@callstack-agent-skills"
  "upgrading-react-native@callstack-agent-skills"
  "nx@nx-claude-plugins"
  "rust-skills@rust-skills"
  "langsmith-tracing@langsmith-claude-code-plugins"
  "langchain-community@langchain-community-marketplace"
)

if command -v claude >/dev/null 2>&1; then
  for m in "${PERSONAL_MARKETPLACES[@]}"; do
    log "registering marketplace: ${m}"
    claude plugin marketplace add "${m}" >/dev/null 2>&1 \
      || log "note: marketplace add for ${m} returned non-zero (already registered?) — continuing."
  done

  for p in "${PERSONAL_PLUGINS[@]}"; do
    name="${p%@*}"
    if claude plugin list 2>/dev/null | grep -qF "${name}"; then
      log "plugin already installed: ${p} (skip)"
    else
      log "installing plugin: ${p}"
      claude plugin install "${p}" --scope user \
        || die "plugin install failed for '${p}' — is its marketplace (GitHub) reachable through the firewall? (FR-015)"
    fi
  done
else
  log "claude CLI not found — skipping plugin install (unexpected; the image bakes Claude Code)."
fi

# --- 3. Logins — left to the persisted volume (never scripted) ----------------------------
log "logins (Claude / gh / Expo) persist in ~/.claude. If prompted, authenticate once; it then reuses."

log "personal bootstrap complete."
