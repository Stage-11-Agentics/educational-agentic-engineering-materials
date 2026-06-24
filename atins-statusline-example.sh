#!/bin/bash
# Claude Code Status Line — two-line layout
#
#   Top line:    [model effort]  context%  $cost/tokens-used/total  +adds -dels  5h-%, 7d-%
#   Bottom line: ~/path  ⎇ branch ●dirty  ⑂ worktree  PR#n  api-time
#
# Reads the Claude Code status JSON on stdin. Designed for a worktree-heavy,
# parallel-agent workflow: the bottom line answers "where am I / which checkout
# is this", the top line answers "how is this session going". Model name is
# colored by family (opus=white, sonnet=purple, haiku=pink); context % uses a
# green→yellow→red gradient; rate limits stay neutral until 80% then warn.
# Git branch+dirty is cached per session_id (3s TTL) so the script stays fast
# on every message.
#
# Requires: jq, git, and a truecolor + unicode-capable terminal.

input=$(cat)
jqr() { printf '%s' "$input" | jq -r "$1" 2>/dev/null; }

# ─── raw fields ──────────────────────────────────────────────────────────────
model_raw=$(jqr '.model.id // ""')
model_disp=$(jqr '.model.display_name // ""')
version=$(jqr '.version // "?"')
current_dir=$(jqr '.workspace.current_dir // .cwd // "."')
session_id=$(jqr '.session_id // "nosession"')
git_worktree=$(jqr '.workspace.git_worktree // empty')

cost=$(jqr '.cost.total_cost_usd // 0')
duration_ms=$(jqr '.cost.total_duration_ms // 0')
api_ms=$(jqr '.cost.total_api_duration_ms // 0')
lines_added=$(jqr '.cost.total_lines_added // 0')
lines_removed=$(jqr '.cost.total_lines_removed // 0')
files_changed=$(jqr '.cost.total_files_changed // 0')

ctx_pct=$(jqr '.context_window.used_percentage // empty')
ctx_in=$(jqr '.context_window.total_input_tokens // 0')
win_size=$(jqr '.context_window.context_window_size // 200000')

effort=$(jqr '.effort.level // empty')
pr_num=$(jqr '.pr.number // empty')
pr_state=$(jqr '.pr.review_state // empty')
rl_5h=$(jqr '.rate_limits.five_hour.used_percentage // empty')
rl_7d=$(jqr '.rate_limits.seven_day.used_percentage // empty')

# ─── colors ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'; DIM='\033[2m'; ITALIC='\033[3m'; RESET='\033[0m'
CYAN='\033[36m'; BLUE='\033[34m'; GREEN='\033[32m'
RED='\033[31m'; YELLOW='\033[33m'; MAGENTA='\033[35m'
ORANGE='\033[38;2;255;140;0m'; REDORANGE='\033[38;2;255;69;0m'
SEP="${DIM}│${RESET}"

# ─── helpers ─────────────────────────────────────────────────────────────────
# Format a token count: 90000→90k, 200000→200k, 1000000→1.0M
fmtk() {
    local n=$1
    if   [ "$n" -ge 1000000 ]; then awk "BEGIN{printf \"%.1fM\", $n/1000000}"
    elif [ "$n" -ge 1000 ];    then printf '%dk' $(( (n + 500) / 1000 ))
    else printf '%d' "$n"; fi
}
# Format seconds as h:mm:ss or m:ss
fmt_hms() {
    local s=$1 h m sec
    h=$((s / 3600)); m=$(((s % 3600) / 60)); sec=$((s % 60))
    if [ "$h" -gt 0 ]; then printf '%d:%02d:%02d' "$h" "$m" "$sec"
    else printf '%d:%02d' "$m" "$sec"; fi
}
# Rate-limit color: neutral until it matters, then warn. <80 default, 80+ yellow, 95+ red
pct_color() {
    local p=${1%.*}
    if   [ "$p" -ge 95 ]; then printf '%b' "$RED"
    elif [ "$p" -ge 80 ]; then printf '%b' "$YELLOW"
    else printf '%b' "$RESET"; fi
}

# ─── model name: claude-opus-4-8[1m] → opus-4.8·1M ───────────────────────────
m="${model_raw#claude-}"
one_m=""
case "$m" in *"[1m]"*) one_m="·1M"; m="${m%%\[1m\]*}";; esac
m=$(printf '%s' "$m" | sed -E 's/-([0-9]+)-([0-9]+)-[0-9]{8}$/-\1.\2/; s/-([0-9]+)-([0-9]+)$/-\1.\2/')
model="${m}${one_m}"
[ -z "$model" ] && model="$model_disp"

# model-family color: opus=white, sonnet=purple, haiku=pink, else cyan
case "$model_raw$model_disp" in
    *[Oo]pus*)   MODEL_COLOR='\033[97m';;             # bright white
    *[Ss]onnet*) MODEL_COLOR='\033[38;2;180;130;255m';;  # purple
    *[Hh]aiku*)  MODEL_COLOR='\033[38;2;255;128;200m';;  # pink
    *)           MODEL_COLOR="$CYAN";;
esac

# ─── path: collapse $HOME to ~ ───────────────────────────────────────────────
path_disp="${current_dir/#$HOME/~}"

# ─── git branch + dirty (cached per session, 3s TTL) ─────────────────────────
CACHE="/tmp/cc-statusline-git-${session_id}"
TTL=3
fresh=0
if [ -f "$CACHE" ]; then
    mtime=$(stat -f %m "$CACHE" 2>/dev/null || stat -c %Y "$CACHE" 2>/dev/null || echo 0)
    age=$(( $(date +%s) - mtime ))
    IFS='|' read -r c_cwd branch dirty < "$CACHE"
    { [ "$age" -le "$TTL" ] && [ "$c_cwd" = "$current_dir" ]; } && fresh=1
