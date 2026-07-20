# Shared Directory Permission Policy

## Goal

Keep `/data/shared` intentionally open to every local user while preserving
private user storage. Any user must be able to read, modify, create, rename,
and delete content under the shared directory. `/data/private/<username>`
remains accessible only to its owner.

## Design

The installer applies a POSIX ACL policy to the complete shared tree.

- Existing directories receive mode `2777`. The setgid bit keeps group
  inheritance consistent, while the absence of the sticky bit allows users to
  delete or rename each other's entries.
- Existing non-directory entries receive read and write permission for all
  users. Existing executable bits are preserved rather than added to every
  regular file.
- Every directory receives an access ACL and a default ACL granting `rwx` to
  owner, group, and others. The default ACL is inherited by newly created
  descendants, so normal file creation produces world-readable and
  world-writable files and normal directory creation produces world-accessible
  directories regardless of the caller's usual umask.
- The shared root policy is also checked by `lab-manage` so the root directory
  remains correctly configured during normal management commands.

The installer performs the recursive repair every time it runs. This upgrades
an existing server and repairs permissions that have drifted. It does not
recursively scan the shared tree from the 30-minute SSH-key sync job because
that could be expensive for large datasets or model caches.

POSIX ACLs establish inherited defaults; a file owner or an application that
explicitly changes a file to a restrictive mode can still override them.
Rerunning `install.sh` repairs those existing entries. Continuous enforcement
against explicit `chmod` would require a filesystem event daemon and is outside
this change.

## Dependencies And Errors

`setfacl` is required and is supplied by Ubuntu's `acl` package. The installer
checks for it before making changes and reports the missing command in the same
way as its existing dependency checks.

Permission or ACL failures stop installation so the installer cannot claim the
shared directory is ready when only part of the policy was applied.

## Verification

Automated shell tests run the installer against a temporary shared tree and
verify that:

- existing nested directories are repaired to `2777`;
- existing files become readable and writable by all without losing an
  executable bit;
- default ACL application is requested for every directory;
- private directories remain `700` when users are provisioned;
- the README describes the implemented ACL policy and Ubuntu dependency.

Syntax checks for both Bash scripts and the complete test suite run before the
change is committed and pushed.
