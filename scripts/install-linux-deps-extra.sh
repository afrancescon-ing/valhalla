#!/usr/bin/env bash
# Script for shared dependencies

set -x -o errexit -o pipefail -o nounset

# Now, go through and install the build dependencies
sudo apt-get update --assume-yes

# build microtar from source
readonly microtar_dir=/tmp/microtar
git clone https://github.com/rxi/microtar.git $microtar_dir
pushd $microtar_dir
# Compile the source files manually since there's no Makefile
gcc -c src/microtar.c -o microtar.o -fPIC
ar rcs microtar.a microtar.o
# Install header and static library
sudo cp src/microtar.h /usr/local/include/
sudo cp microtar.a /usr/local/lib/
#Proper linking 
ln -sf /usr/local/lib/microtar.a /usr/local/lib/libmicrotar.a
# Update library cache
sudo ldconfig
popd && rm -rf $microtar_dir