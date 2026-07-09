#!/bin/bash
# Claude Code Status Line — single adaptive line
#
#   ctx% [model effort]   tok/$cost   C: 5h/7d budget   B: ⑂wt ⎇branch ~/path   D: +/- PR api_time
#   └─ A: always shown ─┘  └────────────────────── dropped as the pane narrows ─────────────────┘
#
# One line, priority-ordered left→right. The pane width arrives in $COLUMNS
# (Claude sets it; e.g. 291 in a full window). As the pane narrows the line
# collapses right-to-left: drop D (stats), then B (location), then C (budget),
# then tokens/cost; ctx% + model are never dropped. Path shrinks to a basename
# below ~150 cols.
#
# Reads the Claude Code status JSON on stdin. Designed for a worktree-heavy,
# parallel-agent workflow. Model name is colored by family (opus=white,
# sonnet=blue, haiku=pink, fable=purple); context % uses a green→yellow→red
# gradient; rate limits stay neutral until 80% then warn. Git branch+dirty is
# cached per session_id (3s TTL) so the script stays fast on every message.
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
rl_5h_reset=$(jqr '.rate_limits.five_hour.resets_at // empty')
rl_7d_reset=$(jqr '.rate_limits.seven_day.resets_at // empty')

# ─── colors ──────────────────────────────────────────────────────────────────
BOLD='\033[1m'; DIM='\033[2m'; ITALIC='\033[3m'; RESET='\033[0m'
CYAN='\033[36m'; BLUE='\033[34m'; GREEN='\033[32m'; GRAY='\033[38;2;130;130;130m'
WHITE='\033[97m'
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
# Render one rate-limit window as: <label>(<time-left>) : <used%>(◇<exp%>).
# Each parenthetical annotates the value right before it: time-left hugs the
# label, glide slope hugs used%.
#   used%     — absolute budget consumed.
#   time-left — time remaining until this window resets, adaptive units:
#               days (≥1d) → hours (≥1h) → minutes, so it never reads "0.5d".
#   (◇exp%)   — glide slope: where you'd be right now if usage were evenly
#               distributed across the window (= % of the window elapsed). The
#               ◇ marks it as the target pace. Compare to used%: under it =
#               headroom, over it = burning faster than even.
# Flat/dim by default so it doesn't distract; colors only when used% crosses
# the per-window threshold ($thresh → yellow, 95%+ → red). The pace delta
# carries no color of its own — the warning is driven by absolute used%.
# args: label  used%  resets_at  window_len_s  warn_threshold
rl_window() {
    local label=$1 used=$2 reset=$3 wlen=$4 thresh=$5
    if [ -z "$used" ]; then
        printf '%b%s: no data%b' "$DIM" "$label" "$RESET"
        return
    fi
    local now remain left expected color u
    now=$(date +%s)
    if [ -n "$reset" ]; then
        remain=$(( reset - now ))
        [ "$remain" -lt 0 ] && remain=0
        if   [ "$remain" -ge 86400 ]; then left=$(awk "BEGIN{printf \"%.1fd\", $remain/86400}")
        elif [ "$remain" -ge 3600 ];  then left=$(awk "BEGIN{printf \"%.1fh\", $remain/3600}")
        else                               left=$(awk "BEGIN{printf \"%dm\", $remain/60}"); fi
        # expected usage now if evenly distributed = % of the window elapsed
        expected=$(awk "BEGIN{el=($wlen-$remain)/$wlen*100; if(el>100)el=100; if(el<0)el=0; printf \"%.0f\", el}")
    else
        left="?"; expected="?"
    fi
    u=${used%.*}                              # integer part, for threshold compares
    local udisp; udisp=$(printf '%.0f' "$used" 2>/dev/null)  # rounded, for display (kills float garbage)
    if   [ "$u" -ge 95 ]      2>/dev/null; then color="$RED"
    elif [ "$u" -ge "$thresh" ] 2>/dev/null; then color="$YELLOW"
    else color="$DIM"; fi
    printf '%b%s(%s): %s%%(◇%s%%)%b' "$color" "$label" "$left" "$udisp" "$expected" "$RESET"
}

# ─── model name: claude-opus-4-8[1m] → opus-4.8·1M ───────────────────────────
m="${model_raw#claude-}"
one_m=""
case "$m" in *"[1m]"*) one_m="·1M"; m="${m%%\[1m\]*}";; esac
m=$(printf '%s' "$m" | sed -E 's/-([0-9]+)-([0-9]+)-[0-9]{8}$/-\1.\2/; s/-([0-9]+)-([0-9]+)$/-\1.\2/')
model="${m}${one_m}"
[ -z "$model" ] && model="$model_disp"

