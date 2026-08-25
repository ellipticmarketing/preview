#!/usr/bin/env bash
set -Eeuo pipefail

repository='ellipticmarketing/preview'
repository_url="https://github.com/$repository.git"
install_directory="${ELLIPTIC_PREVIEW_HOME:-$HOME/.local/share/elliptic-preview}"
command_directory="$HOME/.local/bin"
profile_file="$HOME/.profile"

fail() {
    printf 'preview installer: %s\n' "$1" >&2
    exit 1
}

run_as_root() {
    if [[ $EUID -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        fail "sudo is required to install system packages."
    fi
}

if [[ $(uname -s) != 'Linux' ]]; then
    fail 'This installer is for Linux. Use install-windows.ps1 on Windows.'
fi

if ! command -v apt-get >/dev/null 2>&1; then
    fail 'This automatic installer needs Ubuntu or another system with apt-get.'
fi

missing_packages=()
command -v curl >/dev/null 2>&1 || missing_packages+=(curl)
command -v git >/dev/null 2>&1 || missing_packages+=(git)
command -v python3 >/dev/null 2>&1 || missing_packages+=(python3)
command -v nginx >/dev/null 2>&1 || missing_packages+=(nginx)
command -v avahi-daemon >/dev/null 2>&1 || missing_packages+=(avahi-daemon)
command -v avahi-resolve >/dev/null 2>&1 || missing_packages+=(avahi-utils)
dpkg-query -W -f='${Status}' libnss-mdns 2>/dev/null | grep -Fq 'install ok installed' || missing_packages+=(libnss-mdns)

if ((${#missing_packages[@]} > 0)); then
    printf 'Installing required system packages: %s\n' "${missing_packages[*]}"
    run_as_root apt-get update
    run_as_root apt-get install -y "${missing_packages[@]}"
fi

if ! python3 -c 'import sys; raise SystemExit(sys.version_info < (3, 10))'; then
    fail 'Python 3.10 or newer is required.'
fi

if [[ -e "$install_directory" ]]; then
    if [[ ! -d "$install_directory/.git" ]]; then
        fail "$install_directory exists but is not a Git clone."
    fi

    origin_url=$(git -C "$install_directory" remote get-url origin 2>/dev/null || true)
    case "$origin_url" in
        https://github.com/ellipticmarketing/stage | \
        https://github.com/ellipticmarketing/stage.git | \
        git@github.com:ellipticmarketing/stage.git | \
        https://github.com/ellipticmarketing/preview | \
        https://github.com/ellipticmarketing/preview.git | \
        git@github.com:ellipticmarketing/preview.git)
            ;;
        *)
            fail "$install_directory is not a clone of $repository."
            ;;
    esac

    if [[ -n $(git -C "$install_directory" status --porcelain) ]]; then
        fail "$install_directory has local changes. Commit or remove them before installation."
    fi

    branch=$(git -C "$install_directory" branch --show-current)
    if [[ "$branch" != 'main' ]]; then
        fail "$install_directory is on ${branch:-a detached commit}, not main."
    fi

    printf 'Updating %s...\n' "$install_directory"
    git -C "$install_directory" pull --ff-only origin main
else
    mkdir -p "$(dirname "$install_directory")"
    printf 'Cloning %s into %s...\n' "$repository" "$install_directory"
    git clone "$repository_url" "$install_directory"
fi

"$install_directory/install-ubuntu.sh"

path_setting='export PATH="$HOME/.local/bin:$PATH"'
if [[ ":$PATH:" != *":$command_directory:"* ]] && \
    ! grep -Fqx "$path_setting" "$profile_file" 2>/dev/null; then
    printf '\n%s\n' "$path_setting" >> "$profile_file"
    printf 'Added %s to PATH in %s.\n' "$command_directory" "$profile_file"
fi

printf '\nInstallation complete.\n'
"$command_directory/preview" version

printf '\nOpen a new shell before you use preview.\n'
