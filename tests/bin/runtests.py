#!/usr/bin/env python3
"""
Parallel test driver for LCOV test infrastructure.

Replaces shell-based runtests with Python implementation supporting
parallel execution via -j N flag.

Default execution is serial. Use -j N for parallel execution.
-j 0 uses number of available CPU cores.
"""

import argparse
import os
import sys
import re
import time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import threading
import subprocess

# Import local utilities
sys.path.insert(0, str(Path(__file__).parent))
from common import (
    timestamp, detail, marker, find_topdir, get_parallel_default,
)
from test_worker import run_test_worker, TestResult


# ANSI color codes for output
BOLD = '\033[1m'
GREEN = '\033[32m'
RED = '\033[31m'
BLUE = '\033[34m'
RESET = '\033[0m'


def parse_args():
    """Parse command-line arguments."""
    parser = argparse.ArgumentParser(
        description='Run LCOV tests in parallel',
        usage='%(prog)s [MAKE] [TESTS...] [OPTIONS]'
    )
    
    # First positional arg might be 'make' (for backward compat with shell script)
    # We'll filter it out later if needed
    parser.add_argument('tests', nargs='*', default=[],
                        help='Specific tests to run (default: from Makefile)')
    
    parser.add_argument('-j', '--parallel', type=int, default=None,
                        help='Number of parallel workers (default: serial; 0=CPU count)')
    
    parser.add_argument('--coverage', metavar='DB',
                        help='Enable coverage mode with database path')
    
    parser.add_argument('--script-args', dest='script_args',
                        help='Arguments to pass to test scripts')
    
    parser.add_argument('--keep-logs', action='store_true',
                        help='Keep per-test log files after merge')
    
    parser.add_argument('-k', '--keep-going', action='store_true',
                        help='Continue on test failure')
    
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Verbose output')
    
    parser.add_argument('--list', action='store_true',
                        help='List discovered tests without running')
    
    parser.add_argument('--timeout', type=int, default=None,
                        help='Per-test timeout in seconds (default: 1200s if coverage, 300s otherwise)')
    
    parser.add_argument('-s', '--silent', action='store_true',
                        help='Silent mode (for Makefile compatibility)')
    
    parser.add_argument('--debug', action='store_true',
                        help='Enable debug output')
    
    args = parser.parse_args()

    if not args.timeout:
        args.timeout = 1200 if args.coverage else 300
    
    # Filter out 'make' from tests (backward compat with original shell script)
    # Original: runtests "$(MAKE)" $(TESTS) $(OPTS)
    if args.tests and args.tests[0] in ('make', 'gmake', 'gnumake'):
        args.tests = args.tests[1:]

    return args




