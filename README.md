# Stage preview

`preview` gives the Git project in the current directory a stable address.

The same command runs on Windows and Ubuntu. Windows stages the current worktree with Laragon and shares it through private Tailscale HTTPS. Ubuntu uses Nginx and mDNS to create a local-network address for each project.

## What it does

- Finds the current Git project.
- Reads `APP_URL` from `.env` or `.env.example`.
- Points a stable local web-server path at the current worktree.
- On Ubuntu, publishes `project-machine.local` through Avahi.
- On Windows, starts a private Tailscale HTTPS proxy.

Ubuntu names include the machine name, so two computers can publish the same project without using the same address. For example, Plenchy on a machine named `ubuntu` becomes `http://plenchy-ubuntu.local`.

## Requirements

- Python 3.10 or newer
- Git 2.30 or newer
- `curl` on Ubuntu
- A Git project with `APP_URL` in `.env` or `.env.example`

Windows also needs Laragon and Tailscale 1.86 or newer. The Windows installer installs the `stage` PowerShell command with `preview`.

## Install on Windows

Open PowerShell and paste this command:

```powershell
irm https://raw.githubusercontent.com/ellipticmarketing/preview/main/install.ps1 | iex
```

The installer uses Windows Package Manager to install Git, Python, Tailscale, and Laragon if they are missing. It installs `preview` and `stage` in `%LOCALAPPDATA%\Elliptic\bin`.

When the installer finishes:

1. Open Tailscale from the Start menu and sign in.
2. Start Laragon.
3. Open a new PowerShell window.
4. Check the installation:

```powershell
preview version
preview status
Get-Command stage
```

The installer clones this repository into `%LOCALAPPDATA%\Elliptic\preview`. Run the same command again to update it. The installer stops if its clone has local changes.

To install from a clone instead:

```powershell
git clone https://github.com/ellipticmarketing/preview.git
Set-Location preview
.\install-windows.ps1
```

The installer creates these command links:

```powershell
%LOCALAPPDATA%\Elliptic\bin\preview.ps1
%LOCALAPPDATA%\Elliptic\bin\stage.ps1
```

The bootstrap adds this directory to your user `PATH`. The clone installer only creates the command links, so add the directory to `PATH` when you use the manual method. Both installers save a dated backup if another launcher exists. If Windows blocks symbolic links, they create forwarding scripts.

`preview` detects the running Laragon installation. To use another location, set it before you run `preview`:

```powershell
$env:LARAGON_ROOT = 'C:\laragon'
preview
```

## Install on Ubuntu

Open a terminal and paste this command:

```sh
curl -fsSL https://raw.githubusercontent.com/ellipticmarketing/preview/main/install.sh | bash
```

The installer asks for your password if it must install Git, Python, Nginx, or Avahi. It puts `preview` and `stage` in `$HOME/.local/bin`.

The installer installs Nginx and Avahi if they are missing. Open a new terminal and check the installation:

```sh
preview version
preview status
```

### Start your first preview

Go to your application's Git repository:

```sh
cd /path/to/your/application
```

If the application already runs its own server, set `APP_URL` to that server. For example:

```dotenv
APP_URL=http://127.0.0.1:8000
```

Start the local preview:

```sh
preview
```

The command completes the Nginx and Avahi setup, publishes the current project, and prints all active local preview addresses on the machine:

```text
Published http://my-project-ubuntu.local

Local preview addresses:
http://another-project-ubuntu.local -> http://127.0.0.1:3000
http://my-project-ubuntu.local -> http://127.0.0.1:8000
```

Devices on the same local network can open it. mDNS does not travel through Tailscale or across normal routed networks.

If `APP_URL` points to localhost or an IP address, Nginx proxies the mDNS name to that running server. Otherwise, `stage` points Nginx at the worktree's `public` directory.

You can publish the current worktree without using the Python command:

```sh
stage
```

The command creates a stable link under `/var/lib/elliptic-stage` and an Nginx site under `/etc/nginx/sites-available`. It also creates a small system service that keeps the project's mDNS name active after a reboot. Nginx reloads only when the site configuration changes.

