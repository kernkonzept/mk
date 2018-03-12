#! /bin/bash

BASE_ADDR=0x00400000
VERBOSE=false

while [ $# != 0 ];
do
    TARGET=`echo $1 | sed "s/relocatable.\(.*\)/\1/"`
    if $VERBOSE; then echo ld -o tmp/$TARGET -Ttext $BASE_ADDR $1.reloc; fi
    ld -o tmp/$TARGET -Ttext $BASE_ADDR $1
    TMP=`nm tmp/$TARGET | grep -w _end | cut -c1-8`
    OLD_BASE_ADDR=$BASE_ADDR
    BASE_ADDR=`perl -e "printf \"0x%x\", (0x$TMP + 0x1000) & 0xfffff000"`
    SIZE=`perl -e "printf \"0x%x\", $BASE_ADDR - $OLD_BASE_ADDR"`
    SIZEKB=`perl -e "printf \"%d\", ($BASE_ADDR - $OLD_BASE_ADDR) / 1024"`
    printf "Module \"%-20s\" at 0x%08x size 0x%08x (%5d kB)\n" \
           $TARGET $OLD_BASE_ADDR $SIZE $SIZEKB
    shift 1;
done
