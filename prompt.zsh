# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure
# MIT License


# change this to your own username
DEFAULT_USERNAME='sindresorhus'

# threshold (sec) for showing cmd exec time
CMD_MAX_EXEC_TIME=5


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

autoload -Uz vcs_info
zstyle ':vcs_info:*' enable git # You can add hg too if needed: `git hg`
zstyle ':vcs_info:git*' formats ' %b'
zstyle ':vcs_info:git*' actionformats ' %b|%a'

# enable prompt substitution
setopt PROMPT_SUBST

# only show username if not default
[ $USER != $DEFAULT_USERNAME ] && local username='%n@%m '


# fastest possible way to check if repo is dirty
git_dirty() {
	# check if we're in a git repo
	command git rev-parse --is-inside-work-tree &>/dev/null || return
	# check if it's dirty
	command git diff --quiet --ignore-submodules HEAD &>/dev/null; [ $? -eq 1 ] && echo '*'
}

# displays the exec time of the last command if set threshold was exceeded
cmd_exec_time() {
	local stop=`date +%s`
	local start=${cmd_timestamp:-$stop}
	let local elapsed=$stop-$start
	[ $elapsed -gt $CMD_MAX_EXEC_TIME ] && echo ${elapsed}s
}

preexec() {
	cmd_timestamp=`date +%s`
}

precmd() {
	vcs_info
	# add `%*` to display the time
	print -P '\n%F{blue}%~%F{8}$vcs_info_msg_0_`git_dirty` $username%f %F{yellow}`cmd_exec_time`%f'
	# reset value since `preexec` isn't always triggered
	unset cmd_timestamp
}

# Auto notify git pull!
function prompt_pull() {
    git rev-parse --is-inside-work-tree &>/dev/null &&
    [[ $(git rev-list HEAD...origin/master --count) > 0 ]] &&
    echo "You have stuff to pull..."
}

add-zsh-hook precmd prompt_pull

# prompt turns red if the previous command didn't exit with 0
PROMPT='%(?.%F{magenta}.%F{red})❯%f '
# can be disabled:
# PROMPT='%F{magenta}❯%f '
