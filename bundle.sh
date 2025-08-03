#!/bin/bash

set -e

echo "🚀 Starting bundle process..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install jq if not available
ensure_jq() {
    if ! command_exists jq; then
        echo "📦 Installing jq for JSON parsing..."

        # Detect OS and install jq
        OS=$(uname -s)
        case "$OS" in
            Linux*)
                if command_exists apt-get; then
                    sudo apt-get update && sudo apt-get install -y jq
                elif command_exists yum; then
                    sudo yum install -y jq
                elif command_exists pacman; then
                    sudo pacman -S --noconfirm jq
                else
                    echo "❌ Cannot install jq automatically on this Linux distribution" >&2
                    echo "Please install jq manually and re-run this script" >&2
                    exit 1
                fi
                ;;
            Darwin*)
                if command_exists brew; then
                    brew install jq
                else
                    echo "❌ Please install Homebrew or jq manually" >&2
                    exit 1
                fi
                ;;
            *)
                echo "❌ Cannot install jq automatically on $OS" >&2
                echo "Please install jq manually and re-run this script" >&2
                exit 1
                ;;
        esac

        # Verify jq is now available
        if ! command_exists jq; then
            echo "❌ Failed to install jq" >&2
            exit 1
        fi

        echo "✅ jq installed successfully"
    fi
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

    # Extract download information using jq
    echo "🔍 Parsing download information with jq..."

    # Check if version exists
    if ! echo "$INDEX_JSON" | jq -e ".\"$ZIG_VERSION\"" >/dev/null 2>&1; then
        echo "❌ Version $ZIG_VERSION not found in download index" >&2
        exit 1
    fi

    # Check if platform exists for this version
    if ! echo "$INDEX_JSON" | jq -e ".\"$ZIG_VERSION\".\"$ZIG_PLATFORM\"" >/dev/null 2>&1; then
        echo "❌ Platform $ZIG_PLATFORM not found for version $ZIG_VERSION" >&2
        exit 1
    fi

    # Extract tarball URL and shasum using jq
    TARBALL_URL=$(echo "$INDEX_JSON" | jq -r ".\"$ZIG_VERSION\".\"$ZIG_PLATFORM\".tarball")
    EXPECTED_SHA=$(echo "$INDEX_JSON" | jq -r ".\"$ZIG_VERSION\".\"$ZIG_PLATFORM\".shasum")

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
    # Ensure jq is available for JSON parsing
    ensure_jq

    install_zig
fi

# Verify Zig is now available
if ! command_exists zig; then
    echo "❌ Failed to install or find Zig" >&2
    exit 1
fi

echo "🔨 Building with Zig..."
zig build -Dtarget=wasm32-emscripten --release=safe

# Check if build was successful
if [ ! -d "zig-out/web" ]; then
    echo "❌ Build failed - zig-out/web directory not found" >&2
    exit 1
fi

echo "📁 Creating dist directory..."
mkdir -p dist
mkdir -p dist/assets

echo "📋 Copying build artifacts to dist..."
cp -r zig-out/web/* dist/
cp -r src/web/assets/* dist/assets/

echo "✅ Bundle process completed successfully!"
echo "📦 Build artifacts copied to dist/"

echo "Renaming dist/root.html to dist/index.html..."
mv dist/root.html dist/index.html

# List contents of dist for verification
echo "📋 Contents of dist/:"
ls -la dist/
