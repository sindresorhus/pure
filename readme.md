# Pure

> Pretty, minimal and fast ZSH prompt

![screenshot](screenshot.png)


## Overview

Most prompts are cluttered, ugly and slow. I wanted something visually pleasing that stayed out of my way.

### Why?

- Comes with the perfect prompt character. Author went through the whole Unicode range to find it.
- Shows git branch and whether it's dirty using the [fastest](https://gist.github.com/3898739) method available.
- Prompt character turns red if the last command didn't exit with 0.
- Command execution time will be displayed if it exceeds the set threshold.
- Username and host is only displayed when in an SSH session.
- Shows the current path in the title and the [current directory and command](screenshot-title-cmd.png) when a process is running.
- Can easily be used as a starting point for your own custom prompt.


## Getting started

- Clone this repo, add it as a submodule, or just download `pure.zsh`.

- Symlink `pure.zsh` to somewhere in [`$fpath`](http://www.refining-linux.org/archives/46/ZSH-Gem-12-Autoloading-functions/) with the name `prompt_pure_setup`.

Example:

```sh
$ ln -s "$PWD/pure.zsh" /usr/local/share/zsh/site-functions/prompt_pure_setup
```
*Run `echo $fpath` to see possible locations.*

For a user-specific installation (which would not require escalated privileges), simply add a directory to `$fpath` for that user:

```sh
# .zshenv or .zshrc
fpath=( "$HOME/.zfunctions" $fpath )
```

Then install the theme there:

```sh
$ ln -s "$PWD/pure.zsh" "$HOME/.zfunctions/prompt_pure_setup"
```

- Initialize the prompt system (if not so already):

```sh
# .zshrc
autoload -U promptinit && promptinit
```

- Choose this prompt:

```sh
# .zshrc
prompt pure
```


## Options

### `PURE_CMD_MAX_EXEC_TIME`

The max execution time of a process before its run time is shown when it exits. Defaults to `5` seconds.

### `PURE_GIT_PULL`

Set `PURE_GIT_PULL=0` to prevent Pure from checking whether the current Git remote has been updated.

## Example

```sh
# .zshrc

autoload -U promptinit && promptinit

# optionally define some options
PURE_CMD_MAX_EXEC_TIME=10

prompt pure
```


## Tips

[Tomorrow Night Eighties](https://github.com/chriskempson/tomorrow-theme) theme with the [Droid Sans Mono](http://www.google.com/webfonts/specimen/Droid+Sans+Mono) font (15pt) is a beautiful combination, as seen in the screenshot above.


## [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh)

Symlink (or copy) `pure.zsh` to `~/.oh-my-zsh/custom/pure.zsh-theme` and add `ZSH_THEME="pure"` to your .zshrc file.

## [prezto](https://github.com/sorin-ionescu/prezto)

Symlink (or copy) `pure.zsh` to `~/.prezto/modules/prompt/functions/prompt_pure_setup` alongside Prezto's other prompts. Then `set zstyle ':prezto:module:prompt' theme 'pure'` in `~/.zpreztorc`.

## [antigen](https://github.com/zsh-users/antigen)

Add `antigen bundle sindresorhus/pure` to your .zshrc file (do not use the `antigen theme` function).


## License

MIT © [Sindre Sorhus](http://sindresorhus.com)
