from __future__ import annotations

import platform
from argparse import Namespace

from preview_tool.core import Project


def prepare(project: Project, public_host: str, args: Namespace) -> Project:
    if platform.system() == "Windows":
        if args.no_stage:
            return project
        from .windows import prepare as prepare_windows

        return prepare_windows(project, public_host, args)

    from .linux import prepare as prepare_linux

    return prepare_linux(project, public_host, args)
