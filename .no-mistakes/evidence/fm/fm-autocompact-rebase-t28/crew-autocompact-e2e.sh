#!/usr/bin/env bash
# End-to-end walkthrough of config/crew-autocompact-pct as an operator experiences it:
#   A. primary home sets the knob -> bin/fm-config-push.sh converges it into a LIVE
#      secondmate home (real FM_INHERITABLE_CONFIG propagation + reread instruction)
#   B. that secondmate home then launches its OWN claude crewmate, and the real
#      launch command carries CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=60
#   C. a bad value refuses the spawn with the operator-facing error
set -u
ROOT_REPO=${1:?usage: crew-autocompact-e2e.sh <firstmate-worktree>}
. "$ROOT_REPO/tests/lib.sh"
BASE_PATH=${FM_TEST_BASE_PATH:-/usr/bin:/bin:/usr/sbin:/sbin}
TMP_ROOT=$(fm_test_tmproot fm-crew-autocompact-e2e)

hdr() { printf '\n=== %s ===\n' "$1"; }

make_push_toolchain() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  fm_fake_exit0 "$fakebin" node chrome-devtools-axi gh gh-axi quota-axi treehouse no-mistakes tasks-axi lavish-axi
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
[ -z "${FM_FAKE_TMUX_LOG:-}" ] || printf '%s\n' "$*" >> "$FM_FAKE_TMUX_LOG"
case "$*" in
  *display-message*'#{pane_current_command}'*) printf '%s\n' claude ;;
  *display-message*'#{pane_id}'*) printf '%s\n' '%1' ;;
  *display-message*'#{cursor_y}'*) printf '%s\n' 0 ;;
  *list-windows*) printf '%s\n' fm-sm ;;
  *capture-pane*) printf '\xe2\x9d\xaf\n' ;;
