# zsh-live-history-menu: realtime history menu and path-tab helper for Zsh.

[[ -o interactive ]] || return

zmodload zsh/complist 2>/dev/null
autoload -Uz add-zle-hook-widget

typeset -gi LHM_MAX_RESULTS=${LHM_MAX_RESULTS:-12}
typeset -gi LHM_HISTORY_SCAN_LIMIT=${LHM_HISTORY_SCAN_LIMIT:-1500}
typeset -gi LHM_FUZZY_MIN_QUERY_LENGTH=${LHM_FUZZY_MIN_QUERY_LENGTH:-4}
typeset -gi LHM_ENABLE_FUZZY=${LHM_ENABLE_FUZZY:-1}
typeset -gi LHM_PATH_MAX_RESULTS=${LHM_PATH_MAX_RESULTS:-200}
typeset -g LHM_SELECTED_MARKER=${LHM_SELECTED_MARKER:-'▸'}
typeset -ga _lhm_history_matches=()
typeset -ga _lhm_history_cache=()
typeset -gi _lhm_history_index=0
typeset -g _lhm_history_query=''
typeset -gi _lhm_selecting=0
typeset -gi _lhm_refreshing=0
typeset -gi _lhm_history_cache_histcmd=0
typeset -gi _lhm_history_cache_size=0

typeset -ga _lhm_path_matches=()
typeset -ga _lhm_path_displays=()

_lhm_fuzzy_match() {
  emulate -L zsh

  local query=${(L)1}
  local value=${(L)2}
  local -a query_chars
  local query_pattern

  [[ -n $query ]] || return 1

  query_chars=( "${(@s::)query}" )
  query_pattern="*${(j:*:)${(@b)query_chars}}*"

  [[ $value == ${~query_pattern} ]]
}

