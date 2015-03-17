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
	cd $1

	[[ "$(command git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] && {
		# check if it's dirty
		[[ "$PURE_GIT_UNTRACKED_DIRTY" == 0 ]] && local umode="-uno" || local umode="-unormal"
		command test -n "$(git status --porcelain --ignore-submodules ${umode})"

		(($? == 0)) && echo "*"

		# add artificial delay in such a case that the task is completed "too" fast
		# otherwise preprompt redraw might interfere with initial draw from precmd
		sleep 0.01
	}
}

prompt_pure_git_fetch() {
	cd $1

	(( ${PURE_GIT_PULL:-1} )) && {
		# check if we're in a git repo
		[[ "$(command git rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] &&
		# make sure working tree is not $HOME
		[[ "$(command git rev-parse --show-toplevel)" != "$HOME" ]] &&
		# check check if there is anything to pull
		command git fetch &>/dev/null
	}
}

prompt_pure_git_arrows() {
	# check if there is an upstream configured for this branch
	command git rev-parse --abbrev-ref @'{u}' &>/dev/null && {
		local arrows=''
		(( $(command git rev-list --right-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows='⇣'
		(( $(command git rev-list --left-only --count HEAD...@'{u}' 2>/dev/null) > 0 )) && arrows+='⇡'
		# output the arrows
		echo " ${arrows}"
	}
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
	[[ -n ${cmd_timestamp+x} && "$1" != "precmd" ]] && return

	# construct prompt, beginning with path
	local prompt="%F{blue}%~%f"
	# git info
	prompt+="%F{242}${vcs_info_msg_0_}${_prompt_git_dirty}%f"
	# git pull/push arrows
	prompt+="%F{cyan}${_prompt_git_arrows}%f"
	# username and machine if applicable
	prompt+=$prompt_pure_username
	# execution time
	prompt+="%F{yellow}${_prompt_exec_time}%f"

	# if executing through precmd, do not perform fancy terminal editing
	if [[ "$1" == "precmd" ]]; then
		print -P "\n${prompt}"
	else
		# only redraw if prompt has changed
		[[ "${_prompt_previous_prompt}" != "${prompt}" ]] || return

		# calculate length of prompt for redraw purposes
		local prompt_length=$(prompt_pure_string_length $prompt)
		local lines=$(( $prompt_length / $COLUMNS + 1 ))

		# disable clearing of line if last char of prompt is last column of terminal
		local clr="\e[K"
		(( $prompt_length * $lines == $COLUMNS - 1 )) && clr=""

		# modify previous prompt
		print -Pn "\e7\e[${lines}A\e[1G${prompt}${clr}\e8"
	fi

	# store previous prompt for comparison
	_prompt_previous_prompt=$prompt
}

prompt_pure_precmd() {
	_prompt_ret=$?

	# store exec time for when preprompt gets re-rendered
	_prompt_exec_time=$(prompt_pure_cmd_exec_time)

	# check for git arrows
	_prompt_git_arrows=$(prompt_pure_git_arrows)

	# set timestamp, indicates that preprompt should not be redrawn even if a redraw is triggered
	cmd_timestamp=${cmd_timestamp:-$EPOCHSECONDS}

	# shows the full path in the title
	print -Pn '\e]0;%~\a'

	# preform async git dirty check and fetch
	prompt_pure_async_tasks

	# get vcs info
	vcs_info

	# print the preprompt
	prompt_pure_preprompt_render "precmd"

	unset cmd_timestamp

	return ${_prompt_ret}
}

prompt_pure_chpwd() {
	# prefix working_tree with x as to not match current path, affects variable resolution
	local working_tree="x$(command git rev-parse --show-toplevel 2>/dev/null)"

	# check if the working tree has changed and run git fetch immediately
	if [ "${_pure_git_working_tree}" != "${working_tree}" ]; then
		# stop any running async jobs
		async_flush_jobs "prompt_pure"

		# reset git preprompt variables, switching working tree
		_prompt_git_dirty=
		_prompt_git_delay_dirty_check=

		_pure_git_working_tree=$working_tree
	fi
}

prompt_pure_async_tasks() {
	# initialize async worker
	((!${_pure_async_init:-0})) && {
		trap '
			async_process_results "prompt_pure" prompt_pure_async_callback
		' WINCH
		async_start_worker "prompt_pure" -u -n
		_pure_async_init=1
	}

	# tell worker to do a git fetch
	async_job "prompt_pure" prompt_pure_git_fetch $PWD

	# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
	local dirty_check=$(( $EPOCHSECONDS - ${_prompt_git_delay_dirty_check:-0} ))
	if (( $dirty_check > ${PURE_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		async_job "prompt_pure" prompt_pure_git_dirty $PWD
	fi
}

prompt_pure_async_callback() {
	local job=$1
	local output=$3
	local exec_time=$4

	if [[ "$job" == "prompt_pure_git_dirty" ]]; then
		_prompt_git_dirty=$output
		(( $exec_time > 2 )) && _prompt_git_delay_dirty_check=$EPOCHSECONDS
	elif [[ "$job" == "prompt_pure_git_fetch" ]]; then
		_prompt_git_arrows=$(prompt_pure_git_arrows)
	fi

	prompt_pure_preprompt_render
}

prompt_pure_setup() {
	# prevent percentage showing up
	# if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	# disable auth prompting on git 2.3+
	export GIT_TERMINAL_PROMPT=0

	prompt_opts=(cr subst percent)

	zmodload zsh/datetime
	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec
	add-zsh-hook chpwd prompt_pure_chpwd

	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:git*' formats ' %b'
	zstyle ':vcs_info:git*' actionformats ' %b|%a'

	# show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && prompt_pure_username=' %F{242}%n@%m%f'

	# show username@host if root, with username in white
	[[ $UID -eq 0 ]] && prompt_pure_username=' %F{white}%n%f%F{242}@%m%f'

	# prompt turns red if the previous command didn't exit with 0
	PROMPT="%(?.%F{magenta}.%F{red})${PURE_PROMPT_SYMBOL:-❯}%f "

	# trigger initial chpwd for new sessions
	prompt_pure_chpwd
}

prompt_pure_setup "$@"
