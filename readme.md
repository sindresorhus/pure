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


## Getting Started

- Download `pure.zsh` or submodule this repo
- In your `.zshrc` add `. path/to/pure.zsh`
- Add your username to `DEFAULT_USERNAME`


## Tip

[Tomorrow Night](https://github.com/chriskempson/tomorrow-theme) theme with the [Droid Sans Mono](http://www.google.com/webfonts/specimen/Droid+Sans+Mono) font (15pt) is a beautiful combination, as seen in the screenshot above.


## License

MIT © [Sindre Sorhus](http://sindresorhus.com)
