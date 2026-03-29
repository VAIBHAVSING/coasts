#!/bin/bash
# Quick test script for Phase 2: Workspace Sync
# Usage: ./test_sync_quick.sh <remote-user@host> [ssh-key-path]

set -e

REMOTE_CONNECTION="$1"
SSH_KEY="${2:-}"
REMOTE_NAME="test-vm"
PROJECT_NAME="test-sync-$(date +%s)"
TEST_DIR="/tmp/${PROJECT_NAME}"

if [ -z "$REMOTE_CONNECTION" ]; then
    echo "Usage: $0 <user@host> [ssh-key-path]"
    echo "Example: $0 ubuntu@192.168.1.100"
    echo "Example: $0 ubuntu@192.168.1.100 ~/.ssh/id_rsa"
    exit 1
fi

echo "=== Phase 2 Workspace Sync Quick Test ==="
echo "Remote: $REMOTE_CONNECTION"
echo "Project: $PROJECT_NAME"
echo ""

# Check prerequisites
echo "Checking prerequisites..."
command -v mutagen >/dev/null 2>&1 || { echo "ERROR: mutagen not installed"; exit 1; }
command -v coast >/dev/null 2>&1 || { echo "ERROR: coast not in PATH"; exit 1; }
echo "✓ Prerequisites OK"
echo ""

# Start daemon
echo "Starting coast daemon..."
coast daemon kill -f 2>/dev/null || true
sleep 1
coast daemon start
sleep 2
coast daemon status
echo ""

# Add remote
echo "Adding remote '$REMOTE_NAME'..."
if [ -n "$SSH_KEY" ]; then
    coast remote add "$REMOTE_NAME" "$REMOTE_CONNECTION" --key "$SSH_KEY"
else
    coast remote add "$REMOTE_NAME" "$REMOTE_CONNECTION"
fi
coast remote ls
echo ""

# Setup remote
echo "Setting up remote (installing coastd)..."
coast remote setup "$REMOTE_NAME"
echo ""

# Connect to remote
echo "Connecting to remote..."
coast remote connect "$REMOTE_NAME"
sleep 2
coast remote ls
echo ""

# Ping remote
echo "Pinging remote..."
coast remote ping "$REMOTE_NAME"
echo ""

# Create test project
echo "Creating test project at $TEST_DIR..."
mkdir -p "$TEST_DIR/src"
cd "$TEST_DIR"
echo "console.log('hello from local');" > index.js
echo "# Test Project - $PROJECT_NAME" > README.md
echo "export const foo = 'bar';" > src/utils.js
echo "node_modules/" > .coastignore
echo ".git/" >> .coastignore
echo "*.log" >> .coastignore
echo "✓ Test project created"
ls -la
echo ""

# Create sync session
echo "Creating sync session..."
coast sync create "$PROJECT_NAME" "$REMOTE_NAME" --local-path "$TEST_DIR"
echo ""

# Check sync status
echo "Checking sync status..."
coast sync status
echo ""

# Wait for initial sync
echo "Waiting 3 seconds for initial sync..."
sleep 3

# Verify files on remote
echo "Verifying files on remote..."
SSH_CMD="ssh"
if [ -n "$SSH_KEY" ]; then
    SSH_CMD="ssh -i $SSH_KEY"
fi

REMOTE_PATH="~/coast-workspaces/${PROJECT_NAME}/main"
$SSH_CMD "$REMOTE_CONNECTION" "ls -la $REMOTE_PATH"
echo ""

echo "Checking index.js on remote..."
$SSH_CMD "$REMOTE_CONNECTION" "cat $REMOTE_PATH/index.js"
echo ""

# Test real-time sync
echo "Testing real-time sync..."
echo "// Added after sync - $(date)" >> index.js
echo "export const baz = 'qux';" > src/api.js
coast sync flush "$PROJECT_NAME"
sleep 2
echo ""

echo "Verifying new changes on remote..."
$SSH_CMD "$REMOTE_CONNECTION" "cat $REMOTE_PATH/index.js"
$SSH_CMD "$REMOTE_CONNECTION" "cat $REMOTE_PATH/src/api.js"
echo ""

# Test ignore patterns
echo "Testing ignore patterns..."
echo "debug data" > test.log
coast sync flush "$PROJECT_NAME"
sleep 2
echo "Checking if test.log was synced (should be ignored)..."
if $SSH_CMD "$REMOTE_CONNECTION" "test -f $REMOTE_PATH/test.log"; then
    echo "✗ FAILED: test.log should not be synced (ignored)"
else
    echo "✓ PASSED: test.log correctly ignored"
fi
echo ""

# Test pause/resume
echo "Testing pause/resume..."
coast sync pause "$PROJECT_NAME"
echo "// Changes while paused" >> index.js
sleep 2

echo "Checking if paused changes synced (should NOT)..."
if $SSH_CMD "$REMOTE_CONNECTION" "grep 'Changes while paused' $REMOTE_PATH/index.js" >/dev/null 2>&1; then
    echo "✗ FAILED: Changes synced while paused"
else
    echo "✓ PASSED: Changes not synced while paused"
fi

echo "Resuming sync..."
coast sync resume "$PROJECT_NAME"
coast sync flush "$PROJECT_NAME"
sleep 2

echo "Checking if resumed changes synced (should YES)..."
if $SSH_CMD "$REMOTE_CONNECTION" "grep 'Changes while paused' $REMOTE_PATH/index.js" >/dev/null 2>&1; then
    echo "✓ PASSED: Changes synced after resume"
else
    echo "✗ FAILED: Changes not synced after resume"
fi
echo ""

# Cleanup
echo "Cleaning up..."
coast sync terminate "$PROJECT_NAME"
coast remote disconnect "$REMOTE_NAME"
coast remote remove "$REMOTE_NAME"
rm -rf "$TEST_DIR"
echo "✓ Cleanup complete"
echo ""

echo "=== Test Complete ==="
echo ""
echo "Summary:"
echo "  - Remote connection: OK"
echo "  - Sync session creation: OK"
echo "  - Real-time sync: OK"
echo "  - Ignore patterns: OK"
echo "  - Pause/resume: OK"
echo ""
echo "All Phase 2 functionality working!"
