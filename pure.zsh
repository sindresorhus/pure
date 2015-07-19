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
# https://github.com/sindresorhus/pretty-time-zsh
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

# displays the exec time of the last command if set threshold was exceeded
prompt_pure_check_cmd_exec_time() {
	local stop=$EPOCHSECONDS
	local start=${prompt_pure_cmd_timestamp:-$stop}
	integer elapsed=$stop-$start
	(($elapsed > ${PURE_CMD_MAX_EXEC_TIME:=5})) && prompt_pure_human_time $elapsed
}

if [[ "$PURE_HIGHLIGHT_REPO" == 1 ]] ; then
	# underline
	PURE_UNDERLINE_START="$(tput smul)"
	PURE_UNDERLINE_END="$(tput rmul)"
	# bold
	# PURE_UNDERLINE_START=${fg_bold[blue]}
	# PURE_UNDERLINE_END=${fg_no_bold[blue]}
	prompt_pure_render_preprompt_path() {
		if [[ -n "$vcs_info_msg_1_" ]] ; then
			local prerepo reponame postrepo
			if [[ "$PWD" == "$vcs_info_msg_1_"* ]]; then
				# the working directory is the real path
				prerepo=${vcs_info_msg_1_%/*}
				if [[ "$prerepo" == "$HOME"* ]]; then prerepo="~${prerepo#$HOME}"; fi # replace ~
				prerepo="${prerepo%/}/"
				reponame=${vcs_info_msg_1_##*/}
				postrepo="${PWD#$vcs_info_msg_1_}"
				postrepo=${postrepo#/}
				[[ -n "${postrepo}" ]] && postrepo="/${postrepo}"
				prompt_pure_preprompt_path="%F{blue}${prerepo}${PURE_UNDERLINE_START}${reponame}${PURE_UNDERLINE_END}${postrepo}"
			elif [[ "$PWD" == */"$vcs_info_msg_2_" ]]; then
				# the working directory is in a git repository under a symlink
				local repopath="${PWD%/$vcs_info_msg_2_}"
				reponame=${repopath##*/}
				prerepo=${repopath%/*}
				if [[ "${prerepo}" == "$HOME"* ]]; then prerepo="~${prerepo#$HOME}" fi # replace ~
				prerepo="${prerepo%/}/"
				prompt_pure_preprompt_path="%F{blue}${prerepo}${PURE_UNDERLINE_START}${reponame}${PURE_UNDERLINE_END}/$vcs_info_msg_2_"
			elif [[ "$vcs_info_msg_2_" == "." ]]; then
				# the working directory is at the root of a repo under a symlink
				prerepo=${PWD%/*}
				if [[ "${prerepo}" == "$HOME"* ]]; then prerepo="~${prerepo#$HOME}" fi # replace ~
				prerepo="${prerepo%/}/"
				reponame=${PWD##*/}
				prompt_pure_preprompt_path="%F{blue}${prerepo}${PURE_UNDERLINE_START}${reponame}${PURE_UNDERLINE_END}"
			else
				# fallback: the working directory symlinks into a repo somewhere else
				prompt_pure_preprompt_path="%F{blue}%~"
			fi
		else
			prompt_pure_preprompt_path="%F{blue}%~"
		fi
	}
else
	prompt_pure_render_preprompt_path() {
		prompt_pure_preprompt_path="%F{blue}%~"
	}
fi

prompt_pure_clear_screen() {
	# enable output to terminal
	zle -I
	# clear screen and move cursor to (0, 0)
	print -n '\e[2J\e[0;0H'
	# print preprompt
	prompt_pure_preprompt_render precmd
}

prompt_pure_check_git_arrows() {
	# check if there is an upstream configured for this branch
	command git rev-parse --abbrev-ref @'{u}' &>/dev/null || return

	local right left arrows
	right=$(command git rev-list --right-only --count HEAD...@'{u}' 2>/dev/null)
	left=$(command git rev-list --left-only --count HEAD...@'{u}' 2>/dev/null)

	(( ${right:-0} > 0 )) && arrows="${PURE_GIT_DOWN_ARROW:-⇣}"
	(( ${left:-0} > 0 )) && arrows+="${PURE_GIT_UP_ARROW:-⇡}"
	# output the arrows
	[[ $arrows != "" ]] && echo " ${arrows}"
}

prompt_pure_preexec() {
	prompt_pure_cmd_timestamp=$EPOCHSECONDS

	# tell the terminal we are setting the title
	print -Pn "\e]0;"
	# show hostname if connected through ssh
	[[ "$SSH_CONNECTION" != '' ]] && print -Pn "(%m) "
	# shows the current dir and executed command in the title when a process is active
	# (use print -r to disable potential evaluation of escape characters in cmd)
	print -nr "$PWD:t: $2"
	print -Pn "\a"
}

# string length ignoring ansi escapes
prompt_pure_string_length() {
	echo $(( ${#${(S%%)1//(\%([KF1]|)\{*\}|\%[Bbkf])}} ))
}

prompt_pure_preprompt_render() {
	# check that no command is currently running, the preprompt will otherwise be rendered in the wrong place
	[[ -n ${prompt_pure_cmd_timestamp+x} && "$1" != "precmd" ]] && return

	# set color for git branch/dirty status, change color if dirty checking has been delayed
	local git_color=242
	[[ -n ${prompt_pure_git_last_dirty_check_timestamp+x} ]] && git_color=red

	# construct preprompt, beginning with path
	local prompt_pure_preprompt_path
	prompt_pure_render_preprompt_path
	local preprompt="$prompt_pure_preprompt_path"
	# git info
	preprompt+="%F{$git_color}${vcs_info_msg_0_}${prompt_pure_git_dirty}%f"
	# git pull/push arrows
	preprompt+="%F{cyan}${prompt_pure_git_arrows}%f"
	# username and machine if applicable
	preprompt+=$prompt_pure_username
	# execution time
	preprompt+="%F{yellow}${prompt_pure_cmd_exec_time}%f"

	# if executing through precmd, do not perform fancy terminal editing
	if [[ "$1" == "precmd" ]]; then
		print -P "\n${preprompt}"
	else
		# only redraw if preprompt has changed
		[[ "${prompt_pure_last_preprompt}" != "${preprompt}" ]] || return

		# calculate length of preprompt for redraw purposes
		local preprompt_length=$(prompt_pure_string_length $preprompt)
		local lines=$(( ($preprompt_length - 1) / $COLUMNS + 1 ))

		# disable clearing of line if last char of preprompt is last column of terminal
		local clr="\e[K"
		(( $COLUMNS * $lines == $preprompt_length )) && clr=""

		# modify previous preprompt
		print -Pn "\e7\e[${lines}A\e[1G${preprompt}${clr}\e8"
	fi

	# store previous preprompt for comparison
	prompt_pure_last_preprompt=$preprompt
}

prompt_pure_precmd() {
	# store exec time for when preprompt gets re-rendered
	prompt_pure_cmd_exec_time=$(prompt_pure_check_cmd_exec_time)

	# by making sure that prompt_pure_cmd_timestamp is defined here the async functions are prevented from interfering
	# with the initial preprompt rendering
	prompt_pure_cmd_timestamp=

	# check for git arrows
	prompt_pure_git_arrows=$(prompt_pure_check_git_arrows)

	# tell the terminal we are setting the title
	print -Pn "\e]0;"
	# show hostname if connected through ssh
	[[ "$SSH_CONNECTION" != '' ]] && print -Pn "(%m) "
	# shows the full path in the title
	print -Pn "%~\a"

	# get vcs info
	vcs_info

	# preform async git dirty check and fetch
	prompt_pure_async_tasks

	# print the preprompt
	prompt_pure_preprompt_render "precmd"

	# remove the prompt_pure_cmd_timestamp, indicating that precmd has completed
	unset prompt_pure_cmd_timestamp
}

# fastest possible way to check if repo is dirty
prompt_pure_async_git_dirty() {
	local untracked_dirty=$1; shift

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	cd -q "$*"

	if [[ "$untracked_dirty" == "0" ]]; then
		command git diff --no-ext-diff --quiet --exit-code
	else
		test -z "$(command git status --porcelain --ignore-submodules -unormal)"
	fi

	(( $? )) && echo "*"
}

prompt_pure_async_git_fetch() {
	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	cd -q "$*"

	# set GIT_TERMINAL_PROMPT=0 to disable auth prompting for git fetch (git 2.3+)
	GIT_TERMINAL_PROMPT=0 command git -c gc.auto=0 fetch
}

prompt_pure_async_tasks() {
	# initialize async worker
	((!${prompt_pure_async_init:-0})) && {
		async_start_worker "prompt_pure" -u -n
		async_register_callback "prompt_pure" prompt_pure_async_callback
		prompt_pure_async_init=1
	}

	# get the current git working tree, empty if not inside a git directory
	local working_tree="$(command git rev-parse --show-toplevel 2>/dev/null)"

	# check if the working tree changed (prompt_pure_current_working_tree is prefixed by "x")
	if [[ "${prompt_pure_current_working_tree:-x}" != "x${working_tree}" ]]; then
		# stop any running async jobs
		async_flush_jobs "prompt_pure"

		# reset git preprompt variables, switching working tree
		unset prompt_pure_git_dirty
		unset prompt_pure_git_last_dirty_check_timestamp

		# set the new working tree and prefix with "x" to prevent the creation of a named path by AUTO_NAME_DIRS
		prompt_pure_current_working_tree="x${working_tree}"
	fi

	# only perform tasks inside git working tree
	[[ "${working_tree}" != "" ]] || return

	if (( ${PURE_GIT_PULL:-1} )); then
		# make sure working tree is not $HOME
		[[ "${working_tree}" != "$HOME" ]] &&
		# tell worker to do a git fetch
		async_job "prompt_pure" prompt_pure_async_git_fetch "$working_tree"
	fi

	# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
	local time_since_last_dirty_check=$(( $EPOCHSECONDS - ${prompt_pure_git_last_dirty_check_timestamp:-0} ))
	if (( $time_since_last_dirty_check > ${PURE_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		unset prompt_pure_git_last_dirty_check_timestamp
		# check check if there is anything to pull
		async_job "prompt_pure" prompt_pure_async_git_dirty "${PURE_GIT_UNTRACKED_DIRTY:-1}" "$working_tree"
	fi
}

prompt_pure_async_callback() {
	local job=$1
	local output=$3
	local exec_time=$4

	case "${job}" in
		prompt_pure_async_git_dirty)
			prompt_pure_git_dirty=$output
			prompt_pure_preprompt_render

			# When prompt_pure_git_last_dirty_check_timestamp is set, the git info is displayed in a different color.
			# To distinguish between a "fresh" and a "cached" result, the preprompt is rendered before setting this
			# variable. Thus, only upon next rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 2 )) && prompt_pure_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		prompt_pure_async_git_fetch)
			prompt_pure_git_arrows=$(prompt_pure_check_git_arrows)
			prompt_pure_preprompt_render
			;;
	esac
}

prompt_pure_setup() {
	# prevent percentage showing up
	# if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	zmodload zsh/datetime
	zmodload zsh/zle
	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

	zstyle ':vcs_info:*' max-exports 3
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	zstyle ':vcs_info:git*' formats ' %b' '%R' '%S'
	zstyle ':vcs_info:git*' actionformats ' %b|%a' '%R' '%S'

	# if the user has not registered a custom zle widget for clear-screen,
	# override the builtin one so that the preprompt is displayed correctly when
	# ^L is issued.
	if [[ $widgets[clear-screen] == 'builtin' ]]; then
		zle -N clear-screen prompt_pure_clear_screen
	fi

	# show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && prompt_pure_username=' %F{242}%n@%m%f'

	# show username@host if root, with username in white
	[[ $UID -eq 0 ]] && prompt_pure_username=' %F{white}%n%f%F{242}@%m%f'

	# prompt turns red if the previous command didn't exit with 0
	PROMPT="%(?.%F{magenta}.%F{red})${PURE_PROMPT_SYMBOL:-❯}%f "
}

prompt_pure_setup "$@"
