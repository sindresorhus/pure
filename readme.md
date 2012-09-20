# Pure

Minimal and fast ZSH prompt

![screenshot](https://raw.github.com/sindresorhus/pure/master/screenshot.png)

## Overview

Most prompts are ugly, cluttered and slow. I wanted something visually pleasing that stayed out of my way.

Pure only shows the current user if it's not the default. It shows the current git branch, but not dirty status since that is awfully slow. And the prompt symbol turns red if the last command exited with 0.


## Getting Started

- Download or git submodule it into your dotfiles folder
- In your `.zshrc` add `. prompt.zsh`
- Add your username to the `default_username` variable


## Tip

[Tomorrow Night](https://github.com/chriskempson/tomorrow-theme) theme with the [Droid Sans Mono](http://www.google.com/webfonts/specimen/Droid+Sans+Mono) font (15pt) is a beautiful combination, as seen in the screenshot above.


## License

[MIT License](http://en.wikipedia.org/wiki/MIT_License)
(c) [Sindre Sorhus](http://sindresorhus.com)
