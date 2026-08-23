from __future__ import annotations

from argparse import Namespace

from preview_tool.core import Project


def prepare(project: Project, public_host: str, args: Namespace) -> Project:
    return project
