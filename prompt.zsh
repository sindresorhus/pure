# Pure
# by Sindre Sorhus
# https://github.com/sindresorhus/pure/
# MIT License

local default_username='sindresorhus'

# Only show username if not default
username() {
	if [ $USER != $default_username ]; then echo '%n@%m '; fi
}

git_branch() {
	echo `git symbolic-ref --short -q HEAD 2>/dev/null`
}

precmd() {
	print -P '\n%F{blue}%~%f %F{236}`git_branch` `username`%*%f'
}

# Turns the prompt red if the last command exited with 0
PROMPT='%(?.%F{magenta}.%F{red})❯%f '
# Can be disabled:
# PROMPT='%F{magenta}❯%f '
