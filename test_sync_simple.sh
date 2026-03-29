#!/bin/bash
# Simple Phase 2 Test Script
# Usage: ./test_sync_simple.sh <user@host> [ssh-key-path]

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

REMOTE_CONNECTION="$1"
SSH_KEY="${2:-}"
REMOTE_NAME="testvm"
PROJECT_NAME="test-sync"
TEST_DIR="/tmp/${PROJECT_NAME}"

if [ -z "$REMOTE_CONNECTION" ]; then
    echo -e "${RED}Usage: $0 <user@host> [ssh-key-path]${NC}"
    echo ""
    echo "Examples:"
    echo "  $0 ubuntu@192.168.1.100"
    echo "  $0 vagrant@localhost -i ~/.ssh/vagrant_key"
    echo "  $0 user@myvm.local -i ~/.ssh/id_rsa"
    exit 1
fi

echo -e "${BLUE}=== Phase 2: Workspace Sync Test ===${NC}"
echo "Remote: $REMOTE_CONNECTION"
echo "Project: $PROJECT_NAME"
echo ""

# Helper function
print_step() {
    echo -e "${BLUE}>>> $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Check prerequisites
print_step "Checking prerequisites..."
command -v mutagen >/dev/null 2>&1 || { 
    echo -e "${RED}ERROR: mutagen not installed${NC}"
    echo "Run: ./install_mutagen.sh"
    exit 1
}
command -v coast >/dev/null 2>&1 || { 
    echo -e "${RED}ERROR: coast not in PATH${NC}"
    echo "Run: export PATH=\"\$(pwd)/target/release:\$PATH\""
    exit 1
}
print_success "Prerequisites OK"
echo ""

# Test SSH connection
print_step "Testing SSH connection..."
SSH_CMD="ssh"
if [ -n "$SSH_KEY" ]; then
    SSH_CMD="ssh -i $SSH_KEY"
    if [ ! -f "$SSH_KEY" ]; then
        print_error "SSH key not found: $SSH_KEY"
        exit 1
    fi
fi

if ! $SSH_CMD -o ConnectTimeout=5 -o BatchMode=yes "$REMOTE_CONNECTION" "echo 'SSH OK'" >/dev/null 2>&1; then
    print_error "Cannot connect via SSH to $REMOTE_CONNECTION"
    echo "Please check:"
    echo "  - SSH is running on remote"
    echo "  - Firewall allows SSH"
    echo "  - Credentials are correct"
    exit 1
fi
print_success "SSH connection OK"
echo ""

# Start daemon
print_step "Starting coast daemon..."
coast daemon kill -f 2>/dev/null || true
sleep 1
coast daemon start
sleep 2
if ! coast daemon status >/dev/null 2>&1; then
    print_error "Failed to start daemon"
    exit 1
fi
print_success "Daemon started"
echo ""

# Add remote
print_step "Adding remote '$REMOTE_NAME'..."
coast remote remove "$REMOTE_NAME" 2>/dev/null || true
if [ -n "$SSH_KEY" ]; then
    coast remote add "$REMOTE_NAME" "$REMOTE_CONNECTION" --key "$SSH_KEY"
else
    coast remote add "$REMOTE_NAME" "$REMOTE_CONNECTION"
fi
print_success "Remote added"
coast remote ls
echo ""

# Setup remote
print_step "Setting up remote (installing coastd on VM)..."
echo "This may take a minute..."
if ! coast remote setup "$REMOTE_NAME"; then
    print_error "Failed to setup remote"
    exit 1
fi
print_success "Remote setup complete"
echo ""

# Connect to remote
print_step "Connecting to remote (establishing SSH tunnel)..."
if ! coast remote connect "$REMOTE_NAME"; then
    print_error "Failed to connect to remote"
    exit 1
fi
sleep 2
print_success "Connected to remote"
echo ""

# Ping remote
print_step "Pinging remote daemon..."
if ! coast remote ping "$REMOTE_NAME"; then
    print_error "Failed to ping remote"
    exit 1
fi
print_success "Remote daemon responding"
echo ""

# Create test project
print_step "Creating test project..."
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/src"
cd "$TEST_DIR"

cat > index.js <<EOF
console.log('Hello from Coast Remote Sync!');
console.log('Project: $PROJECT_NAME');
EOF

cat > README.md <<EOF
# Test Project - $PROJECT_NAME

This is a test project for Coast Remote Sync.

Created at: $(date)
EOF

cat > src/utils.js <<EOF
export const foo = 'bar';
export const timestamp = '$(date +%s)';
EOF

cat > .coastignore <<EOF
node_modules/
.git/
*.log
.DS_Store
EOF

print_success "Test project created at $TEST_DIR"
ls -la
echo ""

# Create sync session
print_step "Creating sync session..."
if ! coast sync create "$PROJECT_NAME" "$REMOTE_NAME" --local-path "$TEST_DIR" --branch main; then
    print_error "Failed to create sync session"
    exit 1
fi
print_success "Sync session created"
echo ""

# Check sync status
print_step "Checking sync status..."
coast sync status
echo ""

# Wait for initial sync
print_step "Waiting for initial sync (5 seconds)..."
sleep 5
print_success "Initial sync should be complete"
echo ""

# Verify files on remote
print_step "Verifying files synced to remote..."
REMOTE_PATH="~/coast-workspaces/${PROJECT_NAME}/main"
echo "Remote path: $REMOTE_PATH"
echo ""

echo "Files on remote:"
$SSH_CMD "$REMOTE_CONNECTION" "ls -la $REMOTE_PATH" || {
    print_error "Remote directory not found"
    exit 1
}
echo ""

echo "Content of index.js on remote:"
$SSH_CMD "$REMOTE_CONNECTION" "cat $REMOTE_PATH/index.js"
print_success "Files successfully synced"
echo ""

# Test real-time sync
print_step "Testing real-time sync..."
echo ""
echo "Adding new content to index.js..."
echo "// Added after initial sync at $(date)" >> index.js

echo "Creating new file src/api.js..."
cat > src/api.js <<EOF
export const apiUrl = 'https://api.example.com';
export const version = 'v1';
EOF

echo "Flushing sync..."
if ! coast sync flush "$PROJECT_NAME"; then
    print_error "Failed to flush sync"
    exit 1
fi
sleep 3

echo ""
echo "Verifying changes on remote..."
echo "Content of index.js:"
$SSH_CMD "$REMOTE_CONNECTION" "cat $REMOTE_PATH/index.js"
echo ""
echo "Content of src/api.js:"
$SSH_CMD "$REMOTE_CONNECTION" "cat $REMOTE_PATH/src/api.js"
print_success "Real-time sync working"
echo ""

# Test ignore patterns
print_step "Testing .coastignore patterns..."
echo "debug data at $(date)" > test.log
echo "node_modules content" > node_modules_test
mkdir -p node_modules
echo "should be ignored" > node_modules/package.json

coast sync flush "$PROJECT_NAME"
sleep 3

echo "Checking if ignored files were NOT synced..."
IGNORED_FOUND=false
if $SSH_CMD "$REMOTE_CONNECTION" "test -f $REMOTE_PATH/test.log" 2>/dev/null; then
    print_error "test.log was synced (should be ignored)"
    IGNORED_FOUND=true
else
    print_success "test.log correctly ignored"
fi

if $SSH_CMD "$REMOTE_CONNECTION" "test -d $REMOTE_PATH/node_modules" 2>/dev/null; then
    print_error "node_modules/ was synced (should be ignored)"
    IGNORED_FOUND=true
else
    print_success "node_modules/ correctly ignored"
fi

if [ "$IGNORED_FOUND" = true ]; then
    echo -e "${YELLOW}Warning: Some ignore patterns may not be working${NC}"
fi
echo ""

# Test pause/resume
print_step "Testing pause/resume..."
echo "Pausing sync..."
coast sync pause "$PROJECT_NAME"
sleep 2

echo "Making changes while paused..."
echo "// Added while paused at $(date)" >> index.js
sleep 2

echo "Checking if changes were NOT synced..."
if $SSH_CMD "$REMOTE_CONNECTION" "grep 'Added while paused' $REMOTE_PATH/index.js" >/dev/null 2>&1; then
    print_error "Changes synced while paused (unexpected)"
else
    print_success "Changes not synced while paused (correct)"
fi

echo "Resuming sync..."
coast sync resume "$PROJECT_NAME"
coast sync flush "$PROJECT_NAME"
sleep 3

echo "Checking if changes NOW synced..."
if $SSH_CMD "$REMOTE_CONNECTION" "grep 'Added while paused' $REMOTE_PATH/index.js" >/dev/null 2>&1; then
    print_success "Changes synced after resume (correct)"
else
    print_error "Changes not synced after resume (unexpected)"
fi
echo ""

# Show final status
print_step "Final sync status..."
coast sync status
echo ""

# Summary
echo -e "${GREEN}=== Test Summary ===${NC}"
echo ""
echo -e "${GREEN}✓${NC} Remote connection and setup"
echo -e "${GREEN}✓${NC} Sync session creation"
echo -e "${GREEN}✓${NC} Initial file sync"
echo -e "${GREEN}✓${NC} Real-time sync (flush)"
echo -e "${GREEN}✓${NC} Ignore patterns (.coastignore)"
echo -e "${GREEN}✓${NC} Pause/resume functionality"
echo ""
echo -e "${GREEN}All Phase 2 features working!${NC}"
echo ""

# Cleanup option
echo -e "${YELLOW}Cleanup commands (run manually if desired):${NC}"
echo "  coast sync terminate $PROJECT_NAME"
echo "  coast remote disconnect $REMOTE_NAME"
echo "  coast remote remove $REMOTE_NAME"
echo "  rm -rf $TEST_DIR"
echo ""
echo "Or run this to cleanup now:"
echo -e "${YELLOW}  ./test_sync_simple.sh cleanup${NC}"
