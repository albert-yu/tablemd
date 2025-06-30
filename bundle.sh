#!/bin/bash

set -e

echo "🚀 Starting bundle process..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to detect OS and architecture
detect_platform() {
    OS=$(uname -s)
    ARCH=$(uname -m)

    case "$OS" in
        Linux*)
            case "$ARCH" in
                x86_64) echo "linux-x86_64" ;;
                aarch64|arm64) echo "linux-aarch64" ;;
                *) echo "Unsupported Linux architecture: $ARCH" >&2; exit 1 ;;
            esac
            ;;
        Darwin*)
            case "$ARCH" in
                x86_64) echo "macos-x86_64" ;;
                arm64) echo "macos-aarch64" ;;
                *) echo "Unsupported macOS architecture: $ARCH" >&2; exit 1 ;;
            esac
            ;;
        MINGW*|CYGWIN*|MSYS*)
            case "$ARCH" in
                x86_64) echo "windows-x86_64" ;;
                *) echo "Unsupported Windows architecture: $ARCH" >&2; exit 1 ;;
            esac
            ;;
        *)
            echo "Unsupported operating system: $OS" >&2
            exit 1
            ;;
    esac
}

# Function to install Zig
install_zig() {
    echo "📦 Installing Zig..."

    PLATFORM=$(detect_platform)
    ZIG_VERSION="0.11.0"

    case "$PLATFORM" in
        linux-*)
            ZIG_ARCHIVE="zig-$PLATFORM-$ZIG_VERSION.tar.xz"
            ;;
        macos-*)
            ZIG_ARCHIVE="zig-$PLATFORM-$ZIG_VERSION.tar.xz"
            ;;
        windows-*)
            ZIG_ARCHIVE="zig-$PLATFORM-$ZIG_VERSION.zip"
            ;;
    esac

    ZIG_URL="https://ziglang.org/download/$ZIG_VERSION/$ZIG_ARCHIVE"
    ZIG_DIR="$HOME/.local/zig"

    echo "Downloading Zig from $ZIG_URL..."

    # Create local directory
    mkdir -p "$HOME/.local"

    # Download and extract Zig
    if [[ "$ZIG_ARCHIVE" == *.zip ]]; then
        curl -L "$ZIG_URL" -o "/tmp/$ZIG_ARCHIVE"
        unzip "/tmp/$ZIG_ARCHIVE" -d "/tmp/"
        mv "/tmp/zig-$PLATFORM-$ZIG_VERSION" "$ZIG_DIR"
        rm "/tmp/$ZIG_ARCHIVE"
    else
        curl -L "$ZIG_URL" | tar -xJ -C "/tmp/"
        mv "/tmp/zig-$PLATFORM-$ZIG_VERSION" "$ZIG_DIR"
    fi

    # Add to PATH for this session
    export PATH="$ZIG_DIR:$PATH"

    echo "✅ Zig installed successfully at $ZIG_DIR"
}

# Check if Zig is available
if command_exists zig; then
    echo "✅ Zig is already available"
    zig version
else
    echo "❌ Zig not found, installing..."
    install_zig
fi

# Verify Zig is now available
if ! command_exists zig; then
    echo "❌ Failed to install or find Zig" >&2
    exit 1
fi

echo "🔨 Building with Zig..."
zig build -Dtarget=wasm32-emscripten --release=small

# Check if build was successful
if [ ! -d "zig-out/web" ]; then
    echo "❌ Build failed - zig-out/web directory not found" >&2
    exit 1
fi

echo "📁 Creating dist directory..."
mkdir -p dist

echo "📋 Copying build artifacts to dist..."
cp -r zig-out/web/* dist/

echo "✅ Bundle process completed successfully!"
echo "📦 Build artifacts copied to dist/"

# List contents of dist for verification
echo "📋 Contents of dist/:"
ls -la dist/
