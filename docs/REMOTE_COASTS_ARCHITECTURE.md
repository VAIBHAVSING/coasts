# Remote Coasts Architecture

This document describes how Remote Coasts works - the ability to run coast development environments on remote VMs instead of locally.

## Overview

When remote mode is enabled for a project:
- Your **local `coast-dev` daemon** stays in control
- It opens an **SSH tunnel** to the remote VM
- It syncs project files to the VM with **Mutagen**
- `coast-dev build` and `coast-dev run` execute on the VM
- `coast-dev exec` runs commands inside containers running on the VM

You use local commands, but execution happens remotely.

---

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                    LOCAL MACHINE                                         │
│                                                                                          │
│  ┌─────────────┐         ┌──────────────────────────────────────────────────────────┐   │
│  │             │         │                   LOCAL DAEMON (coastd-dev)               │   │
│  │  coast-dev  │ Unix    │                                                          │   │
│  │    CLI      │ Socket  │  ┌─────────────┐    ┌─────────────────────────────────┐  │   │
│  │             │────────▶│  │   Request   │    │        Request Router           │  │   │
│  │ - build     │         │  │   Handler   │───▶│                                 │  │   │
│  │ - run       │         │  └─────────────┘    │  1. Check instance.remote_name  │  │   │
│  │ - exec      │         │                     │  2. If remote → forward via     │  │   │
│  │ - logs      │         │                     │     SSH tunnel                  │  │   │
│  │ - stop/rm   │         │                     │  3. If local → execute locally  │  │   │
│  └─────────────┘         │                     └──────────────┬──────────────────┘  │   │
│                          │                                    │                      │   │
│                          │         ┌──────────────────────────┼───────────────┐      │   │
│                          │         │                          │               │      │   │
│                          │         ▼                          ▼               │      │   │
│                          │  ┌─────────────┐           ┌───────────────┐       │      │   │
│                          │  │   LOCAL     │           │    TUNNEL     │       │      │   │
│                          │  │  EXECUTION  │           │   MANAGER     │       │      │   │
│                          │  │             │           │               │       │      │   │
│                          │  │ Docker API  │           │ SSH Tunnels   │       │      │   │
│                          │  └─────────────┘           │ (in-memory)   │       │      │   │
│                          │                            └───────┬───────┘       │      │   │
│                          │                                    │               │      │   │
│                          │  ┌─────────────┐                   │               │      │   │
│                          │  │  State DB   │                   │               │      │   │
│                          │  │ ~/.coast-dev/state.db           │               │      │   │
│                          │  │             │                   │               │      │   │
│                          │  │ - instances │◀──────────────────┘               │      │   │
│                          │  │   (shadow)  │  Shadow instance created          │      │   │
│                          │  │ - tunnels   │  after remote run with            │      │   │
│                          │  │ - remotes   │  remote_name set                  │      │   │
│                          │  │ - sync_sess │                                   │      │   │
│                          │  └─────────────┘                                   │      │   │
│                          └────────────────────────────────────────────────────┘      │   │
│                                                                                       │   │
│  ┌─────────────────────┐                                                              │   │
│  │   MUTAGEN DAEMON    │  File sync (local → remote)                                  │   │
│  │                     │  One-way-safe mode                                           │   │
│  │  ~/project/src ─────┼──────────────────────────────────────┐                       │   │
│  └─────────────────────┘                                      │                       │   │
│                                                               │                       │   │
└───────────────────────────────────────────────────────────────┼───────────────────────┘
                                                                │
                         SSH TUNNEL (port forwarding)           │  MUTAGEN SYNC
                         localhost:31417 ──────────────────┐    │  (rsync-like)
                                                           │    │
                                                           │    │