esac
exit 0
SH
  chmod +x "$fakebin"/*
  printf '%s\n' "$fakebin"
}

# fake tmux for spawns: logs every literal send-keys payload (the launch command)
make_spawn_fakebin() {
  local dir=$1 fakebin
  fakebin=$(fm_fakebin "$dir")
  cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
set -u
case "$*" in
  *"#{pane_current_path}"*) printf '%s\n' "${FM_FAKE_PANE_PATH:-}"; exit 0 ;;
esac
case "${1:-}" in
  display-message) printf 'firstmate\n'; exit 0 ;;
  list-windows) exit 0 ;;
  has-session|new-session|new-window|kill-window) exit 0 ;;
  send-keys)
    if [ -n "${FM_FAKE_LAUNCH_LOG:-}" ]; then
      shift; skip_next=
      for a in "$@"; do
        if [ -n "$skip_next" ]; then skip_next=; continue; fi
        case "$a" in
          -t) skip_next=1; continue ;;
          -l|Enter|C-m) continue ;;
          *) printf '%s\n' "$a" >> "$FM_FAKE_LAUNCH_LOG" ;;
        esac
      done
    fi
    exit 0 ;;
esac
exit 0
SH
  chmod +x "$fakebin/tmux"
  fm_fake_exit0 "$fakebin" treehouse
  printf '%s\n' "$fakebin"
}

# ---------------------------------------------------------------------------
# A. primary sets the knob; fm-config-push.sh converges it into a live secondmate
# ---------------------------------------------------------------------------
world="$TMP_ROOT/world"; root="$world/root"; home="$world/home"; sm="$world/sm"
mkdir -p "$home/config" "$home/data" "$home/state" "$root/bin"
touch "$home/state/.last-watcher-beat"
git init -q -b main "$root"
printf 'config/\n' > "$root/.gitignore"
printf '# Firstmate test root\n' > "$root/AGENTS.md"
printf '#!/usr/bin/env bash\nexit 0\n' > "$root/bin/placeholder.sh"; chmod +x "$root/bin/placeholder.sh"
git -C "$root" add -A
git -C "$root" -c user.name=fmtest -c user.email=fmtest@example.invalid commit -qm initial
head=$(git -C "$root" rev-parse HEAD)
git -C "$root" worktree add -q --detach "$sm" "$head"
printf 'sm\n' > "$sm/.fm-secondmate-home"
mkdir -p "$sm/config" "$sm/data" "$sm/state" "$sm/projects"
{ printf 'window=firstmate:fm-sm\n'; printf 'kind=secondmate\n'; printf 'harness=claude\n'; printf 'home=%s\n' "$sm"; } > "$home/state/sm.meta"

hdr "A1. captain sets the knob in the PRIMARY home"
printf '60\n' > "$home/config/crew-autocompact-pct"
printf '$ cat config/crew-autocompact-pct\n'; cat "$home/config/crew-autocompact-pct"
printf '$ ls secondmate-home/config/\n'; ls "$sm/config/" || true
printf '(secondmate config dir is empty - knob not there yet)\n'

hdr "A2. \$ bin/fm-config-push.sh   (real inherited-local-material push)"
pushbin=$(make_push_toolchain "$world/pushfake")
PATH="$pushbin:$BASE_PATH" FM_HOME="$home" FM_ROOT_OVERRIDE="$root" FM_SEND_SETTLE=0 \
  FM_FAKE_TMUX_LOG="$world/tmux.log" "$ROOT_REPO/bin/fm-config-push.sh" 2>&1
printf '(exit=%s)\n' "$?"

hdr "A3. the knob landed in the secondmate home"
printf '$ cat secondmate-home/config/crew-autocompact-pct\n'
cat "$sm/config/crew-autocompact-pct"

hdr "A4. the running secondmate got the literal-content reread instruction"
latest=
for p in "$sm/state"/.fm-inherited-config-reread.*; do
  case "$p" in *.pending) continue ;; esac
  [ -f "$p" ] && latest=$p
done
[ -n "$latest" ] && sed -n '1,40p' "$latest" || printf '(none)\n'

# ---------------------------------------------------------------------------
# B. the secondmate home now launches its OWN claude crewmate with the override
# ---------------------------------------------------------------------------
hdr "B1. that same secondmate home spawns a claude crewmate"
printf 'claude\n' > "$sm/config/crew-harness"
mkdir -p "$sm/data/e2e-crew1" "$sm/state" "$sm/projects" "$sm/user-home"
touch "$sm/state/.last-watcher-beat"
cat > "$sm/data/e2e-crew1/brief.md" <<'BRIEF'
# Task
## Captain's intent
Exercise the inherited crew auto-compaction threshold.

## Firstmate spec
Verify the spawned crewmate receives the expected launch environment.
BRIEF
fm_git_worktree "$world/proj" "$world/wt" wt-e2e
spawnbin=$(make_spawn_fakebin "$world/spawnfake")
launchlog="$world/launch.log"; : > "$launchlog"
printf '$ bin/fm-spawn.sh e2e-crew1 <project> --mode no-mistakes --yolo off\n'
env FM_ROOT_OVERRIDE='' FM_HOME="$sm" HOME="$sm/user-home" CLAUDE_CONFIG_DIR='' \
  FM_STATE_OVERRIDE="$sm/state" FM_DATA_OVERRIDE="$sm/data" \
  FM_PROJECTS_OVERRIDE="$sm/projects" FM_CONFIG_OVERRIDE="$sm/config" \
  FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$world/wt" TMUX="fake,1,0" \
  FM_FAKE_LAUNCH_LOG="$launchlog" PATH="$spawnbin:$PATH" \
  "$ROOT_REPO/bin/fm-spawn.sh" e2e-crew1 "$world/proj" --mode no-mistakes --yolo off 2>&1
printf '(exit=%s)\n' "$?"

hdr "B2. the actual command sent to the crewmate pane"
grep -m1 'CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION' "$launchlog" | fold -w 160

# ---------------------------------------------------------------------------
# C. a malformed value refuses the spawn with the operator-facing error
# ---------------------------------------------------------------------------
hdr "C. operator typos the value"
printf '150\n' > "$sm/config/crew-autocompact-pct"
: > "$launchlog"
mkdir -p "$sm/data/e2e-crew2"; cp "$sm/data/e2e-crew1/brief.md" "$sm/data/e2e-crew2/brief.md"
printf '$ cat config/crew-autocompact-pct\n150\n'
printf '$ bin/fm-spawn.sh e2e-crew2 <project> --mode no-mistakes --yolo off\n'
env FM_ROOT_OVERRIDE='' FM_HOME="$sm" HOME="$sm/user-home" CLAUDE_CONFIG_DIR='' \
  FM_STATE_OVERRIDE="$sm/state" FM_DATA_OVERRIDE="$sm/data" \
  FM_PROJECTS_OVERRIDE="$sm/projects" FM_CONFIG_OVERRIDE="$sm/config" \
  FM_SPAWN_NO_GUARD=1 FM_FAKE_PANE_PATH="$world/wt" TMUX="fake,1,0" \
  FM_FAKE_LAUNCH_LOG="$launchlog" PATH="$spawnbin:$PATH" \
  "$ROOT_REPO/bin/fm-spawn.sh" e2e-crew2 "$world/proj" --mode no-mistakes --yolo off 2>&1
printf '(exit=%s)\n' "$?"
printf 'launch commands sent: %s\n' "$(wc -l < "$launchlog" | tr -d ' ')"
