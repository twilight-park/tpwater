#!/bin/sh
#
head -c 256 /dev/random | sha1sum | awk '{ print $1 }'
