# Stage preview

`preview` shares the Git project in the current directory through private Tailscale HTTPS.

On a personal computer, one URL points to the last project used with `preview`. On a tagged Tailscale server, each project uses its own Tailscale Service URL.

The same command runs on Windows and Ubuntu. Windows uses Laragon and the included `stage` command. Ubuntu sends Tailscale traffic to the local URL in `APP_URL`.

## What it does

- Finds the current Git project.
- Reads `APP_URL` from `.env` or `.env.example`.
- Starts a private Tailscale HTTPS proxy.
- Keeps one active URL on a personal computer.
- Uses one URL per project on a tagged Tailscale server.

The command does not use Tailscale Funnel. The preview is not public.

## Requirements

- Python 3.10 or newer
- Git 2.30 or newer
- Tailscale 1.86 or newer
- GitHub CLI for cloning this private repository
- A Git project with `APP_URL` in `.env` or `.env.example`

Windows also needs Laragon. The Windows installer installs the `stage` PowerShell command with `preview`.

## Install on Windows

Open PowerShell. Check the required commands:

```powershell
python --version
git --version
tailscale version
gh --version
```

Sign in to GitHub if needed:

```powershell
gh auth login
```

Clone the repository:

```powershell
New-Item -ItemType Directory -Path 'D:\Projects\Elliptic' -Force | Out-Null
Set-Location 'D:\Projects\Elliptic'
gh repo clone ellipticmarketing/stage
Set-Location stage
```

Install the command:

```powershell
.\install-windows.ps1
```

The installer creates these command links:

```powershell
C:\Rolando Apps\scripts\preview.ps1
C:\Rolando Apps\scripts\stage.ps1
```

Add `C:\Rolando Apps\scripts` to `PATH`, or call the files from your PowerShell profile. The installer saves a dated backup if another launcher exists. If Windows blocks symbolic links, the installer creates a forwarding script.

Check the installation:

```powershell
preview version
preview status
Get-Command stage
```

The default Laragon directory is `F:\laragon`. Set another location before you run `preview`:

```powershell
$env:LARAGON_ROOT = 'C:\laragon'
preview
```

## Install on Ubuntu

Install the required packages:

```sh
sudo apt update
sudo apt install -y git python3 gh
```

Install Tailscale and sign in before you continue. Check the commands:

```sh
python3 --version
git --version
tailscale version
gh --version
tailscale status
```

Sign in to GitHub if needed:

```sh
gh auth login
```

Clone and install:

```sh
mkdir -p "$HOME/.local/share"
gh repo clone ellipticmarketing/stage "$HOME/.local/share/elliptic-preview"
cd "$HOME/.local/share/elliptic-preview"
./install-ubuntu.sh
```

The installer creates this link:

```sh
$HOME/.local/bin/preview
```

Add the command directory to `PATH` if needed:

```sh
printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.profile"
. "$HOME/.profile"
```

Check the installation:

```sh
preview version
preview status
```

On Ubuntu, the web application must already be running. `preview` does not start PHP, Laravel, Apache, Nginx, or a development server.

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

On Windows, the Python package also installs `stage.ps1` in that scripts directory.

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

Use `--backend` when `APP_URL` is not reachable from the same computer.

Use `--no-stage` to skip Laragon and proxy directly to the backend.

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
