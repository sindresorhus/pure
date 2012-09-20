# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure/
# MIT License


# Change this to your own username
local default_username='sindresorhus'


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

# Only show username if not default
[ $USER != $default_username ] && local username='%n@%m '

# Fastest possible way to check if repo is dirty
git_dirty() {
	git diff --quiet --ignore-submodules HEAD 2>/dev/null; [ $? -eq 1 ] && echo '*'
}


precmd() {
	vcs_info
	# Remove `%*` to hide the time
	print -P '\n%F{blue}%~%F{236}$vcs_info_msg_0_ $username%*%f'
}

# Turns the prompt red if the last command exited with 0
PROMPT='%(?.%F{magenta}.%F{red})❯%f '
# Can be disabled:
# PROMPT='%F{magenta}❯%f '
