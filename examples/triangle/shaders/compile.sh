#!/bin/bash

# Check if VULKAN_SDK is set
if [ -z "$VULKAN_SDK" ]; then
  echo "Error: VULKAN_SDK environment variable is not set."
  exit 1
fi

# Find all .frag and .vert files recursively and compile them to .spv
find . -type f \( -name "*.frag" -o -name "*.vert" \) | while read -r file; do
  # Get the file name without extension
  filename=$(basename "$file" .$(echo "$file" | awk -F . '{print $NF}'))

  # Compile the file using glslc
  "$VULKAN_SDK/bin/glslc" "$file" -o "${filename}.spv"

  # Check if the compilation was successful
  if [ $? -eq 0 ]; then
    echo "Compiled $file to ${filename}.spv"
  else
    echo "Failed to compile $file"
  fi
done