┌──────────────────────────────────────────────────────────┼────┼───────────────────────┐
│                                   REMOTE VM              │    │                        │
│                                                          │    │                        │
│                                                          ▼    ▼                        │
│  ┌───────────────────────────────────────────────────────────────────────────────┐    │
│  │                         REMOTE DAEMON (coastd-dev)                             │    │
│  │                                                                                │    │
│  │   ~/.coast-dev/coastd.sock ◀─── SSH Tunnel ◀─── localhost:31417               │    │
│  │                                                                                │    │
│  │   ┌─────────────┐     ┌─────────────┐     ┌─────────────────────────────┐     │    │
│  │   │   Request   │     │  Handlers   │     │        Docker API           │     │    │
│  │   │   Parser    │────▶│             │────▶│                             │     │    │
│  │   └─────────────┘     │ - build     │     │  docker build/run/exec/...  │     │    │
│  │                       │ - run       │     └──────────────┬──────────────┘     │    │
│  │                       │ - exec      │                    │                    │    │
│  │                       │ - logs      │                    ▼                    │    │
│  │                       │ - stop/rm   │     ┌─────────────────────────────┐     │    │
│  │                       └─────────────┘     │      Docker Containers      │     │    │
│  │                                           │                             │     │    │
│  │   ┌─────────────┐                         │  ┌───────────────────────┐  │     │    │
│  │   │  State DB   │                         │  │ crm-demo-coasts-test1 │  │     │    │
│  │   │ (remote)    │                         │  │   (coast container)   │  │     │    │
│  │   │             │                         │  │                       │  │     │    │
│  │   │ - instances │                         │  │  ┌─────────────────┐  │  │     │    │
│  │   │ - builds    │                         │  │  │ docker-compose  │  │  │     │    │
│  │   │ - ports     │                         │  │  │    services     │  │  │     │    │
│  │   └─────────────┘                         │  │  │  (backend, db)  │  │  │     │    │
│  │                                           │  │  └─────────────────┘  │  │     │    │
│  └───────────────────────────────────────────│──└───────────────────────┘──│─────┘    │
│                                              │                             │          │
│   ~/coast-workspaces/                        │  Shared Services            │          │
│     └── crm-demo/                            │  ┌───────────────────────┐  │          │
│           └── main/  ◀─── Mutagen Sync       │  │ postgres, redis, etc │  │          │
│                 └── (project files)          │  └───────────────────────┘  │          │
│                                              └─────────────────────────────┘          │
└───────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Request Flow Examples

### Example 1: `coast-dev exec test1 -- echo "hello"`

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  1. CLI sends ExecRequest to local daemon                                               │
│  2. Local daemon checks: instance "test1" has remote_name="myvm"                        │
│  3. Local daemon looks up tunnel for "myvm" → port 31417                                │
│  4. Local daemon forwards request via TCP to localhost:31417                            │
│  5. SSH tunnel forwards to remote:~/.coast-dev/coastd.sock                              │
│  6. Remote daemon receives ExecRequest                                                  │
│  7. Remote daemon looks up container_id from its state.db                               │
│  8. Remote daemon runs: docker exec <container_id> echo "hello"                         │
│  9. Response flows back through tunnel to local daemon to CLI                           │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Example 2: `coast-dev build` (in remote mode)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  1. CLI sends BuildRequest to local daemon                                              │
│  2. Local daemon checks project_modes table: project="crm-demo" mode="remote"           │
│  3. Local daemon flushes Mutagen sync (ensures files are on remote)                     │
│  4. Local daemon forwards BuildRequest via SSH tunnel                                   │
│  5. Remote daemon builds using files in ~/coast-workspaces/crm-demo/main/               │
│  6. Build progress streams back through tunnel                                          │
│  7. Build artifacts stored on remote                                                    │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

### Example 3: `coast-dev run test1` (in remote mode)

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  1. CLI sends RunRequest to local daemon                                                │
│  2. Local daemon checks project mode → remote                                           │
│  3. Local daemon forwards RunRequest via SSH tunnel                                     │
│  4. Remote daemon creates container, stores in its state.db                             │
│  5. Response returns with instance info                                                 │
│  6. Local daemon creates "shadow" instance record with remote_name="myvm"               │
│     (This enables future exec/logs/stop to be routed correctly)                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Data Structures

### Local State DB (`~/.coast-dev/state.db`)

#### `instances` table (shadow records for remote instances)

| name  | project  | status  | remote_name | container_id |
|-------|----------|---------|-------------|--------------|
| test1 | crm-demo | running | myvm        | (empty)      |