# model-family color: opus=white, sonnet=periwinkle, haiku=pink, fable=purple, else cyan
is_fable=0
case "$model_raw$model_disp" in
    *[Ff]able*)  MODEL_COLOR='\033[38;2;175;95;255m'; is_fable=1;;  # purple
    *[Oo]pus*)   MODEL_COLOR='\033[97m';;             # bright white
    *[Ss]onnet*) MODEL_COLOR='\033[38;2;90;160;255m';;   # blue (purple reserved for fable)
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

ctx_tok="$(fmtk "$ctx_in")"   # tokens used; window size dropped (effectively always 1M)

# ─── cost / time / effort / PR / rate limits ─────────────────────────────────
cost_fmt=$(printf '%.2f' "$cost")
api_seg="$(fmt_hms $((api_ms / 1000))) ${DIM}api_time${RESET}"

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

s5=$(rl_window "5h" "$rl_5h" "$rl_5h_reset" $((5 * 3600))  80)
s7=$(rl_window "7d" "$rl_7d" "$rl_7d_reset" $((7 * 86400)) 90)
rl_seg="$s5 $s7"

# ─── model segment (effort inside the brackets, family-colored) ──────────────
# Every family uses the plain form: [opus-4.8·1M high]. Fable stays purple
# (MODEL_COLOR) but no longer carries emoji accents.
name_open="["; name_close=" "
if [ -n "$eff_seg" ]; then
    model_seg="${BOLD}${MODEL_COLOR}${name_open}${model}${name_close}${RESET}${eff_seg}${BOLD}${MODEL_COLOR}]${RESET}"
else
    model_seg="${BOLD}${MODEL_COLOR}${name_open}${model}${name_close%[[:space:]]}]${RESET}"
fi

# ─── pane width (Claude sets $COLUMNS; fall back to tput, else assume wide) ───
cols=${COLUMNS:-0}
[ "$cols" -gt 0 ] 2>/dev/null || cols=$(tput cols 2>/dev/null || echo 0)
[ "$cols" -gt 0 ] 2>/dev/null || cols=999

# ─── groups, in priority order ───────────────────────────────────────────────
# A — core: context% then model (never dropped)
core_seg="${CTX_COLOR}${ctx_pct}%${RESET}  ${model_seg}"

# B — location: worktree · branch · path (worktree/path swapped). Path full when wide,
# basename when tight. Built left→right with separators only between present parts.
path_short="${current_dir##*/}"; [ -z "$path_short" ] && path_short="/"
[ "$cols" -ge 150 ] && loc_path="$path_disp" || loc_path="$path_short"
loc_seg=""; loc_sep=""
if [ -n "$git_worktree" ]; then
    loc_seg="${MAGENTA}⑂ ${git_worktree}${RESET}"; loc_sep="  "
fi
if [ -n "$branch" ]; then
    bseg="${GREEN}⎇ ${branch}${RESET}"
    [ -n "$dirty" ] && bseg="${bseg} ${DIM}●${dirty}${RESET}"
    loc_seg="${loc_seg}${loc_sep}${bseg}"; loc_sep="  "
fi
loc_seg="${loc_seg}${loc_sep}${GRAY}${loc_path}${RESET}"

# tokens/cost — its own group, placed right of the model bracket, ahead of the
# budget (C). Order is tokens/$cost; tokens are flat white (high-priority read),
# cost stays dim.
tokcost_seg="${WHITE}${ctx_tok}${RESET}${DIM}/\$${cost_fmt}${RESET}"

# D — droppable stats: diff · PR · api (tokens/cost moved out to its own group above)
stats_seg="${GREEN}+${lines_added}${RESET} ${RED}-${lines_removed}${RESET}"
[ -n "$pr_seg" ] && stats_seg="${stats_seg}  ${pr_seg}"
stats_seg="${stats_seg}  ${api_seg}"

# ─── one adaptive line: add groups while the pane is wide enough ──────────────
line="$core_seg"
[ "$cols" -ge 64 ]  && line="${line}  ${tokcost_seg}"                         # tokens/cost (right of model)
{ [ "$cols" -ge 88 ]  && [ -n "$rl_seg" ]; } && line="${line}  ${rl_seg}"     # C budget
[ "$cols" -ge 92 ]  && line="${line}   ${loc_seg}"                            # B location
[ "$cols" -ge 128 ] && line="${line}   ${stats_seg}"                          # D stats
printf '%b\n' "$line"
