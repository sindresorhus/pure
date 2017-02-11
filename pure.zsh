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
# \e[2K => clear everything on the current line


# turns seconds into human readable time
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pure_human_time_to_var() {
	local human=" " total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s"

	# store human readable time in variable as specified by caller
	typeset -g "${var}"="${human}"
}

# stores (into prompt_pure_cmd_exec_time) the exec time of the last command if set threshold was exceeded
prompt_pure_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_pure_cmd_timestamp:-$EPOCHSECONDS} ))
	prompt_pure_cmd_exec_time=
	(( elapsed > ${PURE_CMD_MAX_EXEC_TIME:=5} )) && {
		prompt_pure_human_time_to_var $elapsed "prompt_pure_cmd_exec_time"
	}
}

prompt_pure_clear_screen() {
	# enable output to terminal
	zle -I
	# clear screen and move cursor to (0, 0)
	print -n '\e[2J\e[0;0H'
	# print preprompt
	prompt_pure_preprompt_render precmd
}

prompt_pure_set_title() {
	# emacs terminal does not support settings the title
	(( ${+EMACS} )) && return

	# tell the terminal we are setting the title
	print -n '\e]0;'
	# show hostname if connected through ssh
	[[ -n $SSH_CONNECTION ]] && print -Pn '(%m) '
	case $1 in
		expand-prompt)
			print -Pn $2;;
		ignore-escape)
			print -rn $2;;
	esac
	# end set title
	print -n '\a'
}

prompt_pure_preexec() {
	if [[ -n $prompt_pure_git_fetch_pattern ]]; then
		# detect when git is performing pull/fetch (including git aliases).
		if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_pure_git_fetch_pattern)(\ .*)?$ ]]; then
			# we must flush the async jobs to cancel our git fetch in order
			# to avoid conflicts with the user issued pull / fetch.
			async_flush_jobs 'prompt_pure'
		fi
	fi

	prompt_pure_cmd_timestamp=$EPOCHSECONDS

	# shows the current dir and executed command in the title while a process is active
	prompt_pure_set_title 'ignore-escape' "$PWD:t: $2"
}

