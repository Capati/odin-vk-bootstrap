#!/bin/bash

OUTPUT_DIR=examples/build
EXECUTABLE_NAME=triangle_debug

# Ensure build folder exists
if [ ! -d $OUTPUT_DIR ]; then
    mkdir $OUTPUT_DIR
fi

# Build and run command
cmd=$1

if [ -z "$cmd" ]; then
    cmd=build
fi

odin build ./examples/triangle \
    -debug \
    -vet \
    -strict-style \
    -o:none \
    -max-error-count:1 \
    -use-separate-modules \
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
