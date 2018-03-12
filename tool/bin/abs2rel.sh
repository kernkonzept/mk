#!/bin/sh

#
# abs2rel
#
# Script to determine the relative path between two directories.  This
# is useful for creating relative links between two directories, such
# that the whole tree can still be moved without breaking the links.
# It is used in the dietlibc package to link some files from the
# contrib dir.
#
# Copyright (c) D. J. Hawkey Jr. 2002
#
#          adapted by Martin Pohlack
#
# Free for anybody's use in any application, in whole or in part,
# as long as the above copyright is retained. By using this stuff,
# you agree that I'm not responsible for anything that might go
# wrong, nor for any damages because something did.
#

# Inputs: $1 = source path, $2 = destination path
#         Inputs must exist if they aren't absolute
# Outputs: $BASEPATH = base of $1 and $2, $DESTPATH = transformed $2

set -e

declare CWD SRCPATH
                
# check for legal arguments
if [ ! -d $1 ]; then
	exit 1
fi

if [ ! -d $2 ]; then
	exit 2
fi

if [ "$1" != "/" -a "${1##*[^/]}" = "/" ]; then
	SRCPATH=${1%?}
else
	SRCPATH=$1
fi
if [ "$2" != "/" -a "${2##*[^/]}" = "/" ]; then
	DESTPATH=${2%?}
else
	DESTPATH=$2
fi

CWD=$PWD
[ "${1%%[^/]*}" != "/" ] && cd $1 && SRCPATH=$PWD
[ "$CWD" != "$PWD" ] && cd $CWD
[ "${2%%[^/]*}" != "/" ] && cd $2 && DESTPATH=$PWD
[ "$CWD" != "$PWD" ] && cd $CWD

BASEPATH=$SRCPATH

[ "$SRCPATH" = "$DESTPATH" ] && DESTPATH="." && echo $DESTPATH && exit
[ "$SRCPATH" = "/" ] && DESTPATH=${DESTPATH#?} && echo $DESTPATH && exit

while [ "$BASEPATH" != "${DESTPATH%${DESTPATH#$BASEPATH}}" ]; do
	BASEPATH=${BASEPATH%/*}
done

SRCPATH=${SRCPATH#$BASEPATH}
DESTPATH=${DESTPATH#$BASEPATH}
DESTPATH=${DESTPATH#?}
while [ -n "$SRCPATH" ]; do
	SRCPATH=${SRCPATH%/*}
	DESTPATH="../$DESTPATH"
done

[ -z "$BASEPATH" ] && BASEPATH="/"
[ "${DESTPATH##*[^/]}" = "/" ] && DESTPATH=${DESTPATH%?}

echo $DESTPATH

# for CLI - leave commented to source
#abs_to_rel $1 $2
#echo $BASEPATH
#echo $DESTPATH
