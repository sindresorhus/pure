# Pure

> Pretty, minimal and fast ZSH prompt

![screenshot](screenshot.png)


## Overview

Most prompts are cluttered, ugly and slow. I wanted something visually pleasing that stayed out of my way.

### Why?

- Comes with the perfect prompt character.  
  Author went through the whole Unicode range to find it.
- Shows `git` branch and whether it's dirty (with a `*`).
- Indicates when you have unpushed/unpulled `git` commits with up/down arrows.
- Prompt character turns red if the last command didn't exit with `0`.
- Command execution time will be displayed if it exceeds the set threshold.
- Username and host only displayed when in an SSH session.
- Shows the current path in the title and the [current folder & command](screenshot-title-cmd.png) when a process is running.
- Makes an excellent starting point for your own custom prompt.


## Install

Can be installed with `npm` or manually. Requires git 2.0.0+ and ZSH 5.0.0+.

### npm

```sh
$ npm install --global pure-prompt
```

That's it. Skip to [Getting started](#getting-started).

### Manually

1. Either…
  - Clone this repo
  - add it as a submodule, or
  - just download `pure.zsh`

2. Symlink `pure.zsh` to somewhere in [`$fpath`](http://www.refining-linux.org/archives/46/ZSH-Gem-12-Autoloading-functions/) with the name `prompt_pure_setup`.

#### Example

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


## Getting started

Initialize the prompt system (if not so already) and choose `pure`:

```sh
# .zshrc
autoload -U promptinit && promptinit
prompt pure
```


## Options

### `PURE_CMD_MAX_EXEC_TIME`

The max execution time of a process before its run time is shown when it exits. Defaults to `5` seconds.

### `PURE_GIT_PULL`

Set `PURE_GIT_PULL=0` to prevent Pure from checking whether the current Git remote has been updated.

### `PURE_GIT_UNTRACKED_DIRTY`

Set `PURE_GIT_UNTRACKED_DIRTY=0` to not include untracked files in dirtiness check. Only really useful on extremely huge repos like the WebKit repo.

### `PURE_PROMPT_SYMBOL`

Defines the prompt symbol. The default value is `❯`.

## Example

```sh
# .zshrc

autoload -U promptinit && promptinit

# optionally define some options
PURE_CMD_MAX_EXEC_TIME=10

prompt pure
```


## Tips

[Tomorrow Night Eighties](https://github.com/chriskempson/tomorrow-theme) theme with the [Droid Sans Mono](http://www.google.com/webfonts/specimen/Droid+Sans+Mono) font (15pt) is a beautiful combination, as seen in the screenshot above. Just make sure you have anti-aliasing enabled in your Terminal.

To have commands colorized as seen in the screenshot install [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting).


## Integration

### [oh-my-zsh](https://github.com/robbyrussell/oh-my-zsh)

Symlink (or copy) `pure.zsh` to `~/.oh-my-zsh/custom/pure.zsh-theme` and add `ZSH_THEME="pure"` to your `.zshrc` file.

### [prezto](https://github.com/sorin-ionescu/prezto)

Set `zstyle ':prezto:module:prompt' theme 'pure'` in `~/.zpreztorc`.

### [antigen](https://github.com/zsh-users/antigen)

Add `antigen bundle sindresorhus/pure` to your .zshrc file (do not use the `antigen theme` function).


## FAQ

### Do you hate almost all software?

[Yes.](https://gist.github.com/cookrn/4015437)

### I am stuck in a shell loop in my terminal that ask me to authenticate. What should I do ?

[This is a known issue](https://github.com/sindresorhus/pure/issues/76).
Using `git pull` when you get the username prompt should help you to break the loop by giving you a real prompt for this. **[This has been fixed in git 2.3](https://github.com/sindresorhus/pure/commit/f43ab97e1cf4a276b7a6e33eac055ee16610be15)**

## License

MIT © [Sindre Sorhus](http://sindresorhus.com)
