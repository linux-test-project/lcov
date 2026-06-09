#!/usr/bin/env python3
"""
Common utilities for test infrastructure.
Provides colors, timestamps, and log file handling.
"""

import os
import sys
import time
from pathlib import Path
from typing import Optional


# ANSI color codes (only if terminal)
if sys.stdout.isatty():
    RED = '\033[31m'
    GREEN = '\033[32m'
    BLUE = '\033[34m'
    BOLD = '\033[1m'
    DEFAULT = '\033[39m'
    RESET = '\033[0m'
else:
    RED = GREEN = BLUE = BOLD = DEFAULT = RESET = ''


def timestamp():
    """Return current timestamp string."""
    return time.strftime('%Y-%m-%d %H:%M:%S %z')


def detail(key: str, value: str) -> str:
    """Format a key-value detail line."""
    dots = " ............"
    return f"{key}{dots[:12-len(key)]}: {value}"


def marker() -> str:
    """Return a separator marker."""
    return "\n" + "=" * 70


def find_topdir():
    """Find the test top directory."""
    # Check environment first
    topdir = os.environ.get('TOPDIR')
    if topdir and Path(topdir).is_dir():
        return Path(topdir)
    
    # Walk up looking for tests/bin directory
    cwd = Path.cwd()
    for p in [cwd] + list(cwd.parents):
        if (p / 'tests' / 'bin').is_dir():
            return p / 'tests'
        if (p / 'bin').is_dir() and (p / 'common.mak').exists():
            return p
    
    raise RuntimeError("Cannot find test directory (TOPDIR)")


def get_parallel_default():
    """Get default parallelism level."""
    try:
        import multiprocessing
        return min(multiprocessing.cpu_count(), 8)
    except (ImportError, NotImplementedError, OSError):
        return 4


class TestResult:
    """Result of a single test execution."""
    
    def __init__(self, name: str, result: str, exit_code: int,
                 duration_ms: int = 0, memory_kb: int = 0,
                 log_file: Optional[Path] = None, coverage_dir: Optional[Path] = None,
                 error_msg: Optional[str] = None):
        self.name = name
        self.result = result  # 'pass', 'fail', 'skip', 'kill'
        self.exit_code = exit_code
        self.duration_ms = duration_ms
        self.memory_kb = memory_kb
        self.log_file = log_file
        self.coverage_dir = coverage_dir
        self.error_msg = error_msg
    
    def __repr__(self):
        return f"TestResult({self.name!r}, {self.result!r})"