For a PHP project, `stage` uses the newest PHP-FPM socket in `/run/php`. If PHP-FPM is missing, it asks before installation. It reloads PHP-FPM after a worktree switch so cached PHP paths do not point to the old worktree. The Nginx user must have permission to read the worktree and its `public` directory.

### What the installer changes

The installer:

- Clones this repository into `$HOME/.local/share/elliptic-preview`.
- Creates `$HOME/.local/bin/preview` and `$HOME/.local/bin/stage`.
- Adds `$HOME/.local/bin` to `PATH` in `$HOME/.profile` if needed.
- Installs missing base packages, Nginx, and Avahi with `apt-get`.

Run the same command again to update an existing installation. The installer stops if its clone has local changes.

To install from a clone instead:

```sh
git clone https://github.com/ellipticmarketing/preview.git
cd preview
./install-ubuntu.sh
```

If the shell cannot find `preview` after installation, start a new terminal or run:

```sh
export PATH="$HOME/.local/bin:$PATH"
```

## Install as a Python package

Create a virtual environment and install the command:

```sh
python -m venv .venv
```

Windows PowerShell:

```powershell
.venv\Scripts\Activate.ps1
python -m pip install -e .
```

Ubuntu:

```sh
. .venv/bin/activate
python -m pip install -e .
```

For a user installation, run:

```sh
python -m pip install --user .
```

Make sure the Python user scripts directory is in `PATH`.

The Python package also installs the platform `stage` launchers in that scripts directory.

You can also run the launchers directly from the cloned repository. The `preview` launchers add the local `src` directory to Python's import path.

## Start a preview

From a Git project:

```sh
preview
```

The command reads `.env` first, then `.env.example`. It uses `APP_URL` as the local backend. If neither file has `APP_URL`, it stages the repository's `public` directory.

Example `.env` setting for an application server that already runs on Ubuntu:

```dotenv
APP_URL=http://127.0.0.1:8000
```

Commands:

```sh
preview
preview status
preview stop
preview version
preview update
preview rollback
preview --backend http://127.0.0.1:8000
preview --site example.test
```

`preview update` checks for local changes, runs `git pull --ff-only`, and runs the tests. It saves the previous commit ID in the user state directory. `preview rollback` returns the clone to that saved commit. Both commands refuse to run when the clone has local changes.

Use `--backend` to keep a running application server as the Ubuntu backend. For example:

```sh
preview --backend http://127.0.0.1:8000
```

On Windows, `--no-stage` skips Laragon and sends Tailscale directly to `APP_URL` or `--backend`. Linux mDNS previews need Nginx, so Ubuntu does not support `--no-stage`.

## Update and rollback

Run this from any directory:

```sh
preview update
```

The update command:

1. Stops if the Stage repository has local changes.
2. Runs `git pull --ff-only`.
3. Runs the unit tests.
4. Records the previous commit.

Return to the recorded commit if an update causes a problem:

```sh
preview rollback
```

Run `preview update` again to move forward.

## Troubleshooting

If the shell cannot find the command, check `PATH`:

```sh
command -v preview
```

On PowerShell:

```powershell
Get-Command preview -All
```

If Tailscale is offline on Windows:

```sh
tailscale up
```

If an Ubuntu backend does not respond, test it on the Ubuntu computer:

```sh
curl -I http://127.0.0.1:8000
```

If an Ubuntu `.local` name does not resolve, make sure the client is on the same local network. Then check Avahi on the server:

```sh
systemctl status avahi-daemon
preview status
```

## Code layout

Shared project code is in `src/preview_tool`. Operating-system code is in:

```text
src/preview_tool/platforms/windows.py
src/preview_tool/platforms/linux.py
```

GitHub Actions runs the unit tests on Windows and Ubuntu with Python 3.10 and 3.13.

## How HTTPS works on Windows

Tailscale ends the HTTPS connection and sends an HTTP request to Laragon. The preview-only Apache host sets `HTTPS=on` for PHP. This makes Laravel generate HTTPS asset URLs and prevents mixed-content errors.

## Test

Run the tests:

```sh
python -m unittest discover -s tests -v
```
