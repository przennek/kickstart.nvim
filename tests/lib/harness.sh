# Drives a real nvim (this config) inside a private tmux server, like a user at the keyboard.
# Needs: WORK (scratch directory), LIB (tests/lib). Sourced by tests/run.sh.
SES=work
S=$WORK/nvim.sock
LOG=$WORK/scenario.log
FAILS=0
t() { tmux -L nvimtest "$@"; }
k() { t send-keys -t $SES "$@"; sleep ${KS:-0.35}; }                   # tmux key names
lit() { t send-keys -t $SES -l "$1"; sleep ${KS:-0.35}; }               # literal text
esc() { t send-keys -t $SES -l "$(printf "$1")"; sleep ${KS:-0.35}; }   # escape sequences
ex() { k Escape; lit ":$1"; k Enter; }
q() { timeout ${QT:-5} nvim --server $S --remote-expr "$1" 2>/dev/null; }
ql() { q "luaeval('$1')"; }
screen() { t capture-pane -t $SES -p; }
wins() { ql "dofile(\"$LIB/wins.lua\")"; }
# F-keys as Alacritty + tmux deliver them
RUN_CTX='\e[21;6~'; DEBUG_CTX='\e[20;6~'; CF2='\e[1;5Q'; SF6='\e[17;2~'; HIDE_ALL='\e[24;6~'; AF8='\e[19;3~'

start() {   # start <dir> <file>
  t kill-session -t $SES 2>/dev/null; rm -f $S
  t new-session -d -s $SES -x 200 -y 50 "cd $1 && XDG_CACHE_HOME=$WORK/cache XDG_STATE_HOME=$WORK/state nvim --listen $S -n -i NONE --cmd 'source $LIB/fakeclip.vim' $2"
}
stop() { q "execute('qa!')" >/dev/null; sleep 2; t kill-server 2>/dev/null; }

editor() {  # focus the first editor window, Normal mode
  ql "(function() for _,w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do local b=vim.api.nvim_win_get_buf(w) if vim.bo[b].buftype==\"\" and vim.api.nvim_buf_get_name(b)~=\"\" and vim.api.nvim_win_get_config(w).relative==\"\" then vim.api.nvim_set_current_win(w) vim.cmd\"stopinsert\" return 1 end end return 0 end)()" >/dev/null
  sleep 0.3
}

LAST_ERR=""; LAST_MSG=""; STEP=0
check() {   # check <label>: nvim alive and answering, no new errors
  STEP=$((STEP + 1))
  if ! t has-session -t $SES 2>/dev/null; then fail "[$STEP $1] nvim is gone"; return 2; fi
  local m; m=$(q "mode()")
  if [ -z "$m" ]; then sleep 2; m=$(q "mode()"); [ -z "$m" ] && { fail "[$STEP $1] nvim not answering: $(screen | tail -2 | tr '\n' ' ')"; k Escape; return 1; }; fi
  local e; e=$(ql "table.concat(vim.tbl_map(function(e) return e.msg:gsub(\"\\n\",\" \"):sub(1,200) end, vim.tbl_filter(function(e) return e.level==\"ERROR\" end, require(\"pc.notifications\").entries())), \" || \")")
  if [ -n "$e" ] && [ "$e" != "$LAST_ERR" ]; then fail "[$STEP $1] error: ${e#"$LAST_ERR"}"; LAST_ERR=$e; fi
  local me; me=$(q "execute('messages')" | grep -E 'E[0-9]+:|rror|stack traceback' | grep -v 'E35\|E21\|E486\|E384\|E385' | tail -2)
  if [ -n "$me" ] && [ "$me" != "$LAST_MSG" ]; then fail "[$STEP $1] message: $me"; LAST_MSG=$me; fi
  echo "ok [$STEP $1] $(wins)" >> $LOG
  return 0
}
fail() { FAILS=$((FAILS + 1)); echo "FAIL $*" | tee -a $LOG; }
expect() {  # expect <label> <actual> <wanted>
  if [ "$2" = "$3" ]; then echo "ok   $1" | tee -a $LOG; else fail "$1: got '$2', wanted '$3'"; fi
}

# a burst of random tool-window keys and IDE actions, like a nervous user
hammer() {
  local n=${1:-30} ops=(M-1 M-0 M-3 M-4 M-5 M-6 M-7 M-9 M-t hide C-h C-j C-k C-l M-e esc " z" diff recent rename eval)
  for i in $(seq $n); do
    local op=${ops[$((RANDOM % ${#ops[@]}))]}
    case "$op" in
      hide) esc "$HIDE_ALL";;
      esc) k Escape; k Escape;;
      diff) editor; k M-d; sleep 1; k Escape;;
      recent) editor; k ' vE'; sleep 1; k Escape; k Escape;;
      rename) editor; esc "$SF6"; sleep 1; k Escape;;
      eval) editor; k ' xe'; sleep 0.5; k Escape;;
      M-e) k "$op"; sleep 0.8; k Escape; k Escape;;
      *) k "$op";;
    esac
    [ "$(q 'mode()')" = "t" ] && k M-t
    check "hammer $op" || return 1
  done
}
