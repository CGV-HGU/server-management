# Shared Permissions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `/data/shared` recursively world-readable and world-writable, inherit that policy for future content, and keep private user directories at mode `700`.

**Architecture:** `install.sh` repairs the complete existing shared tree and installs POSIX default ACLs on every directory. `lab-manage` reapplies the root directory mode and ACL during normal commands without recursively scanning a potentially large dataset. A portable shell regression test records permission and ACL operations in a temporary installation.

**Tech Stack:** Bash, GNU `find`, POSIX ACLs through `setfacl`, Ubuntu `acl` package.

## Global Constraints

- `/data/shared` has no sticky bit: any user may delete or rename another user's entries.
- Existing regular files gain read/write access for everyone without automatically gaining execute permission.
- Existing executable files retain their execute bits.
- `/data/private/<username>` remains mode `700`.
- Rerunning `install.sh` repairs the entire existing shared tree.
- The 30-minute sync job does not recursively scan the shared tree.

---

### Task 1: Shared Tree ACL Policy

**Files:**
- Create: `tests/shared-permissions.sh`
- Modify: `install.sh`
- Modify: `lab-manage`

**Interfaces:**
- Consumes: `SHARED_DIR` and the existing `LAB_MANAGE_TEST_SKIP_ROOT` test switch.
- Produces: `repair_shared_tree()` in `install.sh` and `ensure_shared_dir()` in `lab-manage`, both using the same access/default ACL strings.

- [ ] **Step 1: Write the failing installer regression test**

Create a temporary data tree containing nested directories, a non-executable file, and an executable file. Run `install.sh` with temporary output paths and command wrappers that record `chmod` and `setfacl`. Assert calls equivalent to:

```bash
chmod 2777 "$shared_dir"
chmod 2777 "$shared_dir/nested"
chmod a+rw "$shared_dir/plain.txt"
setfacl -m 'u::rwx,g::rwx,m::rwx,o::rwx,d:u::rwx,d:g::rwx,d:m::rwx,d:o::rwx' "$shared_dir"
setfacl -m 'u::rwx,g::rwx,m::rwx,o::rwx,d:u::rwx,d:g::rwx,d:m::rwx,d:o::rwx' "$shared_dir/nested"
```

Also assert that `plain.txt` is still non-executable, the executable fixture remains executable, and a temporary user's private directory created through `setup_storage` has mode `700`.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash tests/shared-permissions.sh
```

Expected: FAIL because the current installer calls `chmod -R 777` and never calls `setfacl`.

- [ ] **Step 3: Implement recursive repair in `install.sh`**

Add `find` and `setfacl` to the dependency check, define the ACL value, and replace recursive `chmod 777`/`chown` with:

```bash
repair_shared_tree() {
    mkdir -p "$SHARED_DIR"
    chown root:root "$SHARED_DIR" 2>/dev/null || true
    find "$SHARED_DIR" ! -type l -exec setfacl -b {} +
    find "$SHARED_DIR" -type d -exec setfacl -k {} +
    find "$SHARED_DIR" -type d -exec chmod 2777 {} +
    find "$SHARED_DIR" ! -type d ! -type l -exec chmod a+rw {} +
    find "$SHARED_DIR" -type d -exec setfacl -m "$SHARED_DIR_ACL" {} +
}
```

Use this function on every installer run and report that existing permissions and inherited ACLs were applied.

- [ ] **Step 4: Implement root policy enforcement in `lab-manage`**

Change `ensure_shared_dir()` to apply mode `2777` and the same ACL to the shared root only:

```bash
mkdir -p "$SHARED_DIR"
chmod 2777 "$SHARED_DIR"
setfacl -m "$SHARED_DIR_ACL" "$SHARED_DIR"
```

Preserve the existing conditional root ownership operation. Do not add recursive `find` calls here.

- [ ] **Step 5: Run tests and syntax checks**

Run:

```bash
bash tests/shared-permissions.sh
bash -n install.sh
bash -n lab-manage
bash -n tests/shared-permissions.sh
```

Expected: all commands exit `0`.

### Task 2: Operator Documentation And Final Verification

**Files:**
- Modify: `README.md`
- Modify: `tests/shared-permissions.sh`

**Interfaces:**
- Consumes: the `acl` package requirement and shared policy implemented in Task 1.
- Produces: installation and upgrade instructions matching actual behavior.

- [ ] **Step 1: Add failing documentation assertions**

Add checks that `README.md` mentions the Ubuntu `acl` package, default ACL inheritance, recursive repair on every installer run, and private mode `700`.

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
bash tests/shared-permissions.sh
```

Expected: FAIL because the README currently describes `2777` as sufficient for future writable inheritance and does not list `acl`.

- [ ] **Step 3: Update README**

Document:

```bash
sudo apt install -y acl curl passwd libc-bin cron coreutils findutils util-linux
```

Explain that directories are `2777`, files receive `a+rw`, default ACLs govern normal future creation, rerunning `sudo ./install.sh` repairs existing shared content, and private directories remain owner-only at `700`.

- [ ] **Step 4: Run final verification**

Run:

```bash
bash tests/shared-permissions.sh
bash -n install.sh
bash -n lab-manage
bash -n tests/shared-permissions.sh
bash lab-manage help
git diff --check
```

Expected: all commands exit `0`, with no syntax or whitespace errors.

- [ ] **Step 5: Commit and push**

```bash
git add install.sh lab-manage README.md tests/shared-permissions.sh docs/superpowers/plans/2026-07-20-shared-permissions.md
git commit -m "Enforce inherited shared directory permissions"
git push origin main
```