fi
if [ "$fresh" -eq 0 ]; then
    branch=""; dirty=""
    if git -C "$current_dir" rev-parse --git-dir >/dev/null 2>&1; then
        branch=$(git -C "$current_dir" branch --show-current 2>/dev/null)
        [ -z "$branch" ] && branch="@$(git -C "$current_dir" rev-parse --short HEAD 2>/dev/null)"  # detached
        dcount=$(git -C "$current_dir" status --porcelain 2>/dev/null | grep -c .)
        [ "$dcount" -gt 0 ] && dirty="$dcount"
    fi
    printf '%s|%s|%s' "$current_dir" "$branch" "$dirty" > "$CACHE"
fi

# ─── context %, tokens, gradient bar ─────────────────────────────────────────
[ "$win_size" -gt 0 ] 2>/dev/null || win_size=200000
if [ -z "$ctx_pct" ] || [ "$ctx_pct" = "null" ]; then
    ctx_pct=$(( ctx_in * 100 / win_size ))
fi
ctx_pct=${ctx_pct%.*}                       # integer
[ "$ctx_pct" -gt 100 ] 2>/dev/null && ctx_pct=100
[ "$ctx_pct" -lt 0 ]   2>/dev/null && ctx_pct=0

# truecolor gradient: green(0%)→yellow(70%)→red(90%+)
if   [ "$ctx_pct" -le 70 ]; then r=$((ctx_pct * 255 / 70)); g=255; b=0
elif [ "$ctx_pct" -le 90 ]; then r=255; g=$(((90 - ctx_pct) * 255 / 20)); b=0
else r=255; g=0; b=0; fi
CTX_COLOR=$(printf '\033[38;2;%d;%d;%dm' "$r" "$g" "$b")

ctx_tok="$(fmtk "$ctx_in")/$(fmtk "$win_size")"

# ─── cost / time / effort / PR / rate limits ─────────────────────────────────
cost_fmt=$(printf '%.2f' "$cost")
api_seg="$(fmt_hms $((api_ms / 1000))) ${DIM}api${RESET}"

eff_seg=""
if [ -n "$effort" ]; then
    # weight signals intensity: below high → italic, high → normal,
    # above high (xhigh/max) → bold. avoid red for the top tiers — it reads
    # like "bypass permissions on"; use orange for hotter-than-high instead.
    case "$effort" in
        low)       ec="$CYAN";   es="$ITALIC";;
        medium)    ec="$GREEN";  es="$ITALIC";;
        high)      ec="$YELLOW";    es="";;
        xhigh)     ec="$ORANGE";    es="$BOLD";;
        max)       ec="$REDORANGE"; es="$BOLD";;
        *)         ec="$RESET";     es="";;
    esac
    eff_seg="${es}${ec}${effort}${RESET}"
fi

pr_seg=""
if [ -n "$pr_num" ]; then
    case "$pr_state" in
        approved)          pc="$GREEN";  ps="✓";;
        changes_requested) pc="$RED";    ps="✗";;
        pending)           pc="$YELLOW"; ps="●";;
        draft)             pc="$DIM";    ps="◌";;
        *)                 pc="$CYAN";   ps="";;
    esac
    pr_seg="${pc}PR#${pr_num}${ps:+ $ps}${RESET}"
fi

rl_seg=""
if [ -n "$rl_5h" ] || [ -n "$rl_7d" ]; then
    parts=""
    [ -n "$rl_5h" ] && parts="$(pct_color "$rl_5h")5h-$(printf '%.0f' "$rl_5h")%${RESET}"
    [ -n "$rl_7d" ] && parts="${parts:+$parts, }$(pct_color "$rl_7d")7d-$(printf '%.0f' "$rl_7d")%${RESET}"
    rl_seg="$parts"
fi

# ─── model segment (effort inside the brackets, family-colored) ──────────────
if [ -n "$eff_seg" ]; then
    model_seg="${BOLD}${MODEL_COLOR}[${model}${RESET} ${eff_seg}${BOLD}${MODEL_COLOR}]${RESET}"
else
    model_seg="${BOLD}${MODEL_COLOR}[${model}]${RESET}"
fi

# ─── top line: model · context% · cost · lines · rate limits ─────────────────
top="${model_seg}  ${CTX_COLOR}${ctx_pct}%${RESET}"
top="${top}  ${DIM}\$${cost_fmt}/${ctx_tok}${RESET}"
top="${top}  ${GREEN}+${lines_added}${RESET} ${RED}-${lines_removed}${RESET}"
[ -n "$rl_seg" ] && top="${top}  ${rl_seg}"

# ─── bottom line: path · branch · worktree · PR · api time ───────────────────
bottom="${BLUE}${path_disp}${RESET}"
if [ -n "$branch" ]; then
    bseg="${GREEN}⎇ ${branch}${RESET}"
    [ -n "$dirty" ] && bseg="${bseg} ${YELLOW}●${dirty}${RESET}"
    bottom="${bottom}  ${bseg}"
fi
[ -n "$git_worktree" ] && bottom="${bottom}  ${MAGENTA}⑂ ${git_worktree}${RESET}"
[ -n "$pr_seg" ] && bottom="${bottom}  ${pr_seg}"
bottom="${bottom}  ${api_seg}"

printf '%b\n%b\n' "$top" "$bottom"