class TestRunner:
    """Main test runner class."""
    
    def __init__(self, args):
        self.args = args
        self.topdir = find_topdir()
        self.log_dir = self.topdir / 'test.log.d'
        self.coverage_dir = self.topdir / 'cover_db.d'
        # Default: serial (parallel=1)
        # --parallel 0: use CPU count
        # --parallel N: use N
        if args.parallel is None:
            self.parallel = 1
        elif args.parallel == 0:
            self.parallel = get_parallel_default()
        else:
            self.parallel = args.parallel
        self.results = []
        self.results_lock = threading.Lock()
        self.print_lock = threading.Lock()
        self.start_time = None
        
    def setup(self):
        """Initialize test environment."""
        # Create log directory
        self.log_dir.mkdir(parents=True, exist_ok=True)
        
        # Clean old logs
        for f in self.log_dir.glob('*.log'):
            f.unlink()
        
        # Create coverage directory if needed
        if self.args.coverage:
            self.coverage_dir.mkdir(parents=True, exist_ok=True)
        
        # Initialize main log file
        log_file = self.topdir / 'test.log'
        with open(log_file, 'w') as f:
            f.write(marker() + '\n')
            f.write(detail('DATE', timestamp()) + '\n')
            f.write(detail('LCOV', '') + '\n')
        
        # Run testsuite_init
        self._run_init_script()
        
        self.start_time = time.time()
    
    def _run_init_script(self):
        """Run testsuite_init to capture system info."""
        init_script = self.topdir / 'bin' / 'testsuite_init'
        if init_script.exists():
            try:
                subprocess.run([str(init_script)], check=True,
                              stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=str(self.topdir))
            except subprocess.CalledProcessError:
                pass  # Non-fatal if init fails
    
    def discover_tests(self, makefile_path: Path = None):
        """
        Discover tests from Makefile TESTS variable or command line.
        Returns list of (test_name, test_path) tuples.
        """
        tests = []
        
        if self.args.tests:
            # Explicit tests from command line
            for t in self.args.tests:
                test_path = self.topdir / t
                if test_path.is_dir():
                    # Check if it has a Makefile with TESTS
                    sub_makefile = test_path / 'Makefile'
                    if sub_makefile.exists():
                        sub_tests = self._parse_tests_variable(sub_makefile)
                        if sub_tests:
                            # Recurse into this directory
                            tests.extend(self._discover_from_makefile(sub_makefile, t))
                        else:
                            # Leaf directory - find scripts
                            tests.extend(self._discover_in_dir(test_path, t))
                    else:
                        # No Makefile, find scripts
                        tests.extend(self._discover_in_dir(test_path, t))
                elif test_path.exists():
                    tests.append((t, test_path))
        else:
            # Discover from Makefile
            makefile = makefile_path or (self.topdir / 'Makefile')
            if makefile.exists():
                tests = self._discover_from_makefile(makefile, '')
        
        return tests
    
    def _discover_from_makefile(self, makefile: Path, prefix: str):
        """Recursively discover tests from a Makefile."""
        tests = []
        
        # Parse TESTS variable
        tests_var = self._parse_tests_variable(makefile)
        
        for test_name in tests_var:
            test_path = makefile.parent / test_name
            rel_name = f"{prefix}/{test_name}" if prefix else test_name
            
            if test_path.is_dir():
                # Check for sub-Makefile
                sub_makefile = test_path / 'Makefile'
                if sub_makefile.exists():
                    # Check if this Makefile has its own TESTS
                    sub_tests = self._parse_tests_variable(sub_makefile)
                    if sub_tests:
                        # Recurse into subdirectory
                        tests.extend(self._discover_from_makefile(sub_makefile, rel_name))
                    else:
                        # Leaf directory - find .sh scripts
                        tests.extend(self._discover_in_dir(test_path, rel_name))
                else:
                    # No Makefile, find .sh scripts
                    tests.extend(self._discover_in_dir(test_path, rel_name))
            else:
                # It's a file (script)
                tests.append((rel_name.rstrip('/'), test_path))
        
        return tests
    
    def _discover_in_dir(self, dir_path: Path, prefix: str):
        """Discover test scripts in a directory."""
        tests = []
        for f in sorted(dir_path.iterdir()):
            if f.is_file() and f.suffix == '.sh':
                rel_name = f"{prefix}/{f.name}" if prefix else f.name
                tests.append((rel_name, f))
        return tests
    
    def _parse_tests_variable(self, makefile: Path) -> list:
        """Parse TESTS variable from Makefile."""
        tests = []
        try:
            content = makefile.read_text()
            # Handle line continuations (backslash at end of line)
            content = re.sub(r'\\\n\s*', ' ', content)
            # Match: TESTS := a b c or TESTS = a b c
            match = re.search(r'^TESTS\s*[:?]?=\s*(.+?)$', content, re.MULTILINE)
            if match:
                # Split on whitespace, filter empty and backslashes
                tests = [t.rstrip('/') for t in match.group(1).split() if t and t != '\\']
        except Exception:
            pass
        return tests

    def run_all_tests(self, tests: list):
        """
        Run all tests in parallel using ThreadPoolExecutor.
        tests: list of (test_name, test_path) tuples
        """
        total = len(tests)
        if total == 0:
            return
        
        if not self.args.silent:
            with self.print_lock:
                parallel_str = f"parallel={self.parallel}" if self.parallel > 1 else "serial"
                print(f"{BOLD}Starting tests{RESET} ({parallel_str})")
        
        # Debug output
        if self.args.debug:
            print(f"DEBUG: Creating ThreadPoolExecutor with max_workers={self.parallel}", file=sys.stderr)
            sys.stderr.flush()
        
        # Use ThreadPoolExecutor - threads don't have pickling issues
        # and the worker function uses subprocess.run() for actual test execution
        with ThreadPoolExecutor(max_workers=self.parallel) as executor:
            if self.args.debug:
                print(f"DEBUG: ThreadPoolExecutor created, submitting {total} tests", file=sys.stderr)
                sys.stderr.flush()
            
            # Use map for simpler parallel execution
            test_args = [
                (test_name, str(test_path), str(self.log_dir), str(self.topdir),
                 str(self.coverage_dir), self.args.script_args, self.args.timeout,
                 self.args.coverage, self.args.debug)
                for test_name, test_path in tests
            ]
            
            # Submit all tests
            futures = [executor.submit(run_test_worker, *args) for args in test_args]
            if self.args.debug:
                print(f"DEBUG: All tests submitted, waiting for completion", file=sys.stderr)
                sys.stderr.flush()
            
            # Collect results as they complete
            for future in as_completed(futures):
                try:
                    result = future.result()
                    with self.results_lock:
                        self.results.append(result)
                    self._print_result(result)
                except Exception as e:
                    # Find which test failed
                    idx = futures.index(future)
                    test_name, test_path = tests[idx]
                    error_result = TestResult(
                        name=test_name,
                        result='fail',
                        exit_code=1,
                        duration_ms=0,
                        memory_kb=0,
                        error_msg=str(e)
                    )
                    with self.results_lock:
                        self.results.append(error_result)
                    self._print_result(error_result)
    
    def _print_result(self, result: TestResult):
        """Print test result (thread-safe)."""
        if self.args.silent:
            return
        
        name = result.name
        if len(name) > 32:
            name = '...' + name[-29:]
        
        name_field = f"{name} {'.' * (35 - len(name))}"
        
        if result.result == 'pass':
            color = GREEN
        elif result.result == 'skip':
            color = BLUE
        else:
            color = RED
        
        timing = ''
        if result.duration_ms > 0:
            sec = result.duration_ms / 1000
            timing = f" (time {sec:.1f}s"
            if result.memory_kb > 0:
                mem_mb = result.memory_kb / 1024
                timing += f", mem {mem_mb:.1f}MB"
            timing += ")"
        
        with self.print_lock:
            print(f"{name_field} [{color}{result.result}{RESET}]{timing}")
    
    def merge_logs(self):
        """Merge all per-test logs into single test.log."""
        log_file = self.topdir / 'test.log'
        
        # Sort results by name for consistent output order
        sorted_results = sorted(self.results, key=lambda r: r.name)
        
        with open(log_file, 'w') as f:
            # Write header
            f.write(marker() + '\n')
            f.write(detail('DATE', timestamp()) + '\n')
            f.write(detail('TOOL', 'runtests.py') + '\n')
            f.write('\n')
            
            # Write each test log
            for result in sorted_results:
                if result.log_file and result.log_file.exists():
                    content = result.log_file.read_text()
                    f.write(content)
                    f.write('\n')
        
        # Clean up per-test logs unless keeping
        if not self.args.keep_logs:
            for f in self.log_dir.glob('*.log'):
                f.unlink()
            try:
                self.log_dir.rmdir()
            except OSError:
                pass
    
    def merge_coverage(self):
        """Merge all per-test coverage databases."""
        if not self.args.coverage:
            return
        
        # For Perl coverage: we need to merge cover_db.d/* into cover_db
        # Devel::Cover doesn't have a simple merge command, so we use
        # the approach of pointing to the directory and letting 'cover' find all
        
        # Write a note about per-test coverage
        log_file = self.topdir / 'test.log'
        with open(log_file, 'a') as f:
            f.write(marker() + '\n')
            f.write(detail('COVERAGE', 'Per-test databases in cover_db.d/') + '\n')
        
        # For Python coverage: combine using coverage command
        pycov_files = list(self.coverage_dir.glob('*_py'))
        if pycov_files:
            try:
                # Create .coverage file by combining
                result = subprocess.run(
                    ['coverage', 'combine'] + [str(f) for f in pycov_files],
                    cwd=str(self.topdir),
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    check=False
                )
                if result.returncode != 0 and self.args.verbose:
                    print(f"Warning: coverage combine failed (exit {result.returncode})")
                # Move to expected location
                coverage_file = self.topdir / '.coverage'
                pycov_file = self.topdir / 'pycov.dat'
                if coverage_file.exists() and not pycov_file.exists():
                    coverage_file.rename(pycov_file)
            except Exception as e:
                if self.args.verbose:
                    print(f"Warning: coverage combine failed: {e}")
    
    def print_summary(self):
        """Print test summary and return exit code."""
        passed = sum(1 for r in self.results if r.result == 'pass')
        failed = sum(1 for r in self.results if r.result == 'fail')
        skipped = sum(1 for r in self.results if r.result == 'skip')
        killed = sum(1 for r in self.results if r.result == 'kill')
        total = len(self.results)
        
        total_time_ms = sum(r.duration_ms for r in self.results)
        total_mem_kb = sum(r.memory_kb for r in self.results)
        
        # Write counts file
        counts_file = self.topdir / 'test.counts'
        with open(counts_file, 'w') as f:
            f.write(f"start_time {self.start_time}\n")
            for r in self.results:
                f.write(f"{r.result} {r.name}\n")
                if r.duration_ms > 0:
                    f.write(f"elapsed {r.name} {r.duration_ms}\n")
                if r.memory_kb > 0:
                    f.write(f"resident {r.name} {r.memory_kb}\n")
            f.write(f"end_time {time.time()}\n")
        
        # Print summary
        if not self.args.silent:
            total_sec = total_time_ms / 1000
            mem_mb = total_mem_kb / 1024
            
            msg = f"{BOLD}{total} tests executed{RESET}"
            pass_str = f"{GREEN}{passed} passed{RESET}" if passed > 0 else f"{passed} passed"
            fail_str = f"{RED}{failed} failed{RESET}" if failed > 0 else f"{failed} failed"
            skip_str = f"{BLUE}{skipped} skipped{RESET}" if skipped > 0 else f"{skipped} skipped"
            
            print(f"{msg}, {pass_str}, {fail_str}, {skip_str}{RESET}")
            if killed > 0:
                print(f"  {RED}{killed} tests killed (timeout){RESET}")
            print(f"Result log stored in {self.topdir}/test.log")
        
        # Return exit code
        if failed > 0 or killed > 0:
            return 1
        elif skipped > 0:
            return 2
        return 0
    
    def cleanup(self):
        """Cleanup on exit."""
        # Run testsuite_exit
        exit_script = self.topdir / 'bin' / 'testsuite_exit'
        if exit_script.exists():
            try:
                subprocess.run([str(exit_script)], check=False,
                              stdin=subprocess.DEVNULL,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=str(self.topdir))
            except Exception:
                pass
    
    def run(self):
        """Main entry point."""
        try:
            self.setup()
            
            # Discover tests
            tests = self.discover_tests()
            
            if self.args.list:
                # Just list and exit
                for name, path in tests:
                    print(name)
                return 0
            
            if not tests:
                if not self.args.silent:
                    print("No tests found")
                return 0
            
            # Run tests
            self.run_all_tests(tests)
            
            # Merge results
            self.merge_logs()
            self.merge_coverage()
            
            # Print summary
            return self.print_summary()
            
        finally:
            self.cleanup()


def main():
    args = parse_args()
    runner = TestRunner(args)
    sys.exit(runner.run())


if __name__ == '__main__':
    main()
