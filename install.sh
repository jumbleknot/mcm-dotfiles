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

# --- 0. sanity: only meaningful inside a dev container that asks for the personal layer ---
# Two markers are accepted: MCM_DEVCONTAINER=1 (MovieCollectionManager, unchanged) and the
# neutral DEVCONTAINER_PERSONAL_LAYER=1, which any other repository's dev container sets
# (BELAY sets it). Neither set: skip and exit 0, as before. Outside a dev container this
# script must do nothing.
if [ "${MCM_DEVCONTAINER:-}" != "1" ] && [ "${DEVCONTAINER_PERSONAL_LAYER:-}" != "1" ]; then
  log "not inside a dev container that requests the personal layer (neither MCM_DEVCONTAINER=1 nor DEVCONTAINER_PERSONAL_LAYER=1) — skipping personal bootstrap."
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
# PINNED to a release tag. An unpinned `cargo install --git` builds whatever the default branch is on
# the day of the FIRST build, and the "already installed" guard below then keeps that binary on the
# persisted volume for ever — the sandbox ran a July build into November. Bump this to upgrade; the
# next container open rebuilds because the installed version no longer matches. Pick a stable tag
# (not a dev-*-rc prerelease) at least two weeks old.
RTK_VERSION="${RTK_VERSION:-1.2.0}"
installed_rtk=''
[ -x "${RTK_BIN}/rtk" ] && installed_rtk="$("${RTK_BIN}/rtk" --version 2>/dev/null | awk '{print $2}')"
if [ "${installed_rtk}" = "${RTK_VERSION}" ]; then
  log "RTK ${RTK_VERSION} already installed (${RTK_BIN}/rtk) — skipping build (FR-008 idempotent)."
else
  command -v cargo >/dev/null 2>&1 || die "cargo not found — the toolchain image is required for RTK (FR-015)."
  log "building RTK v${RTK_VERSION} from ${RTK_GIT_URL} into ${RTK_ROOT} (installed: ${installed_rtk:-none})…"
  if ! cargo install --locked --force --git "${RTK_GIT_URL}" --tag "v${RTK_VERSION}" --root "${RTK_ROOT}" rtk; then
    die "RTK build failed — is crates.io / ${RTK_GIT_URL} reachable through the egress firewall? (FR-015)"
  fi
  got_rtk="$("${RTK_BIN}/rtk" --version 2>/dev/null | awk '{print $2}')"
  [ "${got_rtk}" = "${RTK_VERSION}" ] || die "RTK built but reports '${got_rtk:-nothing}', expected ${RTK_VERSION} (FR-015)"
  log "RTK ${got_rtk} built → ${RTK_BIN}/rtk"
fi

# Activate the RTK Claude Code hook (idempotent; writes into the persisted ~/.claude).
# Without --auto-patch, `rtk init -g` PROMPTS before editing settings.json, and a non-interactive
# run answers NO — it then exits 0 having wired nothing. So patch explicitly, and VERIFY the hook
# landed rather than trusting the exit code.
if command -v rtk >/dev/null 2>&1; then
  rtk init -g --auto-patch || log "WARN: 'rtk init -g --auto-patch' returned non-zero."
  if grep -qs 'rtk hook' "${CLAUDE_DIR}/settings.json"; then
    log "RTK active — PreToolUse hook present in ${CLAUDE_DIR}/settings.json"
  else
    die "RTK built but its hook is NOT in ${CLAUDE_DIR}/settings.json — run 'rtk init -g --auto-patch' (FR-015)"
  fi
fi

# --- 2. Personal Claude Code marketplaces + plugins (guarded — persist in ~/.claude) ------
# Marketplaces to register (GitHub owner/repo). All GitHub-hosted → reachable through the 038
# egress allowlist. Re-adding an existing marketplace is tolerated (idempotent).
PERSONAL_MARKETPLACES=(
  "anthropics/claude-plugins-official"
  "callstackincubator/agent-skills"
  "actionbook/rust-skills"
  "langchain-ai/langsmith-claude-code-plugins"
  "Codeblockz/langchain-community-plugin"
)

# All 13 plugins as name@marketplace (exact refs mirrored from the host workstation set).
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
  # Callstack restructured into bundles on 2026-08-07 (agent-skills #74); both skills used here
  # (react-native-best-practices, upgrading-react-native) now live in this one plugin.
  "building-react-native-apps@callstack-agent-skills"
  "rust-skills@rust-skills"
  "langsmith-tracing@langsmith-claude-code-plugins"
  "langchain-community@langchain-community-marketplace"
)

# Retired: removed from the lists above, and UNINSTALLED here, because a reused ~/.claude volume
# keeps whatever an earlier run installed — dropping a name from PERSONAL_PLUGINS alone changes
# nothing for an existing environment. Entries are "plugin@marketplace|marketplace-name".
# nx (2026-11-23): unused in this workspace — 0 invocations across 73 sessions — and its
# marketplace was tracked unpinned; MovieCollectionManager removed its project-scope copy in PR #1102.
RETIRED_PLUGINS=(
  "nx@nx-claude-plugins|nx-claude-plugins"
)

if command -v claude >/dev/null 2>&1; then
  for r in "${RETIRED_PLUGINS[@]}"; do
    p="${r%%|*}"; mkt="${r##*|}"
    if claude plugin list 2>/dev/null | grep -qF "${p}"; then
      log "uninstalling retired plugin: ${p}"
      claude plugin uninstall "${p}" --scope user >/dev/null 2>&1         || log "note: uninstall of ${p} returned non-zero — continuing."
    fi
    if claude plugin marketplace list 2>/dev/null | grep -qF "${mkt}"; then
      log "removing retired marketplace: ${mkt}"
      claude plugin marketplace remove "${mkt}" >/dev/null 2>&1         || log "note: marketplace remove for ${mkt} returned non-zero — continuing."
    fi
  done

  for m in "${PERSONAL_MARKETPLACES[@]}"; do
    log "registering marketplace: ${m}"
    claude plugin marketplace add "${m}" >/dev/null 2>&1 \
      || log "note: marketplace add for ${m} returned non-zero (already registered?) — continuing."
  done
  # `marketplace add` does not refresh one that is already registered, so a reused ~/.claude volume
  # keeps a stale catalogue and cannot see an upstream rename. Refresh before installing.
  claude plugin marketplace update >/dev/null 2>&1 \
    || log "note: marketplace update returned non-zero — installing from the cached catalogues."

  failed=()
  for p in "${PERSONAL_PLUGINS[@]}"; do
    name="${p%@*}"
    if claude plugin list 2>/dev/null | grep -qF "${name}"; then
      log "plugin already installed: ${p} (skip)"
    else
      log "installing plugin: ${p}"
      claude plugin install "${p}" --scope user || failed+=("${p}")
    fi
  done
  # Still fail loud (FR-015), but only after trying EVERY plugin: one renamed upstream plugin must
  # not silently skip the rest. "not found in marketplace" = renamed; a network error = firewall.
  [ "${#failed[@]}" -eq 0 ] \
    || die "plugin install failed for: ${failed[*]} — renamed upstream, or marketplace unreachable? (FR-015)"
else
  log "claude CLI not found — skipping plugin install (unexpected; the image bakes Claude Code)."
fi

# --- 3. Logins — left to the persisted volume (never scripted) ----------------------------
log "logins (Claude / gh / Expo) persist in ~/.claude. If prompted, authenticate once; it then reuses."

log "personal bootstrap complete."
