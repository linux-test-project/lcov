"""
Worker function for parallel test execution.
Must be in a separate module for pickling with ProcessPoolExecutor.
"""
import os
import sys
import time
import subprocess
from pathlib import Path
from dataclasses import dataclass


@dataclass
class TestResult:
    """Result of a test execution."""
    name: str
    result: str
    exit_code: int
    duration_ms: int
    memory_kb: int
    log_file: Path = None
    coverage_dir: Path = None
    error_msg: str = None


def run_test_worker(test_name, test_path, log_dir, topdir, coverage_dir,
                     script_args, timeout, coverage_mode, debug=False):
    """
    Execute a single test and return result.
    Standalone function for ThreadPoolExecutor compatibility.
    """
    import resource
    import sys
    
    # Debug output
    if debug:
        print(f"DEBUG_WORKER: Starting {test_name}", file=sys.stderr)
        sys.stderr.flush()
    
    start_time = time.time()
    result = 'fail'
    exit_code = 1
    error_msg = None
    coverage_subdir = None
    
    # Create per-test log file
    log_name = test_name.replace('/', '_')
    log_file = Path(log_dir) / f"{log_name}.log"
    
    # Setup environment
    env = os.environ.copy()
    env['TOPDIR'] = str(topdir)
    env['TESTDIR'] = str(Path(test_path).parent)
    
    # LCOV_HOME - parent of topdir (tests directory)
    lcov_home = str(Path(topdir).parent)
    env['LCOV_HOME'] = lcov_home
    
    # Set up tool paths like common.mak does
    bindir = str(Path(lcov_home) / 'bin')
    testbindir = str(Path(topdir) / 'bin')
    scriptdir = str(Path(lcov_home) / 'share' / 'lcov' / 'support-scripts')
    if not Path(scriptdir).exists():
        scriptdir = str(Path(lcov_home) / 'scripts')
    
    env['PATH'] = bindir + ':' + testbindir + ':' + env.get('PATH', '')
    env['LANG'] = 'C'
    
    # Export tool variables
    env['LCOV_TOOL'] = bindir + '/lcov'
    env['GENHTML_TOOL'] = bindir + '/genhtml'
    env['GENINFO_TOOL'] = bindir + '/geninfo'
    env['PERL2LCOV_TOOL'] = bindir + '/perl2lcov'
    env['LLVM2LCOV_TOOL'] = bindir + '/llvm2lcov'
    env['PY2LCOV_TOOL'] = bindir + '/py2lcov'
    env['XML2LCOV_TOOL'] = bindir + '/xml2lcov'
    env['SPREADSHEET_TOOL'] = scriptdir + '/spreadsheet.py'
    
    # Export convenience variables
    lcovrc = str(Path(topdir) / 'lcovrc')
    env['LCOV'] = env['LCOV_TOOL'] + ' --config-file ' + lcovrc
    env['GENHTML'] = env['GENHTML_TOOL'] + ' --config-file ' + lcovrc
    
    # Export info file paths
    env['ZEROINFO'] = str(Path(topdir) / 'zero.info')
    env['ZEROCOUNTS'] = str(Path(topdir) / 'zero.counts')
    env['FULLINFO'] = str(Path(topdir) / 'full.info')
    env['FULLCOUNTS'] = str(Path(topdir) / 'full.counts')
    env['TARGETINFO'] = str(Path(topdir) / 'target.info')
    env['TARGETCOUNTS'] = str(Path(topdir) / 'target.counts')
    env['PART1INFO'] = str(Path(topdir) / 'part1.info')
    env['PART1COUNTS'] = str(Path(topdir) / 'part1.counts')
    env['PART2INFO'] = str(Path(topdir) / 'part2.info')
    env['PART2COUNTS'] = str(Path(topdir) / 'part2.counts')
    
    # Coverage setup - let common.tst handle coverage wrapping
    # The test scripts source common.tst which sets up the COVER variable.
    if coverage_mode:
        coverage_subdir = Path(coverage_dir) / test_name.replace('/', '_')
        coverage_subdir.mkdir(parents=True, exist_ok=True)
        env['COVER_DB'] = str(coverage_subdir)
        env['COVERAGE_COMMAND'] = 'coverage'
        
        # Ensure the parent coverage directory exists for Python coverage files
        # Python coverage creates files like: cover_db.d/test_name_py
        Path(coverage_dir).mkdir(parents=True, exist_ok=True)
    
    # Build command
    cmd = [test_path]
    
    # For coverage mode, pass --coverage flag to test script and prepend coverage for scripts
    if coverage_mode:
        # Pass --coverage flag to test script so it can set up PYCOVER etc.
        cmd.append('--coverage')
        cmd.append(str(coverage_subdir))
        
        # Check script type and prepend appropriate coverage command
        test_path_str = str(test_path)
        if test_path_str.endswith('.pl'):
            # Perl script - prepend perl with coverage module
            # For standalone Perl scripts, we need to wrap with Devel::Cover
            cmd = ['perl', '-MDevel::Cover=-db,' + str(coverage_subdir) +
                   ',-coverage,statement,branch,condition,subroutine,-silent,1',
                   test_path]
        elif test_path_str.endswith('.py'):
            # Python script - prepend coverage run
            # The Python coverage file will be at coverage_subdir_py
            pycov_file = Path(coverage_dir) / f"{test_name.replace('/', '_')}_py"
            cmd = ['coverage', 'run', '--branch', '--source', str(Path(topdir).parent),
                   '--data-file', str(pycov_file), test_path]
            cmd.append('--coverage')
            cmd.append(str(coverage_subdir))
        else:
            # Shell script - common.tst will handle via COVER variable
            cmd.append('--coverage')
            cmd.append(str(coverage_subdir))
    
    # Add script args if provided
    if script_args:
        cmd.append('--')
        # Split script_args into individual arguments
        import shlex
        cmd.extend(shlex.split(script_args))
    
    # Write log header
    try:
        with open(log_file, 'w') as f:
            f.write('\n')
            f.write('=' * 70 + '\n')
            from datetime import datetime
            f.write(f"DATE .......: {datetime.now().strftime('%Y-%m-%d %H:%M:%S %z')}\n")
            f.write(f"TESTNAME ...: {test_name}\n")
            f.write(f"COMMAND ....: \"{test_path}\"\n")
            f.write(f"OUTPUT .....:\n")
    except Exception:
        pass
    
    # Run test
    try:
        proc = subprocess.run(
            cmd,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            universal_newlines=True,
            cwd=str(Path(test_path).parent),
            env=env,
            timeout=timeout
        )
        
        exit_code = proc.returncode
        result = 'pass' if exit_code == 0 else 'fail'
        
        # Write output to log
        try:
            with open(log_file, 'a') as f:
                for line in proc.stdout.splitlines():
                    f.write(f"  {line}\n")
                if proc.stderr:
                    f.write(f"\n  STDERR:\n")
                    for line in proc.stderr.splitlines():
                        f.write(f"    {line}\n")
        except Exception:
            pass
        
    except subprocess.TimeoutExpired:
        result = 'fail'
        exit_code = 124
        error_msg = f"Timeout after {timeout}s"
        try:
            with open(log_file, 'a') as f:
                f.write(f"\n  ERROR: {error_msg}\n")
        except Exception:
            pass
    except Exception as e:
        result = 'fail'
        exit_code = 1
        error_msg = str(e)
        try:
            with open(log_file, 'a') as f:
                f.write(f"\n  ERROR: {error_msg}\n")
        except Exception:
            pass
    
    # Get memory usage
    memory_kb = 0
    try:
        # Get maximum resident set size
        memory_kb = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
        if memory_kb > 0:
            # Convert to KB (on Linux it's already in KB, on macOS it's in bytes)
            import platform
            if platform.system() == 'Darwin':
                memory_kb = memory_kb // 1024
    except Exception:
        pass
    
    duration_ms = int((time.time() - start_time) * 1000)
    
    # Debug output
    if debug:
        print(f"DEBUG_WORKER: Finished {test_name} (result={result})", file=sys.stderr)
        sys.stderr.flush()
    
    # Finalize log
    try:
        with open(log_file, 'a') as f:
            f.write(f"EXITCODE ...: {exit_code}\n")
            if error_msg:
                f.write(f"ERROR ......: {error_msg}\n")
            f.write(f"TIME .......: {duration_ms}ms\n")
            f.write(f"MEM ........: {memory_kb}kB\n")
            f.write(f"RESULT .....: {result}\n")
    except Exception:
        pass
    
    return TestResult(
        name=test_name,
        result=result,
        exit_code=exit_code,
        duration_ms=duration_ms,
        memory_kb=memory_kb,
        log_file=log_file,
        coverage_dir=coverage_subdir,
        error_msg=error_msg
    )
