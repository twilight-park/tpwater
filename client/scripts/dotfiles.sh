#!/bin/sh
#

for file in $(ls dotfiles) ; do
    rm -rf $HOME/.$(basename $file)
    ln -s $(realpath dotfiles/$file) $HOME/.$(basename $file)
done
