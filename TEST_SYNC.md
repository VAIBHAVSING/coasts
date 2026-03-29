# Manual Testing Guide: Phase 2 Workspace Sync

This guide walks through testing the Remote Coasts workspace sync functionality with a local VM.

## Prerequisites

1. **Mutagen installed locally**
   ```bash
   # On macOS:
   brew install mutagen-io/mutagen/mutagen
   
   # On Linux:
   curl -L https://github.com/mutagen-io/mutagen/releases/latest/download/mutagen_linux_amd64_v0.17.6.tar.gz | tar -xz
   sudo mv mutagen /usr/local/bin/
   mutagen daemon start
   ```

2. **SSH access to a VM**
   - VM hostname/IP (e.g., `192.168.1.100` or `dev-vm`)
   - SSH key configured (e.g., `~/.ssh/id_rsa`)
   - SSH user (e.g., `ubuntu`, `vagrant`, etc.)

3. **Coast built**
   ```bash
   cargo build --release
   export PATH="$(pwd)/target/release:$PATH"
   ```

## Test Scenario 1: Add Remote & Setup

### 1.1 Start the local daemon

```bash
# Kill any existing daemon
coast daemon kill -f

# Start fresh daemon
coast daemon start

# Verify it's running
coast daemon status
```

### 1.2 Add your VM as a remote

```bash
# Replace with your VM details:
# Format: coast remote add <name> <user@host>
coast remote add myvm user@192.168.1.100

# If using a specific SSH key:
coast remote add myvm user@192.168.1.100 --port 22 --key ~/.ssh/id_rsa

# List remotes to verify
coast remote ls
```

Expected output:
```
NAME    HOST                    PORT    KEY
myvm    user@192.168.1.100      22      ~/.ssh/id_rsa
```

### 1.3 Setup the remote (install coastd on VM)

```bash
coast remote setup myvm

# This should:
# - SSH into the VM
# - Install coastd binary
# - Set up the remote environment
```

Expected: Success message indicating remote daemon is installed.

### 1.4 Connect to the remote (establish SSH tunnel)

```bash
coast remote connect myvm

# This should:
# - Create SSH tunnel: localhost:31416 -> remote:31415
# - Start remote daemon if not running
```

Expected output:
```
Connected to remote 'myvm'
Tunnel established: localhost:31416 -> 192.168.1.100:31415
```

Verify tunnel:
```bash
# Check tunnel is active
coast remote ls
# Should show status as "connected"

# Verify you can ping the remote daemon
coast remote ping myvm
```

Expected ping output:
```
Pong from myvm (latency: ~X ms)
Remote daemon version: vX.X.X
```

## Test Scenario 2: Create Sync Session

### 2.1 Create a test project directory

```bash
# Create a test project
mkdir -p /tmp/test-sync-project
cd /tmp/test-sync-project

# Add some test files
echo "console.log('hello from local');" > index.js
echo "# Test Project" > README.md
mkdir src
echo "export const foo = 'bar';" > src/utils.js

# Optionally add .coastignore
echo "node_modules/" > .coastignore
echo ".git/" >> .coastignore
echo "*.log" >> .coastignore
```

### 2.2 Create a sync session

```bash
coast sync create \
  --project test-sync-project \
  --branch main \
  --remote myvm \
  --local-path /tmp/test-sync-project

# Alternative shorter form:
coast sync create test-sync-project myvm --local-path /tmp/test-sync-project
```

Expected output:
```
Sync session created: /tmp/test-sync-project → ~/coast-workspaces/test-sync-project/main
Session name: coast-test-sync-project-main-myvm
Status: Syncing
```

### 2.3 Verify sync is active

```bash
# Check sync status
coast sync status

# Or for specific project:
coast sync status test-sync-project
```

Expected output:
```
PROJECT                REMOTE    STATUS                      LAST SYNC
test-sync-project      myvm      Watching for changes        Just now
```

### 2.4 Verify files on remote

SSH into your VM and check:
```bash
ssh user@192.168.1.100
ls -la ~/coast-workspaces/test-sync-project/main/
cat ~/coast-workspaces/test-sync-project/main/index.js
```

You should see all the files you created locally!

## Test Scenario 3: Real-time Sync

### 3.1 Make local changes

```bash
# In your local /tmp/test-sync-project directory:
echo "// Added after sync" >> index.js
echo "export const baz = 'qux';" > src/api.js
```

### 3.2 Flush sync (force immediate sync)

```bash
coast sync flush test-sync-project
```

Expected:
```
Sync flushed for project 'test-sync-project'
```

