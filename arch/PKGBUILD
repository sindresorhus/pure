# Author: Sindre Sorhus
# Maintainer: Pat Brisbin <pbrisbin@gmail.com>
pkgname=pure
pkgver=0.0.1
pkgrel=1
pkgdesc="pure prompt for zsh"
arch=('any')
url="https://github.com/sindresorhus/pure"
license=('MIT')
source=(pure.zsh)

package() {
  install -Dm644 pure.zsh \
    "$pkgdir/usr/share/zsh/functions/Prompts/prompt_pure_setup"
}
md5sums=('673c5d65495ba6942938925ab4cff2d8')
