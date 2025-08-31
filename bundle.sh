#!/bin/bash

set -e

echo "🚀 Starting bundle process..."

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install minisign if not available
ensure_minisign() {
    if ! command_exists minisign; then
        echo "📦 Installing minisign for signature verification..."

        # Detect OS and install minisign
        OS=$(uname -s)
        case "$OS" in
            Linux*)
                if command_exists apt-get; then
                    sudo apt-get update && sudo apt-get install -y minisign
                elif command_exists yum; then
                    sudo yum install -y minisign
                elif command_exists pacman; then
                    sudo pacman -S --noconfirm minisign
                else
                    echo "❌ Cannot install minisign automatically on this Linux distribution" >&2
                    echo "Please install minisign manually and re-run this script" >&2
                    exit 1
                fi
                ;;
            Darwin*)
                if command_exists brew; then
                    brew install minisign
                else
                    echo "❌ Please install Homebrew or minisign manually" >&2
                    exit 1
                fi
                ;;
            *)
                echo "❌ Cannot install minisign automatically on $OS" >&2
                echo "Please install minisign manually and re-run this script" >&2
                exit 1
                ;;
        esac

        # Verify minisign is now available
        if ! command_exists minisign; then
            echo "❌ Failed to install minisign" >&2
            exit 1
        fi

        echo "✅ minisign installed successfully"
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

# Function to verify minisign signature
verify_minisign() {
    local tarball="$1"
    local signature="$2"
    local pubkey="$3"

    echo "🔐 Verifying minisign signature..."
 
    if minisign -V -m "$tarball" -s "$signature" -P "$pubkey" >/dev/null 2>&1; then
        echo "✅ Minisign signature verified successfully"
        return 0
    else
        echo "❌ Minisign signature verification failed!"
        return 1
    fi
}

# Function to shuffle lines from input
shuffle_lines() {
    local input="$1"
    echo "$input" | shuf 2>/dev/null || echo "$input" | perl -MList::Util=shuffle -e 'print shuffle(<STDIN>);' 2>/dev/null || echo "$input"
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

# Function to install Zig using community mirrors and minisign verification
install_zig() {
    echo "📦 Installing Zig with minisign signature verification..."

    PLATFORM=$(detect_platform)
    ZIG_PLATFORM=$(map_to_zig_platform "$PLATFORM")
    ZIG_VERSION="0.14.1"
    ZIG_DIR="$HOME/.local/zig"

    # Zig's official public key for minisign verification
    PUBKEY="RWSGOq2NVecA2UPNdBUZykf1CCb147pkmdtYxgb3Ti+JO/wCYvhbAb/U"

    # Construct tarball name
    TARBALL_NAME="zig-$ZIG_PLATFORM-$ZIG_VERSION.tar.xz"

    # Fetch community mirrors list
    echo "🌐 Fetching community mirrors..."
    MIRRORS=$(curl -s "https://ziglang.org/download/community-mirrors.txt")
    if [ $? -ne 0 ] || [ -z "$MIRRORS" ]; then
        echo "❌ Failed to fetch community mirrors list" >&2
        exit 1
    fi

    # Shuffle mirrors for load balancing
    echo "🔀 Shuffling mirrors for load balancing..."
    SHUFFLED_MIRRORS=$(shuffle_lines "$MIRRORS")

    # Try each mirror in shuffled order
    SUCCESS=false
    for MIRROR_URL in $SHUFFLED_MIRRORS; do
        # Skip empty lines
        [ -z "$MIRROR_URL" ] && continue

        echo "📥 Trying mirror: $MIRROR_URL"

        # Download tarball with source parameter
        TARBALL_URL="${MIRROR_URL}/${TARBALL_NAME}?source=tablemd_automation"
        if curl -L "$TARBALL_URL" -o "/tmp/$TARBALL_NAME" --connect-timeout 10 --max-time 60; then
            echo "✅ Downloaded tarball from $MIRROR_URL"

            # Download signature
            SIGNATURE_URL="${MIRROR_URL}/${TARBALL_NAME}.minisig?source=tablemd_automation"
            if curl -L "$SIGNATURE_URL" -o "/tmp/$TARBALL_NAME.minisig" --connect-timeout 10 --max-time 30; then
                echo "✅ Downloaded signature from $MIRROR_URL"

                # Verify signature
                if verify_minisign "/tmp/$TARBALL_NAME" "/tmp/$TARBALL_NAME.minisig" "$PUBKEY"; then
                    echo "✅ Signature verification passed for $MIRROR_URL"
                    SUCCESS=true
                    break
                else
                    echo "❌ Signature verification failed for $MIRROR_URL, trying next mirror..."
                    rm -f "/tmp/$TARBALL_NAME" "/tmp/$TARBALL_NAME.minisig"
                fi
            else
                echo "❌ Failed to download signature from $MIRROR_URL, trying next mirror..."
                rm -f "/tmp/$TARBALL_NAME"
            fi
        else
            echo "❌ Failed to download tarball from $MIRROR_URL, trying next mirror..."
        fi
    done

    if [ "$SUCCESS" = false ]; then
        echo "❌ Failed to download and verify Zig from any mirror" >&2
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
    rm -f "/tmp/$TARBALL_NAME" "/tmp/$TARBALL_NAME.minisig"

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
    # Ensure minisign is available for signature verification
    ensure_minisign

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
