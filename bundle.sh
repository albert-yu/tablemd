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

# Function to verify SHA256 checksum
verify_sha256() {
    local file="$1"
    local expected_sha="$2"

    if command_exists sha256sum; then
        actual_sha=$(sha256sum "$file" | cut -d' ' -f1)
    elif command_exists shasum; then
        actual_sha=$(shasum -a 256 "$file" | cut -d' ' -f1)
    else
        echo "❌ No SHA256 utility found (sha256sum or shasum)" >&2
        return 1
    fi

    if [ "$actual_sha" = "$expected_sha" ]; then
        echo "✅ SHA256 checksum verified: $expected_sha"
        return 0
    else
        echo "❌ SHA256 checksum mismatch!"
        echo "   Expected: $expected_sha"
        echo "   Actual:   $actual_sha"
        return 1
    fi
}

# Function to map platform to Zig platform string
map_to_zig_platform() {
    local platform="$1"

    case "$platform" in
        linux-x86_64) echo "x86_64-linux" ;;
        linux-aarch64) echo "aarch64-linux" ;;
        macos-x86_64) echo "x86_64-macos" ;;
        macos-aarch64) echo "aarch64-macos" ;;
        windows-x86_64) echo "x86_64-windows" ;;
        *) echo "$platform" ;;
    esac
}

# Function to install Zig using official download index
install_zig() {
    echo "📦 Installing Zig with checksum verification..."

    PLATFORM=$(detect_platform)
    ZIG_PLATFORM=$(map_to_zig_platform "$PLATFORM")
    ZIG_VERSION="0.14.1"
    ZIG_DIR="$HOME/.local/zig"

    # Fetch download index
    echo "🌐 Fetching Zig download index..."
    INDEX_JSON=$(curl -s "https://ziglang.org/download/index.json")
    if [ $? -ne 0 ] || [ -z "$INDEX_JSON" ]; then
        echo "❌ Failed to fetch Zig download index" >&2
        exit 1
    fi

    # Extract download information using basic JSON parsing
    # This uses grep and sed to extract the needed values from the JSON
    VERSION_SECTION=$(echo "$INDEX_JSON" | grep -A 50 "\"$ZIG_VERSION\":")
    if [ -z "$VERSION_SECTION" ]; then
        echo "❌ Version $ZIG_VERSION not found in download index" >&2
        exit 1
    fi

    PLATFORM_SECTION=$(echo "$VERSION_SECTION" | grep -A 10 "\"$ZIG_PLATFORM\":")
    if [ -z "$PLATFORM_SECTION" ]; then
        echo "❌ Platform $ZIG_PLATFORM not found for version $ZIG_VERSION" >&2
        exit 1
    fi

    # Extract tarball URL and shasum
    TARBALL_URL=$(echo "$PLATFORM_SECTION" | grep '"tarball":' | sed 's/.*"tarball": *"\([^"]*\)".*/\1/')
    EXPECTED_SHA=$(echo "$PLATFORM_SECTION" | grep '"shasum":' | sed 's/.*"shasum": *"\([^"]*\)".*/\1/')

    if [ -z "$TARBALL_URL" ] || [ -z "$EXPECTED_SHA" ]; then
        echo "❌ Failed to extract download URL or checksum from index" >&2
        exit 1
    fi

    echo "📥 Downloading Zig from: $TARBALL_URL"

    # Extract filename from URL
    TARBALL_NAME=$(basename "$TARBALL_URL")

    # Download tarball
    if ! curl -L "$TARBALL_URL" -o "/tmp/$TARBALL_NAME"; then
        echo "❌ Failed to download Zig tarball" >&2
        exit 1
    fi

    echo "✅ Downloaded Zig tarball"

    # Verify checksum
    echo "🔐 Verifying SHA256 checksum..."
    if ! verify_sha256 "/tmp/$TARBALL_NAME" "$EXPECTED_SHA"; then
        echo "❌ Checksum verification failed" >&2
        rm -f "/tmp/$TARBALL_NAME"
        exit 1
    fi

    # Extract Zig
    echo "📦 Extracting Zig..."
    mkdir -p "$HOME/.local"

    if [[ "$TARBALL_NAME" == *.zip ]]; then
        unzip "/tmp/$TARBALL_NAME" -d "/tmp/"
        mv "/tmp/zig-$ZIG_PLATFORM-$ZIG_VERSION" "$ZIG_DIR"
    else
        tar -xJ -f "/tmp/$TARBALL_NAME" -C "/tmp/"
        mv "/tmp/zig-$ZIG_PLATFORM-$ZIG_VERSION" "$ZIG_DIR"
    fi

    # Clean up
    rm -f "/tmp/$TARBALL_NAME"

    # Add to PATH for this session
    export PATH="$ZIG_DIR:$PATH"

    echo "✅ Zig installed successfully at $ZIG_DIR"
    echo "Successfully fetched Zig $ZIG_VERSION!"
}

# Check if Zig is available first
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