# string length ignoring ansi escapes
prompt_pure_string_length_to_var() {
	local str=$1 var=$2 length
	# perform expansion on str and check length
	length=$(( ${#${(S%%)str//(\%([KF1]|)\{*\}|\%[Bbkf])}} ))

	# store string length in variable as specified by caller
	typeset -g "${var}"="${length}"
}

prompt_pure_preprompt_render() {
	# store the current prompt_subst setting so that it can be restored later
	local prompt_subst_status=$options[prompt_subst]

	# make sure prompt_subst is unset to prevent parameter expansion in preprompt
	setopt local_options no_prompt_subst no_sh_word_split

	# check that no command is currently running, the preprompt will otherwise be rendered in the wrong place
	[[ -n ${prompt_pure_cmd_timestamp+x} && "$1" != "precmd" ]] && return

	# set color for git branch/dirty status, change color if dirty checking has been delayed
	local git_color=242
	[[ -n ${prompt_pure_git_last_dirty_check_timestamp+x} ]] && git_color=red

	# Initialize the preprompt array.
	local -a preprompt_parts

	# Expand the working directory for later comparison.
	local expanded_pwd="%~"
	expanded_pwd=${(%)expanded_pwd}

	preprompt_parts+=("%F{blue}$expanded_pwd%f")

	# git info
	typeset -gA prompt_pure_vcs_info
	if [[ -n $prompt_pure_vcs_info[branch] ]]; then
		preprompt_parts+=(" %F{$git_color}${prompt_pure_vcs_info[branch]}%f")
		preprompt_parts+=("%F{$git_color}${prompt_pure_git_dirty}%f")
	fi
	# git pull/push arrows
	if [[ -n $prompt_pure_git_arrows ]]; then
		preprompt_parts+=(" %F{cyan}${prompt_pure_git_arrows}%f")
	fi

	# username and machine if applicable
	[[ -n $prompt_pure_username ]] && preprompt_parts+=($prompt_pure_username)
	# execution time
	[[ -n $prompt_pure_cmd_exec_time ]] && preprompt_parts+=("%F{yellow}${prompt_pure_cmd_exec_time}%f")

	# Join the preprompt array on empty string.
	local preprompt=${(j..)preprompt_parts}

	# if executing through precmd, do not perform fancy terminal editing
	if [[ "$1" == "precmd" ]]; then
		print -P "\n${preprompt}"
	else
		local prev_preprompt=${(j..)prompt_pure_last_preprompt}
		if [[ $prev_preprompt == $preprompt ]]; then
			# Avoid redrawing when there are no changes.
			return
		fi

		# We need the length/lines of the preprompt to
		# figure out what update method we should use.
		integer preprompt_length lines
		prompt_pure_string_length_to_var "$preprompt" preprompt_length
		lines=$(( ((preprompt_length - 1) / COLUMNS) + 1 ))

		# We use the length/lines of the previous preprompt to
		# figure out the best update method for the new one.
		integer last_preprompt_length last_lines
		prompt_pure_string_length_to_var "$prev_preprompt" last_preprompt_length
		last_lines=$(( ((last_preprompt_length - 1) / COLUMNS) + 1 ))

		# The patch position can tell us if we can perform a partial redraw to
		# update the preprompt. A partial update is faster and causes less
		# visual flicker.
		integer patch_pos=1

		# With clr_prev_preprompt we can erase visual artifacts,
		# if any, from the previous preprompt.
		local clr_prev_preprompt

		if (( last_lines > lines )); then
			# Move the cursor to the top (of previous preprompt) and erase
			# line-by-line, moving downwards, until the number of lines matches
			# the new preprompt.
			clr_prev_preprompt="\e[${last_lines}A\e[2K\e[1B"
			while (( last_lines - lines > 1 )); do
				# Add a line clear and move cursor down one line.
				clr_prev_preprompt+='\e[2K\e[1B'
				(( last_lines-- ))
			done

			# Move cursor all the way back down just so we can move it up again
			# during the update, this simplifies the algorithm.
			clr_prev_preprompt+="\e[${lines}B"
		elif (( last_lines < lines )); then
			# When the preprompt takes up more lines than the previous, we must
			# make more vertical space using newlines. Ansi escape sequences
			# alone cannot move the cursor beyond the terminal edge.
			printf $'\n'%.0s {1..$(( lines - last_lines ))}
		else
			# When lines equal, we can try to perform a partial prompt update.
			integer pos
			for (( pos = 1; pos <= $#preprompt_parts; pos++ )); do
				patch_pos=$pos
				if [[ $preprompt_parts[$pos] != $prompt_pure_last_preprompt[$pos] ]]; then
					break  # We found where the preprompts differ.
				fi
			done
		fi

		local clr='\e[K'
		if (( (COLUMNS * lines) == preprompt_length )) || (( preprompt_length > last_preprompt_length )); then
			# When the preprompt ends at the last column of the terminal, or is
			# longer than the previous, clearing the rest makes no sense.
			clr=
		fi

		local move_to_patch_pos
		if (( patch_pos > 1 )); then
			# Find out how long the matching part of the preprompt is.
			integer patch_pos_length
			prompt_pure_string_length_to_var "${(j..)preprompt_parts[1,$patch_pos-1]}" patch_pos_length

			# Consider the line where our patch starts.
			lines=$(( lines - (patch_pos_length / COLUMNS) ))

			# Move the cursor N columns right, into the correct patch position.
			move_to_patch_pos="\e[$(( (patch_pos_length % COLUMNS) + 1 ))G"

			# Modify the prompt since we are performing a partial update.
			preprompt=${(j..)preprompt_parts[$patch_pos,-1]}
		fi

		# Redraw preprompt, either by patching or fully redrawing.
		# TODO: Figure out cursor position instead of relying on ESC[1G
		# The escape, ESC[nG is not part of ANSI.SYS and is not supported by
		# some terminal emulators, Emacs ansi-term comes to mind.
		print -Pn "${clr_prev_preprompt}\e[${lines}A\e[1G${move_to_patch_pos}${preprompt}${clr}\n"

		if [[ $prompt_subst_status = 'on' ]]; then
			# Re-enable prompt_subst for expansion on PS1,
			# affects zle reset-prompt.
			setopt prompt_subst
		fi

		# Redraw prompt to reset cursor position.
		zle && zle .reset-prompt

		setopt no_prompt_subst
	fi

	# Store the preprompt for later comparision.
	prompt_pure_last_preprompt=($preprompt_parts)
}

prompt_pure_precmd() {
	# check exec time and store it in a variable
	prompt_pure_check_cmd_exec_time

	# by making sure that prompt_pure_cmd_timestamp is defined here the async functions are prevented from interfering
	# with the initial preprompt rendering
	prompt_pure_cmd_timestamp=

	# shows the full path in the title
	prompt_pure_set_title 'expand-prompt' '%~'

	# preform async git dirty check and fetch
	prompt_pure_async_tasks

	# print the preprompt
	prompt_pure_preprompt_render "precmd"

	# remove the prompt_pure_cmd_timestamp, indicating that precmd has completed
	unset prompt_pure_cmd_timestamp
}

prompt_pure_async_git_aliases() {
	setopt localoptions noshwordsplit
	local dir=$1
	local -a gitalias pullalias

	# we enter repo to get local aliases as well.
	builtin cd -q $dir

	# list all aliases and split on newline.
	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})           # split line on spaces
		aliasname=${parts[1]#alias.}  # grab the name (alias.[name])
		shift parts                   # remove aliasname

		# check alias for pull or fetch (must be exact match).
		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}  # join on pipe (for use in regex).
}

prompt_pure_async_vcs_info() {
	setopt localoptions noshwordsplit
	builtin cd -q $1 2>/dev/null

	# configure vcs_info inside async task, this frees up vcs_info
	# to be used or configured as the user pleases.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# only export two msg variables from vcs_info
	zstyle ':vcs_info:*' max-exports 2
	# export branch (%b) and git toplevel (%R)
	zstyle ':vcs_info:git*' formats '%b' '%R'
	zstyle ':vcs_info:git*' actionformats '%b|%a' '%R'

	vcs_info

	local -A info
	info[top]=$vcs_info_msg_1_
	info[branch]=$vcs_info_msg_0_

	print -r - ${(@kvq)info}
}

# fastest possible way to check if repo is dirty
prompt_pure_async_git_dirty() {
	setopt localoptions noshwordsplit
	local untracked_dirty=$1 dir=$2

	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $dir

	if [[ $untracked_dirty = 0 ]]; then
		command git diff --no-ext-diff --quiet --exit-code
	else
		test -z "$(command git status --porcelain --ignore-submodules -unormal)"
	fi

	return $?
}

prompt_pure_async_git_fetch() {
	setopt localoptions noshwordsplit
	# use cd -q to avoid side effects of changing directory, e.g. chpwd hooks
	builtin cd -q $1

	# set GIT_TERMINAL_PROMPT=0 to disable auth prompting for git fetch (git 2.3+)
	export GIT_TERMINAL_PROMPT=0
	# set ssh BachMode to disable all interactive ssh password prompting
	export GIT_SSH_COMMAND=${GIT_SSH_COMMAND:-"ssh -o BatchMode=yes"}

	command git -c gc.auto=0 fetch &>/dev/null || return 1

	# check arrow status after a successful git fetch
	prompt_pure_async_git_arrows $1
}

prompt_pure_async_git_arrows() {
	setopt localoptions noshwordsplit
	builtin cd -q $1
	command git rev-list --left-right --count HEAD...@'{u}'
}

prompt_pure_async_tasks() {
	setopt localoptions noshwordsplit

	# initialize async worker
	((!${prompt_pure_async_init:-0})) && {
		async_start_worker "prompt_pure" -u -n
		async_register_callback "prompt_pure" prompt_pure_async_callback
		prompt_pure_async_init=1
	}

	typeset -gA prompt_pure_vcs_info

	local -H MATCH
	if ! [[ $PWD =~ ^$prompt_pure_vcs_info[pwd] ]]; then
		# stop any running async jobs
		async_flush_jobs "prompt_pure"

		# reset git preprompt variables, switching working tree
		unset prompt_pure_git_dirty
		unset prompt_pure_git_last_dirty_check_timestamp
		unset prompt_pure_git_arrows
		unset prompt_pure_git_fetch_pattern
		prompt_pure_vcs_info[branch]=
		prompt_pure_vcs_info[top]=
	fi
	unset MATCH

	async_job "prompt_pure" prompt_pure_async_vcs_info $PWD

	# # only perform tasks inside git working tree
	[[ -n $prompt_pure_vcs_info[top] ]] || return

	prompt_pure_async_refresh
}

prompt_pure_async_refresh() {
	setopt localoptions noshwordsplit

	if [[ -z $prompt_pure_git_fetch_pattern ]]; then
		# we set the pattern here to avoid redoing the pattern check until the
		# working three has changed. pull and fetch are always valid patterns.
		prompt_pure_git_fetch_pattern="pull|fetch"
		async_job "prompt_pure" prompt_pure_async_git_aliases $working_tree
	fi

	async_job "prompt_pure" prompt_pure_async_git_arrows $PWD

	# do not preform git fetch if it is disabled or working_tree == HOME
	if (( ${PURE_GIT_PULL:-1} )) && [[ $working_tree != $HOME ]]; then
		# tell worker to do a git fetch
		async_job "prompt_pure" prompt_pure_async_git_fetch $PWD
	fi

	# if dirty checking is sufficiently fast, tell worker to check it again, or wait for timeout
	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_pure_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${PURE_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		unset prompt_pure_git_last_dirty_check_timestamp
		# check check if there is anything to pull
		async_job "prompt_pure" prompt_pure_async_git_dirty ${PURE_GIT_UNTRACKED_DIRTY:-1} $PWD
	fi
}

prompt_pure_check_git_arrows() {
	setopt localoptions noshwordsplit
	local arrows left=${1:-0} right=${2:-0}

	(( right > 0 )) && arrows+=${PURE_GIT_DOWN_ARROW:-⇣}
	(( left > 0 )) && arrows+=${PURE_GIT_UP_ARROW:-⇡}

	[[ -n $arrows ]] || return
	typeset -g REPLY=$arrows
}

prompt_pure_async_callback() {
	setopt localoptions noshwordsplit
	local job=$1 code=$2 output=$3 exec_time=$4

	case $job in
		prompt_pure_async_vcs_info)
			local -A info
			typeset -gA prompt_pure_vcs_info

			# parse output (z) and unquote as array (Q@)
			info=("${(Q@)${(z)output}}")
			local -H MATCH
			# check if git toplevel has changed
			if [[ $info[top] = $prompt_pure_vcs_info[top] ]]; then
				# if stored pwd is part of $PWD, $PWD is shorter and likelier
				# to be toplevel, so we update pwd
				if [[ $prompt_pure_vcs_info[pwd] =~ ^$PWD ]]; then
					prompt_pure_vcs_info[pwd]=$PWD
				fi
			else
				# store $PWD to detect if we (maybe) left the git path
				prompt_pure_vcs_info[pwd]=$PWD
			fi
			unset MATCH

			# update has a git toplevel set which means we just entered a new
			# git directory, run the async refresh tasks
			[[ -n $info[top] ]] && [[ -z $prompt_pure_vcs_info[top] ]] && prompt_pure_async_refresh

			# always update branch and toplevel
			prompt_pure_vcs_info[branch]=$info[branch]
			prompt_pure_vcs_info[top]=$info[top]

			prompt_pure_preprompt_render
			;;
		prompt_pure_async_git_aliases)
			if [[ -n $output ]]; then
				# append custom git aliases to the predefined ones.
				prompt_pure_git_fetch_pattern+="|$output"
			fi
			;;
		prompt_pure_async_git_dirty)
			local prev_dirty=$prompt_pure_git_dirty
			if (( code == 0 )); then
				prompt_pure_git_dirty=
			else
				prompt_pure_git_dirty="*"
			fi

			[[ $prev_dirty != $prompt_pure_git_dirty ]] && prompt_pure_preprompt_render

			# When prompt_pure_git_last_dirty_check_timestamp is set, the git info is displayed in a different color.
			# To distinguish between a "fresh" and a "cached" result, the preprompt is rendered before setting this
			# variable. Thus, only upon next rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 2 )) && prompt_pure_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		prompt_pure_async_git_fetch|prompt_pure_async_git_arrows)
			# prompt_pure_async_git_fetch executes prompt_pure_async_git_arrows
			# after a successful fetch.
			if (( code == 0 )); then
				local REPLY
				prompt_pure_check_git_arrows ${(ps:\t:)output}
				if [[ $prompt_pure_git_arrows != $REPLY ]]; then
					prompt_pure_git_arrows=$REPLY
					prompt_pure_preprompt_render
				fi
			else
				# non-zero exit means there is no upstream configured.
				if [[ -n $prompt_pure_git_arrows ]]; then
					unset prompt_pure_git_arrows
					prompt_pure_preprompt_render
				fi
			fi
			;;
	esac
}

prompt_pure_setup() {
	# prevent percentage showing up
	# if output doesn't end with a newline
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	# borrowed from promptinit, sets the prompt options in case pure was not
	# initialized via promptinit.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

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
	PROMPT='%(?.%F{magenta}.%F{red})${PURE_PROMPT_SYMBOL:-❯}%f '
}

prompt_pure_setup "$@"
