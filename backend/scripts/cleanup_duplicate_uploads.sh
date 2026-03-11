#!/bin/bash

# Script to clean up duplicate uploads directory
# This removes the incorrectly nested cmd/server/cmd/server/uploads directory

set -e

BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$BACKEND_DIR"

WRONG_DIR="cmd/server/cmd/server/uploads"
CORRECT_DIR="cmd/server/uploads"

if [ -d "$WRONG_DIR" ]; then
    echo "🔍 Found duplicate uploads directory at: $WRONG_DIR"
    
    # Check if correct directory exists
    if [ ! -d "$CORRECT_DIR" ]; then
        echo "⚠️  Correct directory doesn't exist. Creating it..."
        mkdir -p "$CORRECT_DIR/avatars"
        mkdir -p "$CORRECT_DIR/images"
        mkdir -p "$CORRECT_DIR/audio"
    fi
    
    # Copy files if they don't exist in correct location
    echo "📋 Copying files to correct location..."
    if [ -d "$WRONG_DIR/avatars" ]; then
        cp -rn "$WRONG_DIR/avatars/"* "$CORRECT_DIR/avatars/" 2>/dev/null || true
    fi
    if [ -d "$WRONG_DIR/images" ]; then
        cp -rn "$WRONG_DIR/images/"* "$CORRECT_DIR/images/" 2>/dev/null || true
    fi
    if [ -d "$WRONG_DIR/audio" ]; then
        cp -rn "$WRONG_DIR/audio/"* "$CORRECT_DIR/audio/" 2>/dev/null || true
    fi
    
    echo "🗑️  Removing duplicate directory..."
    rm -rf "cmd/server/cmd"
    
    echo "✅ Cleanup complete!"
    echo "📁 Files are now in: $CORRECT_DIR"
else
    echo "✅ No duplicate directory found. Everything is clean!"
fi

# Show current uploads structure
echo ""
echo "📊 Current uploads structure:"
if [ -d "$CORRECT_DIR" ]; then
    echo "Avatars: $(find "$CORRECT_DIR/avatars" -type f 2>/dev/null | wc -l | tr -d ' ') files"
    echo "Images:  $(find "$CORRECT_DIR/images" -type f 2>/dev/null | wc -l | tr -d ' ') files"
    echo "Audio:   $(find "$CORRECT_DIR/audio" -type f 2>/dev/null | wc -l | tr -d ' ') files"
fi
