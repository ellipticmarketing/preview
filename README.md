# Stage preview

`preview` shares the Git project in the current directory through private Tailscale HTTPS.

On a personal computer, one URL points to the last project used with `preview`. On a tagged Tailscale server, each project uses its own Tailscale Service URL.

The same command runs on Windows and Ubuntu. Windows stages the current worktree with Laragon. Ubuntu stages it with Nginx.

## What it does

- Finds the current Git project.
- Reads `APP_URL` from `.env` or `.env.example`.
- Points a stable local web-server path at the current worktree.
- Starts a private Tailscale HTTPS proxy.
- Keeps one active URL on a personal computer.
- Uses one URL per project on a tagged Tailscale server.

The command does not use Tailscale Funnel. The preview is not public.

## Requirements

- Python 3.10 or newer
- Git 2.30 or newer
- Tailscale 1.86 or newer
- `curl` on Ubuntu
- A Git project with `APP_URL` in `.env` or `.env.example`

Windows also needs Laragon. The Windows installer installs the `stage` PowerShell command with `preview`.

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

The installer asks for your password if it must install Git, Python, or Tailscale. It puts `preview` and `stage` in `$HOME/.local/bin`.

When the installer finishes, connect the machine to Tailscale:

```sh
sudo tailscale up
```

Open the link that Tailscale prints and sign in. Then open a new terminal and check the installation:

```sh
preview version
preview status
```

### Start your first preview

Go to your application's Git repository. It must have a `public` directory:

```sh
cd /path/to/your/application
```

Check that `.env` contains the local URL of the running application. For example:

```dotenv
APP_URL=http://my-project.test
```

Start the private preview:

```sh
preview
```

If Nginx is installed, `preview` runs `stage` and points Nginx at the current worktree. If Nginx is missing, it asks whether to install it. Choose no to send Tailscale directly to `APP_URL`.

The command then prints the private HTTPS URL. Only devices allowed by your Tailscale network can open it.

You can switch Nginx to a worktree without starting a Tailscale preview:

```sh
stage
```

The command creates a stable link under `/var/lib/elliptic-stage` and an Nginx site under `/etc/nginx/sites-available`. It uses a local port that stays the same for that project. Nginx reloads only when the site configuration changes.

For a PHP project, `stage` uses the newest PHP-FPM socket in `/run/php`. If PHP-FPM is missing, it asks before installation. It reloads PHP-FPM after a worktree switch so cached PHP paths do not point to the old worktree. The Nginx user must have permission to read the worktree and its `public` directory.

### What the installer changes

The installer:

- Clones this repository into `$HOME/.local/share/elliptic-preview`.
- Creates `$HOME/.local/bin/preview` and `$HOME/.local/bin/stage`.
- Adds `$HOME/.local/bin` to `PATH` in `$HOME/.profile` if needed.
- Installs missing base system packages with `apt-get`.
- Uses the official Tailscale installer when Tailscale is missing.

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

The command reads `.env` first, then `.env.example`. It uses `APP_URL` as the local backend. If neither file has `APP_URL`, it uses `http://<repository-name>.test`.

Example `.env` setting:

```dotenv
APP_URL=http://my-project.test
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

Use `--backend` to keep a running application server as the backend. `stage` still updates the Nginx worktree unless you also use `--no-stage`.

Use `--no-stage` to skip Laragon or Nginx and proxy directly to `APP_URL` or `--backend`.

## Tagged Tailscale servers

The command checks `Self.Tags` in `tailscale status --json`. A device with one or more tags uses a service named after the project. For example:

```text
APP_URL=http://dg.emforward.test
Service=svc:dg-emforward
URL=https://dg-emforward.<tailnet>.ts.net
```

Create the service once on the Tailscale Services page. The command reports the required service name when it is missing. Tailscale may also require approval before the service becomes active.

Personal devices do not use Tailscale Services. They keep the single machine URL, and the last project wins.

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

If Tailscale is offline:

```sh
tailscale up
```

If a tagged server reports a missing service, create the reported `svc:<name>` entry on the Tailscale Services page. Approve the host if Tailscale requests approval.

If an Ubuntu backend does not respond, test it on the Ubuntu computer:

```sh
curl -I http://my-project.test
```

## Code layout

Shared project and Tailscale code is in `src/preview_tool`. Operating-system code is in:

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
