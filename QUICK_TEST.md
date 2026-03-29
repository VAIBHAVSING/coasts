# Quick Test Instructions - Phase 2 Sync

## Prerequisites

1. **Your VM details** - you need:
   - IP address or hostname (e.g., `192.168.1.100`)
   - SSH user (e.g., `ubuntu`, `vagrant`, `user`)
   - SSH key path (optional, e.g., `~/.ssh/id_rsa`)

2. **VM requirements**:
   - SSH server running
   - Bash shell available
   - ~50MB free disk space (for coastd + mutagen agent)

## Step-by-Step

### 1. Install Mutagen (first time only)

```bash
cd /home/vsing/code/osp/coasts
./install_mutagen.sh
export PATH="$HOME/.local/bin:$PATH"
```

Verify:
```bash
mutagen version
```

### 2. Build Coast

```bash
cd /home/vsing/code/osp/coasts
cargo build --release
export PATH="$(pwd)/target/release:$PATH"
```

Verify:
```bash
coast --version
```

### 3. Run the Test

Replace with your actual VM details:

```bash
# Example 1: Basic (uses default SSH key)
./test_sync_simple.sh ubuntu@192.168.1.100

# Example 2: With specific SSH key
./test_sync_simple.sh ubuntu@192.168.1.100 ~/.ssh/id_rsa

# Example 3: Vagrant VM
./test_sync_simple.sh vagrant@localhost ~/.vagrant.d/insecure_private_key

# Example 4: Custom port (if SSH is not on 22)
# Note: You'll need to modify the script or use SSH config
./test_sync_simple.sh user@myvm.local ~/.ssh/id_rsa
```

### 4. Watch the Output

The script will:
- ✅ Test SSH connection
- ✅ Start local daemon
- ✅ Add and setup remote
- ✅ Create sync session
- ✅ Verify file sync
- ✅ Test real-time updates
- ✅ Test ignore patterns
- ✅ Test pause/resume

Expected runtime: **2-3 minutes**

### 5. Manual Verification (optional)

While the test is running, you can SSH into your VM and watch:

```bash
# In another terminal:
ssh ubuntu@192.168.1.100

# Watch for the directory being created:
watch -n 1 ls -la ~/coast-workspaces/

# After sync starts, check the files:
ls -la ~/coast-workspaces/test-sync/main/
cat ~/coast-workspaces/test-sync/main/index.js
```

### 6. Cleanup

After testing, clean up:

```bash
coast sync terminate test-sync
coast remote disconnect testvm
coast remote remove testvm
rm -rf /tmp/test-sync
```

## Troubleshooting

### "mutagen: command not found"
```bash
./install_mutagen.sh
export PATH="$HOME/.local/bin:$PATH"
```

### "coast: command not found"
```bash
cargo build --release
export PATH="$(pwd)/target/release:$PATH"
```

### "Cannot connect via SSH"
Test SSH manually:
```bash
ssh ubuntu@192.168.1.100 "echo test"
```

If that fails, check:
- Is the VM running?
- Is SSH server running on VM? (`sudo systemctl status sshd`)
- Firewall blocking port 22?
- Correct username/key?

### "Failed to setup remote"
The setup command copies coastd to the VM. Check:
- Does user have write permission to `~/.coast/bin/`?
- Is there disk space on VM? (`df -h`)
- Can you manually SSH and create files?

### "Failed to create sync session"
Check mutagen:
```bash
mutagen daemon start
mutagen sync list
```

Check SSH config if using custom port:
```bash
# Add to ~/.ssh/config
Host myvm
    HostName 192.168.1.100
    User ubuntu
    Port 2222
    IdentityFile ~/.ssh/id_rsa

# Then use:
./test_sync_simple.sh ubuntu@myvm
```

## What Gets Tested

| Feature | What it tests |
|---------|---------------|
| Remote setup | Installs coastd on VM via SSH |
| Tunnel | SSH tunnel from localhost:31416 → VM:31415 |
| Sync create | Creates mutagen session, initial file sync |
| Real-time sync | Detects local changes, syncs to remote |
| Ignore patterns | .coastignore respected |
| Pause/resume | Can pause and resume sync |
| Status | Shows sync session info |

## Next Steps After Testing

If all tests pass, Phase 2 is complete! 

Next phases:
- **Phase 3**: Remote build/run (forward build commands to remote)
- **Phase 4**: Remote exec/logs (run commands on remote instances)
- **Phase 5**: Remote assign/unassign (instance lifecycle on remote)
- **Phase 6**: Port forwarding for remote instances

## Advanced: Manual Commands

Instead of the script, you can run commands manually:

```bash
# Start daemon
coast daemon start

# Add remote
coast remote add myvm ubuntu@192.168.1.100

# Setup (install coastd)
coast remote setup myvm

# Connect (SSH tunnel)
coast remote connect myvm

# Ping test
coast remote ping myvm

# Create sync (replace /path/to/code with your project)
coast sync create myproject myvm --local-path /path/to/code --branch main

# Check status
coast sync status

# Flush (force sync now)
coast sync flush myproject

# Pause
coast sync pause myproject

# Resume
coast sync resume myproject

# Terminate
coast sync terminate myproject

# Cleanup
coast remote disconnect myvm
coast remote remove myvm
```
