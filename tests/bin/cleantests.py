#!/usr/bin/env python3
"""
Clean test artifacts.
Replaces shell-based cleantests.
"""

import argparse
import os
import shutil
import subprocess
from pathlib import Path


def parse_args():
    parser = argparse.ArgumentParser(description='Clean test artifacts')
    parser.add_argument('tests', nargs='*', help='Tests to clean')
    parser.add_argument('-s', '--silent', action='store_true',
                        help='Silent mode')
    return parser.parse_args()


def find_topdir():
    """Find test top directory.
    
    Prefers current working directory if it contains common.mak
    (for subdirectory Makefiles), otherwise uses TOPDIR env var
    or searches upward.
    """
    cwd = Path.cwd()
    
    # If current directory contains common.mak, use it
    # This handles the case when called from subdirectory Makefiles
    if (cwd / 'common.mak').exists():
        return cwd
    
    # Check TOPDIR environment variable
    topdir = os.environ.get('TOPDIR')
    if topdir:
        return Path(topdir)
    
    # Search upward for test directory
    for p in [cwd] + list(cwd.parents):
        if (p / 'bin').is_dir() and (p / 'common.mak').exists():
            return p
    return cwd


def clean_test(base_dir: Path, test_name: str):
    """Clean a single test directory by running 'make clean'.
    
    Args:
        base_dir: Base directory for resolving test paths
        test_name: Test name (can be a script like 'test.sh' or a directory like 'subdir/')
    
    Note: If test_name ends with .sh or .pl, it's a script in the current directory
          and is handled by the parent Makefile's clean target, so we skip it here.
    """
    # Skip scripts - they are cleaned by the parent Makefile's clean target
    if test_name.endswith('.sh') or test_name.endswith('.pl'):
        return
    
    test_path = base_dir / test_name.rstrip('/')
    
    if not test_path.is_dir():
        return
    
    # Run 'make clean' in the test directory
    makefile = test_path / 'Makefile'
    if makefile.exists():
        try:
            subprocess.run(
                ['make', '-C', str(test_path), 'clean', '-s'],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                check=False
            )
        except Exception:
            pass


def main():
    args = parse_args()
    
    # Use current working directory as base for test paths
    # The clean_subdirs target calls cleantests.py from the directory containing the tests
    base_dir = Path.cwd()
    
    # Also find topdir for cleaning top-level artifacts
    topdir = find_topdir()
    
    # Clean test artifacts in topdir
    for artifact in ['test.log', 'test.counts', 'test.time']:
        f = topdir / artifact
        if f.exists():
            f.unlink()
    
    # Clean log directory
    log_dir = topdir / 'test.log.d'
    if log_dir.exists():
        shutil.rmtree(log_dir)
    
    # Clean coverage directories
    for cov_dir in ['cover_db', 'cover_db.d', 'lcov_coverage']:
        d = topdir / cov_dir
        if d.exists():
            shutil.rmtree(d)
    
    # Clean info files in topdir
    for pattern in ['*.info', '*.counts']:
        for f in topdir.glob(pattern):
            f.unlink()
    
    # Clean test directories
    if args.tests:
        for test_name in args.tests:
            clean_test(base_dir, test_name)
    else:
        # Clean common test subdirs relative to topdir
        for subdir in ['genhtml', 'lcov', 'llvm2lcov', 'py2lcov', 'perl2lcov', 'xml2lcov']:
            clean_test(topdir, subdir)


if __name__ == '__main__':
    main()
