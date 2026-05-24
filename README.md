# server-management

Research lab server user-management scripts.

This repository provides two Bash scripts:

- `install.sh`: prepares a Linux server for lab-managed accounts.
- `lab-manage`: creates, removes, lists, and syncs lab user accounts.

The scripts are intended for Ubuntu-like Linux servers where users log in with SSH keys published on GitHub.

## What This Manages

`lab-manage` supports two account types.

Personal lab users:

- One Linux account per GitHub username.
- The account's SSH `authorized_keys` is populated from `https://github.com/<username>.keys`.
- The account is added to the `docker` group and the lab user group.

Team shared accounts:

- One Linux account shared by multiple GitHub users.
- The account's SSH `authorized_keys` is the merged set of SSH keys from the configured GitHub source users.
- The account is added to the `docker` group and the lab team group.
- Source-user metadata is stored in `/etc/lab-manage/team-sources`.

Each managed account also gets storage links in its home directory:

- `~/shared` -> `/data/shared`
- `~/private` -> `/data/private/<username>`

## Default Layout

By default, the scripts use:

```text
/data/shared                 Shared lab directory
/data/private                Parent directory for per-user private storage
/data/private/<username>     Per-user private storage
/data/config                 Root-managed lab config directory
/data/config/shared_bashrc   Shared shell defaults sourced by managed users
/etc/default/lab-manage      Runtime configuration written by install.sh
/etc/lab-manage              lab-manage metadata directory
/etc/lab-manage/team-sources Team account source-user metadata
/usr/local/bin/lab-manage    Installed command
```

Default groups:

```text
labusers   Personal lab users
labteams   Team shared accounts
docker     Required existing group for Docker access
```

## Installation

Install dependencies on Ubuntu:

```bash
sudo apt update
sudo apt install -y curl passwd libc-bin cron coreutils util-linux
sudo systemctl enable --now cron
```

`lab-manage` requires the `docker` group. If Docker is already installed, this group usually exists. If Docker will be installed later but you want to prepare the server now:

```bash
sudo groupadd docker
```

Prepare `/data`.

For a server with an additional HDD or SSD mounted at `/data`, mount it first and preferably register it in `/etc/fstab`.

For a single-disk server, `/data` may simply be a normal directory:

```bash
sudo mkdir -p /data
```

Run the installer from this repository:

```bash
chmod +x install.sh lab-manage
sudo ./install.sh
```

## What `install.sh` Does

`install.sh` must be run as root. It performs the following setup:

1. Checks required commands are available:

   ```text
   curl useradd userdel usermod passwd getent crontab groupadd install mountpoint
   ```

2. Creates the lab groups if missing:

   ```text
   labusers
   labteams
   ```

3. Verifies `/data` exists. `/data` may be either:

   - a real mount point, or
   - a normal directory.

4. Creates and configures `/data/shared`:

   ```bash
   chown root:labusers /data/shared
   chmod 2777 /data/shared
   ```

   `2777` means everyone can read/write/enter the directory, and new files/directories inherit the `labusers` group because of the setgid bit.

5. Creates and configures `/data/private`:

   ```bash
   chmod 755 /data/private
   ```

   Per-user directories under this path are later created by `lab-manage` with mode `700`.

6. Writes runtime configuration to `/etc/default/lab-manage`.

   This file stores the install-time data root, group names, and any explicitly overridden paths so `lab-manage` and the cron job use the same configuration later. For example, if the installer is run with `LAB_MANAGE_DATA_DIR=/mnt/labdata`, that data root is persisted here and the default runtime paths derive from it.

7. Creates `/data/config` and `/data/config/shared_bashrc`:

   ```bash
   chown root:root /data/config
   chmod 755 /data/config
   chown root:root /data/config/shared_bashrc
   chmod 644 /data/config/shared_bashrc
   ```

   Lab users can read this config, but only root/admin can edit it.

8. Installs the command:

   ```text
   /usr/local/bin/lab-manage
   ```

9. Registers a root cron job:

   ```cron
   */30 * * * * /usr/local/bin/lab-manage sync >/dev/null 2>&1
   ```

   This refreshes SSH keys from GitHub every 30 minutes.

## Shared Bash Defaults

The installer creates `/data/config/shared_bashrc` as an empty lab-wide shell configuration file if it does not already exist:

```bash
# Lab-wide shell defaults.
# Add shared environment variables, aliases, or shell setup here.
```

New managed accounts get a small block in `~/.bashrc`:

```bash
# >>> lab-manage defaults >>>
# Load lab-wide shell defaults managed outside user homes.
if [[ -f /data/config/shared_bashrc ]]; then
    source /data/config/shared_bashrc
fi
# <<< lab-manage defaults <<<
```

