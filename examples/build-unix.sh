#!/bin/bash

OUTPUT_DIR=build
BUILD_TARGET=$1
EXECUTABLE_NAME=${BUILD_TARGET}
RUN_AFTER_BUILD=false

# Check for arguments
ARG_COUNTER=0
for arg in "$@"; do
	if [ $ARG_COUNTER -eq 0 ]; then
		# Skip the build target first argument
		:
	else
		if [ "$arg" = "run" ]; then
			RUN_AFTER_BUILD=true
		fi
	fi
	((ARG_COUNTER++))
done

# Build command
odin build ./${BUILD_TARGET} \
	-debug \
	-out:$OUTPUT_DIR/$EXECUTABLE_NAME

compiler_error_code=$?

if [ $compiler_error_code -ne 0 ]; then
	echo "Failed to compile!"
	exit 1
fi

echo "Compiled successfully!"

if [ "$RUN_AFTER_BUILD" = true ]; then
	pushd "$OUTPUT_DIR" > /dev/null
	./$EXECUTABLE_NAME
	popd > /dev/null
fi

exit $compiler_error_code