### 3.3 Verify changes on remote

```bash
ssh user@192.168.1.100 "cat ~/coast-workspaces/test-sync-project/main/index.js"
ssh user@192.168.1.100 "cat ~/coast-workspaces/test-sync-project/main/src/api.js"
```

You should see the new changes!

### 3.4 Test ignore patterns

```bash
# Create a file that should be ignored
echo "debug data" > test.log
coast sync flush test-sync-project

# Verify it's NOT synced
ssh user@192.168.1.100 "ls ~/coast-workspaces/test-sync-project/main/ | grep test.log"
# Should return nothing (file not synced)
```

## Test Scenario 4: Pause/Resume

### 4.1 Pause sync

```bash
coast sync pause test-sync-project
```

Expected:
```
Sync paused for project 'test-sync-project'
```

### 4.2 Make changes while paused

```bash
echo "// Changes while paused" >> index.js
```

### 4.3 Verify changes NOT synced

```bash
ssh user@192.168.1.100 "cat ~/coast-workspaces/test-sync-project/main/index.js"
# Should NOT contain "Changes while paused"
```

### 4.4 Resume sync

```bash
coast sync resume test-sync-project
coast sync flush test-sync-project
```

### 4.5 Verify changes now synced

```bash
ssh user@192.168.1.100 "cat ~/coast-workspaces/test-sync-project/main/index.js"
# Should now contain "Changes while paused"
```

## Test Scenario 5: Multiple Projects

### 5.1 Create second project

```bash
mkdir -p /tmp/another-project
cd /tmp/another-project
echo "# Another Project" > README.md
```

### 5.2 Create second sync session

```bash
coast sync create another-project myvm --local-path /tmp/another-project
```

### 5.3 List all sync sessions

```bash
coast sync status
```

Expected output:
```
PROJECT                REMOTE    STATUS                      LAST SYNC
test-sync-project      myvm      Watching for changes        2 minutes ago
another-project        myvm      Watching for changes        Just now
```

### 5.4 Verify both projects on remote

```bash
ssh user@192.168.1.100 "ls -la ~/coast-workspaces/"
# Should see both: test-sync-project/ and another-project/
```

## Test Scenario 6: Cleanup

### 6.1 Terminate sync sessions

```bash
coast sync terminate test-sync-project
coast sync terminate another-project
```

Expected:
```
Sync session terminated for project 'test-sync-project'
Sync session terminated for project 'another-project'
```

### 6.2 Verify sessions removed

```bash
coast sync status
# Should show empty or "No sync sessions"

# Verify with mutagen directly
mutagen sync list
# Should show no coast-* sessions
```

### 6.3 Disconnect from remote

```bash
coast remote disconnect myvm
```

Expected:
```
Disconnected from remote 'myvm'
Tunnel closed
```

### 6.4 Remove remote

```bash
coast remote remove myvm
```

Expected:
```
Remote 'myvm' removed
```

## Troubleshooting

### Check Mutagen daemon

```bash
mutagen daemon start
mutagen sync list
```

### Check Coast daemon logs

```bash
coast daemon logs
```

### Check SSH connectivity

```bash
ssh -v user@192.168.1.100 "echo 'SSH works'"
```

### Check remote daemon

```bash
ssh user@192.168.1.100 "~/.coast/bin/coastd --version"
ssh user@192.168.1.100 "ps aux | grep coastd"
```

### Manual mutagen session inspection

```bash
# List all mutagen sessions
mutagen sync list

# Monitor a specific session
mutagen sync monitor coast-test-sync-project-main-myvm
```

## Expected File Structure on Remote

After sync, on the VM you should have:

```
~/coast-workspaces/
├── test-sync-project/
│   └── main/
│       ├── index.js
│       ├── README.md
│       └── src/
│           ├── utils.js
│           └── api.js
└── another-project/
    └── main/
        └── README.md
```

## Success Criteria

- ✅ Remote can be added, setup, and connected
- ✅ Sync session can be created and files appear on remote
- ✅ Real-time changes sync automatically (after flush)
- ✅ Ignore patterns work (.coastignore respected)
- ✅ Pause/resume controls sync correctly
- ✅ Multiple projects can sync simultaneously
- ✅ Terminate cleans up session properly
- ✅ Disconnect/remove remote works cleanly

## Known Limitations (Phase 2)

- Sync is **one-way only** (local → remote). Changes on remote won't sync back.
- Need to manually specify `--local-path` (we can improve this in future phases)
- Remote build/run not yet implemented (Phase 3)