> **Note:** Shadow records have `remote_name` set but no `container_id`. This tells the router to forward requests to the remote.

#### `remotes` table

| name | host            | port | ssh_key_path        |
|------|-----------------|------|---------------------|
| myvm | 192.168.122.139 | 22   | ~/.ssh/coast_vm_key |

#### `tunnels` table

| remote | local_port | ssh_pid | status    |
|--------|------------|---------|-----------|
| myvm   | 31417      | 105023  | connected |

#### `project_modes` table

| project  | mode   | remote_name |
|----------|--------|-------------|
| crm-demo | remote | myvm        |

#### `sync_sessions` table

| project  | remote_name | local_path               | remote_path          |
|----------|-------------|--------------------------|----------------------|
| crm-demo | myvm        | /home/user/code/crm-demo | ~/coast-workspaces/  |

### Remote State DB (`~/.coast-dev/state.db` on VM)

#### `instances` table (actual container records)

| name  | project  | status  | remote_name | container_id                             |
|-------|----------|---------|-------------|------------------------------------------|
| test1 | crm-demo | running | (null)      | 21e52136e4aebc9f99503e51ddd69a535c04... |

> **Note:** Remote instances have the actual Docker `container_id` and no `remote_name` (they are local to that machine).

---

## Component Summary

| Component | Purpose |
|-----------|---------|
| **Local Daemon** | Routes requests based on `remote_name` field |
| **SSH Tunnel** | Forwards TCP (localhost:31417) → Remote Unix socket |
| **Mutagen** | Syncs project files local → remote (one-way-safe) |
| **Shadow Instance** | Local DB record with `remote_name` set, no `container_id` |
| **Remote Daemon** | Executes actual Docker operations |
| **Remote Instance** | Full DB record with actual `container_id` |

---

## Routing Logic

### For `build` and `run` commands

Routes based on **project mode** (from `project_modes` table):

```
if project_modes[project].mode == "remote":
    forward to remote daemon via tunnel
else:
    execute locally
```

### For `exec`, `logs`, `stop`, `start`, `rm` commands

Routes based on **instance location** (from `instances` table):

```
if instances[name].remote_name is not None:
    forward to remote daemon via tunnel
else:
    execute locally
```

---

## SSH Tunnel Details

The tunnel forwards a local TCP port to the remote daemon's Unix socket:

```bash
ssh -N -L 31417:/home/ubuntu/.coast-dev/coastd.sock ubuntu@192.168.122.139
```

- **Local side:** TCP port 31417 on localhost
- **Remote side:** Unix socket at `~/.coast-dev/coastd.sock`
- **Protocol:** JSON-over-newline (same as local Unix socket)

---

## Mutagen Sync Details

File synchronization uses Mutagen in one-way-safe mode:

- **Direction:** Local → Remote only
- **Mode:** `one-way-safe` (prevents accidental remote overwrites)
- **Scope:** Active worktree only (e.g., `main` branch)

```bash
mutagen sync create \
  --name "coast-crm-demo-main-myvm" \
  --sync-mode "one-way-safe" \
  /local/path/to/project \
  ubuntu@192.168.122.139:~/coast-workspaces/crm-demo/main
```

---

## Troubleshooting

### Tunnel not connected

```bash
coast-dev remote connect myvm
coast-dev remote ls
```

### Remote daemon not responding

```bash
# Check remote daemon status
ssh ubuntu@<VM_IP> "pgrep -fa coastd"

# Check remote daemon logs
ssh ubuntu@<VM_IP> "tail -20 ~/.coast-dev/coastd.log"

# Restart remote daemon
ssh ubuntu@<VM_IP> "pkill -f coastd-dev; nohup ~/.local/bin/coastd-dev > ~/.coast-dev/coastd.log 2>&1 &"
```

### Sync not working

```bash
coast-dev sync status
mutagen sync list
```

### Instance not found

Ensure you're specifying the correct project:

```bash
coast-dev exec test1 --project crm-demo -- echo "hello"
```

Or run from the project directory containing the `Coastfile`.