This means future changes can be made once in:

```bash
sudoedit /data/config/shared_bashrc
```

Existing managed users can be updated with:

```bash
sudo lab-manage refresh-bashrc
```

## Usage

Show help:

```bash
lab-manage help
```

List managed users and team accounts:

```bash
sudo lab-manage list
```

Add personal users:

```bash
sudo lab-manage add octocat
sudo lab-manage add student1 student2 student3
```

This creates Linux users, locks password login, fetches GitHub SSH keys, adds storage symlinks, and configures the shared bashrc loader.

Add a team shared account:

```bash
sudo lab-manage add --team projx --from alice,bob
```

This creates the Linux account `projx` and allows SSH login using the combined GitHub SSH keys from `alice` and `bob`.

Replace all source users for a team account:

```bash
sudo lab-manage update --team projx --from alice,charlie
```

Add source users to a team account:

```bash
sudo lab-manage update --team projx --add charlie
```

Remove source users from a team account:

```bash
sudo lab-manage update --team projx --remove alice
```

Refresh SSH keys immediately:

```bash
sudo lab-manage sync
```

Remove accounts:

```bash
sudo lab-manage remove student1
sudo lab-manage remove projx
```

For personal accounts, removal is allowed only when the account is managed by `lab-manage` through the lab user group. For team accounts, removal requires valid team metadata.

## GitHub SSH Key Sync

SSH keys are fetched from:

```text
https://github.com/<username>.keys
```

For personal accounts, the GitHub username and Linux username are the same after lowercasing.

For team accounts, `lab-manage` stores a comma-separated list of source GitHub usernames and merges their valid SSH public keys into the team account's `authorized_keys`.

The installer registers automatic sync every 30 minutes. Manual sync is also available:

```bash
sudo lab-manage sync
```

If GitHub is temporarily unavailable or a user has no valid SSH keys, the script logs a warning. For team accounts, existing keys are kept when no valid replacement keys can be fetched.

## Configuration

Most paths and names can be overridden with environment variables. `install.sh` writes the install-time data root, group names, and explicit path overrides to `/etc/default/lab-manage`, and `lab-manage` loads that file on every run. Environment variables passed directly to a `lab-manage` command still take precedence over the config file.

Installer variables:

```text
LAB_MANAGE_CONFIG_FILE
LAB_MANAGE_LABGROUP
LAB_MANAGE_TEAMGROUP
LAB_MANAGE_DATA_DIR
LAB_MANAGE_SHARED_DIR
LAB_MANAGE_PRIVATE_DIR
LAB_MANAGE_CONFIG_DIR
LAB_MANAGE_SHARED_BASHRC_FILE
LAB_MANAGE_INSTALL_PATH
LAB_MANAGE_CRON_ENTRY
```

Runtime variables:

```text
LAB_MANAGE_CONFIG_FILE
LAB_MANAGE_DATA_DIR
LAB_MANAGE_SHARED_DIR
LAB_MANAGE_PRIVATE_DIR
LAB_MANAGE_HOME_BASE_DIR
LAB_MANAGE_LABGROUP
LAB_MANAGE_TEAMGROUP
LAB_MANAGE_CONFIG_DIR
LAB_MANAGE_SHARED_BASHRC_FILE
LAB_MANAGE_METADATA_DIR
LAB_MANAGE_TEAM_SOURCES_FILE
LAB_MANAGE_SYNC_LOCK_DIR
LAB_MANAGE_SKIP_BASHRC_DEFAULTS
```

Example using a different data root:

```bash
sudo LAB_MANAGE_DATA_DIR=/mnt/labdata ./install.sh
```

After this install, `/etc/default/lab-manage` keeps that data root for normal `lab-manage` commands and cron sync.

Example using a different shared bashrc file:

```bash
sudo LAB_MANAGE_SHARED_BASHRC_FILE=/data/config/lab_bashrc ./install.sh
```

## Notes and Cautions

- These scripts perform root-level account and filesystem changes. Read the output before using them on a production server.
- `/data/shared` is configured as `2777`, which is intentionally permissive. Users may be able to remove or rename other users' files depending on the file permissions.
- `install.sh` only changes the permissions of `/data/shared` itself, not every existing child file or directory under it.
- `lab-manage` locks password login with `passwd -l`; SSH key login remains the intended login path.
- Usernames are normalized to lowercase and must be Linux-safe: `a-z`, `0-9`, `_`, `-`; no leading digit, no leading hyphen, no period, max 32 characters.
- The `docker` group must exist before running `lab-manage` commands.
