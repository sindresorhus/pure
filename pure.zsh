# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License

# For my own and others sanity
# git:
# %b => current branch
# %a => current action (rebase/merge)
# prompt:
# %F => color dict
# %f => reset color
# %~ => current path
# %* => time
# %n => username
# %m => shortname host
# %(?..) => prompt conditional - %(condition.true.false)
# terminal codes:
# \e7   => save cursor position
# \e[2A => move cursor 2 lines up
# \e[1G => go to position 1 in terminal
# \e8   => restore cursor position
# \e[K  => clears everything after the cursor on the current line


# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
prompt_pure_human_time() {
	echo -n " "
	local tmp=$1
	local days=$(( tmp / 60 / 60 / 24 ))
	local hours=$(( tmp / 60 / 60 % 24 ))
	local minutes=$(( tmp / 60 % 60 ))
	local seconds=$(( tmp % 60 ))
	(( $days > 0 )) && echo -n "${days}d "
	(( $hours > 0 )) && echo -n "${hours}h "
	(( $minutes > 0 )) && echo -n "${minutes}m "
	echo "${seconds}s"
}

# fastest possible way to check if repo is dirty
prompt_pure_git_dirty() {
	local dirty=""
	local start=$EPOCHSECONDS

	[[ "$(command git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] && {
		# check if it's dirty
		[[ "$PURE_GIT_UNTRACKED_DIRTY" == 0 ]] && local umode="-uno" || local umode="-unormal"
		command test -n "$(git status --porcelain --ignore-submodules ${umode})"

		(($? == 0)) && dirty="*"
	}

	echo "dirty|${dirty}:$(( $EPOCHSECONDS - $start ))"
}

prompt_pure_git_fetch() {
	local state=""
	local start=$EPOCHSECONDS

	(( ${PURE_GIT_PULL:-1} )) && {
		# check if we're in a git repo
		[[ "$(command git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] &&
		# make sure working tree is not $HOME
		[[ "$(command git rev-parse --show-toplevel)" != "$HOME" ]] &&
		# check check if there is anything to pull
		command git fetch &>/dev/null &&
		state="done"
	}

	echo "fetch|${state}:$(( $EPOCHSECONDS - $start ))"
}

prompt_pure_git_arrows() {
	# check if there is an upstream configured for this branch
	command git rev-parse --abbrev-ref @'{u}' &>/dev/null && {
		local arrows=''
		(( $(command git rev-list --right-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows='⇣'
		(( $(command git rev-list --left-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows+='⇡'
		# output the arrows
		echo " %F{cyan}${arrows}%f"
	}
}

prompt_pure_check_worker_results() {
	integer count=0

	# read output from zpty and parse it if available
	while zpty -r prompt_pure_worker line; do
		count+=1
		local cmd=${line%|*}
		local result=${line#*|}
		local value=${result%:*}
		local timestamp=${result#*:}
		# remove ^M at end
		timestamp=${timestamp//[^0-9]/}

		[[ $cmd == "dirty" ]] && {
			_prompt_git_dirty=$value
			(( ${timestamp} > 2 )) && _prompt_git_delay_dirty_check=$EPOCHSECONDS
		}
		[[ $cmd == "fetch" && $value == "done" ]] && _prompt_git_arrows=$(prompt_pure_git_arrows)
	done

	# if there were results, attempt to redraw the preprompt
	(( $count )) && prompt_pure_preprompt_render

	# re-start time for periodic instance
	[[ $1 == "periodic" ]] && sched +15 prompt_pure_check_worker_results periodic

	# because this task can run at any time, prevent it from destroying last cmd return status
	return ${_prompt_ret}
}

# the background worker does some processing for us without locking up the terminal
prompt_pure_background_worker() {
	local storage
	typeset -A storage

	while read -r line; do
		local cmd=${line%|*}
		local dir=${line#*|}
		local job="prompt_pure_git_${cmd}"

		# change working directory if it has changed
		[[ ${storage[dir]} != $dir ]] && {
			cd "$dir"
			# kill any child processes still running, we don't care about their results
			kill ${${(v)jobstates##*:*:}%=*} &>/dev/null
			storage[dir]=$dir
		}

		# check if a previous job is still running, if yes, let it finnish
		for pid in ${${(v)jobstates##*:*:}%=*}; do
			[[ "${storage[$cmd]}" == "$pid" ]] && continue 2
		done

		# run task in background
		$job &
		# store pid because zsh job manager is extremely unflexible (show jobname as non-unique '$job')...
		storage[$cmd]=$!
	done
}

# displays the exec time of the last command if set threshold was exceeded
prompt_pure_cmd_exec_time() {
	local stop=$EPOCHSECONDS
	local start=${cmd_timestamp:-$stop}
	integer elapsed=$stop-$start
	(($elapsed > ${PURE_CMD_MAX_EXEC_TIME:=5})) && prompt_pure_human_time $elapsed
}

prompt_pure_preexec() {
	cmd_timestamp=$EPOCHSECONDS

	# shows the current dir and executed command in the title when a process is active
	print -Pn "\e]0;"
	echo -nE "$PWD:t: $2"
	print -Pn "\a"
}

# string length ignoring ansi escapes
prompt_pure_string_length() {
	# Subtract one since newline is counted as two characters
	echo $(( ${#${(S%%)1//(\%([KF1]|)\{*\}|\%[Bbkf])}} - 1 ))
}

prompt_pure_preprompt_render() {
	# check that no command is currently running, rendering might not be safe
	[[ -n ${cmd_timestamp+x} ]] && return

	# get vcs info
	vcs_info

	local prompt="%F{blue}%~%F{242}${vcs_info_msg_0_}${_prompt_git_dirty}$prompt_pure_username%f%F{yellow}${_prompt_exec_time}%f${_prompt_git_arrows}"
	local prompt_length=$(prompt_pure_string_length $prompt)
	local lines=$(( $prompt_length / $COLUMNS + 1 ))

	# if executing through precmd, do not perform fancy terminal editing
	if [[ "$1" == "precmd" ]]; then
		print -P "\n${prompt}"
	else
		# only redraw if prompt has changed
		[[ "${_prompt_previous_prompt}" != "${prompt}" ]] || return

		# disable clearing of line if last char of prompt is last column of terminal
		local clr="\e[K"
		(( $prompt_length * $lines == $COLUMNS - 1 )) && clr=""

		# modify previous prompt
		# {
		print -Pn "\e7\e[${lines}A\e[1G${prompt}${clr}\e8" #} &!
	fi

	# store previous prompt for comparison
	_prompt_previous_prompt=$prompt
}

prompt_pure_precmd() {
	_prompt_ret=$?
	# shows the full path in the title
	print -Pn '\e]0;%~\a'

	# store exec time for when preprompt gets re-rendered
	_prompt_exec_time=$(prompt_pure_cmd_exec_time)
	unset cmd_timestamp

	# make sure the worker is initialized, delete it if it has failed
	zpty -t prompt_pure_worker &>/dev/null || zpty -b prompt_pure_worker prompt_pure_background_worker || zpty -d prompt_pure_worker

	# check for possible worker results now, and in a second
	prompt_pure_check_worker_results
	sched +1 prompt_pure_check_worker_results

	# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
	(( $EPOCHSECONDS - ${_prompt_git_delay_dirty_check:-0} > ${PURE_GIT_DELAY_DIRTY_CHECK:-1800} )) &&
	zpty -w prompt_pure_worker "dirty|$PWD"

	# tell worker to do a git fetch
	zpty -w prompt_pure_worker "fetch|$PWD"

	# print the preprompt
	prompt_pure_preprompt_render precmd

	return ${_prompt_ret}
}

prompt_pure_chpwd() {
	# prefix working_tree with x as to not match current path, affects variable resolution
	local working_tree="x$(command git rev-parse --show-toplevel 2>/dev/null)"

	# check if the working tree has changed and run git fetch immediately
	if [ "${_pure_git_working_tree}" != "${working_tree}" ]; then
		# reset git preprompt variables, switching working tree
		_prompt_git_dirty=
		_prompt_git_delay_dirty_check=
		_prompt_git_arrows=$(prompt_pure_git_arrows)

		_pure_git_working_tree=$working_tree
	fi
}

prompt_pure_setup() {
	# prevent percentage showing up
	# if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	# disable auth prompting on git 2.3+
	export GIT_TERMINAL_PROMPT=0

	prompt_opts=(cr subst percent)

	# loat zpty and sched for async & monitoring
	zmodload zsh/zpty
	zmodload zsh/sched

	zmodload zsh/datetime
	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec
	add-zsh-hook chpwd prompt_pure_chpwd

	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:git*' formats ' %b'
	zstyle ':vcs_info:git*' actionformats ' %b|%a'

	# show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && prompt_pure_username=' %n@%m'

	# show username@host if root, with username in white
	[[ $UID -eq 0 ]] && prompt_pure_username=' %F{white}%n%F{242}@%m'

	# prompt turns red if the previous command didn't exit with 0
	PROMPT="%(?.%F{magenta}.%F{red})${PURE_PROMPT_SYMBOL:-❯}%f "

	# trigger initial chpwd for new sessions
	prompt_pure_chpwd
	# initialize periodic check for worker results
	sched +15 prompt_pure_check_worker_results periodic
}

prompt_pure_setup "$@"
