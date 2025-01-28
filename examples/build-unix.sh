#!/bin/bash

OUTPUT_DIR=build
EXECUTABLE_NAME=triangle_debug

# Build and run command
cmd=$1

if [ -z "$cmd" ]; then
    cmd=build
fi

odin build ./triangle \
    -debug \
    -vet \
    -strict-style \
    -out:$OUTPUT_DIR/$EXECUTABLE_NAME

compiler_error_code=$?

if [ $compiler_error_code -ne 0 ]; then
    echo -e "\nFailed to compile!"
    exit 1
fi

echo -e "\nCompiled successfully!\n"

if [ "$cmd" == "run" ]; then
    cd "./$OUTPUT_DIR"
    ./$EXECUTABLE_NAME
fi
