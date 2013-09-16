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

# fastest possible way to check if repo is dirty
prompt_pure_git_dirty() {
	# check if we're in a git repo
	command git rev-parse --is-inside-work-tree &>/dev/null || return
	# check if it's dirty
	command git diff --quiet --ignore-submodules HEAD &>/dev/null

	(($? == 1)) && echo '*'
}

# displays the exec time of the last command if set threshold was exceeded
prompt_pure_cmd_exec_time() {
	local stop=`date +%s`
	local start=${cmd_timestamp:-$stop}
	integer elapsed=$stop-$start
	(($elapsed > ${PURE_CMD_MAX_EXEC_TIME:=5})) && echo ${elapsed}s
}

prompt_pure_preexec() {
	cmd_timestamp=`date +%s`

	# shows the current dir and executed command in the title when a process is active
	print -Pn "\e]0;$PWD:t: $2\a"
}

# string length ignoring ansi escapes
prompt_pure_string_length() {
	echo ${#${(S%%)1//(\%([KF1]|)\{*\}|\%[Bbkf])}}
}

prompt_pure_precmd() {
	# shows the full path in the title
	print -Pn '\e]0;%~\a'

	# git info
	vcs_info

	local prompt_pure_preprompt='\n%F{blue}%~%F{8}$vcs_info_msg_0_`prompt_pure_git_dirty` $prompt_pure_username%f %F{yellow}`prompt_pure_cmd_exec_time`%f'
	print -P $prompt_pure_preprompt

	# check async if there is anything to pull
	{
		# check if we're in a git repo
		command git rev-parse --is-inside-work-tree &>/dev/null || return
		# check check if there is anything to pull
		command git fetch && (( $(git rev-list --count HEAD...@'{u}' 2>/dev/null) > 0 )) &&
		# some crazy ansi magic to inject the symbol into the previous line
		printf "\e[A\e[`prompt_pure_string_length $prompt_pure_preprompt`C\e[90m⇣\e[0m\n\e[2C"
	} &!

	# reset value since `preexec` isn't always triggered
	unset cmd_timestamp
}


prompt_pure_setup() {
	prompt_opts=(cr subst percent)

	autoload -Uz add-zsh-hook
	autoload -Uz vcs_info

	add-zsh-hook precmd prompt_pure_precmd
	add-zsh-hook preexec prompt_pure_preexec

	zstyle ':vcs_info:*' enable git
	zstyle ':vcs_info:git*' formats ' %b'
	zstyle ':vcs_info:git*' actionformats ' %b|%a'

	# show username@host if logged in through SSH
	[[ "$SSH_CONNECTION" != '' ]] && prompt_pure_username='%n@%m '

	# prompt turns red if the previous command didn't exit with 0
	PROMPT='%(?.%F{magenta}.%F{red})❯%f '
}

prompt_pure_setup "$@"
