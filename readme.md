# Pure

Pretty, minimal and fast ZSH prompt

![screenshot](https://raw.github.com/sindresorhus/pure/master/screenshot.png)


## Overview

Most prompts are cluttered, ugly and slow. I wanted something visually pleasing that stayed out of my way.

### Why?

- Comes with the perfect prompt character. Author went through the whole Unicode range to find it.
- Username is only displayed if not default
- Shows git branch and if it's dirty using the [fastest](https://gist.github.com/3898739) method available
- Prompt character turns red if the last command didn't exit with 0
- Command execution time will be displayed if it exceeds the set threshold
- Can easily be used as a starting point for your own custom prompt


## Getting started

- Download `pure.zsh` or submodule this repo.
- In your `.zshrc` add any of the below options, then import pure `. path/to/pure.zsh`.


## Options

### `PURE_DEFAULT_USERNAME`

Define your username if you want to hide it from the prompt when it matches the current username.

### `PURE_CMD_MAX_EXEC_TIME`

The max execution time of a process before its run time is shown when it exits. Defaults to `5` seconds.


## Example

```sh
# .zshrc

# optionally define some options
PURE_DEFAULT_USERNAME='sindresorhus'
PURE_CMD_MAX_EXEC_TIME=10

# import the prompt
. pure.zsh
```


## Tip

[Tomorrow Night](https://github.com/chriskempson/tomorrow-theme) theme with the [Droid Sans Mono](http://www.google.com/webfonts/specimen/Droid+Sans+Mono) font (15pt) is a beautiful combination, as seen in the screenshot above.


## License

MIT © [Sindre Sorhus](http://sindresorhus.com)
