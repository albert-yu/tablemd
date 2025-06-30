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

# Function to shuffle lines in a string
shuffle_lines() {
    echo "$1" | shuf
}

# Function to install minisign
install_minisign() {
    echo "📦 Installing minisign..."

    PLATFORM=$(detect_platform)
    MINISIGN_VERSION="0.12"
    MINISIGN_DIR="$HOME/.local/minisign"

    mkdir -p "$HOME/.local"

    case "$PLATFORM" in
        linux-x86_64)
            MINISIGN_URL="https://github.com/jedisct1/minisign/releases/download/$MINISIGN_VERSION/minisign-$MINISIGN_VERSION-linux.tar.gz"
            curl -L "$MINISIGN_URL" | tar -xz -C "/tmp/"
            mkdir -p "$MINISIGN_DIR"
            mv "/tmp/minisign-linux/x86_64/minisign" "$MINISIGN_DIR/"
            ;;
        macos-*)
            MINISIGN_URL="https://github.com/jedisct1/minisign/releases/download/$MINISIGN_VERSION/minisign-$MINISIGN_VERSION-macos.zip"
            curl -L "$MINISIGN_URL" -o "/tmp/minisign.zip"
            unzip "/tmp/minisign.zip" -d "/tmp/"
            mkdir -p "$MINISIGN_DIR"
            mv "/tmp/minisign-macos/minisign" "$MINISIGN_DIR/"
            rm "/tmp/minisign.zip"
            ;;
        windows-*)
            MINISIGN_URL="https://github.com/jedisct1/minisign/releases/download/$MINISIGN_VERSION/minisign-$MINISIGN_VERSION-win64.zip"
            curl -L "$MINISIGN_URL" -o "/tmp/minisign.zip"
            unzip "/tmp/minisign.zip" -d "/tmp/"
            mkdir -p "$MINISIGN_DIR"
            mv "/tmp/minisign-win64/minisign.exe" "$MINISIGN_DIR/"
            rm "/tmp/minisign.zip"
            ;;
        *)
            echo "❌ Unsupported platform for minisign: $PLATFORM" >&2
            exit 1
            ;;
    esac

    # Add to PATH for this session
    export PATH="$MINISIGN_DIR:$PATH"

    # Verify minisign installation
    if ! command_exists minisign; then
        echo "❌ Failed to install minisign" >&2
        exit 1
    fi

    echo "✅ Minisign installed successfully at $MINISIGN_DIR"
}

# Function to verify minisign signature
minisign_verify() {
    local file="$1"
    local pubkey="$2"

    # Verify signature using public key directly
    if minisign -Vm "$file" -P "$pubkey"; then
        return 0
    else
        return 1
    fi
}

# Function to install Zig using community mirrors
install_zig() {
    echo "📦 Installing Zig with signature verification..."

    PLATFORM=$(detect_platform)
    ZIG_VERSION="0.14.1"

    case "$PLATFORM" in
        linux-*|macos-*)
            TARBALL_NAME="zig-$PLATFORM-$ZIG_VERSION.tar.xz"
            ;;
        windows-*)
            TARBALL_NAME="zig-$PLATFORM-$ZIG_VERSION.zip"
            ;;
    esac

    ZIG_DIR="$HOME/.local/zig"

    # Get community mirrors
    echo "🌐 Fetching community mirrors..."
    MIRRORS=$(curl -s "https://ziglang.org/download/community-mirrors.txt")
    if [ $? -ne 0 ] || [ -z "$MIRRORS" ]; then
        echo "❌ Failed to fetch community mirrors" >&2
        exit 1
    fi

    # Shuffle mirrors for load balancing
    SHUFFLED_MIRRORS=$(shuffle_lines "$MIRRORS")

    # Try each mirror until we get a verified download
    echo "🔄 Trying mirrors for Zig download..."
    SUCCESS=false

    while IFS= read -r mirror_url; do
        # Skip empty lines
        [ -z "$mirror_url" ] && continue

        echo "🌐 Trying mirror: $mirror_url"

        # Download tarball
        TARBALL_URL="${mirror_url}/${TARBALL_NAME}?source=tablemd_automation"
        if curl -L "$TARBALL_URL" -o "/tmp/$TARBALL_NAME" 2>/dev/null; then
            echo "✅ Downloaded tarball from $mirror_url"

            # Download signature
            SIGNATURE_URL="${mirror_url}/${TARBALL_NAME}.minisig?source=tablemd_automation"
            if curl -L "$SIGNATURE_URL" -o "/tmp/$TARBALL_NAME.minisig" 2>/dev/null; then
                echo "✅ Downloaded signature from $mirror_url"

                # Verify signature
                echo "🔐 Verifying signature..."
                if minisign_verify "/tmp/$TARBALL_NAME" "$ZIG_PUB_KEY"; then
                    echo "✅ Signature verification successful!"
                    SUCCESS=true
                    break
                else
                    echo "❌ Signature verification failed for $mirror_url"
                    rm -f "/tmp/$TARBALL_NAME"
                fi
            else
                echo "❌ Failed to download signature from $mirror_url"
                rm -f "/tmp/$TARBALL_NAME"
            fi
        else
            echo "❌ Failed to download tarball from $mirror_url"
        fi
    done <<< "$SHUFFLED_MIRRORS"

    if [ "$SUCCESS" != "true" ]; then
        echo "❌ Failed to download and verify Zig from any mirror" >&2
        exit 1
    fi

    # Extract Zig
    echo "📦 Extracting Zig..."
    mkdir -p "$HOME/.local"

    if [[ "$TARBALL_NAME" == *.zip ]]; then
        unzip "/tmp/$TARBALL_NAME" -d "/tmp/"
        mv "/tmp/zig-$PLATFORM-$ZIG_VERSION" "$ZIG_DIR"
    else
        tar -xJ -f "/tmp/$TARBALL_NAME" -C "/tmp/"
        mv "/tmp/zig-$PLATFORM-$ZIG_VERSION" "$ZIG_DIR"
    fi

    # Clean up
    rm -f "/tmp/$TARBALL_NAME" "/tmp/$TARBALL_NAME.minisig"

    # Add to PATH for this session
    export PATH="$ZIG_DIR:$PATH"

    echo "✅ Zig installed successfully at $ZIG_DIR"
    echo "Successfully fetched Zig 0.14.1!"
}

# Check if Zig is available first
if command_exists zig; then
    echo "✅ Zig is already available"
    zig version
else
    echo "❌ Zig not found, installing..."

    # Check required environment variables
    if [ -z "$ZIG_PUB_KEY" ]; then
        echo "❌ Error: ZIG_PUB_KEY environment variable is required" >&2
        exit 1
    fi

    if [ -z "$MINISIGN_PUB_KEY" ]; then
        echo "❌ Error: MINISIGN_PUB_KEY environment variable is required" >&2
        exit 1
    fi

    # Install minisign if not available (needed for Zig verification)
    if command_exists minisign; then
        echo "✅ Minisign is already available"
    else
        echo "❌ Minisign not found, installing..."
        install_minisign
    fi

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
