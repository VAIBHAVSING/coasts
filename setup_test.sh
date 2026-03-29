#!/bin/bash
# Quick setup script for testing Phase 2

set -e

cd "$(dirname "$0")"

echo "=== Coast Phase 2 Test Setup ==="
echo ""

# Check if mutagen is installed
if ! command -v mutagen >/dev/null 2>&1; then
    echo "📦 Installing Mutagen..."
    ./install_mutagen.sh
    echo ""
else
    echo "✓ Mutagen already installed: $(mutagen version | head -1)"
fi

# Build coast if needed
if [ ! -f target/release/coast ]; then
    echo "🔨 Building Coast (release mode)..."
    cargo build --release
    echo ""
else
    echo "✓ Coast already built"
fi

# Set up PATH
export PATH="$HOME/.local/bin:$(pwd)/target/release:$PATH"

echo ""
echo "✓ Setup complete!"
echo ""
echo "Environment configured:"
echo "  Mutagen: $(which mutagen)"
echo "  Coast: $(which coast)"
echo ""
echo "To use in this shell session:"
echo "  export PATH=\"\$HOME/.local/bin:$(pwd)/target/release:\$PATH\""
echo ""
echo "Or add to your ~/.bashrc:"
echo "  echo 'export PATH=\"\$HOME/.local/bin:$(pwd)/target/release:\$PATH\"' >> ~/.bashrc"
echo ""
echo "Now you can run the test:"
echo "  ./test_sync_simple.sh user@your-vm-ip"
echo ""
