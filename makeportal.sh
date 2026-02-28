#!/usr/bin/env bash
perl sxpsg2.perl \
    --config-dir "configuration" \
    --config-file "$1" \
    --list-file "$2" \
    --include-hash "script/hash_guard.js" \
    --hash-key "$3" \
    --encrypt
