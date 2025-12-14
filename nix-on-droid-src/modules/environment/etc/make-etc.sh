# Copyright (c) 2019-2020, see AUTHORS. Licensed under MIT License, see LICENSE.

# Inspired by
# https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/system/etc/make-etc.sh
# (Copyright (c) 2003-2019 Eelco Dolstra and the Nixpkgs/NixOS contributors,
#  licensed under MIT License as well)

source $stdenv/setup

mkdir -p $out

set -f
sources_=($sources)
targets_=($targets)
set +f

# storePrefix is passed via environment variable from Nix
prefix="${storePrefix:-}"

for ((i = 0; i < ${#targets_[@]}; i++)); do
    source="${sources_[$i]}"
    target="${targets_[$i]}"

    if [[ "$source" =~ '*' ]]; then

        # If the source name contains '*', perform globbing.
        mkdir -p $out/etc/$target
        for fn in $source; do
            ln -s "${prefix}$fn" $out/etc/$target/
        done

    else

        mkdir -p $out/etc/$(dirname $target)
        if ! [ -e $out/etc/$target ]; then
            ln -s "${prefix}$source" $out/etc/$target
        else
            echo "duplicate entry $target -> $source"
            if test "$(readlink $out/etc/$target)" != "${prefix}$source"; then
                echo "mismatched duplicate entry $(readlink $out/etc/$target) <-> ${prefix}$source"
                exit 1
            fi
        fi

    fi
done
