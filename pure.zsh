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


# Turns seconds into human readable time.
# 165392 => 1d 21h 56m 32s
# https://github.com/sindresorhus/pretty-time-zsh
prompt_pure_human_time_to_var() {
	local human total_seconds=$1 var=$2
	local days=$(( total_seconds / 60 / 60 / 24 ))
	local hours=$(( total_seconds / 60 / 60 % 24 ))
	local minutes=$(( total_seconds / 60 % 60 ))
	local seconds=$(( total_seconds % 60 ))
	(( days > 0 )) && human+="${days}d "
	(( hours > 0 )) && human+="${hours}h "
	(( minutes > 0 )) && human+="${minutes}m "
	human+="${seconds}s"

	# Store human readable time in a variable as specified by the caller
	typeset -g "${var}"="${human}"
}

# Stores (into prompt_pure_cmd_exec_time) the execution
# time of the last command if set threshold was exceeded.
prompt_pure_check_cmd_exec_time() {
	integer elapsed
	(( elapsed = EPOCHSECONDS - ${prompt_pure_cmd_timestamp:-$EPOCHSECONDS} ))
	typeset -g prompt_pure_cmd_exec_time=
	(( elapsed > ${PURE_CMD_MAX_EXEC_TIME:-5} )) && {
		prompt_pure_human_time_to_var $elapsed "prompt_pure_cmd_exec_time"
	}
}

prompt_pure_set_title() {
	setopt localoptions noshwordsplit

	# Allow disabling title management.
	zstyle -T ":prompt:pure:title" show || return

	# Emacs terminal does not support settings the title.
	(( ${+EMACS} || ${+INSIDE_EMACS} )) && return

	case $TTY in
		# Don't set title over serial console.
		/dev/ttyS[0-9]*) return;;
	esac

	# Show hostname if connected via SSH and host display is enabled.
	local hostname=
	if (( psvar[13] )) && (( ${prompt_pure_state[show_host]:-1} )); then
		# Expand in-place in case ignore-escape is used.
		hostname="${(%):-(%m) }"
	fi

	local -a opts
	case $1 in
		expand-prompt) opts=(-P);;
		ignore-escape) opts=(-r);;
	esac

	# Set title atomically in one print statement so that it works when XTRACE is enabled.
	print -n $opts $'\e]0;'${hostname}${2}$'\a'
}

prompt_pure_preexec() {
	if [[ -n $prompt_pure_git_fetch_pattern ]]; then
		# Detect when Git is performing pull/fetch, including Git aliases.
		local -H MATCH MBEGIN MEND match mbegin mend
		if [[ $2 =~ (git|hub)\ (.*\ )?($prompt_pure_git_fetch_pattern)(\ .*)?$ ]]; then
			# We must flush the async jobs to cancel our git fetch in order
			# to avoid conflicts with the user issued pull / fetch.
			async_flush_jobs 'prompt_pure'
		fi
	fi

	typeset -g prompt_pure_cmd_timestamp=$EPOCHSECONDS

	# Shows the current directory and executed command in the title while a process is active.
	prompt_pure_set_title 'ignore-escape' "$PWD:t: $2"

	# Disallow Python virtualenv from updating the prompt. Set it to 20 if
	# untouched by the user to indicate that Pure modified it. Here we use
	# the magic number 20, same as in `psvar`.
	export VIRTUAL_ENV_DISABLE_PROMPT=${VIRTUAL_ENV_DISABLE_PROMPT:-20}
}

# Change the colors if their value are different from the current ones.
prompt_pure_set_colors() {
	local color_temp key value
	for key value in ${(kv)prompt_pure_colors}; do
		zstyle -t ":prompt:pure:$key" color "$value" && continue
		case $? in
			1) # The current style is different from the one from zstyle.
				zstyle -s ":prompt:pure:$key" color color_temp
				prompt_pure_colors[${key}]=$color_temp ;;
			2) # No style is defined.
				prompt_pure_colors[${key}]=${prompt_pure_colors_default[${key}]} ;;
		esac
	done

	prompt_pure_set_path_separator

	return 0
}

prompt_pure_set_path_separator() {
	typeset -g prompt_pure_path_segment="%F{${prompt_pure_colors[path]}}%~%f"

	if zstyle -t ':prompt:pure:path:separator' dim; then
		typeset -g prompt_pure_path_separator_dimmed=1
	else
		typeset -g prompt_pure_path_separator_dimmed=
	fi
}

