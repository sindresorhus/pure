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


() {
	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info

	add-zsh-hook precmd pure_precmd
	add-zsh-hook preexec pure_preexec

	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:git*' formats ' %b'
	zstyle ':vcs_info:git*' actionformats ' %b|%a'

	# enable prompt substitution
	setopt prompt_subst

	# show username@host if logged in through SSH
	if [[ $SSH_CLIENT != '' || $SSH_TTY != '' ]]; then
		local username='%n@%m '
	fi

	# fastest possible way to check if repo is dirty
	pure_git_dirty() {
		# check if we're in a git repo
		command git rev-parse --is-inside-work-tree &>/dev/null || return
		# check if it's dirty
		command git diff --quiet --ignore-submodules HEAD &>/dev/null; [ $? -eq 1 ] && echo '*'
	}

	# displays the exec time of the last command if set threshold was exceeded
	pure_cmd_exec_time() {
		local stop=`date +%s`
		local start=${cmd_timestamp:-$stop}
		integer elapsed=$stop-$start
		[[ $elapsed -gt ${PURE_CMD_MAX_EXEC_TIME:=5} ]] && echo ${elapsed}s
	}

	pure_preexec() {
		cmd_timestamp=`date +%s`

		# shows the current dir and executed command in the title when a process is active
		print -Pn "\e]0;$PWD:t: $2\a"
	}

	pure_precmd() {
		# shows the full path in the title
		print -Pn '\e]0;%~\a'

		# git info
		vcs_info

		# add `%*` to display the time
		print -P '\n%F{blue}%~%F{8}$vcs_info_msg_0_`pure_git_dirty` $username%f %F{yellow}`pure_cmd_exec_time`%f'

		# reset value since `preexec` isn't always triggered
		unset cmd_timestamp
	}

	# prompt turns red if the previous command didn't exit with 0
	PROMPT='%(?.%F{magenta}.%F{red})❯%f '
}
