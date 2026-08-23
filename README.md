# preview

`preview` shares the Git project in the current directory through private Tailscale HTTPS.

On a personal computer, one URL points to the last project used with `preview`. On a tagged Tailscale server, each project uses its own Tailscale Service URL.

The shared code runs on Windows and Ubuntu. Windows uses the existing global `stage` command to point Laragon at the current worktree. Ubuntu sends Tailscale traffic to the project's `APP_URL`.

## Requirements

- Python 3.10 or later
- Git
- Tailscale
- A Git project with `APP_URL` in `.env` or `.env.example`

Windows also needs Laragon and the global `stage` PowerShell command.

## Install

On Windows PowerShell:

```powershell
.\install-windows.ps1
```

The installer creates a symbolic link to the Git launcher. It saves a dated backup if another launcher already exists. If Windows blocks symbolic links, it installs a forwarding script instead.

On Ubuntu:

```sh
./install-ubuntu.sh
```

Make sure `$HOME/.local/bin` is in `PATH`.

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

You can also run either launcher directly from the cloned repository. The launchers add the local `src` directory to Python's import path.

## Use

From a Git project:

```sh
preview
```

The command reads `.env` first, then `.env.example`. It uses `APP_URL` as the local backend. If neither file has `APP_URL`, it uses `http://<repository-name>.test`.

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

On Ubuntu, the local backend must already be running. Use `--backend` when `APP_URL` does not work from the same computer.

On Windows, set a different Laragon location with an environment variable:

```powershell
$env:LARAGON_ROOT = 'C:\laragon'
preview
```

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