prompt_pure_render_dimmed_path() {
	setopt localoptions noshwordsplit

	# This runs from PROMPT_SUBST so directory changes followed by reset-prompt redraw correctly without precmd.
	local current_path=${1:-${(%):-%~}}
	current_path=${current_path//\%/%%}

	local separator=$'%{\e[2m%}/%{\e[22m%}'
	# Keep the leading / on absolute paths at full brightness.
	local prefix=
	if [[ $current_path == /* ]]; then
		prefix=/
		current_path=${current_path:1}
	fi
	print -n -r -- "%F{${prompt_pure_colors[path]}}${prefix}${current_path//\//$separator}%f"
}

prompt_pure_preprompt_render() {
	setopt localoptions noshwordsplit

	unset prompt_pure_async_render_requested

	# Update git branch color based on cache state.
	typeset -g prompt_pure_git_branch_color=$prompt_pure_colors[git:branch]
	[[ -n ${prompt_pure_git_last_dirty_check_timestamp+x} ]] && prompt_pure_git_branch_color=$prompt_pure_colors[git:branch:cached]

	# Update psvar values. PROMPT uses %(NV.true.false) to conditionally
	# render each part. See prompt_pure_setup for the PROMPT template.
	#
	# psvar[12]: Suspended jobs symbol.
	psvar[12]=
	((${(M)#jobstates:#suspended:*} != 0)) && psvar[12]=${PURE_SUSPENDED_JOBS_SYMBOL-✦}

	# psvar[13]: Username flag (set once in prompt_pure_state_setup).

	# psvar[14]: Git branch name.
	psvar[14]=${prompt_pure_vcs_info[branch]}

	# psvar[15]: Git dirty marker.
	psvar[15]=${prompt_pure_git_dirty}

	# psvar[16]: Git action (rebase/merge).
	psvar[16]=${prompt_pure_vcs_info[action]}

	# psvar[17]: Git arrows (push/pull).
	psvar[17]=${prompt_pure_git_arrows}

	# psvar[18]: Git stash symbol.
	psvar[18]=
	[[ -n $prompt_pure_git_stash ]] && psvar[18]=${PURE_GIT_STASH_SYMBOL-≡}

	# psvar[19]: Command execution time.
	psvar[19]=${prompt_pure_cmd_exec_time}

	# psvar[21]: Node.js version.
	psvar[21]=
	if [[ -n $prompt_pure_node_version ]]; then
		local node_symbol
		zstyle -s ":prompt:pure:environment:node_version" symbol node_symbol || node_symbol='⬢'
		psvar[21]="${node_symbol}${prompt_pure_node_version}"
	fi

	# psvar[22]: Custom prefix, psvar[23]: Custom suffix.
	# Set by the user-defined prompt_pure_precustom function.
	psvar[22]=
	psvar[23]=
	if (( $+functions[prompt_pure_precustom] )); then
		prompt_pure_precustom
	fi

	# Build a fingerprint from all dynamic prompt components to detect changes
	# without expanding PROMPT (which forks a subshell when dimmed path is on).
	local -a prompt_fingerprint_parts=(
		"${psvar[12]}"
		"${psvar[13]}"
		"${psvar[14]}"
		"${psvar[15]}"
		"${psvar[16]}"
		"${psvar[17]}"
		"${psvar[18]}"
		"${psvar[19]}"
		"${psvar[20]}"
		"${psvar[21]}"
		"${psvar[22]}"
		"${psvar[23]}"
		"${prompt_pure_state[prompt]}"
		"${prompt_pure_git_branch_color}"
		"${PWD}"
	)
	local prompt_fingerprint="${(pj:|:)${(@qqq)prompt_fingerprint_parts}}"

	if [[ $1 == precmd ]]; then
		# Initial newline, for spaciousness.
		print
	elif [[ $prompt_pure_last_prompt != $prompt_fingerprint ]]; then
		# Redraw the prompt.
		prompt_pure_reset_prompt
	fi

	typeset -g prompt_pure_last_prompt=$prompt_fingerprint
}

prompt_pure_precmd() {
	setopt localoptions noshwordsplit

	# Check execution time and store it in a variable.
	prompt_pure_check_cmd_exec_time
	unset prompt_pure_cmd_timestamp

	# Shows the full path in the title.
	prompt_pure_set_title 'expand-prompt' '%~'

	# Modify the colors if some have changed..
	prompt_pure_set_colors

	# Perform async Git dirty check and fetch.
	prompt_pure_async_tasks

	# Check if we should display the virtual env (psvar[20]).
	psvar[20]=
	if zstyle -T ":prompt:pure:environment:virtualenv" show; then
		# Check if a Conda environment is active and display its name.
		# The 'base' environment is always active and not informative.
		if [[ -n $CONDA_DEFAULT_ENV ]] && [[ ${CONDA_DEFAULT_ENV:t} != base ]]; then
			psvar[20]="${${CONDA_DEFAULT_ENV:t}//[$'\t\r\n']}"
		fi
		# When VIRTUAL_ENV_DISABLE_PROMPT is empty, it was unset by the user and
		# Pure should take back control.
		if [[ -n $VIRTUAL_ENV ]] && [[ -z $VIRTUAL_ENV_DISABLE_PROMPT || $VIRTUAL_ENV_DISABLE_PROMPT = 20 ]]; then
			if [[ -n $VIRTUAL_ENV_PROMPT ]]; then
				psvar[20]="${VIRTUAL_ENV_PROMPT}"
			else
				psvar[20]="${VIRTUAL_ENV:t}"
			fi
			export VIRTUAL_ENV_DISABLE_PROMPT=20
		fi
	fi

	# Nix package manager integration. If used from within 'nix shell' - shell name is shown like so:
	# ~/Projects/flake-utils-plus master
	# flake-utils-plus ❯
	if zstyle -T ":prompt:pure:environment:nix-shell" show; then
		if [[ -n $IN_NIX_SHELL ]]; then
			psvar[20]="${name:-nix-shell}"
		fi
	fi

	# Make sure VIM prompt is reset.
	prompt_pure_reset_prompt_symbol

	# Print the preprompt.
	prompt_pure_preprompt_render "precmd"

	if [[ -n $ZSH_THEME ]]; then
		print "WARNING: Oh My Zsh themes are enabled (ZSH_THEME='${ZSH_THEME}'). Pure might not be working correctly."
		print "For more information, see: https://github.com/sindresorhus/pure#oh-my-zsh"
		unset ZSH_THEME  # Only show this warning once.
	fi
}

prompt_pure_async_print_generation() {
	if [[ -n ${PROMPT_PURE_WORKER_GENERATION-} ]]; then
		print -r -- "$PROMPT_PURE_WORKER_GENERATION"
	fi
}

prompt_pure_async_git_aliases() {
	setopt localoptions noshwordsplit
	prompt_pure_async_print_generation
	local -a gitalias pullalias

	# List all aliases and split on newline.
	gitalias=(${(@f)"$(command git config --get-regexp "^alias\.")"})
	for line in $gitalias; do
		parts=(${(@)=line})           # Split line on spaces.
		aliasname=${parts[1]#alias.}  # Grab the name (alias.[name]).
		shift parts                   # Remove `aliasname`

		# Check alias for pull or fetch. Must be exact match.
		if [[ $parts =~ ^(.*\ )?(pull|fetch)(\ .*)?$ ]]; then
			pullalias+=($aliasname)
		fi
	done

	print -- ${(j:|:)pullalias}  # Join on pipe, for use in regex.
}

prompt_pure_async_vcs_info() {
	setopt localoptions noshwordsplit
	prompt_pure_async_print_generation

	# Configure `vcs_info` inside an async task. This frees up `vcs_info`
	# to be used or configured as the user pleases.
	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:*' use-simple true
	# Only export four message variables from `vcs_info`.
	zstyle ':vcs_info:*' max-exports 3
	# Export branch (%b), Git toplevel (%R), action (rebase/cherry-pick) (%a)
	zstyle ':vcs_info:git*' formats '%b' '%R' '%a'
	zstyle ':vcs_info:git*' actionformats '%b' '%R' '%a'

	vcs_info

	local -A info
	info[pwd]=$PWD
	info[branch]=${vcs_info_msg_0_//\%/%%}
	info[top]=$vcs_info_msg_1_
	info[action]=$vcs_info_msg_2_

	print -r - ${(@kvq)info}
}

# Fastest possible way to check if a Git repo is dirty.
# When detailed mode is enabled, outputs markers: * (unstaged), + (staged), ? (untracked).
prompt_pure_async_git_dirty() {
	setopt localoptions noshwordsplit
	prompt_pure_async_print_generation
	local untracked_dirty=$1
	local detailed=${2:-0}
	local untracked_git_mode=$(command git config --get status.showUntrackedFiles)
	if [[ "$untracked_git_mode" != 'no' ]]; then
		untracked_git_mode='normal'
	fi

	# Prevent e.g. `git status` from refreshing the index as a side effect.
	export GIT_OPTIONAL_LOCKS=0

	if (( ! detailed )); then
		if [[ $untracked_dirty = 0 ]]; then
			command git diff --no-ext-diff --quiet --exit-code || return $?
			command git diff --no-ext-diff --cached --quiet --exit-code
		else
			test -z "$(command git status --porcelain -u${untracked_git_mode})"
		fi

		return
	fi

	local u_flag
	if [[ $untracked_dirty = 0 ]]; then
		u_flag='-uno'
	else
		u_flag="-u${untracked_git_mode}"
	fi

	local output
	output=$(command git status --porcelain $u_flag)
	[[ -z $output ]] && return 0

	local has_unstaged=0 has_staged=0 has_untracked=0 line
	for line in "${(f)output}"; do
		(( ! has_unstaged )) && [[ ${line[2]} == [MTDUA] ]] && has_unstaged=1
		(( ! has_staged )) && [[ ${line[1]} == [MTADRCU] ]] && has_staged=1
		(( ! has_untracked )) && [[ $line == '??'* ]] && has_untracked=1
		(( has_unstaged + has_staged + has_untracked == 3 )) && break
	done

	local markers=""
	(( has_unstaged )) && markers+="*"
	(( has_staged )) && markers+="+"
	(( has_untracked )) && markers+="?"

	print -r - "$markers"
	return 1
}

prompt_pure_async_git_fetch() {
	setopt localoptions noshwordsplit
	prompt_pure_async_print_generation

	local only_upstream=${1:-0}

	# Sets `GIT_TERMINAL_PROMPT=0` to disable authentication prompt for Git fetch (Git 2.3+).
	export GIT_TERMINAL_PROMPT=0
	# Set SSH `BachMode` to disable all interactive SSH password prompting.
	export GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-"ssh"} -o BatchMode=yes"

	# If gpg-agent is set to handle SSH keys for `git fetch`, make
	# sure it doesn't corrupt the parent TTY.
	# Setting an empty GPG_TTY forces pinentry-curses to close immediately rather
	# than stall indefinitely waiting for user input.
	export GPG_TTY=

	local -a remote
	if ((only_upstream)); then
		local ref
		ref=$(command git symbolic-ref -q HEAD)
		# Set remote to only fetch information for the current branch.
		remote=($(command git for-each-ref --format='%(upstream:remotename) %(refname)' $ref))
		if [[ -z $remote[1] ]]; then
			# No remote specified for this branch, skip fetch.
			return 97
		fi
	fi

	# Default return code, which indicates Git fetch failure.
	local fail_code=99

	# Guard against all forms of password prompts. By setting the shell into
	# MONITOR mode we can notice when a child process prompts for user input
	# because it will be suspended. Since we are inside an async worker, we
	# have no way of transmitting the password and the only option is to
	# kill it. If we don't do it this way, the process will corrupt with the
	# async worker.
	setopt localtraps monitor

	# Make sure local HUP trap is unset to allow for signal propagation when
	# the async worker is flushed.
	trap - HUP

	trap '
		# Unset trap to prevent infinite loop
		trap - CHLD
		if [[ $jobstates = suspended* ]]; then
			# Set fail code to password prompt and kill the fetch.
			fail_code=98
			kill %%
		fi
	' CHLD

	# Do git fetch and avoid fetching tags or
	# submodules to speed up the process.
	command git -c gc.auto=0 -c fetch.prune=false fetch \
		--quiet \
		--no-tags \
		--no-prune-tags \
		--recurse-submodules=no \
		$remote &>/dev/null &
	wait $! || return $fail_code

	unsetopt monitor

	# Check arrow status after a successful `git fetch`.
	# Pass 0 to skip generation printing (this function already printed it).
	prompt_pure_async_git_arrows 0
}

prompt_pure_async_git_arrows() {
	setopt localoptions noshwordsplit
	if (( ${1:-1} )); then
		prompt_pure_async_print_generation
	fi
	command git rev-list --left-right --count HEAD...@'{u}'
}

prompt_pure_async_git_stash() {
	prompt_pure_async_print_generation
	command git rev-list --walk-reflogs --count refs/stash
}

prompt_pure_check_node_version() {
	setopt localoptions noshwordsplit

	# Walk up to find package.json (similar to how git detects repos).
	local dir=$PWD
	while [[ $dir != "/" ]]; do
		[[ -f "$dir/package.json" ]] && break
		dir=${dir:h}
	done

	local version=
	if [[ -f "$dir/package.json" ]]; then
		version=$(command node --version 2>/dev/null) || version=
		version=${${${version#v}%%.*}//[$'\t\r\n']}
	fi

	print -r -- "$version"
}

# Try to lower the priority of the worker so that disk heavy operations
# like `git status` has less impact on the system responsivity.
prompt_pure_async_renice() {
	setopt localoptions noshwordsplit

	if command -v renice >/dev/null; then
		command renice +15 -p $$
	fi

	if command -v ionice >/dev/null; then
		command ionice -c 3 -p $$
	fi
}

prompt_pure_clear_git_state() {
	unset prompt_pure_git_dirty prompt_pure_git_last_dirty_check_timestamp prompt_pure_git_arrows prompt_pure_git_stash prompt_pure_git_fetch_pattern
	typeset -gA prompt_pure_worker_env=()
	typeset -gA prompt_pure_vcs_info
	prompt_pure_vcs_info[branch]=
	prompt_pure_vcs_info[top]=
	prompt_pure_vcs_info[action]=
	prompt_pure_vcs_info[pwd]=
}

prompt_pure_async_init() {
	typeset -g prompt_pure_async_inited
	if ((${prompt_pure_async_inited:-0})); then
		return
	fi
	if ! async_start_worker "prompt_pure" -u -n 2>/dev/null; then
		# Worker failed to start (e.g. zpty permission denied).
		# Degrade gracefully by skipping async git operations.
		return 1
	fi
	prompt_pure_async_inited=1
	async_register_callback "prompt_pure" prompt_pure_async_callback
	async_worker_eval "prompt_pure" prompt_pure_async_renice
}

prompt_pure_async_tasks() {
	setopt localoptions noshwordsplit

	# Check if Node.js version display is enabled (independent of Git).
	if zstyle -t ":prompt:pure:environment:node_version" show; then
		# Cache key uses "|" separator so the value is never a valid directory
		# path, preventing zsh from treating it as a named directory for %~.
		local node_cache_key="$PWD|$PATH"
		if [[ ${prompt_pure_node_cache_key-} != "$node_cache_key" ]]; then
			typeset -g prompt_pure_node_version=$(prompt_pure_check_node_version)
			typeset -g prompt_pure_node_cache_key=$node_cache_key
		fi
	else
		unset prompt_pure_node_version
		unset prompt_pure_node_cache_key
	fi

	# Check if git integration is enabled (default: yes).
	if ! zstyle -T ":prompt:pure:git" show; then
		# Flush any in-flight async git jobs.
		if (( ${prompt_pure_async_inited:-0} )); then
			async_flush_jobs "prompt_pure"
		fi

		prompt_pure_clear_git_state
		return
	fi

	# Initialize the async worker. If it fails (e.g. zpty unavailable),
	# skip all async tasks and show prompt without git info.
	if ! prompt_pure_async_init; then
		prompt_pure_clear_git_state
		return
	fi

	# Sync working directory and git environment variables to the async worker.
	# Skip if nothing changed since last sync (common case: running commands in same dir).
	# Uses an associative array to avoid scalar globals triggering AUTO_NAME_DIRS.
	# The evals are queued fire-and-forget, so the git jobs below run after them
	# in worker FIFO order, keeping the git info a single async cycle behind a `cd`.
	typeset -gA prompt_pure_worker_env
	local cur_git_dir=${GIT_DIR-__unset__}
	local cur_git_work_tree=${GIT_WORK_TREE-__unset__}
	local working_directory_changed=0
	if [[ $PWD != ${prompt_pure_worker_env[pwd]-} ]]; then
		working_directory_changed=1
	fi
	local git_environment_changed=0
	if [[ $cur_git_dir != ${prompt_pure_worker_env[git_dir]-} ||
		$cur_git_work_tree != ${prompt_pure_worker_env[git_work_tree]-} ]]; then
		git_environment_changed=1
	fi

	typeset -gA prompt_pure_vcs_info

	local working_tree_changed=0
	if [[ ${prompt_pure_vcs_info[pwd]} != / &&
		$PWD != ${prompt_pure_vcs_info[pwd]} &&
		$PWD != ${prompt_pure_vcs_info[pwd]}/* ]]; then
		working_tree_changed=1
	fi

	if [[ $git_environment_changed == 1 ||
		$working_directory_changed == 1 ||
		$working_tree_changed == 1 ]]; then
		# Reset preprompt variables before syncing the new working tree.
		unset prompt_pure_git_dirty prompt_pure_git_last_dirty_check_timestamp prompt_pure_git_arrows prompt_pure_git_stash prompt_pure_git_fetch_pattern
		prompt_pure_vcs_info[branch]=
		prompt_pure_vcs_info[top]=
		prompt_pure_vcs_info[action]=
	fi

	if [[ $working_directory_changed == 1 ||
		$git_environment_changed == 1 ]]; then
		# Cancel any in-flight git jobs from the previous working tree.
		async_flush_jobs "prompt_pure"
		typeset -gi prompt_pure_worker_generation
		(( prompt_pure_worker_generation++ ))
		local sync_generation=$prompt_pure_worker_generation

		prompt_pure_worker_env[pwd]=$PWD
		prompt_pure_worker_env[git_dir]=$cur_git_dir
		prompt_pure_worker_env[git_work_tree]=$cur_git_work_tree
		prompt_pure_worker_env[generation]=$sync_generation
		prompt_pure_worker_env[sync_pending]=$sync_generation

		local git_dir_command='unset GIT_DIR'
		if (( ${+GIT_DIR} )); then
			git_dir_command="export GIT_DIR=${(q)GIT_DIR}"
		fi

		local git_work_tree_command='unset GIT_WORK_TREE'
		if (( ${+GIT_WORK_TREE} )); then
			git_work_tree_command="export GIT_WORK_TREE=${(q)GIT_WORK_TREE}"
		fi

		local sync_command="print -r -- ${(q)sync_generation}; builtin cd -q ${(q)PWD} && $git_dir_command && $git_work_tree_command && typeset -g PROMPT_PURE_WORKER_GENERATION=${(q)sync_generation}"
		if ! async_worker_eval "prompt_pure" "$sync_command"; then
			if [[ ${prompt_pure_worker_env[sync_pending]-} == $sync_generation ]]; then
				typeset -gA prompt_pure_worker_env=()
			fi
			return
		fi
	fi

	async_job "prompt_pure" prompt_pure_async_vcs_info || return

	# Only perform tasks inside a Git working tree.
	[[ -n $prompt_pure_vcs_info[top] ]] || return

	prompt_pure_async_refresh
}

prompt_pure_async_refresh() {
	setopt localoptions noshwordsplit

	if [[ -z $prompt_pure_git_fetch_pattern ]]; then
		# We set the pattern here to avoid redoing the pattern check until the
		# working tree has changed. Pull and fetch are always valid patterns.
		typeset -g prompt_pure_git_fetch_pattern="pull|fetch"
		async_job "prompt_pure" prompt_pure_async_git_aliases || return
	fi

	async_job "prompt_pure" prompt_pure_async_git_arrows || return

	# Do not perform `git fetch` if it is disabled or in home folder.
	if (( ${PURE_GIT_PULL:-1} )) && [[ $prompt_pure_vcs_info[top] != $HOME ]]; then
		zstyle -t :prompt:pure:git:fetch only_upstream
		local only_upstream=$((? == 0))
		async_job "prompt_pure" prompt_pure_async_git_fetch $only_upstream || return
	fi

	# If dirty checking is sufficiently fast,
	# tell the worker to check it again, or wait for timeout.
	integer time_since_last_dirty_check=$(( EPOCHSECONDS - ${prompt_pure_git_last_dirty_check_timestamp:-0} ))
	if (( time_since_last_dirty_check > ${PURE_GIT_DELAY_DIRTY_CHECK:-1800} )); then
		unset prompt_pure_git_last_dirty_check_timestamp
		# Check if the working tree is dirty.
		zstyle -t ":prompt:pure:git:dirty" detailed
		local detailed_dirty=$((? == 0))
		async_job "prompt_pure" prompt_pure_async_git_dirty ${PURE_GIT_UNTRACKED_DIRTY:-1} $detailed_dirty || return
	fi

	# If stash is enabled, tell async worker to count stashes
	if zstyle -t ":prompt:pure:git:stash" show; then
		async_job "prompt_pure" prompt_pure_async_git_stash || return
	else
		unset prompt_pure_git_stash
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
	local job=$1 code=$2 output=$3 exec_time=$4 next_pending=$6
	local do_render=0

	if [[ $job != '[async]' ]] &&
		(( ! ${prompt_pure_async_inited:-0} )); then
		return
	fi

	case $job in
		prompt_pure_async_vcs_info|prompt_pure_async_git_aliases|prompt_pure_async_git_dirty|prompt_pure_async_git_fetch|prompt_pure_async_git_arrows|prompt_pure_async_git_stash)
			local result_generation=${output%%$'\n'*}
			if [[ $output == *$'\n'* ]]; then
				output=${output#*$'\n'}
			else
				output=
			fi
			[[ $result_generation == ${prompt_pure_worker_env[generation]-} ]] || return
			[[ -z ${prompt_pure_worker_env[sync_pending]-} ]] || return
			[[ ${prompt_pure_worker_env[pwd]-} == $PWD ]] || return
			;;
	esac

	case $job in
		\[async])
			# Handle all the errors that could indicate a crashed
			# async worker. See zsh-async documentation for the
			# definition of the exit codes.
			if (( code == 2 )) || (( code == 3 )) || (( code == 130 )); then
				# Our worker died unexpectedly, try to recover immediately.
				# TODO(mafredri): Do we need to handle next_pending
				#                 and defer the restart?
				typeset -g prompt_pure_async_inited=0
				async_stop_worker prompt_pure
				typeset -gA prompt_pure_worker_env=()
				if prompt_pure_async_init; then
					prompt_pure_async_tasks  # Restart all tasks.
				else
					prompt_pure_clear_git_state
					do_render=1
					next_pending=0
				fi

				# Reset render state due to restart.
				unset prompt_pure_async_render_requested
			fi
			;;
		\[async/eval])
			local eval_generation=${output%%$'\n'*}
			local pending_generation=${prompt_pure_worker_env[sync_pending]-}
			if [[ -n $pending_generation ]]; then
				if (( code )) &&
					[[ -z $eval_generation || $eval_generation == $pending_generation ]]; then
					typeset -gA prompt_pure_worker_env=()
				elif [[ $eval_generation == $pending_generation ]]; then
					unset "prompt_pure_worker_env[sync_pending]"
				fi
			fi
			;;
		prompt_pure_async_vcs_info)
			local -A info
			typeset -gA prompt_pure_vcs_info

			# Parse output (z) and unquote as array (Q@).
			info=("${(Q@)${(z)output}}")
			local -H MATCH MBEGIN MEND
			if [[ $info[pwd] != $PWD ]]; then
				# The path has changed since the check started, abort.
				return
			fi
			# Check if Git top-level has changed.
			if [[ $info[top] = $prompt_pure_vcs_info[top] ]]; then
				# If the stored pwd is part of $PWD, $PWD is shorter and likelier
				# to be top-level, so we update pwd.
				if [[ $prompt_pure_vcs_info[pwd] = ${PWD}* ]]; then
					prompt_pure_vcs_info[pwd]=$PWD
				fi
			else
				# Store $PWD to detect if we (maybe) left the Git path.
				prompt_pure_vcs_info[pwd]=$PWD
			fi
			unset MATCH MBEGIN MEND

			# The update has a Git top-level set, which means we just entered a new
			# Git directory. Run the async refresh tasks.
			[[ -n $info[top] ]] && [[ -z $prompt_pure_vcs_info[top] ]] && prompt_pure_async_refresh

			# Always update branch, top-level and stash.
			prompt_pure_vcs_info[branch]=$info[branch]
			prompt_pure_vcs_info[top]=$info[top]
			prompt_pure_vcs_info[action]=$info[action]

			do_render=1
			;;
		prompt_pure_async_git_aliases)
			if [[ -n $output ]]; then
				# Append custom Git aliases to the predefined ones.
				prompt_pure_git_fetch_pattern+="|$output"
			fi
			;;
		prompt_pure_async_git_dirty)
			local prev_dirty=$prompt_pure_git_dirty
			if (( code == 0 )); then
				unset prompt_pure_git_dirty
			else
				typeset -g prompt_pure_git_dirty="${output:-*}"
			fi

			[[ $prev_dirty != $prompt_pure_git_dirty ]] && do_render=1

			# When `prompt_pure_git_last_dirty_check_timestamp` is set, the Git info is displayed
			# in a different color. To distinguish between a "fresh" and a "cached" result, the
			# preprompt is rendered before setting this variable. Thus, only upon the next
			# rendering of the preprompt will the result appear in a different color.
			(( $exec_time > 5 )) && prompt_pure_git_last_dirty_check_timestamp=$EPOCHSECONDS
			;;
		prompt_pure_async_git_fetch|prompt_pure_async_git_arrows)
			# `prompt_pure_async_git_fetch` executes `prompt_pure_async_git_arrows`
			# after a successful fetch.
			case $code in
				0)
					local REPLY
					prompt_pure_check_git_arrows ${(ps:\t:)output}
					if [[ $prompt_pure_git_arrows != $REPLY ]]; then
						typeset -g prompt_pure_git_arrows=$REPLY
						do_render=1
					fi
					;;
				97)
					# No remote available, make sure to clear git arrows if set.
					if [[ -n $prompt_pure_git_arrows ]]; then
						typeset -g prompt_pure_git_arrows=
						do_render=1
					fi
					;;
				99|98)
					# Git fetch failed.
					;;
				*)
					# Non-zero exit status from `prompt_pure_async_git_arrows`,
					# indicating that there is no upstream configured.
					if [[ -n $prompt_pure_git_arrows ]]; then
						unset prompt_pure_git_arrows
						do_render=1
					fi
					;;
			esac
			;;
		prompt_pure_async_git_stash)
			local prev_stash=$prompt_pure_git_stash
			typeset -g prompt_pure_git_stash=$output
			[[ $prev_stash != $prompt_pure_git_stash ]] && do_render=1
			;;
	esac

	if (( next_pending )); then
		(( do_render )) && typeset -g prompt_pure_async_render_requested=1
		return
	fi

	[[ ${prompt_pure_async_render_requested:-$do_render} = 1 ]] && prompt_pure_preprompt_render
	unset prompt_pure_async_render_requested
}

prompt_pure_reset_prompt() {
	if [[ $CONTEXT == cont ]]; then
		# When the context is "cont", PS2 is active and calling
		# reset-prompt will have no effect on PS1, but it will
		# reset the execution context (%_) of PS2 which we don't
		# want. Unfortunately, we can't save the output of "%_"
		# either because it is only ever rendered as part of the
		# prompt, expanding in-place won't work.
		return
	fi

	zle && zle .reset-prompt
}

prompt_pure_reset_prompt_symbol() {
	prompt_pure_state[prompt]=${PURE_PROMPT_SYMBOL:-❯}
}

prompt_pure_update_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_pure_state[prompt]=${${${KEYMAP/vicmd/${PURE_PROMPT_VICMD_SYMBOL:-❮}}/visual/${PURE_PROMPT_VICMD_SYMBOL:-❮}}/(main|viins)/${PURE_PROMPT_SYMBOL:-❯}}

	prompt_pure_reset_prompt
}

prompt_pure_reset_vim_prompt_widget() {
	setopt localoptions noshwordsplit
	prompt_pure_reset_prompt_symbol

	# We can't perform a prompt reset at this point because it
	# removes the prompt marks inserted by macOS Terminal.
}

prompt_pure_state_setup() {
	setopt localoptions noshwordsplit

	# Check SSH_CONNECTION and the current state.
	local ssh_connection=${SSH_CONNECTION:-$PROMPT_PURE_SSH_CONNECTION}
	local username hostname
	if [[ -z $ssh_connection ]] && (( $+commands[who] )); then
		# When changing user on a remote system, the $SSH_CONNECTION
		# environment variable can be lost. Attempt detection via `who`.
		local who_out
		who_out=$(who -m 2>/dev/null)
		if (( $? )); then
			# Who am I not supported, fallback to plain who.
			local -a who_in
			who_in=( ${(f)"$(who 2>/dev/null)"} )
			who_out="${(M)who_in:#*[[:space:]]${TTY#/dev/}[[:space:]]*}"
		fi

		local reIPv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'  # Simplified, only checks partial pattern.
		local reIPv4='([0-9]{1,3}\.){3}[0-9]+'   # Simplified, allows invalid ranges.
		# Here we assume two non-consecutive periods represents a
		# hostname. This matches `foo.bar.baz`, but not `foo.bar`.
		local reHostname='([.][^. ]+){2}'

		# Usually the remote address is surrounded by parenthesis, but
		# not on all systems (e.g. busybox).
		local -H MATCH MBEGIN MEND
		if [[ $who_out =~ "\(?($reIPv4|$reIPv6|$reHostname)\)?\$" ]]; then
			ssh_connection=$MATCH

			# Export variable to allow detection propagation inside
			# shells spawned by this one (e.g. tmux does not always
			# inherit the same tty, which breaks detection).
			export PROMPT_PURE_SSH_CONNECTION=$ssh_connection
		fi
		unset MATCH MBEGIN MEND
	fi

	local user_color
	# Show `username@host` if logged in through SSH.
	[[ -n $ssh_connection ]] && user_color=user

	# Show `username@host` if inside a container and not in GitHub Codespaces.
	[[ -z "${CODESPACES}" ]] && prompt_pure_is_inside_container && user_color=user

	# Show `username@host` if root, with username in default color.
	[[ $UID -eq 0 ]] && user_color=user:root

	# Set psvar[13] flag for username display in PROMPT.
	[[ -n $user_color ]] && psvar[13]=1

	# Check if hostname display is enabled (default: yes).
	local show_host=1
	zstyle -T ":prompt:pure:host" show || show_host=0

	typeset -gA prompt_pure_state
	prompt_pure_state[version]="1.28.2"
	prompt_pure_state+=(
		user_color "$user_color"
		show_host  "$show_host"
		prompt	   "${PURE_PROMPT_SYMBOL:-❯}"
	)
}

# Return true if executing inside a Docker, OCI, LXC, or systemd-nspawn container.
prompt_pure_is_inside_container() {
	local -r nspawn_file='/run/host/container-manager'
	local -r podman_crio_file='/run/.containerenv'
	local -r docker_file='/.dockerenv'
	local -r k8s_token_file='/var/run/secrets/kubernetes.io/serviceaccount/token'
	local -r cgroup_file='/proc/1/cgroup'
	[[ "$container" == "lxc" ]] \
		|| [[ "$container" == "oci" ]] \
		|| [[ "$container" == "podman" ]] \
		|| [[ -r "$nspawn_file" ]] \
		|| [[ -r "$podman_crio_file" ]] \
		|| [[ -r "$docker_file" ]] \
		|| [[ -r "$k8s_token_file" ]] \
		|| [[ -r "$cgroup_file" && "$(< $cgroup_file)" = *(lxc|docker|containerd)* ]]
}

prompt_pure_system_report() {
	setopt localoptions noshwordsplit

	local shell=$SHELL
	if [[ -z $shell ]]; then
		shell=$commands[zsh]
	fi
	print - "- Zsh: $($shell --version) ($shell)"
	print -n - "- Operating system: "
	case "$(uname -s)" in
		Darwin)	print "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))";;
		*)	print "$(uname -s) ($(uname -r) $(uname -v) $(uname -m) $(uname -o))";;
	esac
	print - "- Terminal program: ${TERM_PROGRAM:-unknown} (${TERM_PROGRAM_VERSION:-unknown})"
	print -n - "- Tmux: "
	[[ -n $TMUX ]] && print "yes" || print "no"

	local git_version
	git_version=($(git --version))  # Remove newlines, if hub is present.
	print - "- Git: $git_version"

	print - "- Pure state:"
	for k v in "${(@kv)prompt_pure_state}"; do
		print - "    - $k: \`${(q-)v}\`"
	done
	print - "- zsh-async version: \`${ASYNC_VERSION}\`"
	print - "- PROMPT: \`$(typeset -p PROMPT)\`"
	print - "- Colors: \`$(typeset -p prompt_pure_colors)\`"
	print - "- TERM: \`$(typeset -p TERM)\`"
	print - "- Virtualenv: \`$(typeset -p VIRTUAL_ENV_DISABLE_PROMPT)\`"
	print - "- Conda: \`$(typeset -p CONDA_CHANGEPS1)\`"

	local ohmyzsh=0
	typeset -la frameworks
	(( $+ANTIBODY_HOME )) && frameworks+=("Antibody")
	(( $+ADOTDIR )) && frameworks+=("Antigen")
	(( $+ANTIGEN_HS_HOME )) && frameworks+=("Antigen-hs")
	(( $+functions[upgrade_oh_my_zsh] )) && {
		ohmyzsh=1
		frameworks+=("Oh My Zsh")
	}
	(( $+ZPREZTODIR )) && frameworks+=("Prezto")
	(( $+ZPLUG_ROOT )) && frameworks+=("Zplug")
	(( $+ZPLGM )) && frameworks+=("Zplugin")

	(( $#frameworks == 0 )) && frameworks+=("None")
	print - "- Detected frameworks: ${(j:, :)frameworks}"

	if (( ohmyzsh )); then
		print - "    - Oh My Zsh:"
		print - "        - Plugins: ${(j:, :)plugins}"
	fi
}

prompt_pure_preview() {
	setopt localoptions noshwordsplit

	prompt_pure_set_colors

	local -A c=("${(@kv)prompt_pure_colors}")
	local node_symbol
	zstyle -s ":prompt:pure:environment:node_version" symbol node_symbol || node_symbol='⬢'

	local path_sample="%F{$c[path]}~/dev/pure%f"
	if zstyle -t ':prompt:pure:path:separator' dim; then
		path_sample=$(prompt_pure_render_dimmed_path '~/dev/pure')
	fi

	local host_sample=''
	if zstyle -T ":prompt:pure:host" show; then
		host_sample="%F{$c[host]}@heartofgold%f"
	fi

	# Sample preprompt with all components visible.
	print -P "%F{$c[custom:prefix]}prefix%f %F{$c[suspended_jobs]}${PURE_SUSPENDED_JOBS_SYMBOL-✦}%f %F{$c[user]}zaphod%f${host_sample} ${path_sample} %F{$c[git:branch]}main%f%F{$c[git:dirty]}*%f %F{$c[git:action]}rebase-i%f %F{$c[git:arrow]}${PURE_GIT_DOWN_ARROW:-⇣}${PURE_GIT_UP_ARROW:-⇡}%f %F{$c[git:stash]}${PURE_GIT_STASH_SYMBOL-≡}%f %F{$c[node_version]}${node_symbol}22%f %F{$c[execution_time]}42s%f %F{$c[custom:suffix]}suffix%f"
	print -P "%F{$c[virtualenv]}venv%f %F{$c[prompt:success]}${PURE_PROMPT_SYMBOL:-❯}%f"
	print
	print -P "%F{$c[prompt:error]}${PURE_PROMPT_SYMBOL:-❯}%f  prompt after error"
	print; print
	print -P "%F{$c[git:branch:cached]}main%f  branch color when data is cached"
	print; print
	print -P "%F{$c[user:root]}root%f${host_sample}  root user"
	print; print
	print -P "%F{$c[prompt:continuation]}… if%f %F{$c[prompt:success]}${PURE_PROMPT_SYMBOL:-❯}%f  continuation prompt"
}

prompt_pure_setup() {
	# Prevent percentage showing up if output doesn't end with a newline.
	export PROMPT_EOL_MARK=''

	prompt_opts=(subst percent)

	# Borrowed from `promptinit`. Sets the prompt options in case Pure was not
	# initialized via `promptinit`.
	setopt noprompt{bang,cr,percent,subst} "prompt${^prompt_opts[@]}"

	if [[ -z $prompt_newline ]]; then
		# This variable needs to be set, usually set by promptinit.
		typeset -g prompt_newline=$'\n%{\r%}'
	fi

	zmodload zsh/datetime
	zmodload zsh/zle
	zmodload zsh/parameter
	zmodload zsh/zutil

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info
	autoload -Uz async && async

	# The `add-zle-hook-widget` function is not guaranteed to be available.
	# It was added in Zsh 5.3.
	autoload -Uz +X add-zle-hook-widget 2>/dev/null

	# Set the colors.
	typeset -gA prompt_pure_colors_default prompt_pure_colors
	prompt_pure_colors_default=(
		custom:prefix        242
		custom:suffix        242
		execution_time       yellow
		git:arrow            cyan
		git:stash            cyan
		git:branch           242
		git:branch:cached    red
		git:action           yellow
		git:dirty            218
		host                 242
		node_version         green
		path                 blue
		prompt:error         red
		prompt:success       magenta
		prompt:continuation  242
		suspended_jobs       red
		user                 242
		user:root            default
		virtualenv           242
	)
	prompt_pure_colors=("${(@kv)prompt_pure_colors_default}")

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

	prompt_pure_state_setup

	zle -N prompt_pure_reset_prompt
	zle -N prompt_pure_update_vim_prompt_widget
	zle -N prompt_pure_reset_vim_prompt_widget
	if (( $+functions[add-zle-hook-widget] )); then
		add-zle-hook-widget zle-line-finish prompt_pure_reset_vim_prompt_widget
		add-zle-hook-widget zle-keymap-select prompt_pure_update_vim_prompt_widget
	fi

	# Initialize git globals referenced by PROMPT via prompt subst.
	typeset -gA prompt_pure_vcs_info
	typeset -g prompt_pure_git_branch_color=$prompt_pure_colors[git:branch]

	# Construct PROMPT once, both preprompt and prompt line. Kept
	# dynamic via variables and psvar[12-21], updated each render
	# in prompt_pure_preprompt_render. Numbering starts at 12 for
	# legacy reasons (Pure originally used psvar[12] for virtualenv)
	# and to avoid collisions with low psvar indices which users
	# may rely on (e.g. %v expands psvar[1]).
	#
	#   psvar[12] = suspended jobs symbol (e.g. ✦)
	#   psvar[13] = username flag, renders user/host (e.g. user@host)
	#   psvar[14] = git branch
	#   psvar[15] = git dirty marker, nested inside [14] conditional
	#   psvar[16] = git action (e.g. rebase, merge)
	#   psvar[17] = git arrows (e.g. ⇣⇡)
	#   psvar[18] = git stash symbol (e.g. ≡)
	#   psvar[19] = exec time (e.g. 1d 3h 2m 5s)
	#   psvar[20] = virtualenv/conda/nix-shell name
	#   psvar[21] = Node.js version (e.g. ⬢22)
	#   psvar[22] = custom prefix (set by prompt_pure_precustom)
	#   psvar[23] = custom suffix (set by prompt_pure_precustom)
	#
	# Example output:
	#   prefix ✦ user@host ~/Code/pure main* rebase ⇣⇡ ≡ ⬢22 3s suffix
	#   myenv ❯
	#
	# Preprompt line: each %(NV..) section only renders when its psvar is non-empty.
	PROMPT='%(22V.%F{$prompt_pure_colors[custom:prefix]}%22v%f .)'
	PROMPT+='%(12V.%F{$prompt_pure_colors[suspended_jobs]}%12v%f .)'
	local hostname_part=''
	if (( prompt_pure_state[show_host] )); then
		hostname_part='%F{$prompt_pure_colors[host]}@%m%f'
	fi
	PROMPT+='%(13V.%F{$prompt_pure_colors['"${prompt_pure_state[user_color]:-user}"']}%n%f'"${hostname_part}"' .)'
	prompt_pure_set_path_separator
	PROMPT+='${${prompt_pure_path_separator_dimmed:+$(prompt_pure_render_dimmed_path)}:-${prompt_pure_path_segment}}'
	PROMPT+='%(14V. %F{${prompt_pure_git_branch_color}}%14v%(15V.%F{$prompt_pure_colors[git:dirty]}%15v.)%f.)'
	PROMPT+='%(16V. %F{$prompt_pure_colors[git:action]}%16v%f.)'
	PROMPT+='%(17V. %F{$prompt_pure_colors[git:arrow]}%17v%f.)'
	PROMPT+='%(18V. %F{$prompt_pure_colors[git:stash]}%18v%f.)'
	PROMPT+='%(21V. %F{$prompt_pure_colors[node_version]}%21v%f.)'
	PROMPT+='%(19V. %F{$prompt_pure_colors[execution_time]}%19v%f.)'
	PROMPT+='%(23V. %F{$prompt_pure_colors[custom:suffix]}%23v%f.)'

	# Newline separating preprompt from prompt.
	PROMPT+='${prompt_newline}'

	# Prompt line: virtualenv and prompt symbol.
	PROMPT+='%(20V.%F{$prompt_pure_colors[virtualenv]}%20v%f .)'
	# Prompt symbol: turns red if the previous command didn't exit with 0.
	local prompt_indicator='%(?.%F{$prompt_pure_colors[prompt:success]}.%F{$prompt_pure_colors[prompt:error]})${prompt_pure_state[prompt]}%f '
	PROMPT+=$prompt_indicator

	# Indicate continuation prompt by … and use a darker color for it.
	PROMPT2='%F{$prompt_pure_colors[prompt:continuation]}… %(1_.%_ .%_)%f'$prompt_indicator

	# Store prompt expansion symbols for in-place expansion via (%). For
	# some reason it does not work without storing them in a variable first.
	typeset -ga prompt_pure_debug_depth
	prompt_pure_debug_depth=('%e' '%N' '%x')

	# Compare is used to check if %N equals %x. When they differ, the main
	# prompt is used to allow displaying both filename and function. When
	# they match, we use the secondary prompt to avoid displaying duplicate
	# information.
	local -A ps4_parts
	ps4_parts=(
		depth 	  '%F{yellow}${(l:${(%)prompt_pure_debug_depth[1]}::+:)}%f'
		compare   '${${(%)prompt_pure_debug_depth[2]}:#${(%)prompt_pure_debug_depth[3]}}'
		main      '%F{blue}${${(%)prompt_pure_debug_depth[3]}:t}%f%F{242}:%I%f %F{242}@%f%F{blue}%N%f%F{242}:%i%f'
		secondary '%F{blue}%N%f%F{242}:%i'
		prompt 	  '%F{242}>%f '
	)
	# Combine the parts with conditional logic. First the `:+` operator is
	# used to replace `compare` either with `main` or an empty string. Then
	# the `:-` operator is used so that if `compare` becomes an empty
	# string, it is replaced with `secondary`.
	local ps4_symbols='${${'${ps4_parts[compare]}':+"'${ps4_parts[main]}'"}:-"'${ps4_parts[secondary]}'"}'

	# Improve the debug prompt (PS4), show depth by repeating the +-sign and
	# add colors to highlight essential parts like file and function name.
	PROMPT4="${ps4_parts[depth]} ${ps4_symbols}${ps4_parts[prompt]}"

	# Pure does not use a right-side prompt. Clear RPROMPT to prevent
	# frameworks (e.g. Prezto) from leaking a previous theme's RPROMPT.
	RPROMPT=

	# Guard against Oh My Zsh themes overriding Pure.
	unset ZSH_THEME

	# Guard against (ana)conda changing the PS1 prompt
	# (we manually insert the env when it's available).
	export CONDA_CHANGEPS1=no

	# Guard against pyenv-virtualenv changing the PS1 prompt
	# (we manually insert the env when it's available).
	export PYENV_VIRTUALENV_DISABLE_PROMPT=1
}

prompt_pure_setup "$@"