_lhm_word_prefix_match() {
  emulate -L zsh

  local query=${(L)1}
  local value=${(L)2}
  local word
  local -a words

  value=${value//\// }
  value=${value//_/ }
  value=${value//./ }
  value=${value//:/ }
  value=${value//-/ }
  value=${value//$'\t'/ }
  value=${value//$'\n'/ }
  words=( "${(@s: :)value}" )

  for word in $words; do
    [[ -n $word && $word == "$query"* ]] && return 0
  done

  return 1
}

_lhm_structured_query() {
  emulate -L zsh

  local query=$1
  local single_quote="'"

  [[ $query == *[[:space:]]* ||
     $query == *\"* ||
     $query == *"$single_quote"* ||
     $query == *\\* ]]
}

_lhm_structured_match() {
  emulate -L zsh

  local query=${(L)1}
  local value=${(L)2}
  local chunk raw_chunk remaining
  local -a chunks=()

  for raw_chunk in "${(@s: :)query}"; do
    [[ -n $raw_chunk ]] && chunks+=( "$raw_chunk" )
  done

  (( $#chunks )) || return 1
  [[ $value == "${chunks[1]}"* ]] || return 1

  remaining=$value
  for chunk in $chunks; do
    [[ $remaining == *"$chunk"* ]] || return 1
    remaining=${remaining#*"$chunk"}
  done

  return 0
}

_lhm_history_match_bucket() {
  emulate -L zsh
  setopt extendedglob

  local query=${(L)1}
  local value=${(L)2}
  local query_length=${#query}

  if _lhm_structured_query "$query"; then
    if [[ $value == "$query" ]]; then
      reply=( 1 )
    elif [[ $value == "${query}"* ]]; then
      reply=( 2 )
    elif _lhm_structured_match "$query" "$value"; then
      reply=( 3 )
    else
      return 1
    fi
    return 0
  fi

  if [[ $value == "$query" ]]; then
    reply=( 1 )
  elif [[ $value == "$query"* ]]; then
    reply=( 2 )
  elif (( query_length >= 2 )) &&
       _lhm_word_prefix_match "$query" "$value"; then
    reply=( 3 )
  elif (( query_length >= 3 )) && [[ $value == *"$query"* ]]; then
    reply=( 4 )
  elif (( LHM_ENABLE_FUZZY )) &&
       (( query_length >= LHM_FUZZY_MIN_QUERY_LENGTH )) &&
       _lhm_fuzzy_match "$query" "$value"; then
    reply=( 5 )
  else
    return 1
  fi
}

_lhm_refresh_history_cache() {
  emulate -L zsh

  local -A seen_history=()
  local -a history_numbers=()
  local history_number command_line scan_count scan_limit current_history_number

  _lhm_history_cache=()

  scan_limit=$LHM_HISTORY_SCAN_LIMIT
  (( scan_limit <= 0 )) && scan_limit=${#history}
  current_history_number=${HISTCMD:-0}

  if (( current_history_number > 0 )); then
    for (( history_number = current_history_number - 1;
           history_number > 0 && scan_count < scan_limit;
           history_number-- )); do
      (( scan_count++ ))
      command_line=${history[$history_number]}
      [[ -n $command_line ]] || continue
      [[ -n ${seen_history[$command_line]-} ]] && continue

      seen_history[$command_line]=1
      _lhm_history_cache+=( "$command_line" )
    done
  else
    history_numbers=( ${(On)${(k)history}} )
    for history_number in $history_numbers; do
      (( scan_count++ ))
      command_line=${history[$history_number]}
      [[ -n $command_line ]] || continue
      [[ -n ${seen_history[$command_line]-} ]] && continue

      seen_history[$command_line]=1
      _lhm_history_cache+=( "$command_line" )

      (( scan_count >= scan_limit )) && break
    done
  fi

  _lhm_history_cache_histcmd=${HISTCMD:-0}
  _lhm_history_cache_size=${#history}
}

_lhm_ensure_history_cache() {
  emulate -L zsh

  if (( $#_lhm_history_cache == 0 )) ||
     (( _lhm_history_cache_histcmd != ${HISTCMD:-0} )) ||
     (( _lhm_history_cache_size != ${#history} )); then
    _lhm_refresh_history_cache
  fi
}

_lhm_format_history_display_line() {
  emulate -L zsh

  local marker=$1
  local index=$2
  local total=$3
  local command_line=${4//$'\n'/\\n}
  local number_width=${#total}
  local columns=${COLUMNS:-80}
  local command_width prefix

  (( number_width < 2 )) && number_width=2
  (( columns < 40 )) && columns=40

  printf -v prefix '%s %*d  ' "$marker" "$number_width" "$index"
  command_width=$(( columns - ${#prefix} - 1 ))
  (( command_width < 20 )) && command_width=20

  if (( ${#command_line} > command_width )); then
    command_line="${command_line[1,$(( command_width - 3 ))]}..."
  fi

  REPLY="${prefix}${command_line}"
}

_lhm_build_history_matches() {
  emulate -L zsh

  local query=${1//$'\n'/ }
  local -A seen_matches=()
  local -a bucket_1=() bucket_2=() bucket_3=() bucket_4=() bucket_5=()
  local command_line value max_results query_length

  [[ -n ${query//[[:space:]]/} ]] || return 1
  if [[ $_lhm_history_query == $query && $#_lhm_history_matches -gt 0 ]] &&
     (( _lhm_history_cache_histcmd == ${HISTCMD:-0} )) &&
     (( _lhm_history_cache_size == ${#history} )); then
    return 0
  fi

  _lhm_history_matches=()
  _lhm_history_query=$query
  _lhm_history_index=0

  query=${(L)query}
  query_length=${#query}
  max_results=$LHM_MAX_RESULTS

  _lhm_ensure_history_cache

  for command_line in "${_lhm_history_cache[@]}"; do
    [[ -n $command_line && $command_line != "$BUFFER" ]] || continue
    value=${(L)command_line}

    if [[ $value == "$query" ]]; then
      bucket_1+=( "$command_line" )
      seen_matches[$command_line]=1
    elif [[ $value == "$query"* ]]; then
      bucket_2+=( "$command_line" )
      seen_matches[$command_line]=1
    fi

    (( ${#bucket_1} + ${#bucket_2} >= max_results )) && break
  done

  if (( ${#bucket_1} + ${#bucket_2} < max_results )); then
    for command_line in "${_lhm_history_cache[@]}"; do
      [[ -n $command_line && $command_line != "$BUFFER" ]] || continue
      [[ -n ${seen_matches[$command_line]-} ]] && continue
      value=${(L)command_line}

      if _lhm_structured_query "$query"; then
        _lhm_structured_match "$query" "$value" || continue
      else
        (( query_length >= 2 )) || continue
        _lhm_word_prefix_match "$query" "$value" || continue
      fi

      bucket_3+=( "$command_line" )
      seen_matches[$command_line]=1
      (( ${#bucket_1} + ${#bucket_2} + ${#bucket_3} >= max_results )) && break
    done
  fi

  if ! _lhm_structured_query "$query" &&
     (( query_length >= 3 )) &&
     (( ${#bucket_1} + ${#bucket_2} + ${#bucket_3} < max_results )); then
    for command_line in "${_lhm_history_cache[@]}"; do
      [[ -n $command_line && $command_line != "$BUFFER" ]] || continue
      [[ -n ${seen_matches[$command_line]-} ]] && continue
      value=${(L)command_line}
      [[ $value == *"$query"* ]] || continue

      bucket_4+=( "$command_line" )
      seen_matches[$command_line]=1
      (( ${#bucket_1} + ${#bucket_2} + ${#bucket_3} + ${#bucket_4} >= max_results )) && break
    done
  fi

  if (( LHM_ENABLE_FUZZY )) &&
     ! _lhm_structured_query "$query" &&
     (( query_length >= LHM_FUZZY_MIN_QUERY_LENGTH )) &&
     (( ${#bucket_1} + ${#bucket_2} + ${#bucket_3} + ${#bucket_4} < max_results )); then
    for command_line in "${_lhm_history_cache[@]}"; do
      [[ -n $command_line && $command_line != "$BUFFER" ]] || continue
      [[ -n ${seen_matches[$command_line]-} ]] && continue
      value=${(L)command_line}
      _lhm_fuzzy_match "$query" "$value" || continue

      bucket_5+=( "$command_line" )
      seen_matches[$command_line]=1
      (( ${#bucket_1} + ${#bucket_2} + ${#bucket_3} + ${#bucket_4} + ${#bucket_5} >= max_results )) && break
    done
  fi

  _lhm_history_matches=(
    "$bucket_1[@]"
    "$bucket_2[@]"
    "$bucket_3[@]"
    "$bucket_4[@]"
    "$bucket_5[@]"
  )
  _lhm_history_matches=( "${_lhm_history_matches[@]:0:$max_results}" )

  (( $#_lhm_history_matches ))
}

_lhm_complete_history() {
  emulate -L zsh

  if ! (( _lhm_selecting )) ||
     (( _lhm_history_index == 0 )) ||
     [[ $BUFFER != ${_lhm_history_matches[_lhm_history_index]-} ]]; then
    _lhm_build_history_matches "$BUFFER" || return 1
  fi

  local -a displays
  local index marker command_line

  for index in {1..$#_lhm_history_matches}; do
    marker=' '
    (( index == _lhm_history_index )) && marker=$LHM_SELECTED_MARKER
    command_line=${_lhm_history_matches[index]}
    _lhm_format_history_display_line "$marker" "$index" "$#_lhm_history_matches" "$command_line"
    displays+=( "$REPLY" )
  done

  compadd -Q -U -V lhm-history-commands -d displays -a _lhm_history_matches
}

_lhm_clear_history_display() {
  POSTDISPLAY=''
  zle -R -c
}

_lhm_render_history_display() {
  emulate -L zsh

  if (( $#_lhm_history_matches == 0 )); then
    _lhm_clear_history_display
    return
  fi

  local -a lines=()
  local index marker command_line

  for index in {1..$#_lhm_history_matches}; do
    marker=' '
    (( index == _lhm_history_index )) && marker=$LHM_SELECTED_MARKER
    command_line=${_lhm_history_matches[index]}
    _lhm_format_history_display_line "$marker" "$index" "$#_lhm_history_matches" "$command_line"
    lines+=( "$REPLY" )
  done

  POSTDISPLAY=$'\n'"${(F)lines}"
  zle -R -c
}

_lhm_refresh_history_list() {
  emulate -L zsh

  (( _lhm_refreshing )) && return
  [[ $CONTEXT == start && $KEYMAP != menuselect ]] || return
  [[ -n ${BUFFER//[[:space:]]/} ]] || {
    _lhm_history_matches=()
    _lhm_history_query=''
    _lhm_history_index=0
    _lhm_selecting=0
    _lhm_clear_history_display
    return
  }

  _lhm_refreshing=1
  if _lhm_build_history_matches "$BUFFER"; then
    _lhm_render_history_display
  else
    _lhm_clear_history_display
  fi
  _lhm_refreshing=0
}

_lhm_after_edit() {
  _lhm_selecting=0
  _lhm_refresh_history_list
}

_lhm_self_insert() {
  zle .self-insert
  _lhm_after_edit
}

_lhm_backward_delete_char() {
  zle .backward-delete-char
  _lhm_after_edit
}

_lhm_delete_char() {
  zle .delete-char
  _lhm_after_edit
}

_lhm_backward_kill_line() {
  zle .backward-kill-line
  _lhm_after_edit
}

_lhm_kill_whole_line() {
  zle .kill-whole-line
  _lhm_after_edit
}

_lhm_kill_line() {
  zle .kill-line
  _lhm_after_edit
}

_lhm_backward_kill_word() {
  zle .backward-kill-word
  _lhm_after_edit
}

_lhm_kill_word() {
  zle .kill-word
  _lhm_after_edit
}

_lhm_select_history_previous() {
  emulate -L zsh

  if ! (( _lhm_selecting )) ||
     (( _lhm_history_index == 0 )) ||
     [[ $BUFFER != ${_lhm_history_matches[_lhm_history_index]-} ]]; then
    _lhm_build_history_matches "$BUFFER" || {
      zle .up-line-or-history
      return
    }
  fi

  if (( _lhm_history_index <= 1 )); then
    _lhm_history_index=$#_lhm_history_matches
  else
    (( _lhm_history_index-- ))
  fi

  BUFFER=${_lhm_history_matches[_lhm_history_index]}
  CURSOR=$#BUFFER
  _lhm_selecting=1
  _lhm_render_history_display
}

_lhm_select_history_next() {
  emulate -L zsh

  if ! (( _lhm_selecting )) ||
     (( _lhm_history_index == 0 )) ||
     [[ $BUFFER != ${_lhm_history_matches[_lhm_history_index]-} ]]; then
    _lhm_build_history_matches "$BUFFER" || {
      zle .down-line-or-history
      return
    }
  fi

  if (( _lhm_history_index == 0 ||
        _lhm_history_index >= $#_lhm_history_matches )); then
    _lhm_history_index=1
  else
    (( _lhm_history_index++ ))
  fi

  BUFFER=${_lhm_history_matches[_lhm_history_index]}
  CURSOR=$#BUFFER
  _lhm_selecting=1
  _lhm_render_history_display
}

_lhm_choose_history_match() {
  emulate -L zsh

  local index=$1

  (( index >= 1 && index <= $#_lhm_history_matches )) || return 1

  BUFFER=${_lhm_history_matches[index]}
  CURSOR=$#BUFFER
  _lhm_history_index=$index
  _lhm_selecting=1
  _lhm_render_history_display
}

_lhm_select_history_number() {
  emulate -L zsh

  local digit=${WIDGET##*-}
  local index=$digit
  local direct_select=0

  [[ $digit == 0 ]] && index=10
  [[ $WIDGET == *-alt-* ]] && direct_select=1

  if (( $#_lhm_history_matches == 0 )) &&
     (( direct_select )) &&
     [[ -n ${BUFFER//[[:space:]]/} ]]; then
    _lhm_build_history_matches "$BUFFER" || return 1
  fi

  if (( $#_lhm_history_matches == 0 )) ||
     (( ! direct_select && ! _lhm_selecting )); then
    zle .self-insert
    _lhm_after_edit
    return
  fi

  _lhm_choose_history_match "$index" || {
    (( direct_select )) && return 1
    zle .self-insert
    _lhm_after_edit
  }
}

_lhm_reset_history_state() {
  _lhm_history_matches=()
  _lhm_history_query=''
  _lhm_history_index=0
  _lhm_selecting=0
  POSTDISPLAY=''
}

_lhm_clear_empty_buffer_list() {
  emulate -L zsh

  [[ -n ${BUFFER//[[:space:]]/} ]] && return
  _lhm_history_matches=()
  _lhm_history_query=''
  _lhm_history_index=0
  _lhm_selecting=0
  _lhm_clear_history_display
}

_lhm_prepare_path_matches() {
  emulate -L zsh
  setopt extendedglob nullglob

  local typed_prefix=$1
  local -a local_entries=()
  local replacement_prefix matched_entry display_entry path_limit

  _lhm_path_matches=()
  _lhm_path_displays=()

  if [[ -z $typed_prefix ]]; then
    local_entries=( *(N) )
  elif [[ $typed_prefix == */* ]]; then
    replacement_prefix=${typed_prefix:h}
    [[ $replacement_prefix == $typed_prefix ]] && replacement_prefix='.'
    local_entries=( "$replacement_prefix"/"${typed_prefix:t}"*(N) )
  else
    local_entries=( "$typed_prefix"*(N) )
  fi

  path_limit=$LHM_PATH_MAX_RESULTS
  (( path_limit <= 0 )) && path_limit=$#local_entries

  for matched_entry in "$local_entries[@]"; do
    display_entry=$matched_entry
    [[ -d $matched_entry ]] && display_entry=${display_entry%/}/
    _lhm_path_matches+=( "$display_entry" )
    _lhm_path_displays+=( "$display_entry" )
    (( $#_lhm_path_matches >= path_limit )) && break
  done

  (( $#_lhm_path_matches ))
}

_lhm_complete_path() {
  emulate -L zsh

  if (( $#_lhm_path_matches )); then
    compadd -Q -U -V lhm-current-path -d _lhm_path_displays -a _lhm_path_matches
  fi
}

_lhm_path_tab() {
  emulate -L zsh
  setopt extendedglob nullglob

  local typed_prefix matched_entry replacement

  _lhm_clear_history_display

  if [[ -z ${LBUFFER//[[:space:]]/} ]]; then
    zle .expand-or-complete
    return
  fi

  if [[ $LBUFFER == *[[:space:]] ]]; then
    typed_prefix=''
  else
    typed_prefix=${LBUFFER##*[[:space:]]}
  fi

  _lhm_prepare_path_matches "$typed_prefix" || return 1

  if (( $#_lhm_path_matches == 1 )); then
    matched_entry=${_lhm_path_matches[1]}
    replacement=${(q)matched_entry}
    LBUFFER="${LBUFFER[1,$(( ${#LBUFFER} - ${#typed_prefix} ))]}${replacement}"
    return
  fi

  zle lhm-path-list
}

zle -C lhm-history-list list-choices _lhm_complete_history
zle -C lhm-path-list list-choices _lhm_complete_path
zle -N self-insert _lhm_self_insert
zle -N backward-delete-char _lhm_backward_delete_char
zle -N delete-char _lhm_delete_char
zle -N backward-kill-line _lhm_backward_kill_line
zle -N kill-whole-line _lhm_kill_whole_line
zle -N kill-line _lhm_kill_line
zle -N backward-kill-word _lhm_backward_kill_word
zle -N kill-word _lhm_kill_word
zle -N lhm-select-history-previous _lhm_select_history_previous
zle -N lhm-select-history-next _lhm_select_history_next
zle -N lhm-path-tab _lhm_path_tab

for _lhm_digit in {0..9}; do
  zle -N lhm-select-history-number-$_lhm_digit _lhm_select_history_number
  zle -N lhm-select-history-alt-number-$_lhm_digit _lhm_select_history_number
done
unset _lhm_digit

add-zle-hook-widget line-pre-redraw _lhm_clear_empty_buffer_list
add-zle-hook-widget line-finish _lhm_reset_history_state

bindkey '^[[A' lhm-select-history-previous
bindkey '^[[B' lhm-select-history-next
bindkey '^[OA' lhm-select-history-previous
bindkey '^[OB' lhm-select-history-next
bindkey '^I' lhm-path-tab

for _lhm_digit in {0..9}; do
  bindkey "$_lhm_digit" lhm-select-history-number-$_lhm_digit
  bindkey "^[$_lhm_digit" lhm-select-history-alt-number-$_lhm_digit
done
unset _lhm_digit

bindkey -M menuselect '^[[D' .backward-char  '^[OD' .backward-char 2>/dev/null
bindkey -M menuselect '^[[C' .forward-char   '^[OC' .forward-char  2>/dev/null
bindkey -M menuselect '^M' .accept-line 2>/dev/null
