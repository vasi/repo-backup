#!/bin/sh
exec $(which ssh) -i $PWD/key "$@"
