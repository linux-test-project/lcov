# some common utilities for lcov-related scripts

use strict;
use warnings;
require Exporter;

package lcovutil;

use File::Path qw(rmtree);
use File::Basename qw(basename dirname);
use File::Temp qw /tempdir/;
use File::Spec;
use Scalar::Util qw/looks_like_number/;
use Cwd qw/abs_path getcwd/;
use Storable qw(dclone);
use Capture::Tiny;
use Module::Load::Conditional qw(check_install);
use Digest::MD5 qw(md5_base64);
use FindBin;
use Getopt::Long;
use DateTime;
use Config;
use POSIX;
use Fcntl qw(:flock SEEK_END);

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw($tool_name $tool_dir $lcov_version $lcov_url $VERSION
     @temp_dirs set_tool_name
     info warn_once set_info_callback init_verbose_flag $verbose
     debug $debug
     append_tempdir create_temp_dir temp_cleanup folder_is_empty $tmp_dir $preserve_intermediates
     summarize_messages define_errors
     parse_ignore_errors ignorable_error ignorable_warning
     is_ignored message_count explain_once
     die_handler warn_handler abort_handler

     $maxParallelism $maxMemory init_parallel_params current_process_size
     $memoryPercentage $max_fork_fails $fork_fail_timeout
     save_profile merge_child_profile save_cmd_line

     @opt_rc apply_rc_params $split_char parseOptions
     strip_directories
     @file_subst_patterns subst_file_name
     @comments

     $br_coverage $func_coverage $mcdc_coverage
     @cpp_demangle do_mangle_check $demangle_cpp_cmd
     $cpp_demangle_tool $cpp_demangle_params
     get_overall_line rate

     $FILTER_BRANCH_NO_COND $FILTER_FUNCTION_ALIAS
     $FILTER_EXCLUDE_REGION $FILTER_EXCLUDE_BRANCH $FILTER_LINE
     $FILTER_LINE_CLOSE_BRACE $FILTER_BLANK_LINE $FILTER_LINE_RANGE
     $FILTER_TRIVIAL_FUNCTION $FILTER_DIRECTIVE
     $FILTER_MISSING_FILE $FILTER_INITIALIZER_LIST
     $FILTER_EXCEPTION_BRANCH $FILTER_ORPHAN_BRANCH
     @cov_filter
     $EXCL_START $EXCL_STOP $EXCL_BR_START $EXCL_BR_STOP
     $EXCL_EXCEPTION_BR_START $EXCL_EXCEPTION_BR_STOP
     $EXCL_LINE $EXCL_BR_LINE $EXCL_EXCEPTION_LINE
     $UNREACHABLE_START $UNREACHABLE_STOP $UNREACHABLE_LINE
     @exclude_file_patterns @include_file_patterns %excluded_files
     @omit_line_patterns @exclude_function_patterns $case_insensitive
     munge_file_patterns warn_file_patterns transform_pattern
     parse_cov_filters summarize_cov_filters
     disable_cov_filters reenable_cov_filters is_filter_enabled
     filterStringsAndComments simplifyCode balancedParens
     set_extensions
     $source_filter_lookahead $source_filter_bitwise_are_conditional
     $exclude_exception_branch
     $derive_function_end_line $derive_function_end_line_all_files
     $trivial_function_threshold
     $filter_blank_aggressive

     $lcov_filter_parallel $lcov_filter_chunk_size

     %lcovErrors $ERROR_GCOV $ERROR_SOURCE $ERROR_GRAPH $ERROR_MISMATCH
     $ERROR_BRANCH $ERROR_EMPTY $ERROR_FORMAT $ERROR_VERSION $ERROR_UNUSED
     $ERROR_PACKAGE $ERROR_CORRUPT $ERROR_NEGATIVE $ERROR_COUNT $ERROR_PATH
     $ERROR_UNSUPPORTED $ERROR_DEPRECATED $ERROR_INCONSISTENT_DATA
     $ERROR_CALLBACK $ERROR_RANGE $ERROR_UTILITY $ERROR_USAGE $ERROR_INTERNAL
     $ERROR_PARALLEL $ERROR_PARENT $ERROR_CHILD $ERROR_FORK
     $ERROR_EXCESSIVE_COUNT $ERROR_MISSING $ERROR_UNREACHABLE
     report_parallel_error report_exit_status check_parent_process
     report_unknown_child

     $ERROR_UNMAPPED_LINE $ERROR_UNKNOWN_CATEGORY $ERROR_ANNOTATE_SCRIPT
     $stop_on_error

     @extractVersionScript $verify_checksum $compute_file_version

     configure_callback cleanup_callbacks

     is_external @internal_dirs $opt_no_external @build_directory
     $default_precision check_precision

     system_no_output $devnull $dirseparator

     %tlaColor %tlaTextColor use_vanilla_color %pngChar %pngMap
     %dark_palette %normal_palette parse_w3cdtf
);

our @ignore;
our @message_count;
our @expected_message_count;
our %message_types;
our $message_log;
our $message_filename;
our $suppressAfter = 100;    # stop warning after this number of messages
our %ERROR_ID;
our %ERROR_NAME;
our $tool_dir  = "$FindBin::RealBin";
our $tool_name = basename($0);          # import from lcovutil module
our $VERSION   = `"$tool_dir"/get_version.sh --full`;
chomp($VERSION);
our $lcov_version = 'LCOV version ' . $VERSION;
our $lcov_url     = "https://github.com//linux-test-project/lcov";
our @temp_dirs;
our $tmp_dir = '/tmp';          # where to put temporary/intermediate files
our $preserve_intermediates;    # this is useful only for debugging
our $sort_inputs;    # sort input file lists - to reduce unpredictability
our $devnull      = File::Spec->devnull();    # portable way to do it
our $dirseparator = ($^O =~ /Win/) ? '\\' : '/';
our $interp       = ($^O =~ /Win/) ? $^X : undef;

our $debug   = 0;    # if set, emit debug messages
our $verbose = 0;    # default level - higher to enable additional logging

our $split_char = ',';    # by default: split on comma

# share common definition for all error types.
# Note that geninfo cannot produce some types produced by genhtml, and vice
# versa.  Easier to maintain a common definition.
our $ERROR_GCOV;
our $ERROR_SOURCE;
our $ERROR_GRAPH;
our $ERROR_FORMAT;               # bad record in .info file
our $ERROR_EMPTY;                # no records found in info file
our $ERROR_VERSION;
our $ERROR_UNUSED;               # exclude/include/substitute pattern not used
our $ERROR_MISMATCH;
our $ERROR_BRANCH;               # branch numbering is not correct
our $ERROR_PACKAGE;              # missing utility package
our $ERROR_CORRUPT;              # corrupt file
our $ERROR_NEGATIVE;             # unexpected negative count in coverage data
our $ERROR_COUNT;                # too many messages of type
our $ERROR_UNSUPPORTED;          # some unsupported feature or usage
our $ERROR_PARALLEL;             # error in fork/join
our $ERROR_DEPRECATED;           # deprecated feature
our $ERROR_CALLBACK;             # callback produced an error
our $ERROR_INCONSISTENT_DATA;    # something wrong with .info
our $ERROR_UNREACHABLE;          # coverpoint hit in "unreachable" region
our $ERROR_RANGE;                # line number out of range
our $ERROR_UTILITY;              # some tool failed - e.g., 'find'
our $ERROR_USAGE;                # misusing some feature
our $ERROR_PATH;                 # path issues
our $ERROR_INTERNAL;             # tool issue
our $ERROR_PARENT;               # parent went away so child should die
our $ERROR_CHILD;                # nonzero child exit status
our $ERROR_FORK;                 # fork failed
our $ERROR_EXCESSIVE_COUNT;      # suspiciously large hit count
our $ERROR_MISSING;              # file missing/not found
# genhtml errors
our $ERROR_UNMAPPED_LINE;        # inconsistent coverage data
our $ERROR_UNKNOWN_CATEGORY;     # we did something wrong with inconsistent data
our $ERROR_ANNOTATE_SCRIPT;      # annotation failed somehow

my @lcovErrs = (["annotate", \$ERROR_ANNOTATE_SCRIPT],
                ["branch", \$ERROR_BRANCH],
                ["callback", \$ERROR_CALLBACK],
                ["category", \$ERROR_UNKNOWN_CATEGORY],
                ["child", \$ERROR_CHILD],
                ["corrupt", \$ERROR_CORRUPT],
                ["count", \$ERROR_COUNT],
                ["deprecated", \$ERROR_DEPRECATED],
                ["empty", \$ERROR_EMPTY],
                ['excessive', \$ERROR_EXCESSIVE_COUNT],
                ["format", \$ERROR_FORMAT],
                ["fork", \$ERROR_FORK],
                ["gcov", \$ERROR_GCOV],
                ["graph", \$ERROR_GRAPH],
                ["inconsistent", \$ERROR_INCONSISTENT_DATA],
                ["internal", \$ERROR_INTERNAL],
                ["mismatch", \$ERROR_MISMATCH],
                ["missing", \$ERROR_MISSING],
                ["negative", \$ERROR_NEGATIVE],
                ["package", \$ERROR_PACKAGE],
                ["parallel", \$ERROR_PARALLEL],
                ["parent", \$ERROR_PARENT],
                ["path", \$ERROR_PATH],
                ["range", \$ERROR_RANGE],
                ["source", \$ERROR_SOURCE],
                ["unmapped", \$ERROR_UNMAPPED_LINE],
                ["unreachable", \$ERROR_UNREACHABLE],
                ["unsupported", \$ERROR_UNSUPPORTED],
                ["unused", \$ERROR_UNUSED],
                ['usage', \$ERROR_USAGE],
                ['utility', \$ERROR_UTILITY],
                ["version", \$ERROR_VERSION],);

our %lcovErrors;

our $stop_on_error;                # attempt to keep going
our $treat_warning_as_error = 0;
our $warn_once_per_file     = 1;
our $excessive_count_threshold;    # default not set: don't check

our $br_coverage   = 0;    # If set, generate branch coverage statistics
our $mcdc_coverage = 0;    # MC/DC
our $func_coverage = 1;    # If set, generate function coverage statistics

# for external file filtering
our @internal_dirs;
our $opt_no_external;

# Where code was built/where .gcno files can be found
# (if .gcno files are in a different place than the .gcda files)
# also used by genhtml to match diff file entries to .info file
our @build_directory;

our @configured_callbacks;

# optional callback to keep track of whatever user decides is important
our @contextCallback;
our $contextCallback;

# filename substitutions
our @file_subst_patterns;
# resolve callback
our @resolveCallback;
our $resolveCallback;
our %resolveCache;

# C++ demangling
our @cpp_demangle;        # the options passed in
our $demangle_cpp_cmd;    # the computed command string
# deprecated: demangler for C++ function names is c++filt
our $cpp_demangle_tool;
# Deprecated:  prefer -Xlinker approach with @cpp_dmangle_tool
our $cpp_demangle_params;

# version extract may be expensive - so only do it once
our %versionCache;
our @extractVersionScript;    # script/callback to find version ID of file
our $versionCallback;
our $verify_checksum;    # compute and/or check MD5 sum of source code lines

our $check_file_existence_before_callback = 1;
our $check_data_consistency               = 1;

# Specify coverage rate default precision
our $default_precision = 1;

# undef indicates not set by command line or RC option - so default to
# sequential processing
our $maxParallelism;
our $max_fork_fails    = 5;     # consecutive failures
our $fork_fail_timeout = 10;    # how long to wait, in seconds
our $maxMemory;                 # zero indicates no memory limit to parallelism
our $memoryPercentage;
our $in_child_process   = 0;
our $max_tasks_per_core = 20;    # maybe default to 0?

our $lcov_filter_parallel = 1;   # enable by default
our $lcov_filter_chunk_size;

our $fail_under_lines;
our $fail_under_branches;

our $fix_inconsistency = 1;

sub default_info_impl(@);

our $info_callback = \&default_info_impl;

# filter classes that may be requested
# don't report BRDA data for line which seem to have no conditionals
#   These may be from C++ exception handling (for example) - and are not
#   interesting to users.
our $FILTER_BRANCH_NO_COND;
# don't report line coverage for closing brace of a function
#   or basic block, if the immediate predecessor line has the same count.
our $FILTER_LINE_CLOSE_BRACE;
# merge functions which appear on same file/line - guess that that
#   they are all the same
our $FILTER_FUNCTION_ALIAS;
# region between LCOV EXCL_START/STOP
our $FILTER_EXCLUDE_REGION;
# region between LCOV EXCL_BR_START/STOP
our $FILTER_EXCLUDE_BRANCH;
# empty line
our $FILTER_BLANK_LINE;
# out of range line - beyond end of file
our $FILTER_LINE_RANGE;
# backward compatibility: empty line, close brace
our $FILTER_LINE;
# filter initializer list-like stuff
our $FILTER_INITIALIZER_LIST;
# remove functions which have only a single line
our $FILTER_TRIVIAL_FUNCTION;
# remove compiler directive lines which llvm-cov seems to generate
our $FILTER_DIRECTIVE;
# remove missing source file
our $FILTER_MISSING_FILE;
# remove branches marked as related to exceptions
our $FILTER_EXCEPTION_BRANCH;
# remove lone branch in block - it can't be an actual conditional
our $FILTER_ORPHAN_BRANCH;
# MC/DC with single expression is identical to branch
our $FILTER_MCDC_SINGLE;
our $FILTER_OMIT_PATTERNS;    # special/somewhat faked filter

our %COVERAGE_FILTERS = ("branch"        => \$FILTER_BRANCH_NO_COND,
                         'brace'         => \$FILTER_LINE_CLOSE_BRACE,
                         'blank'         => \$FILTER_BLANK_LINE,
                         'directive'     => \$FILTER_DIRECTIVE,
                         'range'         => \$FILTER_LINE_RANGE,
                         'line'          => \$FILTER_LINE,
                         'initializer'   => \$FILTER_INITIALIZER_LIST,
                         'function'      => \$FILTER_FUNCTION_ALIAS,
                         'missing'       => \$FILTER_MISSING_FILE,
                         'region'        => \$FILTER_EXCLUDE_REGION,
                         'branch_region' => \$FILTER_EXCLUDE_BRANCH,
                         'exception'     => \$FILTER_EXCEPTION_BRANCH,
                         'orphan'        => \$FILTER_ORPHAN_BRANCH,
                         'mcdc'          => \$FILTER_MCDC_SINGLE,
                         "trivial"       => \$FILTER_TRIVIAL_FUNCTION,);
our @cov_filter;    # 'undef' if filter is not enabled,
                    # [line_count, coverpoint_count] histogram if
                    #   filter is enabled: number of applications
                    #   of this filter

our $EXCL_START = "LCOV_EXCL_START";
our $EXCL_STOP  = "LCOV_EXCL_STOP";
# Marker to say that this code is unreachable - so exclude from
#   report, but also generate error if anything in the region is hit
our $UNREACHABLE_START                = "LCOV_UNREACHABLE_START";
our $UNREACHABLE_STOP                 = "LCOV_UNREACHABLE_STOP";
our $UNREACHABLE_LINE                 = "LCOV_UNREACHABLE_LINE";
our $retainUnreachableCoverpointIfHit = 1;
# Marker to exclude branch coverage but keep function and line coverage
our $EXCL_BR_START = "LCOV_EXCL_BR_START";
our $EXCL_BR_STOP  = "LCOV_EXCL_BR_STOP";
# marker to exclude exception branches but keep other branches
our $EXCL_EXCEPTION_BR_START = 'LCOV_EXCL_EXCEPTION_BR_START';
our $EXCL_EXCEPTION_BR_STOP  = 'LCOV_EXCL_EXCEPTION_BR_STOP';
# exclude on this line
our $EXCL_LINE           = 'LCOV_EXCL_LINE';
our $EXCL_BR_LINE        = 'LCOV_EXCL_BR_LINE';
our $EXCL_EXCEPTION_LINE = 'LCOV_EXCL_EXCEPTION_BR_LINE';

our @exclude_file_patterns;
our @include_file_patterns;
our %excluded_files;
our $case_insensitive                   = 0;
our $exclude_exception_branch           = 0;
our $derive_function_end_line           = 1;
our $derive_function_end_line_all_files = 0;    # by default, C only
our $trivial_function_threshold         = 5;

# list of regexps applied to line text - if exclude if matched
our @omit_line_patterns;
# HGC: does not really make sense to support command-line '--unreachable-line
#  patterns.  Unreachable is typically a branch clause/structural feature -
#  as opposed to an 'omit' pattern is typically trace/debug or logging code
#  which may or may not be executed (and we don't care)
#our @unreachable_line_patterns;
our @exclude_function_patterns;
# need a pattern copy that we don't disable for function message suppressions
our @suppress_function_patterns;

our %languageExtensions = ('c'      => 'c|h|i|C|H|I|icc|cpp|cc|cxx|hh|hpp|hxx',
                           'rtl'    => 'v|vh|sv|vhdl?',
                           'perl'   => 'pl|pm',
                           'python' => 'py',
                           'java'   => 'java');

our $info_file_pattern = '*.info';

# don't look more than 10 lines ahead when filtering (default)
our $source_filter_lookahead = 10;
# by default, don't treat expressions containing bitwise operators '|', '&', '~'
#   as conditional in bogus branch filtering
our $source_filter_bitwise_are_conditional = 0;
# filter out blank lines whether they are hit or not
our $filter_blank_aggressive = 0;

our %dark_palette = ('COLOR_00' => "e4e4e4",
                     'COLOR_01' => "58a6ff",
                     'COLOR_02' => "8b949e",
                     'COLOR_03' => "3b4c71",
                     'COLOR_04' => "006600",
                     'COLOR_05' => "4b6648",
                     'COLOR_06' => "495366",
                     'COLOR_07' => "143e4f",
                     'COLOR_08' => "1c1e23",
                     'COLOR_09' => "202020",
                     'COLOR_10' => "801b18",
                     'COLOR_11' => "66001a",
                     'COLOR_12' => "772d16",
                     'COLOR_13' => "796a25",
                     'COLOR_14' => "000000",
                     'COLOR_15' => "58a6ff",
                     'COLOR_16' => "eeeeee",
                     'COLOR_17' => "E5DBDB",
                     'COLOR_18' => "82E0AA",
                     'COLOR_19' => 'F9E79F',
                     'COLOR_20' => 'EC7063',);
our %normal_palette = ('COLOR_00' => "000000",
                       'COLOR_01' => "00cb40",
                       'COLOR_02' => "284fa8",
                       'COLOR_03' => "6688d4",
                       'COLOR_04' => "a7fc9d",
                       'COLOR_05' => "b5f7af",
                       'COLOR_06' => "b8d0ff",
                       'COLOR_07' => "cad7fe",
                       'COLOR_08' => "dae7fe",
                       'COLOR_09' => "efe383",
                       'COLOR_10' => "ff0000",
                       'COLOR_11' => "ff0040",
                       'COLOR_12' => "ff6230",
                       'COLOR_13' => "ffea20",
                       'COLOR_14' => "ffffff",
                       'COLOR_15' => "284fa8",
                       'COLOR_16' => "ffffff",
                       'COLOR_17' => "E5DBDB",    # very light pale grey/blue
                       'COLOR_18' => "82E0AA",    # light green
                       'COLOR_19' => 'F9E79F',    # light yellow
                       'COLOR_20' => 'EC7063',    # lighter red
);

our %tlaColor = ("UBC" => "#FDE007",
                 "GBC" => "#448844",
                 "LBC" => "#CC6666",
                 "CBC" => "#CAD7FE",
                 "GNC" => "#B5F7AF",
                 "UNC" => "#FF6230",
                 "ECB" => "#CC66FF",
                 "EUB" => "#DDDDDD",
                 "GIC" => "#30CC37",
                 "UIC" => "#EEAA30",
                 # we don't actually use a color for deleted code.
                 #  ... it is deleted.  Does not appear
                 "DUB" => "#FFFFFF",
                 "DCB" => "#FFFFFF",);
# colors for the text in the PNG image of the corresponding TLA line
our %tlaTextColor = ("UBC" => "#aaa005",
                     "GBC" => "#336633",
                     "LBC" => "#994444",
                     "CBC" => "#98a0aa",
                     "GNC" => "#90a380",
                     "UNC" => "#aa4020",
                     "ECB" => "#663388",
                     "EUB" => "#777777",
                     "GIC" => "#18661c",
                     "UIC" => "#aa7718",
                     # we don't actually use a color for deleted code.
                     #  ... it is deleted.  Does not appear
                     "DUB" => "#FFFFFF",
                     "DCB" => "#FFFFFF",);

our %pngChar = ('CBC' => '=',
                'LBC' => '=',
                'GBC' => '-',
                'UBC' => '-',
                'ECB' => '<',
                'EUB' => '<',
                'GIC' => '>',
                'UIC' => '>',
                'GNC' => '+',
                'UNC' => '+',);

our %pngMap = ('=' => ['CBC', 'LBC']
               ,    # 0th element 'covered', 1st element 'not covered
               '-' => ['GBC', 'UBC'],
               '<' => ['ECB', 'EUB'],
               '>' => ['GIC', 'UIC'],
               '+' => ['GNC', 'UNC'],);

our @opt_rc;        # list of command line RC overrides

our %profileData;
our $profile;       # the 'enable' flag/name of output file

# need to defer any errors until after the options have been
#  processed as user might have suppressed the error we were
#  trying to emit
my @deferred_rc_errors;    # ([err|warn, key, string])

sub set_tool_name($)
{
    $tool_name = shift;
}

#
# system_no_output(mode, parameters)
#
# Call an external program using PARAMETERS while suppressing depending on
# the value of MODE:
#
#   MODE & 1: suppress STDOUT (return empty string)
#   MODE & 2: suppress STDERR (return empty string)
#   MODE & 4: redirect to string
#
# Return (stdout, stderr, rc):
#    stdout: stdout string or ''
#    stderr: stderr string or ''
#    0 on success, non-zero otherwise
#

sub system_no_output($@)
{
    my $mode = shift;
    # all current uses redirect both stdout and stderr
    my @args = @_;
    my ($stdout, $stderr, $code) = Capture::Tiny::capture {
        system(@args);
    };
    if (0 == ($mode & 4)) {
        $stdout = '' if $mode & 0x1;
        $stderr = '' if $mode & 0x2;
    } else {
        print(STDOUT $stdout) unless $mode & 0x1;
        print(STDERR $stderr) unless $mode & 0x2;
    }
    return ($stdout, $stderr, $code);
}

#
# info(printf_parameter)
#
# Use printf to write PRINTF_PARAMETER to stdout only when not --quiet
#

sub default_info_impl(@)
{
    # Print info string
    printf(@_);
}

sub set_info_callback($)
{
    $info_callback = shift;
}

sub init_verbose_flag($)
{
    my $quiet = shift;
    $lcovutil::verbose -= $quiet;
}

sub info(@)
{
    my $level = 0;
    if ($_[0] =~ /^-?[0-9]+$/) {
        $level = shift;
    }
    &{$info_callback}(@_)
        if ($level <= $lcovutil::verbose);

}

sub debug
{
    my $level = 0;
    if ($_[0] =~ /^[0-9]+$/) {
        $level = shift;
    }
    my $msg = shift;
    print(STDERR "DEBUG: $msg")
        if ($level < $lcovutil::debug);
}

sub temp_cleanup()
{
    if (@temp_dirs) {
        # Ensure temp directory is not in use by current process
        my $cwd = Cwd::getcwd();
        chdir(File::Spec->rootdir());
        info("Removing temporary directories.\n");
        foreach (@temp_dirs) {
            rmtree($_);
        }
        @temp_dirs = ();
        chdir($cwd);
    }
}

#
# create_temp_dir()
#
# Create a temporary directory and return its path.
#
# Die on error.
#

sub create_temp_dir()
{
    my $dir = tempdir(DIR     => $lcovutil::tmp_dir,
                      CLEANUP => !defined($lcovutil::preserve_intermediates));
    if (!defined($dir)) {
        die("cannot create temporary directory\n");
    }
    append_tempdir($dir);
    return $dir;
}

sub append_tempdir($)
{
    push(@temp_dirs, @_);
}

sub _msg_handler
{
    my ($msg, $error) = @_;

    if (!($debug || $verbose > 0 || exists($ENV{LCOV_SHOW_LOCATION}))) {
        $msg =~ s/ at \S+ line \d+\.$//;
    }
    # Enforce consistent "WARNING/ERROR:" message prefix
    $msg =~ s/^(error|warning):\s+//i;
    my $type = $error ? 'ERROR' : 'WARNING';

    my $txt = "$tool_name: $type: $msg";
    if ($message_log && 'GLOB' eq ref($message_log)) {
        flock($message_log, LOCK_EX);
        # don't bother to seek...assume modern O_APPEND semantics
        #seek($message_log, 0, SEEK_END);
        print $message_log $txt;
        flock($message_log, LOCK_UN);
    }
    return $txt;
}

sub warn_handler($$)
{
    print(STDERR _msg_handler(@_));
}

sub die_handler($)
{
    die(_msg_handler(@_, 1));
}

sub abort_handler($)
{
    temp_cleanup();
    exit(1);
}

sub count_cores()
{
    # how many cores?
    $maxParallelism = 1;
    #linux solution...
    if (open my $handle, '/proc/cpuinfo') {
        $maxParallelism = scalar(map /^processor/, <$handle>);
        close($handle) or die("unable to close /proc/cpuinfo: $!\n");
    }
}

our $use_MemoryProcess;

sub read_proc_vmsize
{
    if (open(PROC, "<", '/proc/self/stat')) {
        my $str = do { local $/; <PROC> };    # slurp whole thing
        close(PROC) or die("unable to close /proc/self/stat: $!\n");
        my @data = split(' ', $str);
        return $data[23 - 1];                 # man proc - vmsize is at index 22
    } else {
        lcovutil::ignorable_error($lcovutil::ERROR_PACKAGE,
                                  "unable to open: $!");
        return 0;
    }
}

sub read_system_memory
{
    # NOTE:  not sure how to do this on windows...
    my $total = 0;
    eval {
        my $f = InOutFile->in('/proc/meminfo');
        my $h = $f->hdl();
        while (<$h>) {
            if (/MemTotal:\s+(\d+) kB/) {
                $total = $1 * 1024;    # read #kB
                last;
            }
        }
    };
    if ($@) {
        lcovutil::ignorable_error($lcovutil::ERROR_PACKAGE, $@);
    }
    return $total;
}

sub init_parallel_params()
{
    if (!defined($lcovutil::maxParallelism)) {
        $lcovutil::maxParallelism = 1;
    } elsif (0 == $lcovutil::maxParallelism) {
        lcovutil::count_cores();
        info("Found $maxParallelism cores.\n");
    }

    if (1 != $lcovutil::maxParallelism &&
        (defined($lcovutil::maxMemory) ||
            defined($lcovutil::memoryPercentage))
    ) {

        # need Memory::Process to enable the maxMemory feature
        my $cwd = Cwd::getcwd();
        #debug("init: CWD is $cwd\n");

        eval {
            require Memory::Process;
            Memory::Process->import();
            $use_MemoryProcess = 1;
        };
        # will have done 'cd /' in the die_handler - if Mem::Process not found
        #debug("init: chdir back to $cwd\n");
        chdir($cwd);
        if ($@) {
            push(
                @deferred_rc_errors,
                [   1,
                    $lcovutil::ERROR_PACKAGE,
                    "package Memory::Process is required to control memory consumption during parallel operations: $@"
                ]);
            $use_MemoryProcess = 0;
        }
    }

    if (defined($lcovutil::maxMemory)) {
        $lcovutil::maxMemory *= 1 << 20;
    } elsif (defined($lcovutil::memoryPercentage)) {
        if ($lcovutil::memoryPercentage !~ /^\d+\.?\d*$/ ||
            $lcovutil::memoryPercentage <= 0) {
            push(
                @deferred_rc_errors,
                [   1,
                    $lcovutil::ERROR_USAGE,
                    "memory_percentage '$lcovutil::memoryPercentage' is not a valid value"
                ]);
            $lcovutil::memoryPercentage = 100;
        }
        $lcovutil::maxMemory =
            read_system_memory() * ($lcovutil::memoryPercentage / 100.0);
        if ($maxMemory) {
            my $v    = $maxMemory / ((1 << 30) * 1.0);
            my $unit = 'Gb';
            if ($v < 1.0) {
                $unit = 'Mb';
                $v    = $maxMemory / ((1 << 20) * 1.0);
            }
            info(sprintf("Setting memory throttle limit to %0.1f %s.\n",
                         $v, $unit
            ));
        }
    } else {
        $lcovutil::maxMemory = 0;
    }
    if (1 != $lcovutil::maxParallelism &&    # no memory limits if not parallel
        0 != $lcovutil::maxMemory
    ) {
        if (!$use_MemoryProcess) {
            lcovutil::info(
                     "Attempting to retrieve memory size from /proc instead\n");
            # check if we can get this from /proc (i.e., are we on linux?)
            if (0 == read_proc_vmsize()) {
                $lcovutil::maxMemory = 0;    # turn off that feature
                lcovutil::info(
                    "Continuing execution without Memory::Process or /proc.  Note that your maximum memory constraint will be ignored\n"
                );
            }
        }
    }
    InOutFile::checkGzip()  # we know we are going to use gzip for intermediates
        if 1 != $lcovutil::maxParallelism;
}

our $memoryObj;

sub current_process_size
{
    if ($use_MemoryProcess) {
        $memoryObj = Memory::Process->new
            unless defined($memoryObj);
        $memoryObj->record('size');
        my $arr = $memoryObj->state;
        $memoryObj->reset();
        # current vmsize in kB is element 2 of array
        return $arr->[0]->[2] * 1024;    # return total in bytes
    } else {
        # assume we are on linux - and get it from /proc
        return read_proc_vmsize();
    }
}

sub merge_child_profile($)
{
    my $profile = shift;
    while (my ($key, $d) = each(%$profile)) {
        if ('HASH' eq ref($d)) {
            while (my ($f, $t) = each(%$d)) {
                if ('HASH' eq ref($t)) {
                    while (my ($x, $y) = each(%$t)) {
                        lcovutil::ignorable_error($lcovutil::ERROR_INTERNAL,
                                   "unexpected duplicate key $x=$y at $key->$f")
                            if exists($lcovutil::profileData{$key}{$f}{$x});
                        $lcovutil::profileData{$key}{$f}{$x} = $y;
                    }
                } else {
                    # 'total' key appears in genhtml report
                    # the others in geninfo.
                    if (exists($lcovutil::profileData{$key}{$f})
                        &&
                        grep(/^$key$/,
                             (   'version', 'parse',
                                 'append', 'total',
                                 'resolve', 'derive_end',
                                 'check_consistency'))
                    ) {
                        $lcovutil::profileData{$key}{$f} += $t;
                    } else {
                        lcovutil::ignorable_error($lcovutil::ERROR_INTERNAL,
                            "unexpected duplicate key $f=$t in $key:$lcovutil::profileData{$key}{$f}"
                        ) if exists($lcovutil::profileData{$key}{$f});
                        $lcovutil::profileData{$key}{$f} = $t;
                    }
                }
            }
        } else {
            lcovutil::ignorable_error($lcovutil::ERROR_INTERNAL,
                              "unexpected duplicate key $key=$d in profileData")
                if exists($lcovutil::profileData{$key});
            $lcovutil::profileData{$key} = $d;
        }
    }
}

sub save_cmd_line($$)
{
    my ($argv, $bin) = @_;
    my $cmd = $lcovutil::tool_name;
    $lcovutil::profileData{config}{bin} = "$FindBin::RealBin";
    foreach my $arg (@$argv) {
        $cmd .= ' ';
        if ($arg =~ /\s/) {
            $cmd .= "'$arg'";
        } else {
            $cmd .= $arg;
        }
    }
    $lcovutil::profileData{config}{cmdLine}  = $cmd;
    $lcovutil::profileData{config}{buildDir} = Cwd::getcwd();
}

sub save_profile($@)
{
    my ($dest, $html) = @_;

    if (defined($lcovutil::profile)) {
        $lcovutil::profileData{config}{maxParallel} = $maxParallelism;
        $lcovutil::profileData{config}{tool}        = $lcovutil::tool_name;
        $lcovutil::profileData{config}{version}     = $lcovutil::lcov_version;
        $lcovutil::profileData{config}{tool_dir}    = $lcovutil::tool_dir;
        $lcovutil::profileData{config}{url}         = $lcovutil::lcov_url;
        foreach my $t ('date', 'uname -a', 'hostname') {
            my $v = `$t`;
            chomp($v);
            $lcovutil::profileData{config}{(split(' ', $t))[0]} = $v;
        }
        my $save = $maxParallelism;
        count_cores();
        $lcovutil::profileData{config}{cores} = $maxParallelism;
        $maxParallelism = $save;

        my $json = JsonSupport::encode(\%lcovutil::profileData);

        if ('' ne $lcovutil::profile) {
            $dest = $lcovutil::profile;
        } else {
            $dest .= ".json";
        }
        if (open(JSON, ">", "$dest")) {
            print(JSON $json);
            close(JSON) or die("unable to close $dest: $!\n");
        } else {
            warn("unable to open profile output $dest: '$!'\n");
        }

        # only generate the extra data if profile enabled
        if ($html) {

            my $leader =
                '<object data="https://www.w3.org/TR/PNG/iso_8859-1.txt" width="300" height="200">'
                . "\n";
            my $tail = "</object>\n";

            my $outDir = File::Basename::dirname($html);
            open(CMD, '>', File::Spec->catfile($outDir, 'cmdline.html')) or
                die("unable to create cmdline.html: $!");
            print(CMD $leader, $lcovutil::profileData{config}{cmdLine},
                  "\n", $tail);
            close(CMD) or die("unable to close cmdline.html: $!");

            # and the profile data
            open(PROF, '>', $html) or die("unable to create $html: $!");
            print(PROF $leader);

            open(IN, '<', $dest) or die("unable to open $dest: $!");
            while (<IN>) {
                print(PROF $_);
            }
            close(IN) or die("unable to close $dest: $!");
            print(PROF "\n", $tail);
            close(PROF) or die("unable to close cmdline.html: $!");
        }
    }
}

sub set_extensions
{
    my ($type, $str) = @_;
    die("unknown language '$type'") unless exists($languageExtensions{$type});
    $languageExtensions{$type} = join('|', split($split_char, $str));
}

sub do_mangle_check
{
    return unless @lcovutil::cpp_demangle;

    if (1 == scalar(@lcovutil::cpp_demangle)) {
        if ('' eq $lcovutil::cpp_demangle[0]) {
            # no demangler specified - use c++filt by default
            if (defined($lcovutil::cpp_demangle_tool)) {
                $lcovutil::cpp_demangle[0] = $lcovutil::cpp_demangle_tool;
            } else {
                $lcovutil::cpp_demangle[0] = 'c++filt';
            }
        }
    } elsif (1 < scalar(@lcovutil::cpp_demangle)) {
        die("unsupported usage:  --demangle-cpp with genhtml_demangle_cpp_tool")
            if (defined($lcovutil::cpp_demangle_tool));
        die(
          "unsupported usage:  --demangle-cpp with genhtml_demangle_cpp_params")
            if (defined($lcovutil::cpp_demangle_params));
    }
    if ($lcovutil::cpp_demangle_params) {
        # deprecated usage
        push(@lcovutil::cpp_demangle,
             split(' ', $lcovutil::cpp_demangle_params));
    }
    # Extra flag necessary on OS X so that symbols listed by gcov get demangled
    # properly.
    push(@lcovutil::cpp_demangle, '--no-strip-underscores')
        if ($^ eq "darwin");

    $lcovutil::demangle_cpp_cmd = '';
    foreach my $e (@lcovutil::cpp_demangle) {
        $lcovutil::demangle_cpp_cmd .= (($e =~ /\s/) ? "'$e'" : $e) . ' ';
    }
    my $tool = $lcovutil::cpp_demangle[0];
    die("could not find $tool tool needed for --demangle-cpp")
        if (lcovutil::system_no_output(3, "echo \"\" | '$tool'"));
}

sub configure_callback
{
    # if there is just one argument, then assume it might be a
    # concatenation - otherwise, just use straight.
    my $cb = shift;
    my @args =
        1 == scalar(@_) ?
        split($lcovutil::split_char, join($lcovutil::split_char, @_)) :
        @_;
    my $script = $args[0];
    if ($script =~ /\.pm$/) {
        my $dir     = File::Basename::dirname($script);
        my $package = File::Basename::basename($script);
        my $class   = $package;
        $class =~ s/\.pm$//;
        unshift(@INC, $dir);
        eval {
            require $package;
            #$package->import(qw(new));
            # the first value in @_ is the script name
            $$cb = $class->new(@args);
        };
        if ($@ ||
            !defined($$cb)) {
            lcovutil::ignorable_error($lcovutil::ERROR_PACKAGE,
                             "unable to create callback from module '$script'" .
                                 (defined($@) ? ": $@" : ''));
        }
        shift(@INC);
    } else {
        # not module
        $$cb = ScriptCaller->new(@args);
    }
    push(@configured_callbacks, $cb);
}

sub cleanup_callbacks
{
    if ($lcovutil::contextCallback) {
        my $ctx;
        eval { $ctx = $lcovutil::contextCallback->context(); };
        if ($@) {
            lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                      "context callback '" .
                                          $lcovutil::contextCallback[0] .
                                          " ...' failed: $@");
        } else {
            die('unexpect context callback result: expected hash ref')
                unless 'HASH' eq ref($ctx);
            $lcovutil::profileData{context} = $ctx;
        }
    }
    foreach my $cb (@configured_callbacks) {
        undef $$cb;
    }
}

# use these list values from the RC file unless the option is
#   passed on the command line
my (@rc_filter, @rc_ignore, @rc_exclude_patterns,
    @rc_include_patterns, @rc_subst_patterns, @rc_omit_patterns,
    @rc_erase_patterns, @rc_version_script, @unsupported_config,
    @rc_source_directories, @rc_build_dir, %unsupported_rc,
    $keepGoing, $help, @rc_resolveCallback,
    @rc_expected_msg_counts, @rc_criteria_script, @rc_contextCallback,
    $rc_no_branch_coverage, $rc_no_func_coverage, $rc_no_checksum,
    $version);
my $quiet = 0;
our $tempdirname;

# these options used only by lcov - but moved here so that we can
#   share arg parsing
our ($lcov_remove,     # If set, removes parts of tracefile
     $lcov_capture,    # If set, capture data
     $lcov_extract);    # If set, extracts parts of tracefile
our @opt_config_files;
our @opt_ignore_errors;
our @opt_expected_message_counts;
our @opt_filter;
our @comments;

my %deprecated_rc = ("genhtml_demangle_cpp"        => "demangle_cpp",
                     "genhtml_demangle_cpp_tool"   => "demangle_cpp",
                     "genhtml_demangle_cpp_params" => "demangle_cpp",
                     "geninfo_checksum"            => "checksum",
                     "geninfo_no_exception_branch" => "no_exception_branch",
                     'geninfo_adjust_src_path'     => 'substitute',
                     "lcov_branch_coverage"        => "branch_coverage",
                     "lcov_function_coverage"      => "function_coverage",
                     "genhtml_function_coverage"   => "function_coverage",
                     "genhtml_branch_coverage"     => "branch_coverage",
                     'genhtml_criteria_script'     => 'criteria_script',
                     "lcov_fail_under_lines"       => 'fail_under_lines',
                     'genhtml_highlight'           => undef,);

my ($cExtensions, $rtlExtensions, $javaExtensions,
    $perlExtensions, $pythonExtensions);

my %rc_common = (
             'derive_function_end_line' => \$lcovutil::derive_function_end_line,
             'derive_function_end_line_all_files' =>
        \$derive_function_end_line_all_files,
             'trivial_function_threshold' => \$lcovutil::trivial_function_threshold,
             "lcov_tmp_dir"                => \$lcovutil::tmp_dir,
             "lcov_json_module"            => \$JsonSupport::rc_json_module,
             "branch_coverage"             => \$lcovutil::br_coverage,
             'mcdc_coverage'               => \$lcovutil::mcdc_coverage,
             "function_coverage"           => \$lcovutil::func_coverage,
             "lcov_excl_line"              => \$lcovutil::EXCL_LINE,
             "lcov_excl_br_line"           => \$lcovutil::EXCL_BR_LINE,
             "lcov_excl_exception_br_line" => \$lcovutil::EXCL_EXCEPTION_LINE,
             "lcov_excl_start"             => \$lcovutil::EXCL_START,
             "lcov_excl_stop"              => \$lcovutil::EXCL_STOP,
             "lcov_excl_br_start"          => \$lcovutil::EXCL_BR_START,
             "lcov_excl_br_stop"           => \$lcovutil::EXCL_BR_STOP,
             "lcov_excl_exception_br_start" => \$lcovutil::EXCL_EXCEPTION_BR_START,
             "lcov_excl_exception_br_stop" => \$lcovutil::EXCL_EXCEPTION_BR_STOP,
             'lcov_unreachable_start'      => \$lcovutil::UNREACHABLE_START,
             'lcov_unreachable_stop'       => \$lcovutil::UNREACHABLE_STOP,
             'lcov_unreachable_line'       => \$lcovutil::UNREACHABLE_LINE,
             'retain_unreachable_coverpoints_if_executed' =>
        \$lcovutil::retainUnreachableCoverpointIfHit,
             "lcov_function_coverage" => \$lcovutil::func_coverage,
             "lcov_branch_coverage"   => \$lcovutil::br_coverage,
             "ignore_errors"          => \@rc_ignore,
             "max_message_count"      => \$lcovutil::suppressAfter,
             "message_log"            => \$lcovutil::message_log,
             'expected_message_count' => \@rc_expected_msg_counts,
             'stop_on_error'          => \$lcovutil::stop_on_error,
             'treat_warning_as_error' => \$lcovutil::treat_warning_as_error,
             'warn_once_per_file'     => \$lcovutil::warn_once_per_file,
             'check_data_consistency' => \$lcovutil::check_data_consistency,
             "rtl_file_extensions"    => \$rtlExtensions,
             "c_file_extensions"      => \$cExtensions,
             "perl_file_extensions"   => \$perlExtensions,
             "python_file_extensions" => \$pythonExtensions,
             "java_file_extensions"   => \$javaExtensions,
             'info_file_pattern'      => \$info_file_pattern,
             "filter_lookahead"       => \$lcovutil::source_filter_lookahead,
             "filter_bitwise_conditional" =>
        \$lcovutil::source_filter_bitwise_are_conditional,
             'filter_blank_aggressive' => \$filter_blank_aggressive,
             "profile"                 => \$lcovutil::profile,
             "parallel"                => \$lcovutil::maxParallelism,
             "memory"                  => \$lcovutil::maxMemory,
             "memory_percentage"       => \$lcovutil::memoryPercentage,
             "max_fork_fails"          => \$lcovutil::max_fork_fails,
             "max_tasks_per_core"      => \$lcovutil::max_tasks_per_core,
             "fork_fail_timeout"       => \$lcovutil::fork_fail_timeout,
             'source_directory'        => \@rc_source_directories,
             'build_directory'         => \@rc_build_dir,

             "no_exception_branch"    => \$lcovutil::exclude_exception_branch,
             'filter'                 => \@rc_filter,
             'exclude'                => \@rc_exclude_patterns,
             'include'                => \@rc_include_patterns,
             'substitute'             => \@rc_subst_patterns,
             'omit_lines'             => \@rc_omit_patterns,
             'erase_functions'        => \@rc_erase_patterns,
             'context_script'         => \@rc_contextCallback,
             "version_script"         => \@rc_version_script,
             'resolve_script'         => \@rc_resolveCallback,
             'criteria_callback_data' =>
                 \@CoverageCriteria::criteriaCallbackTypes,
             'criteria_callback_levels' =>
                 \@CoverageCriteria::criteriaCallbackLevels,
             'criteria_script' => \@rc_criteria_script,

             "checksum"              => \$lcovutil::verify_checksum,
             'compute_file_version'  => \$lcovutil::compute_file_version,
             "case_insensitive"      => \$lcovutil::case_insensitive,
             "forget_testcase_names" => \$TraceFile::ignore_testcase_name,
             "split_char"            => \$lcovutil::split_char,

             'check_existence_before_callback' =>
                 \$check_file_existence_before_callback,

             "demangle_cpp"              => \@lcovutil::cpp_demangle,
             'excessive_count_threshold' => \$excessive_count_threshold,

             'sort_input' => \$lcovutil::sort_inputs,

             "fail_under_lines"       => \$fail_under_lines,
             "fail_under_branches"    => \$fail_under_branches,
             'lcov_filter_parallel'   => \$lcovutil::lcov_filter_parallel,
             'lcov_filter_chunk_size' => \$lcovutil::lcov_filter_chunk_size,);

# lcov needs to know the options which might get passed to geninfo in --capture mode
our $defaultChunkSize;      # for performance tweaking
our $defaultInterval;       # for performance tweaking
our @rc_gcov_tool;
our $geninfo_adjust_testname;
our $opt_external;
our $opt_follow            = 0;
our $opt_follow_file_links = 0;
our $opt_compat_libtool;
our $opt_gcov_all_blocks          = 1;
our $opt_adjust_unexecuted_blocks = 0;
our $geninfo_opt_compat;
our $rc_adjust_src_path;    # Regexp specifying parts to remove from source path
our $rc_auto_base    = 1;
our $rc_intermediate = "auto";
our $geninfo_captureAll;    # look for both .gcda and lone .gcno files

our %geninfo_rc_opts = (
          "geninfo_gcov_tool"           => \@rc_gcov_tool,
          "geninfo_adjust_testname"     => \$geninfo_adjust_testname,
          "geninfo_checksum"            => \$lcovutil::verify_checksum,
          "geninfo_compat_libtool"      => \$opt_compat_libtool,
          "geninfo_external"            => \$opt_external,
          "geninfo_follow_symlinks"     => \$opt_follow,
          "geninfo_follow_file_links"   => \$opt_follow_file_links,
          "geninfo_gcov_all_blocks"     => \$opt_gcov_all_blocks,
          "geninfo_unexecuted_blocks"   => \$opt_adjust_unexecuted_blocks,
          "geninfo_compat"              => \$geninfo_opt_compat,
          "geninfo_adjust_src_path"     => \$rc_adjust_src_path,
          "geninfo_auto_base"           => \$rc_auto_base,
          "geninfo_intermediate"        => \$rc_intermediate,
          "geninfo_no_exception_branch" => \$lcovutil::exclude_exception_branch,
          'geninfo_chunk_size'          => \$defaultChunkSize,
          'geninfo_interval_update'     => \$defaultInterval,
          'geninfo_capture_all'         => \$geninfo_captureAll);

our %argCommon = ("tempdir=s"         => \$tempdirname,
                  "version-script=s"  => \@lcovutil::extractVersionScript,
                  "criteria-script=s" =>
                      \@CoverageCriteria::coverageCriteriaScript,

                  "checksum"    => \$lcovutil::verify_checksum,
                  "no-checksum" => \$rc_no_checksum,
                  "quiet|q+"    => \$quiet,
                  "verbose|v+"  => \$lcovutil::verbose,
                  "debug+"      => \$lcovutil::debug,
                  "help|h|?"    => \$help,
                  "version"     => \$version,
                  'comment=s'   => \@comments,
                  'toolname=s'  => \$lcovutil::tool_name,

                  "function-coverage"    => \$lcovutil::func_coverage,
                  "branch-coverage"      => \$lcovutil::br_coverage,
                  'mcdc-coverage'        => \$lcovutil::mcdc_coverage,
                  "no-function-coverage" => \$rc_no_func_coverage,
                  "no-branch-coverage"   => \$rc_no_branch_coverage,

                  "fail-under-lines=s"    => \$fail_under_lines,
                  "fail-under-branches=s" => \$fail_under_branches,
                  'source-directory=s'    =>
                      \@ReadCurrentSource::source_directories,
                  'build-directory=s' => \@lcovutil::build_directory,

                  'resolve-script=s'       => \@lcovutil::resolveCallback,
                  'context-script=s'       => \@lcovutil::contextCallback,
                  "filter=s"               => \@opt_filter,
                  "demangle-cpp:s"         => \@lcovutil::cpp_demangle,
                  "ignore-errors=s"        => \@opt_ignore_errors,
                  "expect-message-count=s" => \@opt_expected_message_counts,
                  'msg-log:s'              => \$message_log,
                  "keep-going"             => \$keepGoing,
                  "config-file=s"          => \@unsupported_config,
                  "rc=s%"                  => \%unsupported_rc,
                  "profile:s"              => \$lcovutil::profile,
                  "exclude=s"              => \@lcovutil::exclude_file_patterns,
                  "include=s"              => \@lcovutil::include_file_patterns,
                  "erase-functions=s" => \@lcovutil::exclude_function_patterns,
                  "omit-lines=s"      => \@lcovutil::omit_line_patterns,
                  "substitute=s"      => \@lcovutil::file_subst_patterns,
                  "parallel|j:i"      => \$lcovutil::maxParallelism,
                  "memory=i"          => \$lcovutil::maxMemory,
                  "forget-test-names" => \$TraceFile::ignore_testcase_name,
                  "preserve"          => \$lcovutil::preserve_intermediates,
                  'sort-input'        => \$lcovutil::sort_inputs,);

sub warnDeprecated
{
    my ($key, $replacement) = @_;
    my $opt_used = defined($replacement);
    my $suffix =
        $opt_used ?
        ".  Consider using '$replacement'. instead.  (Backward-compatible support will be removed in the future.)"
        :
        ' and ignored.';

    push(@deferred_rc_errors,
         [0, $lcovutil::ERROR_DEPRECATED,
          "RC option '$key' is deprecated$suffix"
         ]);
    return $opt_used;
}

sub _set_config($$$)
{
    # write an RC configuration value - array or scalar
    my ($ref, $key, $value) = @_;
    my $r = $ref->{$key};
    my $t = ref($r);
    if ('ARRAY' eq $t) {
        info(2, "  append $value to list $key\n");
        if ('ARRAY' eq ref($value)) {
            push(@$r, @$value);
        } else {
            push(@$r, $value);
        }
    } else {
        # opt is a scalar or not defined
        #  only way for $value to NOT be an array is if there is a bug in
        #  the caller such that a scalar ref was passed where a prior call
        #  had passed a list ref for the same RC option name
        die("unexpected ARRAY for $key value")
            if ('ARRAY' eq ref($value));
        $$r = $value;
        info(2, "  assign $$r to $key\n");
    }
}

#
# read_config(filename, $optionsHash)
#
# Read configuration file FILENAME and write supported key/values into
#   RC options hash
# Return: 1 if some config value was set, 0 if not (used for error messaging)

sub read_config($$);    # forward decl, to make perl happy about recursive call
my %included_config_files;
my @include_stack;

sub read_config($$)
{
    my ($filename, $opts) = @_;
    my $key;
    my $value;
    local *HANDLE;

    my $set_value = 0;
    info(1, "read_config: $filename\n");
    if (exists($included_config_files{abs_path($filename)})) {
        lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                                  'config file inclusion loop detected: "' .
                                      join('" -> "', @include_stack) .
                                      '" -> "' . $filename . '"');
        # this line is unreachable as we can't ignore the 'usage' error
        #   because it is generated when we parse the config-file options
        #   but the '--ignore-errors' option isn't parsed until later, after
        #   the GetOptions call.
        # This could be fixed by doing some early processing on the command
        #   line (similar to how config file options are handled) - but that
        #   seems like overkill.  Just force the user to fix the issues.
        return 0;    # LCOV_UNREACHABLE_LINE
    }

    if (!open(HANDLE, "<", $filename)) {
        lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                              "cannot read configuration file '$filename': $!");
        # similarly, this line is also unreachable for the same reasons as
        #   described above.
        return 0;    # didn't set anything LCOV_UNREACHABLE_LINE
    }
    $included_config_files{abs_path($filename)} = 1;
    push(@include_stack, $filename);
    VAR: while (<HANDLE>) {
        chomp;
        # Skip comments
        s/#.*//;
        # Remove leading blanks
        s/^\s+//;
        # Remove trailing blanks
        s/\s+$//;
        next unless length;
        ($key, $value) = split(/\s*=\s*/, $_, 2);
        # is this an environment variable?
        while (defined($value) &&
               $value =~ /\$ENV\{([^}]+)\}/) {
            my $varname = $1;
            if (!exists($ENV{$varname})) {
                push(
                    @deferred_rc_errors,
                    [   1,
                        $lcovutil::ERROR_USAGE,
                        "\"$filename\": $.:  variable '$key' uses environment variable '$varname' - which is not set (ignoring '$_')."
                    ]);
                next VAR;
            }
            $value =~ s/^\$ENV\{$varname\}/$ENV{$varname}/g;
        }
        if (defined($key) &&
            exists($deprecated_rc{$key})) {
            next unless warnDeprecated($key, $deprecated_rc{$key});
            $key = $deprecated_rc{$key};
        }
        if (defined($key) && defined($value)) {
            info(2, "  set: $key = $value\n");
            # special case: read included file
            if ($key eq 'config_file') {
                $set_value |= read_config($value, $opts);
                next;
            }
            # skip if application doesn't use this setting
            next unless exists($opts->{$key});
            _set_config($opts, $key, $value);
            $set_value = 1;
        } else {
            my $context = MessageContext::context();
            push(
                @deferred_rc_errors,
                [   1,
                    $lcovutil::ERROR_FORMAT,
                    "\"$filename\": $.: malformed configuration file statement '$_':  expected \"key = value\"/"
                ]);
        }
    }
    close(HANDLE) or die("unable to close $filename: $!\n");
    delete $included_config_files{abs_path($filename)};
    pop(@include_stack);
    return $set_value;
}

# common utility used by genhtml, geninfo, lcov to clean up RC options,
#  check for various possible system-wide RC files, and apply the result
# return 1 if we set something
sub apply_rc_params($)
{
    my $rcHash = shift;

    # merge common RC values with the ones passed in
    my %rcHash = (%$rcHash, %rc_common);

    # Check command line for a configuration file name
    # have to set 'verbosity' flag from environment - otherwise, it isn't
    #  set (from GetOpt) when we parse the RC file
    Getopt::Long::Configure("pass_through", "no_auto_abbrev");
    my $quiet = 0;
    Getopt::Long::GetOptions("config-file=s" => \@opt_config_files,
                             "rc=s%"         => \@opt_rc,
                             "quiet|q+"      => \$quiet,
                             "verbose|v+"    => \$lcovutil::verbose,
                             "debug+"        => \$lcovutil::debug,);
    init_verbose_flag($quiet);
    Getopt::Long::Configure("default");

    my $set_value = 0;

    if (0 != scalar(@opt_config_files)) {
        foreach my $f (@opt_config_files) {
            $set_value |= read_config($f, \%rcHash);
        }
    } else {
        foreach my $v (['HOME', '.lcovrc'], ['LCOV_HOME', 'etc', 'lcovrc']) {
            next unless exists($ENV{$v->[0]});
            my $f = File::Spec->catfile($ENV{$v->[0]}, splice(@$v, 1));
            if (-r $f) {
                $set_value |= read_config($f, \%rcHash);
                last;
            }
        }
    }

    my $first;
    foreach my $v (@opt_rc) {
        my $index = index($v, '=');
        if ($index == -1) {
            push(@deferred_rc_errors,
                 [1, $lcovutil::ERROR_USAGE,
                  "malformed --rc option '$v' - should be 'key=value'"
                 ]);
            next;
        }
        my $key   = substr($v, 0, $index);
        my $value = substr($v, $index + 1);
        $key =~ s/^\s+|\s+$//g;
        unless (exists($rcHash{$key})) {
            push(
                @deferred_rc_errors,
                [   1,
                    $lcovutil::ERROR_USAGE,
                    "unknown/unsupported key '$key' found in '--rc $v' - see 'man lcovrc(5)' for the list of valid options"
                ]);
            next;
        }
        info(1, "apply --rc overrides\n")
            unless defined($first);
        $first = 1;
        # can't complain about deprecated uses here because the user
        #  might have suppressed that message - but we haven't looked at
        #  the suppressions in the parameter list yet.
        if (exists($deprecated_rc{$key})) {
            next unless warnDeprecated($key, $deprecated_rc{$key});
        }
        # strip spaces
        $value =~ s/^\s+|\s+$//g;
        _set_config(\%rcHash, $key, $value);
        $set_value = 1;
    }
    foreach my $d (['rtl', $rtlExtensions],
                   ['c', $cExtensions],
                   ['perl', $perlExtensions],
                   ['python', $pythonExtensions],
                   ['java', $javaExtensions]
    ) {
        lcovutil::set_extensions(@$d) if $d->[1];
    }
    return $set_value;
}

sub parseOptions
{
    my ($rcOptions, $cmdLineOpts, $output_arg) = @_;

    apply_rc_params($rcOptions);

    my %options = (%argCommon, %$cmdLineOpts);
    if (!GetOptions(%options)) {
        return 0;
    }
    foreach my $d (['--config-file', scalar(@unsupported_config)],
                   ['--rc', scalar(%unsupported_rc)]) {
        die("'" . $d->[0] . "' option name cannot be abbreviated\n")
            if ($d->[1]);
    }
    if ($help) {
        main::print_usage(*STDOUT);
        exit(0);
    }
    # Check for version option
    if ($version) {
        print("$tool_name: $lcov_version\n");
        exit(0);
    }
    if (defined($message_log)) {
        if (!$message_log) {
            # base log file name on output arg (if specified) or tool name otherwise
            $message_log = (
                        defined($$output_arg) ?
                            substr($$output_arg, 0, rindex($$output_arg, '.')) :
                            $tool_name) .
                ".msg";
        }
        $message_filename = $message_log;
        open(LOG, ">", $message_log) or
            die("unable to write message log '$message_log': $!");
        $message_log = \*LOG;
    }

    lcovutil::init_verbose_flag($quiet);
    # apply the RC file settings if no command line arg
    foreach my $rc ([\@opt_filter, \@rc_filter],
                    [\@opt_ignore_errors, \@rc_ignore],
                    [\@opt_expected_message_counts, \@rc_expected_msg_counts],
                    [\@lcovutil::exclude_file_patterns, \@rc_exclude_patterns],
                    [\@lcovutil::include_file_patterns, \@rc_include_patterns],
                    [\@lcovutil::file_subst_patterns, \@rc_subst_patterns],
                    [\@lcovutil::omit_line_patterns, \@rc_omit_patterns],
                    [\@lcovutil::exclude_function_patterns, \@rc_erase_patterns
                    ],
                    [\@lcovutil::extractVersionScript, \@rc_version_script],
                    [\@CoverageCriteria::coverageCriteriaScript,
                     \@rc_criteria_script
                    ],
                    [\@ReadCurrentSource::source_directories,
                     \@rc_source_directories
                    ],
                    [\@lcovutil::build_directory, \@rc_build_dir],
                    [\@lcovutil::resolveCallback, \@rc_resolveCallback],
                    [\@lcovutil::contextCallback, \@rc_contextCallback],
    ) {
        @{$rc->[0]} = @{$rc->[1]} unless (@{$rc->[0]});
    }

    $ReadCurrentSource::searchPath =
        SearchPath->new('source directory',
                        @ReadCurrentSource::source_directories);

    $lcovutil::stop_on_error = 0
        if (defined $keepGoing);

    push(@lcovutil::exclude_file_patterns, @ARGV)
        if $lcov_remove;
    push(@lcovutil::include_file_patterns, @ARGV)
        if $lcov_extract;

    # Merge options
    $lcovutil::func_coverage = 0
        if ($rc_no_func_coverage);
    $lcovutil::br_coverage = 0
        if ($rc_no_branch_coverage);

    $lcovutil::verify_checksum = 0
        if (defined($rc_no_checksum));

    foreach my $cb ([\$versionCallback, \@lcovutil::extractVersionScript],
                    [\$resolveCallback, \@lcovutil::resolveCallback],
                    [\$CoverageCriteria::criteriaCallback,
                     \@CoverageCriteria::coverageCriteriaScript
                    ],
                    [\$contextCallback, \@lcovutil::contextCallback],
    ) {
        lcovutil::configure_callback($cb->[0], @{$cb->[1]})
            if (@{$cb->[1]});
    }
    # perhaps warn that date/owner and directory are only supported by genhtml?
    foreach my $data (['criteria_callback_levels',
                       \@CoverageCriteria::criteriaCallbackLevels,
                       ['top', 'directory', 'file']
                      ],
                      ['criteria_callback_data',
                       \@CoverageCriteria::criteriaCallbackTypes,
                       ['date', 'owner']
                      ]
    ) {
        my ($rc, $user, $valid) = @$data;
        @$user = split(',', join(',', @$user));
        foreach my $x (@$user) {
            die("invalid '$rc' value \"$x\" - expected (" .
                join(", ", @$valid) . ")")
                unless grep(/^$x$/, @$valid);
        }
    }
    # context only gets grabbed/stored with '--profile'
    $lcovutil::profile = ''
        if ($contextCallback && !defined($lcovutil::profile));

    if (!$lcov_capture) {
        if ($lcovutil::compute_file_version &&
            !defined($versionCallback)) {
            lcovutil::ignorable_warning($lcovutil::ERROR_USAGE,
                "'compute_file_version=1' option has no effect without either '--version-script' or 'version_script=...'."
            );
        }
        lcovutil::munge_file_patterns();
        lcovutil::init_parallel_params();
        # Determine which errors the user wants us to ignore
        parse_ignore_errors(@opt_ignore_errors);
        parse_expected_message_counts(@opt_expected_message_counts);
        # Determine what coverpoints the user wants to filter
        push(@opt_filter, 'exception') if $lcovutil::exclude_exception_branch;
        parse_cov_filters(@opt_filter);

        # Ensure that the c++filt tool is available when using --demangle-cpp
        lcovutil::do_mangle_check();

        foreach my $entry (@deferred_rc_errors) {
            my ($isErr, $type, $msg) = @$entry;
            if ($isErr) {
                lcovutil::ignorable_error($type, $msg);
            } else {
                lcovutil::ignorable_warning($type, $msg);
            }
        }
    }

    return 1;
}

#
# transform_pattern(pattern)
#
# Transform shell wildcard expression to equivalent Perl regular expression.
# Return transformed pattern.
#

sub transform_pattern($)
{
    my $pattern = $_[0];

    # Escape special chars

    $pattern =~ s/\\/\\\\/g;
    $pattern =~ s/\//\\\//g;
    $pattern =~ s/\^/\\\^/g;
    $pattern =~ s/\$/\\\$/g;
    $pattern =~ s/\(/\\\(/g;
    $pattern =~ s/\)/\\\)/g;
    $pattern =~ s/\[/\\\[/g;
    $pattern =~ s/\]/\\\]/g;
    $pattern =~ s/\{/\\\{/g;
    $pattern =~ s/\}/\\\}/g;
    $pattern =~ s/\./\\\./g;
    $pattern =~ s/\,/\\\,/g;
    $pattern =~ s/\|/\\\|/g;
    $pattern =~ s/\+/\\\+/g;
    $pattern =~ s/\!/\\\!/g;

    # Transform ? => (.) and * => (.*)

    $pattern =~ s/\*/\(\.\*\)/g;
    $pattern =~ s/\?/\(\.\)/g;
    $pattern = "/$pattern/i"
        if ($lcovutil::case_insensitive);
    return qr($pattern);
}

sub verify_regexp_patterns
{
    my ($flag, $list, $checkInsensitive) = @_;
    PAT: foreach my $pat (@$list) {
        my $text = 'abc';
        my $str  = eval "\$text =~ $pat ;";
        die("Invalid regexp \"$flag $pat\":\n$@")
            if $@;

        if ($checkInsensitive) {
            for (my $i = length($pat) - 1; $i >= 0; --$i) {
                my $char = substr($pat, $i, 1);
                next PAT
                    if ($char eq 'i');
                last    # didn't see the 'i' character
                    if ($char =~ /[\/#!@%]/);
            }
            lcovutil::ignorable_warning($lcovutil::ERROR_USAGE,
                "$flag pattern '$pat' does not seem to be case insensitive - but you asked for case insensitive matching"
            );
        }
    }
}

sub munge_file_patterns
{
    # Need perlreg expressions instead of shell pattern
    if (@exclude_file_patterns) {
        @exclude_file_patterns =
            map({ [transform_pattern($_), $_, 0]; } @exclude_file_patterns);
    }

    if (@include_file_patterns) {
        @include_file_patterns =
            map({ [transform_pattern($_), $_, 0]; } @include_file_patterns);
    }

    # precompile match patterns and check for validity
    foreach my $p (['omit-lines', \@omit_line_patterns],
                   ['exclude-functions', \@exclude_function_patterns]) {
        my ($flag, $list) = @$p;
        next unless (@$list);
        # keep track of number of times pattern was applied
        # regexp compile will die if pattern is invalid
        eval {
            @$list = map({ [qr($_), $_, 0]; } @$list);
        };
        die("Invalid $flag regexp in ('" . join('\' \'', @$list) . "'):\n$@")
            if $@;
    }
    # sadly, substitutions aren't regexps and can't be precompiled
    if (@file_subst_patterns) {
        verify_regexp_patterns('--substitute', \@file_subst_patterns,
                               \$lcovutil::case_insensitive);

        # keep track of number of times this was applied
        @file_subst_patterns = map({ [$_, 0]; } @file_subst_patterns);
    }

    # and check for valid region patterns
    for my $regexp (['lcov_excl_line', $lcovutil::EXCL_LINE],
                    ['lcov_excl_br_line', $lcovutil::EXCL_BR_LINE],
                    ['lcov_excl_exception_br_line',
                     $lcovutil::EXCL_EXCEPTION_LINE
                    ],
                    ["lcov_excl_start", \$lcovutil::EXCL_START],
                    ["lcov_excl_stop", \$lcovutil::EXCL_STOP],
                    ["lcov_excl_br_start", \$lcovutil::EXCL_BR_START],
                    ["lcov_excl_br_stop", \$lcovutil::EXCL_BR_STOP],
                    ["lcov_excl_exception_br_start",
                     \$lcovutil::EXCL_EXCEPTION_BR_START
                    ],
                    ["lcov_excl_exception_br_stop",
                     \$lcovutil::EXCL_EXCEPTION_BR_STOP
                    ],
                    ["lcov_unreachable_start", \$lcovutil::UNREACHABLE_START],
                    ["lcov_unreachable_stop", \$lcovutil::UNREACHABLE_STOP],
                    ["lcov_excl_line", \$lcovutil::UNREACHABLE_LINE],
    ) {
        eval 'qr/' . $regexp->[1] . '/';
        my $error = $@;
        chomp($error);
        $error =~ s/at \(eval.*$//;
        die("invalid '" . $regexp->[0] . "' exclude pattern: $error")
            if $error;
    }
    @suppress_function_patterns = map({ $_->[0] } @exclude_function_patterns);
}

sub warn_file_patterns
{
    foreach my $p (['include', \@include_file_patterns],
                   ['exclude', \@exclude_file_patterns],
                   ['substitute', \@file_subst_patterns],
                   ['omit-lines', \@omit_line_patterns],
                   ['exclude-functions', \@exclude_function_patterns],
    ) {
        my ($type, $patterns) = @$p;
        foreach my $pat (@$patterns) {
            my $count = $pat->[scalar(@$pat) - 1];
            if (0 == $count) {
                my $str = $pat->[scalar(@$pat) - 2];
                lcovutil::ignorable_error($ERROR_UNUSED,
                                          "'$type' pattern '$str' is unused.");
            }
        }
    }
}

#
# subst_file_name($path)
#
# apply @file_subst_patterns to $path and return
#
sub subst_file_name($)
{
    my $name = shift;
    foreach my $p (@file_subst_patterns) {
        my $old = $name;
        # sadly, no support for pre-compiled patterns
        eval '$name =~ ' . $p->[0] . ';';  # apply pattern that user provided...
            # $@ should never match:  we already checked pattern validity during
            #   initialization - above.  Still: belt and braces.
        die("invalid 'subst' regexp '" . $p->[0] . "': $@")
            if ($@);
        $p->[-1] += 1
            if $old ne $name;
    }
    return $name;
}

#
# strip_directories($path, $depth)
#
# Remove DEPTH leading directory levels from PATH.
#

sub strip_directories($$)
{
    my $filename = $_[0];
    my $depth    = $_[1];
    my $i;

    if (!defined($depth) || ($depth < 1)) {
        return $filename;
    }
    my $d = $lcovutil::dirseparator;
    for ($i = 0; $i < $depth; $i++) {
        if ($lcovutil::case_insensitive) {
            $filename =~ s/^[^$d]*$d+(.*)$/$1/i;
        } else {
            $filename =~ s/^[^$d]*$d+(.*)$/$1/;
        }
    }
    return $filename;
}

sub define_errors()
{
    my $id = 0;
    foreach my $d (@lcovErrs) {
        my ($k, $ref) = @$d;
        $$ref                        = $id;
        $lcovErrors{$k}              = $id;
        $ERROR_ID{$k}                = $id;
        $ERROR_NAME{$id}             = $k;
        $ignore[$id]                 = 0;
        $message_count[$id]          = 0;
        $expected_message_count[$id] = undef;    # no expected count, by default
        ++$id;
    }
}

sub summarize_messages
{
    my $silent = shift;
    return if $lcovutil::in_child_process;

    # first check for expected message count constraints
    for (my $idx = 0; $idx <= $#expected_message_count; ++$idx) {
        my $expr = $expected_message_count[$idx];
        next unless defined($expr);
        my $t = $message_count[$idx];
        $expr =~ s/%C/$t/g;
        my $v;
        eval { $v = eval $expr; };
        if ($@ || !defined($v)) {
            # we checked the syntax of the message - so should not be able to fail
            lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                      "evaluation of '$expr' failed: $@");
            next;
        }
        unless ($v) {
            my $type = $ERROR_NAME{$idx};
            lcovutil::ignorable_error($lcovutil::ERROR_COUNT,
                "'$type' constraint '$expr' is not true (see '--expect_message_count' for details)."
            );
        }
    }

    # now summarize
    my %total = ('error'   => 0,
                 'warning' => 0,
                 'ignore'  => 0,);
    # use verbosity level -1:  so print unless user says "-q -q"...really quiet

    my $found = 0;
    while (my ($type, $hash) = each(%message_types)) {
        while (my ($name, $count) = each(%$hash)) {
            $total{$type} += $count;
            $found = 1;
        }
    }
    my $header = "Message summary:\n";
    foreach my $type ('error', 'warning', 'ignore') {
        next unless $total{$type};
        $found = 1;
        my $leader = $header . '  ' . $total{$type} . " $type message" .
            ($total{$type} > 1 ? 's' : '') . ":\n";
        my $h = $message_types{$type};
        foreach my $k (sort keys %$h) {
            info(-1, $leader . '    ' . $k . ": " . $h->{$k} . "\n");
            $leader = '';
        }
        $header = '';
    }
    info(-1, "$header  no messages were reported\n") unless $found || $silent;
}

sub parse_ignore_errors(@)
{
    my @ignore_errors = split($split_char, join($split_char, @_));

    # first, mark that all known errors are not ignored
    foreach my $item (keys(%ERROR_ID)) {
        my $id = $ERROR_ID{$item};
        $ignore[$id] = 0
            unless defined($ignore[$id]);
    }

    return if (!@ignore_errors);

    foreach my $item (@ignore_errors) {
        die("unknown argument for --ignore-errors: '$item'")
            unless exists($ERROR_ID{lc($item)});
        my $item_id = $ERROR_ID{lc($item)};
        $ignore[$item_id] += 1;
    }
}

sub parse_expected_message_counts(@)
{
    my @constraints = split($split_char, join($split_char, @_));
    # parse the list and look for errors..
    foreach my $c (@constraints) {
        if ($c =~ /^s*(\S+?)\s*:\s*((\d+)|(.+?))\s*$/) {
            unless (exists($ERROR_ID{lc($1)})) {
                lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                       "unknown 'expected-message-count' message type \"$1\".");
                next;
            }

            my $id = $ERROR_ID{lc($1)};
            if (defined($expected_message_count[$id])) {
                my $ignore = $lcovutil::ignore[$lcovutil::ERROR_USAGE];
                lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                                        "duplicate 'expected' constraint '$c'" .
                                            ($ignore ? ': ignoring.' : ''));
                next;
            }
            # check if syntax look reasonable
            my $expr = $2;
            if (Scalar::Util::looks_like_number($expr)) {
                $expected_message_count[$id] = "%C == $expr";
                next;
            }
            lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                "expect-message-count constraint '$c' does not appear to depend on message count:  '%C' substitution not found."
            ) unless ($expr =~ /%C/);

            # now lets try an eval
            my $v = $expr;
            $v =~ s/%C/0/g;
            $v = eval $v;
            if (defined($v)) {
                $expected_message_count[$id] = $expr;
            } else {
                my $ignore = $lcovutil::ignore[$lcovutil::ERROR_USAGE];
                lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                      "eval error in 'expect-message-count' constraint '$c': $@"
                          . ($ignore ? ': ignoring.' : ''));
            }
        } else {
            lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                "malformed expected-message-count constraint \"$c\". Expected 'msg_type = expr'."
            );
        }
    }
}

sub message_count($)
{
    my $code = shift;

    return $message_count[$code];
}

sub is_ignored($)
{
    my $code = shift;
    die("invalid error code $code")
        unless 0 <= $code && $code < scalar(@ignore);
    return $ignore[$code] || (defined($stop_on_error) && 0 == $stop_on_error);
}

our %explainOnce;    # append explanation to first error/warning message (only)

sub explain_once
{
    # NOTE:  in parallel execution, the explanations may appear more than
    #   once - e.g., when two or more child processes generate them
    #   simultaneously.
    #   They will eventually update the parent process state such that
    #   subsequent children won't report the issues.
    my $key = shift;
    if (!exists($explainOnce{$key})) {
        $explainOnce{$key} = 1;
        my $msg = '';
        # each element is either a string or a pair of [string, predicate]
        foreach my $e (@_) {
            if ('ARRAY' eq ref($e)) {
                $msg .= $e->[0] if defined($e->[1]) && $e->[1];
            } else {
                $msg .= $e;
            }
        }
        return $msg;
    }
    return '';
}

our %warnOnlyOnce;
our $deferWarnings = 0;
# if 'stop_on_error' is false, then certain errors should be emitted at most once
#  (not relevant if stop_on_error is true - as we will exit after the error.
sub warn_once
{
    my ($msgType, $key) = @_;
    return 0
        if (exists($warnOnlyOnce{$msgType}) &&
            exists($warnOnlyOnce{$msgType}{$key}));
    $warnOnlyOnce{$msgType}{$key} = 1;
    return 1;
}

sub store_deferred_message
{
    my ($msgType, $isError, $key, $msg) = @_;
    die(
       "unexpected deferred value of $msg->$key: $warnOnlyOnce{$msgType}{$key}")
        unless 1 == $warnOnlyOnce{$msgType}{$key};
    if ($deferWarnings) {
        $warnOnlyOnce{$msgType}{$key} = [$msg, $isError];
    } else {
        if ($isError) {
            lcovutil::ignorable_error($msgType, $msg);
        } else {
            lcovutil::ignorable_warning($msgType, $msg);
        }
    }
}

sub merge_deferred_warnings
{
    my $hash = shift;
    while (my ($type, $d) = each(%$hash)) {
        while (my ($key, $m) = each(%$d)) {
            if (!(exists($warnOnlyOnce{$type}) &&
                  exists($warnOnlyOnce{$type}{$key}))) {
                if ('ARRAY' eq ref($m)) {
                    # this is a
                    my ($msg, $isError) = @$m;
                    if ($isError) {
                        lcovutil::ignorable_error($type, $msg);
                    } else {
                        lcovutil::ignorable_warning($type, $msg);
                    }
                }
                $warnOnlyOnce{$type}{$key} = 1;
            }
        }
    }
}

sub initial_state
{
    # a bit of a hack:   this method is called at the start of each
    #  child process - so use it to record that we are executing in a
    #  child.
    # The flag is used to reduce verbosity from children - and possibly
    #  for other things later
    $lcovutil::in_child_process = 1;

    # keep track of number of warnings, etc. generated in child -
    #  so we can merge back into parent.  This may prevent us from
    #  complaining about the same thing in multiple children - but only
    #  if those children don't execute in parallel.
    %message_types = ();    #reset
    $ReadCurrentSource::searchPath->reset();
    # clear profile - want only my contribution
    %lcovutil::profileData  = ();
    %lcovutil::warnOnlyOnce = ();

    # clear pattern counts so we can update number found in children
    foreach my $patType (\@lcovutil::exclude_file_patterns,
                         \@lcovutil::include_file_patterns,
                         \@lcovutil::file_subst_patterns,
                         \@lcovutil::omit_line_patterns,
                         \@lcovutil::exclude_function_patterns,
    ) {
        foreach my $p (@$patType) {
            $p->[-1] = 0;
        }
    }

    return Storable::dclone([\@message_count, \%versionCache, \%resolveCache]);
}

sub compute_update
{
    my $state = shift;
    my @new_count;
    my ($initialCount, $initialVersionCache, $initialResolveCache) = @$state;
    my $id = 0;
    foreach my $count (@message_count) {
        my $v = $count - $initialCount->[$id++];
        push(@new_count, $v);
    }
    my %versionUpdate;
    while (my ($f, $v) = each(%versionCache)) {
        $versionUpdate{$f} = $v
            unless exists($initialVersionCache->{$f});
    }
    my %resolveUpdate;
    while (my ($f, $v) = each(%resolveCache)) {
        $resolveUpdate{$f} = $v
            unless exists($initialResolveCache->{$f});
    }
    my @rtn = (\@new_count,
               \%versionUpdate,
               \%resolveUpdate,
               \%message_types,
               $ReadCurrentSource::searchPath->current_count(),
               \%lcovutil::profileData,
               \%lcovutil::warnOnlyOnce,
               \%lcovutil::explainOnce);

    foreach my $patType (\@lcovutil::exclude_file_patterns,
                         \@lcovutil::include_file_patterns,
                         \@lcovutil::file_subst_patterns,
                         \@lcovutil::omit_line_patterns,
                         \@lcovutil::exclude_function_patterns,
    ) {
        my @count;
        foreach my $p (@$patType) {
            push(@count, $p->[-1]);
        }
        push(@rtn, \@count);
    }

    return \@rtn;
}

sub update_state
{
    my $updateCount = shift;
    my $id          = 0;
    foreach my $count (@$updateCount) {
        $message_count[$id++] += $count;
    }
    my $updateVersionCache = shift;
    while (my ($f, $v) = each(%$updateVersionCache)) {
        lcovutil::ignorable_error($lcovutil::ERROR_INTERNAL,
                                  "unexpected version entry")
            if exists($versionCache{$f}) && $versionCache{$f} ne $v;
        $versionCache{$f} = $v;
    }
    my $updateResolveCache = shift;
    while (my ($f, $v) = each(%$updateResolveCache)) {
        lcovutil::ignorable_error($lcovutil::ERROR_INTERNAL,
                                  "unexpected resolve entry")
            if exists($resolveCache{$f}) && $resolveCache{$f} ne $v;
        $resolveCache{$f} = $v;
    }
    my $msgTypes = shift;
    while (my ($type, $h) = each(%$msgTypes)) {
        while (my ($err, $count) = each(%$h)) {
            if (exists($message_types{$type}) &&
                exists($message_types{$type}{$err})) {
                $message_types{$type}{$err} += $count;
            } else {
                $message_types{$type}{$err} = $count;
            }
        }
    }
    my $searchCount = shift;
    $ReadCurrentSource::searchPath->update_count(@$searchCount);

    my $profile = shift;
    lcovutil::merge_child_profile($profile);
    my $warnOnce = shift;
    lcovutil::merge_deferred_warnings($warnOnce);
    my $explainOnce = shift;
    while (my ($key, $v) = each(%$explainOnce)) {
        $lcovutil::explainOnce{$key} = $v;
    }

    foreach my $patType (\@lcovutil::exclude_file_patterns,
                         \@lcovutil::include_file_patterns,
                         \@lcovutil::file_subst_patterns,
                         \@lcovutil::omit_line_patterns,
                         \@lcovutil::exclude_function_patterns,
    ) {
        my $count = shift;
        die("unexpected pattern count") unless $#$count == $#$patType;
        foreach my $p (@$patType) {
            $p->[-1] += shift @$count;
        }
    }
    die("unexpected update data") unless -1 == $#_;    # exhausted list
}

sub warnSuppress($$)
{
    my ($code, $errName) = @_;

    if ($ignore[$code] <= 1 &&    # don't warn if already suppressed
        $message_count[$code] == ($suppressAfter + 1)
    ) {
        # explain once per error type, if verbose - else only once
        my $explain = explain_once(
            'error_count' . ($lcovutil::verbose ? $errName : ''),
            "\n\tTo increase or decrease this limit use '--rc max_message_count=value'."
        );
        ignorable_warning($ERROR_COUNT,
            "max_message_count=$suppressAfter reached for '$errName' messages: no more will be reported.$explain"
        );
    }
}

sub _count_message($$)
{
    my ($type, $name) = @_;

    $message_types{$type}{$name} = 0
        unless (exists($message_types{$type}) &&
                exists($message_types{$type}{$name}));
    ++$message_types{$type}{$name};
}

sub saw_error
{
    # true if we saw at least one error when 'stop_on_error' is false
    # enables us to return non-zero exit status if any errors were detected
    return exists($message_types{error});
}

sub ignorable_error($$;$)
{
    my ($code, $msg, $quiet) = @_;
    die("undefined error code for '$msg'") unless defined($code);

    my $errName = "code_$code";
    $errName = $ERROR_NAME{$code}
        if exists($ERROR_NAME{$code});

    if ($message_count[$code]++ >= $suppressAfter &&
        0 < $suppressAfter) {
        # safe to just continue without checking anything else - as either
        #  this message is not fatal and we emitted it some number of times,
        #  or the message is fatal - and this is the first time we see it

        _count_message('ignore', $errName);
        # warn that we are suppressing from here on - for the first skipped
        #   message of this type
        warnSuppress($code, $errName);
        return;
    }

    chomp($msg);    # we insert the newline
    if ($code >= scalar(@ignore) ||
        !$ignore[$code]) {
        my $ignoreOpt =
            "\t(use \"$tool_name --ignore-errors $errName ...\" to bypass this error)\n";
        $ignoreOpt = ''
            if ($lcovutil::in_child_process ||
                !($lcovutil::verbose || $message_count[$code] == 1));
        if (defined($stop_on_error) && 0 == $stop_on_error) {
            _count_message('error', $errName);
            warn_handler("($errName) $msg\n$ignoreOpt", 1);
            return;
        }
        _count_message('error', $errName);
        die_handler("($errName) $msg\n$ignoreOpt");
    }
    # only tell the user how to suppress this on the first occurrence
    my $ignoreOpt =
        "\t(use \"$tool_name --ignore-errors $errName,$errName ...\" to suppress this warning)\n";
    $ignoreOpt = ''
        if ($lcovutil::in_child_process ||
            !($lcovutil::verbose || $message_count[$code] == 1));

    if ($ignore[$code] > 1 || (defined($quiet) && $quiet)) {
        _count_message('ignore', $errName);
    } else {
        _count_message('warning', $errName);
        warn_handler("($errName) $msg\n$ignoreOpt", 0);
    }
}

sub ignorable_warning($$;$)
{
    my ($code, $msg, $quiet) = @_;
    if ($lcovutil::treat_warning_as_error) {
        ignorable_error($code, $msg, $quiet);
        return;
    }
    die("undefined error code for '$msg'") unless defined($code);

    my $errName = "code_$code";
    $errName = $ERROR_NAME{$code}
        if exists($ERROR_NAME{$code});
    if ($message_count[$code]++ >= $suppressAfter &&
        0 < $suppressAfter) {
        # warn that we are suppressing from here on - for the first skipped
        #   message of this type
        warnSuppress($code, $errName);
        _count_message('ignore', $errName);
        return;
    }
    chomp($msg);    # we insert the newline
    if ($code >= scalar(@ignore) ||
        !$ignore[$code]) {
        # only tell the user how to suppress this on the first occurrence
        my $ignoreOpt =
            "\t(use \"$tool_name --ignore-errors $errName,$errName ...\" to suppress this warning)\n";
        $ignoreOpt = ''
            if ($lcovutil::in_child_process ||
                !($lcovutil::verbose || $message_count[$code] == 1));
        warn_handler("($errName) $msg\n$ignoreOpt", 0);
        _count_message('warning', $errName);
    } else {
        _count_message('ignore', $errName);
    }
}

sub report_unknown_child
{
    my $child = shift;
    # this can happen if the user loads a callback module which starts a chaild
    # process when it is loaded or initialized and fails to wait for that child
    # to finish.  How it manifests is an orphan PID which is smaller (older)
    # than any of the children that this parent actually scheduled
    lcovutil::ignorable_error($lcovutil::ERROR_CHILD,
        "found unknown process $child while waiting for parallel child:\n  perhaps you forgot to close a process in your callback?"
    );
}

sub report_fork_failure
{
    my ($when, $errcode, $failedAttempts) = @_;
    if ($failedAttempts > $lcovutil::max_fork_fails) {
        lcovutil::ignorable_error($lcovutil::ERROR_PARALLEL,
            "$failedAttempts consecutive fork() failures:  consider reduced parallelism or increase the max_fork_fails limit.  See man(5) lcovrc."
        );
    }
    my $explain = explain_once('fork_fail',
                               ["\n\tUse '$tool_name --ignore_errors " .
                                    $ERROR_NAME{$ERROR_FORK} .
                                    "' to bypass error and retry.",
                                $ignore[$lcovutil::ERROR_FORK] == 0
                               ]);
    my $retry =
        lcovutil::is_ignored($lcovutil::ERROR_FORK) ? ' (retrying)' : '';
    lcovutil::ignorable_error($lcovutil::ERROR_FORK,
                              "fork() syscall failed while trying to $when: " .
                                  $errcode . $retry . $explain);
    # if errors were ignored, then we wait for a while (in parent)
    #  before re-trying.
    sleep($lcovutil::fork_fail_timeout);
}

sub report_exit_status
{
    my ($errType, $message, $exitstatus, $prefix, $suffix) = @_;
    my $status = $exitstatus >> 8;
    my $signal = $exitstatus & 0xFF;
    my $explain =
        "$prefix " .
        ($exitstatus ? "returned non-zero exit status $status" : 'failed') .
        MessageContext::context();
    if ($signal) {
        $explain =
            "$prefix died died due to signal $signal (SIG" .
            (split(' ', $Config{sig_name}))[$signal] .
            ')' . MessageContext::context() .
            ': possibly killed by OS due to out-of-memory';
        $explain .=
            lcovutil::explain_once('out_of_memory',
                       ' - see --memory and --parallel options for throttling');
    }
    ignorable_error($errType, "$message: $explain$suffix");
}

sub report_parallel_error
{
    my $operation   = shift;
    my $errno       = shift;
    my $pid         = shift;
    my $childstatus = shift;
    my $msg         = shift;
    # kill all my remaining children so user doesn't see unexpected console
    #  messages from dangling children (who cannot open files because the
    #  temp directory has been deleted, and so forth)
    kill(9, @_) if @_ && !is_ignored($errno);
    report_exit_status($errno, "$operation: '$msg'",
                       $childstatus, "child $pid",
                       " (try removing the '--parallel' option)");
}

sub report_format_error($$$$)
{
    my ($errType, $countType, $count, $obj) = @_;
    my $context = MessageContext::context();
    my $explain =
        explain_once(
             'err_negative',
             ["\n\tPerhaps you need to compile with '-fprofile-update=atomic'.",
              ($lcovutil::ERROR_NEGATIVE == $errType &&
                   'geninfo' eq $lcovutil::tool_name)
             ]);
    my $errStr =
        $lcovutil::ERROR_NEGATIVE == $errType ? 'negative' :
        ($lcovutil::ERROR_FORMAT == $errType ? 'non-integer' : 'excessive');
    lcovutil::ignorable_error($errType,
        "Unexpected $errStr $countType count '$count' for $obj$context.$explain"
    );
}

sub check_parent_process
{
    die("must call from child process") unless $lcovutil::in_child_process;
    # if parent PID changed to 1 (init) - then my parent went away so
    #  I should exit now
    # for reasons which are unclear to me:  the PPID is sometimes unchanged
    #  after the parent process dies - to also check if we can send it a signal
    my $ppid = getppid();
    lcovutil::info(2, "check_parent_process($$) = $ppid\n");
    if (1 == getppid() ||
        1 != kill(0, $ppid)) {
        lcovutil::ignorable_error($lcovutil::ERROR_PARENT,
            "parent process died during '--parallel' execution - child $$ cannot continue."
        );
        exit(0);
    }
}

sub is_filter_enabled
{
    # return true of there is an opportunity for filtering
    return (grep({ defined($_) } @lcovutil::cov_filter) ||
            0 != scalar(@lcovutil::omit_line_patterns) ||
            0 != scalar(@lcovutil::exclude_function_patterns));
}

sub init_filters
{
    # initialize filter index numbers and mark that all filters are disabled.
    my $idx = 0;
    foreach my $item (sort keys(%COVERAGE_FILTERS)) {
        my $ref = $COVERAGE_FILTERS{$item};
        $COVERAGE_FILTERS{$item} = $idx;
        $$ref                    = $idx;
        $cov_filter[$idx++]      = undef;
    }
}

sub parse_cov_filters(@)
{
    my @filters = split($split_char, join($split_char, @_));

    goto final if (!@filters);

    foreach my $item (@filters) {
        die("unknown argument for --filter: '$item'\n")
            unless exists($COVERAGE_FILTERS{lc($item)});
        my $item_id = $COVERAGE_FILTERS{lc($item)};

        $cov_filter[$item_id] = [$item, 0, 0];
    }
    if ($cov_filter[$FILTER_LINE]) {
        # when line filtering is enabled, turn on brace and blank filtering as well
        #  (backward compatibility)
        $cov_filter[$FILTER_LINE_CLOSE_BRACE] = ['brace', 0, 0];
        $cov_filter[$FILTER_BLANK_LINE]       = ['blank', 0, 0];
    }
    if ((defined($cov_filter[$FILTER_BRANCH_NO_COND]) ||
         defined($cov_filter[$FILTER_EXCLUDE_BRANCH])) &&
        !($br_coverage || $mcdc_coverage)
    ) {
        lcovutil::ignorable_warning($ERROR_USAGE,
            "branch filter enabled but neither branch or condition coverage is enabled"
        );
    }
    lcovutil::ignorable_warning($ERROR_USAGE,
                     "'mcdc' filter enabled but MC/DC coverage is not enabled.")
        if (defined($cov_filter[$FILTER_MCDC_SINGLE]) &&
            !$mcdc_coverage);
    if ($cov_filter[$FILTER_BRANCH_NO_COND]) {
        # turn on exception and orphan filtering too
        $cov_filter[$FILTER_EXCEPTION_BRANCH] = ['exception', 0, 0];
        $cov_filter[$FILTER_ORPHAN_BRANCH]    = ['orphan', 0, 0];
    }
    final:
    if (@lcovutil::omit_line_patterns) {
        $lcovutil::FILTER_OMIT_PATTERNS = scalar(@lcovutil::cov_filter);
        push(@lcovutil::cov_filter, ['omit_lines', 0, 0]);
        $lcovutil::COVERAGE_FILTERS{'omit_lines'} =
            $lcovutil::FILTER_OMIT_PATTERNS;
    }
}

sub summarize_cov_filters
{
    # use verbosity level -1:  so print unless user says "-q -q"...really quiet

    my $leader = "Filter suppressions:\n";
    for my $key (keys(%COVERAGE_FILTERS)) {
        my $id = $COVERAGE_FILTERS{$key};
        next unless defined($lcovutil::cov_filter[$id]);
        my $histogram = $lcovutil::cov_filter[$id];
        next if 0 == $histogram->[-2];
        my $points = '';
        if ($histogram->[-2] != $histogram->[-1]) {
            $points = '    ' . $histogram->[-1] . ' coverpoint' .
                ($histogram->[-1] > 1 ? 's' : '') . "\n";
        }
        info(-1,
             "$leader  $key:\n    " . $histogram->[-2] . " instance" .
                 ($histogram->[-2] > 1 ? "s" : "") . "\n" . $points);
        $leader = '';
    }
    foreach my $q (['omit-lines', 'line', \@omit_line_patterns],
                 ['erase-functions', 'function', \@exclude_function_patterns]) {
        my ($opt, $type, $patterns) = @$q;
        my $patternCount = scalar(@$patterns);
        if ($patternCount) {
            my $omitCount = 0;
            foreach my $p (@$patterns) {
                $omitCount += $p->[-1];
            }
            info(-1,
                 "Omitted %d total $type%s matching %d '--$opt' pattern%s\n",
                 $omitCount,
                 $omitCount == 1 ? '' : 's',
                 $patternCount,
                 $patternCount == 1 ? '' : 's');
        }
    }
}

sub disable_cov_filters
{
    # disable but return current status - so they can be re-enabled
    my @filters = @lcovutil::cov_filter;
    foreach my $f (@lcovutil::cov_filter) {
        $f = undef;
    }
    my @omit = @lcovutil::omit_line_patterns;
    @lcovutil::omit_line_patterns = ();
    my @erase = @lcovutil::exclude_function_patterns;
    @lcovutil::exclude_function_patterns = ();
    return [\@filters, \@omit, \@erase];
}

sub reenable_cov_filters
{
    my $data    = shift;
    my $filters = $data->[0];
    # re-enable in the same order
    for (my $i = 0; $i < scalar(@$filters); $i++) {
        $cov_filter[$i] = $filters->[$i];
    }
    @lcovutil::omit_line_patterns        = @{$data->[1]};
    @lcovutil::exclude_function_patterns = @{$data->[2]};
}

sub filterStringsAndComments
{
    my $src_line = shift;

    # remove compiler directives
    $src_line =~ s/^\s*#.*$//g;
    # remove comments
    $src_line =~ s#(/\*.*?\*/|//.*$)##g;
    # remove strings
    $src_line =~ s/\\"//g;
    $src_line =~ s/"[^"]*"//g;

    return $src_line;
}

sub simplifyCode
{
    my $src_line = shift;

    # remove comments
    $src_line = filterStringsAndComments($src_line);
    # remove some keywords..
    $src_line =~ s/\b(const|volatile|typename)\b//g;
    #collapse nested class names
    # remove things that look like template names
    my $id = '(::)?\w+\s*(::\s*\w+\s*)*';
    while (1) {
        my $current = $src_line;
        $src_line =~ s/<\s*${id}(,\s*${id})*([*&]\s*)?>//g;
        last if $src_line eq $current;
    }
    # remove ref and pointer decl
    $src_line =~ s/^\s*$id[&*]\s*($id)/$3/g;
    # cast which contains optional location spec
    my $cast = "\\s*${id}(\\s+$id)?[*&]\\s*";
    # C-style cast - with optional location spec
    $src_line =~ s/\($cast\)//g;
    $src_line =~ s/\b(reinterpret|dynamic|const)_cast<$cast>//g;
    # remove addressOf that follows an open paren or a comma
    #$src_line =~ s/([(,])\s*[&*]\s*($id)/$1 $2/g;

    # remove some characters which might look like conditionals
    $src_line =~ s/(->|>>|<<|::)//g;

    return $src_line;
}

sub balancedParens
{
    my $line = shift;

    my $open  = 0;
    my $close = 0;

    foreach my $char (split('', $line)) {
        if ($char eq '(') {
            ++$open;
        } elsif ($char eq ')') {
            ++$close;
        }
    }
    return ($open == $close ||
                # lambda code may have trailing parens after the function...
                ($close > $open && $line =~ /{lambda\(/)
    );    # this is a C++-specific check
}

#
# is_external(filename)
#
# Determine if a file is located outside of the specified data directories.
#

sub is_external($)
{
    my $filename = shift;

    # nothing is 'external' unless the user has requested "--no-external"
    return 0 unless (defined($opt_no_external) && $opt_no_external);

    foreach my $dir (@internal_dirs) {
        return 0
            if (($lcovutil::case_insensitive && $filename =~ /^\Q$dir\E/i) ||
                (!$lcovutil::case_insensitive && $filename =~ /^\Q$dir\E/));
    }
    return 1;
}

#
# rate(hit, found[, suffix, precision, width])
#
# Return the coverage rate [0..100] for HIT and FOUND values. 0 is only
# returned when HIT is 0. 100 is only returned when HIT equals FOUND.
# PRECISION specifies the precision of the result. SUFFIX defines a
# string that is appended to the result if FOUND is non-zero. Spaces
# are added to the start of the resulting string until it is at least WIDTH
# characters wide.
#

sub rate($$;$$$)
{
    my ($hit, $found, $suffix, $precision, $width) = @_;

    # Assign defaults if necessary
    $precision = $default_precision
        if (!defined($precision));
    $suffix = "" if (!defined($suffix));
    $width  = 0 if (!defined($width));

    return sprintf("%*s", $width, "-") if (!defined($found) || $found == 0);
    my $rate = sprintf("%.*f", $precision, $hit * 100 / $found);

    # Adjust rates if necessary
    if ($rate == 0 && $hit > 0) {
        $rate = sprintf("%.*f", $precision, 1 / 10**$precision);
    } elsif ($rate == 100 && $hit != $found) {
        $rate = sprintf("%.*f", $precision, 100 - 1 / 10**$precision);
    }

    return sprintf("%*s", $width, $rate . $suffix);
}

#
# get_overall_line(found, hit, type)
#
# Return a string containing overall information for the specified
# found/hit data.
#

sub get_overall_line($$$)
{
    my ($found, $hit, $name) = @_;
    return "no data found" if (!defined($found) || $found == 0);

    my $plural =
        ($found == 1) ? "" : (('ch' eq substr($name, -2, 2)) ? 'es' : 's');

    return lcovutil::rate($hit, $found, "% ($hit of $found $name$plural)");
}

# Make sure precision is within valid range [1:4]
sub check_precision()
{
    die("specified precision is out of range (1 to 4)\n")
        if ($default_precision < 1 || $default_precision > 4);
}

# use vanilla color palette.
sub use_vanilla_color()
{
    for my $tla (('CBC', 'GNC', 'GIC', 'GBC')) {
        $lcovutil::tlaColor{$tla}     = "#CAD7FE";
        $lcovutil::tlaTextColor{$tla} = "#98A0AA";
    }
    for my $tla (('UBC', 'UNC', 'UIC', 'LBC')) {
        $lcovutil::tlaColor{$tla}     = "#FF6230";
        $lcovutil::tlaTextColor{$tla} = "#AA4020";
    }
    for my $tla (('EUB', 'ECB')) {
        $lcovutil::tlaColor{$tla}     = "#FFFFFF";
        $lcovutil::tlaTextColor{$tla} = "#AAAAAA";
    }
}

my $didFirstExistenceCheck;

sub fileExistenceBeforeCallbackError
{
    my $filename = shift;
    if ($lcovutil::check_file_existence_before_callback &&
        !-e $filename) {

        my $explanation =
            $didFirstExistenceCheck ? '' :
            '  Use \'check_existence_before_callback = 0\' config file option to remove this check.';
        lcovutil::ignorable_error($lcovutil::ERROR_SOURCE,
                                "\"$filename\" does not exist." . $explanation);
        $didFirstExistenceCheck = 1;
        return 1;
    }
    return 0;
}

# figure out what file version we see
sub extractFileVersion
{
    my $filename = shift;

    return undef
        unless $versionCallback;
    return $versionCache{$filename} if exists($versionCache{$filename});

    return undef if fileExistenceBeforeCallbackError($filename);

    my $start = Time::HiRes::gettimeofday();
    my $version;
    eval { $version = $versionCallback->extract_version($filename); };
    if ($@) {
        my $context = MessageContext::context();
        lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                               "extract_version($filename) failed$context: $@");
    }
    my $end = Time::HiRes::gettimeofday();
    if (exists($lcovutil::profileData{version}) &&
        exists($lcovutil::profileData{version}{$filename})) {
        $lcovutil::profileData{version}{$filename} += $end - $start;
    } else {
        $lcovutil::profileData{version}{$filename} = $end - $start;
    }
    $versionCache{$filename} = $version;
    return $version;
}

sub checkVersionMatch
{
    my ($filename, $me, $you, $reason, $silent) = @_;

    return 1
        if defined($me) && defined($you) && $me eq $you; # simple string compare

    if ($versionCallback) {
        # work harder
        my $status;
        eval {
            $status = $versionCallback->compare_version($you, $me, $filename);
        };
        if ($@) {
            my $context = MessageContext::context();
            lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                    "compare_version($you, $me, $filename) failed$context: $@");
            $status = 1;
        }
        lcovutil::info(1, "compare_version: $status\n");
        return 1 unless $status;    # match if return code was zero
    }
    lcovutil::ignorable_error($ERROR_VERSION,
                          (defined($reason) ? ($reason . ' ') : '') .
                              "$filename: revision control version mismatch: " .
                              (defined($me) ? $me : 'undef') .
                              ' <- ' . (defined($you) ? $you : 'undef'))
        unless $silent;
    # claim mismatch unless $me and $you are both undef
    return !(defined($me) || defined($you));
}

#
# parse_w3cdtf(date_string)
#
# Parse date string in W3CDTF format into DateTime object.
#
my $have_w3cdtf;

sub parse_w3cdtf($)
{
    if (!defined($have_w3cdtf)) {
        # check to see if the package is here for us to use..
        $have_w3cdtf = 1;
        eval {
            require DateTime::Format::W3CDTF;
            DateTime::Format::W3CDTF->import();
        };
        if ($@) {
            # package not there - fall back
            lcovutil::ignorable_warning($lcovutil::ERROR_PACKAGE,
                'package DateTime::Format::W3CDTF is not available - falling back to local implementation'
            );
            $have_w3cdtf = 0;
        }
    }
    my $str = shift;
    if ($have_w3cdtf) {
        return DateTime::Format::W3CDTF->parse_datetime($str);
    }

    my ($year, $month, $day, $hour, $min, $sec, $ns, $tz) =
        (0, 1, 1, 0, 0, 0, 0, "Z");

    if ($str =~ /^(\d\d\d\d)$/) {
        # YYYY
        $year = $1;
    } elsif ($str =~ /^(\d\d\d\d)-(\d\d)$/) {
        # YYYY-MM
        $year  = $1;
        $month = $2;
    } elsif ($str =~ /^(\d\d\d\d)-(\d\d)-(\d\d)$/) {
        # YYYY-MM-DD
        $year  = $1;
        $month = $2;
        $day   = $3;
    } elsif (
         $str =~ /^(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d)(Z|[+-]\d\d:\d\d)?$/) {
        # YYYY-MM-DDThh:mmTZD
        $year  = $1;
        $month = $2;
        $day   = $3;
        $hour  = $4;
        $min   = $5;
        $tz    = $6 if defined($6);
    } elsif ($str =~
          /^(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)(Z|[+-]\d\d:\d\d)?$/) {
        # YYYY-MM-DDThh:mm:ssTZD
        $year  = $1;
        $month = $2;
        $day   = $3;
        $hour  = $4;
        $min   = $5;
        $sec   = $6;
        $tz    = $7 if (defined($7));
    } elsif ($str =~
        /^(\d\d\d\d)-(\d\d)-(\d\d)T(\d\d):(\d\d):(\d\d)\.(\d+)(Z|[+-]\d\d:\d\d)?$/
    ) {
        # YYYY-MM-DDThh:mm:ss.sTZD
        $year  = $1;
        $month = $2;
        $day   = $3;
        $hour  = $4;
        $min   = $5;
        $sec   = $6;
        $ns    = substr($7 . "00000000", 0, 9);
        $tz    = $8 if (defined($8));
    } else {
        die("Invalid W3CDTF date format: $str\n");
    }

    return
        DateTime->new(year       => $year,
                      month      => $month,
                      day        => $day,
                      hour       => $hour,
                      minute     => $min,
                      second     => $sec,
                      nanosecond => $ns,
                      time_zone  => $tz,);
}

package HTML_fileData;

use constant {
              NAME    => 0,
              PARENT  => 1,
              HREFS   => 2,
              ANCHORS => 3,
};

sub new
{
    my ($class, $parentDir, $filename) = @_;

    my $self = [$parentDir, $filename, [], {}];

    my $name = File::Spec->catfile($parentDir, $filename);

    open(HTML, '<', $name) or die("unable to open $name: $!");
    while (<HTML>) {
        if (/<(a|span) .*id=\"([^\"]+)\"/) {
            lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                            "\"$name\":$.: duplicate anchor '$2' original at " .
                                $self->[ANCHORS]->{$2} . '.')
                if exists($self->[ANCHORS]->{$2});
            $self->[ANCHORS]->{$2} = $.;
        } elsif (/<a .*href=\"([^#\"]+)(#([^\"]+))?\"/) {
            next if 'http' eq substr($1, 0, 4);
            push(@{$self->[HREFS]}, [$., $1, $3]);    # lineNo, filename, anchor
        } elsif (/<frame .*src=\"([^\"]+)\"/) {
            push(@{$self->[HREFS]}, [$., $1, $3]);    # lineNo, filename, anchor
        }
    }
    close(HTML) or die("unable to close $name: $!");

    return bless $self, $class;
}

sub verifyAnchor
{
    my ($self, $anchor) = @_;

    return exists($self->[ANCHORS]->{$anchor});
}

sub hrefs
{
    my $self = shift;
    return $self->[HREFS];
}

package ValidateHTML;

sub new
{
    my ($class, $topDir, $htmlExt) = @_;
    my $self = {};

    $htmlExt = '.html' unless defined($htmlExt);

    my @dirstack = ($topDir);
    my %visited;
    while (@dirstack) {
        my $top = pop(@dirstack);
        die("unexpected link $top") if -l $top;
        opendir(my $dh, $top) or die("can't open directory $top: $!");
        while (my $e = readdir($dh)) {
            next if $e eq '.' || $e eq '..';
            my $p = File::Spec->catfile($top, $e);
            die("unexpected link $p") if -l $p;
            if (-d $p) {
                die("already visited $p") if exists($visited{$p});
                $visited{$p} = [$top, $e];
                push(@dirstack, $p);
            } elsif (-f $p &&
                     $p =~ /.+$htmlExt$/) {
                die("duplicate file $p??") if exists($self->{$p});
                lcovutil::info(1, "schedule $p\n");
                $self->{$p} = HTML_fileData->new($top, $e);
            }
        }
        closedir($dh);
    }
    my %fileReferred;
    while (my ($filename, $data) = each(%$self)) {
        my $dir = File::Basename::dirname($filename);
        lcovutil::info(1, "verify $filename:\n");
        foreach my $href (@{$data->hrefs()}) {
            my ($lineNo, $link, $anchor) = @$href;
            my $path = File::Spec->catfile($dir, $link);
            $path = File::Spec->abs2rel(Cwd::realpath($path), $main::cwd)
                unless exists($self->{$path});
            lcovutil::info(1,
                       "  $lineNo: $link" . ($anchor ? "#$anchor" : '') . "\n");
            unless (exists($self->{$path})) {
                lcovutil::ignorable_error($lcovutil::ERROR_PATH,
                           "\"$filename\":$lineNo: non-existent file '$link'.");
                next;
            }
            if (exists($fileReferred{$path})) {
                # keep only one use
                push(@{$fileReferred{$path}}, $filename)
                    if ($fileReferred{$path}->[-1] ne $filename);
            } else {
                $fileReferred{$path} = [$filename];
            }

            if (defined($anchor)) {
                my $a = $self->{$path};
                unless ($a->verifyAnchor($anchor)) {
                    lcovutil::ignorable_error($lcovutil::ERROR_PATH,
                        "\"$filename\":$lineNo: \"$link#$anchor\" doesn't point to valid anchor."
                    );
                }
            }
        }
    }

    while (my ($filename, $data) = each(%$self)) {
        lcovutil::ignorable_error($lcovutil::ERROR_UNUSED,
                                  "HTML file \"$filename\" is not referenced.")
            unless (exists($fileReferred{$filename}) ||
                    ($topDir eq File::Basename::dirname($filename) &&
                     "index$htmlExt" eq File::Basename::basename($filename)));
    }
    return bless $self, $class;
}

package CoverageCriteria;

our @coverageCriteriaScript;
our $criteriaCallback;
our %coverageCriteria;              # hash of name->(type, success 0/1, string)
our $coverageCriteriaStatus = 0;    # set to non-zero if we see any errors
our @criteriaCallbackTypes;         # include date, owner bin info
our @criteriaCallbackLevels;        # call back at (top, directory, file) levels

sub executeCallback
{
    my ($type, $name, $data) = @_;

    my ($status, $msgs);
    eval {
        ($status, $msgs) =
            $criteriaCallback->check_criteria($name, $type, $data);
    };
    if ($@) {
        my $context = MessageContext::context();
        lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                  "check_criteria failed$context: $@");
        $status = 2;
        $msgs   = [$@];
    }

    $coverageCriteria{$name} = [$type, $status, $msgs]
        if (0 != $status ||
            (defined $msgs &&
             0 != scalar(@$msgs)));
    $coverageCriteriaStatus = $status
        if $status != 0;
}

sub check_failUnder
{
    my $info = shift;
    my $msg  = $info->check_fail_under_criteria();
    if ($msg) {
        $coverageCriteriaStatus |= 1;
        $coverageCriteria{'top'} = ['top', 1, [$msg]];
    }
}

sub summarize
{
    # print the criteria summary to stdout:
    #   all criteria fails + any non-empty messages
    # In addition:  print fails to stderr
    # This way:  Jenkins script can log failure if stderr is not empty
    my $leader = '';
    if ($coverageCriteriaStatus != 0) {
        print("Failed coverage criteria:\n");
    } else {
        $leader = "Coverage criteria:\n";
    }
    # sort to print top-level report first, then directories, then files.
    foreach my $name (sort({
                               my $da = $coverageCriteria{$a};
                               my $db = $coverageCriteria{$b};
                               my $ta = $da->[0];
                               my $tb = $db->[0];
                               return -1 if ($ta eq 'top');
                               return 1 if ($tb eq 'top');
                               if ($ta ne $tb) {
                                   return $ta eq 'file' ? 1 : -1;
                               }
                               $a cmp $b
                           }
                           keys(%coverageCriteria))
    ) {
        my $criteria = $coverageCriteria{$name};
        my $v        = $criteria->[1];
        next if (!$v || $v == 0) && 0 == scalar(@{$criteria->[2]});    # passed

        my $msg = $criteria->[0];
        if ($criteria->[0] ne 'top') {
            $msg .= " \"" . $name . "\"";
        }
        $msg .= ": \"" . join(' ', @{$criteria->[2]}) . "\"\n";
        print($leader);
        $leader = '';
        print("  " . $msg);
        if (0 != $criteria->[1]) {
            print(STDERR $msg);
        }
    }
}

package MessageContext;

our @message_context;

sub new
{
    my ($class, $str) = @_;
    push(@message_context, $str);
    my $self = [$str];
    return bless $self, $class;
}

sub context
{
    my $context = join(' while ', @message_context);
    $context = ' while ' . $context if $context;
    return $context;
}

sub DESTROY
{
    my $self = shift;
    die('unbalanced context "' . $self->[0] . '" not head of ("' .
        join('" "', @message_context) . '")')
        unless scalar(@message_context) && $self->[0] eq $message_context[-1];
    pop(@message_context);
}

package PipeHelper;

sub new
{
    my $class  = shift;
    my $reason = shift;

    # backward compatibility:  see if the arguments were passed in a
    #  one long string
    my $args   = \@_;
    my $arglen = 'criteria' eq $reason ? 4 : 2;
    if ($arglen == scalar(@_) && !-e $_[0]) {
        # two arguments:  a string (which seems not to be executable) and the
        #  file we are acting on
        # After next release, issue 'deprecated' warning here.
        my @args = split(' ', $_[0]);
        push(@args, splice(@_, 1));    # append the rest of the args
        $args = \@args;
    }

    my $self = [$reason, join(' ', @$args)];
    bless $self, $class;
    if (open(PIPE, "-|", @$args)) {
        push(@$self, \*PIPE);
    } else {
        lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                       "$reason: 'open(-| " . $self->[1] . ")' failed: \"$!\"");
        return undef;
    }
    return $self;
}

sub next
{
    my $self = shift;
    die("no handle") unless scalar(@$self) == 3;
    my $hdl = $self->[2];
    return scalar <$hdl>;
}

sub close
{
    # close pipe and return exit status
    my ($self, $checkError) = @_;
    close($self->[2]);
    if (0 != $? && $checkError) {
        # $reason: $cmd returned non-zero exit...
        lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                  $self->[0] . ' \'' . $self->[1] .
                                      "\' returned non-zero exit code: '$!'");
    }
    pop(@$self);
    return $?;
}

sub DESTROY
{
    my $self = shift;
    # FD can be undef if 'open' failed for any reason (e.g., filesystem issues)
    # otherwise:  don't close if FD was STDIN or STDOUT
    CORE::close($self->[2])
        if 3 == scalar(@$self);
}

package ScriptCaller;

sub new
{
    my $class = shift;
    my $self  = [@_];
    return bless $self, $class;
}

sub call
{
    my ($self, $reason, @args) = @_;
    my $cmd = join(' ', @$self) . ' ' . join(' ', @args);
    lcovutil::info(1, "$reason: \"$cmd\"\n");
    my $rtn = `$cmd`;
    return $?;
}

sub pipe
{
    my $self   = shift;
    my $reason = shift;
    return PipeHelper->new($reason, @$self, @_);
}

sub context
{
    my $self = shift;
    lcovutil::info(1, 'context ' . join(' ', @$self) . "\n");
    my $iter = $self->pipe('context');
    return unless defined($iter);
    my %context;
    while (my $line = $iter->next()) {
        chomp($line);
        $line =~ s/\r//g;    # remove CR from line-end
                             # first word on line is the key..
        my ($key, $value) = split(/ +/, $line, 2);
        if (exists($context{key})) {
            $context{key} .= "\n" . $value;
        } else {
            $context{key} = $value;
        }
    }
    my $status = $iter->close(1);    # check error return

    return \%context;
}

sub extract_version
{
    my ($self, $filename) = @_;
    my $version;
    my $pipe = $self->pipe('extract_version', $filename);
    if (defined $pipe &&
        ($version = $pipe->next())) {
        chomp($version);
        $version =~ s/\r//;
        lcovutil::info(1, "  version: $version\n");
    }
    return $version;
}

sub resolve
{
    my ($self, $filename) = @_;
    my $path;
    my $pipe = $self->pipe('resolve_filename', $filename);
    if ($pipe &&
        ($path = $pipe->next())) {
        chomp($path);
        $path =~ s/\r//;
        lcovutil::info(1, "  resolve: $path\n");
    }
    return $path;
}

sub compare_version
{
    my ($self, $yours, $mine, $file) = @_;
    return
        $self->call('compare_version', '--compare',
                    "'$yours'", "'$mine'",
                    "'$file'");
}

# annotate callback is passed filename (as munged) -
# should return reference to array of line data,
# line data of the form list of:
#    source_text:  the content on that line
#    abbreviated author name:  (must be set to something - possibly NONE
#    full author name:  some string or undef
#    date string:  when this line was last changed
#    commit ID:  something meaningful to you
sub annotate
{
    my ($self, $filename) = @_;
    lcovutil::info(1, 'annotate ' . join(' ', @$self) . ' ' . $filename . "\n");
    my $iter = $self->pipe('annotate', $filename);
    return unless defined($iter);
    my @lines;
    while (my $line = $iter->next()) {
        chomp $line;
        $line =~ s/\r//g;    # remove CR from line-end

        my ($commit, $author, $when, $text) = split(/\|/, $line, 4);
        # semicolon is not a legal character in email address -
        #   so we use that to delimit the 'abbreviated name' and
        #   the 'full name' - in case they are different.
        # this is an attempt to be backward-compatible with
        # existing annotation scripts which return only one name
        my ($abbrev, $full) = split(/;/, $author, 2);
        push(@lines, [$text, $abbrev, $full, $when, $commit]);
    }
    my $status = $iter->close();

    return ($status, \@lines);
}

sub check_criteria
{
    my ($self, $name, $type, $data) = @_;

    my $iter =
        $self->pipe('criteria', $name, $type, JsonSupport::encode($data));
    return (0) unless $iter;    # constructor will have given error message
    my @messages;
    while (my $line = $iter->next()) {
        chomp $line;
        $line =~ s/\r//g;       # remove CR from line-end
        next if '' eq $line;
        push(@messages, $line);
    }
    return ($iter->close(), \@messages);
}

sub select
{
    my ($self, $lineData, $annotateData, $filename, $lineNo) = @_;

    my @params = ('select',
                  defined($lineData) ?
                      JsonSupport::encode($lineData->to_list()) : '',
                  defined($annotateData) ?
                      JsonSupport::encode($annotateData->to_list()) : '',
                  $filename,
                  $lineNo);
    return $self->call(@params);
}

sub simplify
{
    my ($self, $func) = @_;

    my $name;
    my $pipe = $self->pipe('simplify', $func);
    die("broken 'simplify' callback")
        unless ($pipe &&
                ($name = $pipe->next()));

    chomp($name);
    $name =~ s/\r//;
    lcovutil::info(1, "  simplify: $name\n");
    return $name;
}

package JsonSupport;

our $rc_json_module = 'auto';

our $did_init;

#
# load_json_module(rc)
#
# If RC is "auto", load best available JSON module from a list of alternatives,
# otherwise load the module specified by RC.
#
sub load_json_module($)
{
    my ($rc) = shift;
    # List of alternative JSON modules to try
    my @alternatives = ("JSON::XS",         # Fast, but not always installed
                        "Cpanel::JSON::XS", # Fast, a more recent fork
                        "JSON::PP",         # Slow, part of core-modules
                        "JSON",             # Not available in all distributions
    );

    # Determine JSON module
    if (lc($rc) eq "auto") {
        for my $m (@alternatives) {
            if (Module::Load::Conditional::check_install(module => $m)) {
                $did_init = $m;
                last;
            }
        }

        if (!defined($did_init)) {
            die("No Perl JSON module found on your system.  Please install of of the following supported modules: "
                    . join(" ", @alternatives)
                    . " - for example (as root):\n  \$ perl -MCPAN -e 'install "
                    . $alternatives[0]
                    . "'\n");
        }
    } else {
        $did_init = $rc;
    }

    eval "use $did_init qw(encode_json decode_json);";
    if ($@) {
        die("Module is not installed: " . "'$did_init':$@\n");
    }
    lcovutil::info(1, "Using JSON module $did_init\n");
    my ($index) =
        grep { $alternatives[$_] eq $did_init } (0 .. @alternatives - 1);
    warn(
        "using JSON module \"$did_init\" - which is much slower than some alternatives.  Consider installing one of "
            . join(" or ", @alternatives[0 .. $index - 1]))
        if (defined($index) && $index > 1);
}

sub encode($)
{
    my $data = shift;

    load_json_module($rc_json_module)
        unless defined($did_init);

    return encode_json($data);
}

sub decode($)
{
    my $text = shift;
    load_json_module($rc_json_module)
        unless defined($did_init);

    return decode_json($text);
}

sub load($)
{
    my $filename = shift;
    my $f        = InOutFile->in($filename);
    my $h        = $f->hdl();
    my @lines    = <$h>;
    return decode(join("\n", @lines));
}

package InOutFile;

our $checkedGzipAvail;

sub checkGzip
{
    # Check for availability of GZIP tool
    lcovutil::system_no_output(1, "gzip", "-h") and
        die("gzip command not available!\n");
    $checkedGzipAvail = 1;
}

sub out
{
    my ($class, $f, $mode, $demangle) = @_;
    $demangle = 0 unless defined($demangle);

    my $self = [undef, $f];
    bless $self, $class;
    my $m = (defined($mode) && $mode eq 'append') ? ">>" : ">";

    if (!defined($f) ||
        '-' eq $f) {
        if ($demangle) {
            open(HANDLE, '|-', $lcovutil::demangle_cpp_cmd) or
                die("unable to demangle: $!\n");
            $self->[0] = \*HANDLE;
        } else {
            $self->[0] = \*STDOUT;
        }
    } else {
        my $cmd = $demangle ? "$lcovutil::demangle_cpp_cmd " : '';
        if ($f =~ /\.gz$/) {
            checkGzip()
                unless defined($checkedGzipAvail);
            $cmd .= '| ' if $cmd;
            # Open compressed file
            $cmd .= "gzip -c $m'$f'";
            open(HANDLE, "|-", $cmd) or
                die("cannot start gzip to compress to file $f: $!\n");
        } else {
            if ($demangle) {
                $cmd .= "$m '$f'";
            } else {
                $cmd .= $f;
            }
            open(HANDLE, $demangle ? '|-' : $m, $cmd) or
                die("cannot write to $f: $!\n");
        }
        $self->[0] = \*HANDLE;
    }
    return $self;
}

sub in
{
    my ($class, $f, $demangle) = @_;
    $demangle = 0 unless defined($demangle);

    my $self = [undef, $f];
    bless $self, $class;

    if (!defined($f) ||
        '-' eq $f) {
        $self->[0] = \*STDIN;
    } else {
        if ($f =~ /\.gz$/) {

            checkGzip()
                unless defined($checkedGzipAvail);

            die("file '$f' does not exist\n")
                unless -f $f;
            die("'$f': unsupported empty gzipped file\n")
                if (-z $f);
            # Check integrity of compressed file - fails for zero size file
            lcovutil::system_no_output(1, "gzip", "-dt", $f) and
                die("integrity check failed for compressed file $f!\n");

            # Open compressed file
            my $cmd = "gzip -cd '$f'";
            $cmd .= " | " . $lcovutil::demangle_cpp_cmd
                if ($demangle);
            open(HANDLE, "-|", $cmd) or
                die("cannot start gunzip to decompress file $f: $!\n");

        } elsif ($demangle &&
                 defined($lcovutil::demangle_cpp_cmd)) {
            open(HANDLE, "-|", "cat '$f' | $lcovutil::demangle_cpp_cmd") or
                die("cannot start demangler for file $f: $!\n");
        } else {
            # Open decompressed file
            open(HANDLE, "<", $f) or
                die("cannot read file $f: $!\n");
        }
        $self->[0] = \*HANDLE;
    }
    return $self;
}

sub DESTROY
{
    my $self = shift;
    # FD can be undef if 'open' failed for any reason (e.g., filesystem issues)
    # otherwise:  don't close if FD was STDIN or STDOUT
    close($self->[0])
        unless !defined($self->[1]) ||
        '-' eq $self->[1] ||
        !defined($self->[0]);
}

sub hdl
{
    my $self = shift;
    return $self->[0];
}

package SearchPath;

sub new
{
    my $class  = shift;
    my $option = shift;
    my $self   = [];
    bless $self, $class;
    foreach my $p (@_) {
        if (-d $p) {
            push(@$self, [$p, 0]);
        } else {
            lcovutil::ignorable_error($lcovutil::ERROR_PATH,
                                      "$option '$p' is not a directory");
        }
    }
    return $self;
}

sub patterns
{
    my $self = shift;
    return $self;
}

sub resolve
{
    my ($self, $filename, $applySubstitutions) = @_;
    $filename = lcovutil::subst_file_name($filename) if $applySubstitutions;
    return $filename if -e $filename;
    if (!File::Spec->file_name_is_absolute($filename)) {
        foreach my $d (@$self) {
            my $path = File::Spec->catfile($d->[0], $filename);
            if (-e $path) {
                lcovutil::info(1, "found $filename at $path\n");
                ++$d->[1];
                return $path;
            }
        }
    }
    return resolveCallback($filename, 0);
}

sub resolveCallback
{
    my ($filename, $applySubstitutions, $returnCbValue) = @_;
    $filename = lcovutil::subst_file_name($filename) if $applySubstitutions;

    if ($lcovutil::resolveCallback) {
        return $lcovutil::resolveCache{$filename}
            if exists($lcovutil::resolveCache{$filename});
        my $start = Time::HiRes::gettimeofday();
        my $path;
        eval { $path = $resolveCallback->resolve($filename); };
        if ($@) {
            my $context = MessageContext::context();
            lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                      "resolve($filename) failed$context: $@");
        }
        # look up particular path at most once...
        $lcovutil::resolveCache{$filename} = $path if $path;
        my $cost = Time::HiRes::gettimeofday() - $start;
        if (!$returnCbValue) {
            $path = $filename unless $path;
        }
        my $p = $path ? $path : $filename;
        if (exists($lcovutil::profileData{resolve}) &&
            exists($lcovutil::profileData{resolve}{$p})) {
            # might see multiple aliases for the same source file
            $lcovutil::profileData{resolve}{$p} += $cost;
        } else {
            $lcovutil::profileData{resolve}{$p} = $cost;
        }
        return $path;
    }
    return $filename;
}

sub warn_unused
{
    my ($self, $optName) = @_;
    foreach my $d (@$self) {
        my $name = $d->[0];
        $name = "'$name'" if $name =~ /\s/;
        if (0 == $d->[1]) {
            lcovutil::ignorable_error($lcovutil::ERROR_UNUSED,
                                      "\"$optName $name\" is unused.");
        } else {
            lcovutil::info(1,
                           "\"$optName $name\" used " . $d->[1] . " times\n");
        }
    }
}

sub reset
{
    my $self = shift;
    foreach my $d (@$self) {
        $d->[1] = 0;
    }
}

sub current_count
{
    my $self = shift;
    my @rtn;
    foreach my $d (@$self) {
        push(@rtn, $d->[1]);
    }
    return \@rtn;
}

sub update_count
{
    my $self = shift;
    die("invalid update count: " . scalar(@$self) . ' ' . scalar(@_))
        unless ($#$self == $#_);
    foreach my $d (@$self) {
        $d->[1] += shift;
    }
}

package MapData;

sub new
{
    my $class = shift;
    my $self  = {};
    bless $self, $class;

    return $self;
}

sub is_empty
{
    my $self = shift;
    return 0 == scalar(keys %$self);
}

sub append_if_unset
{
    my $self = shift;
    my $key  = shift;
    my $data = shift;

    if (!defined($self->{$key})) {
        $self->{$key} = $data;
    }
    return $self;
}

sub replace
{
    my $self = shift;
    my $key  = shift;
    my $data = shift;

    $self->{$key} = $data;

    return $self;
}

sub value
{
    my $self = shift;
    my $key  = shift;

    if (!exists($self->{$key})) {
        return undef;
    }

    return $self->{$key};
}

sub remove
{
    my ($self, $key, $check_is_present) = @_;

    if (!defined($check_is_present) || exists($self->{$key})) {
        delete $self->{$key};
        return 1;
    }
    return 0;
}

sub mapped
{
    my $self = shift;
    my $key  = shift;

    return defined($self->{$key}) ? 1 : 0;
}

sub keylist
{
    my $self = shift;
    return keys(%$self);
}

sub entries
{
    my $self = shift;
    return scalar(keys(%$self));
}

# Class definitions
package CountData;

our $UNSORTED = 0;
our $SORTED   = 1;

use constant {
              HASH     => 0,
              SORTABLE => 1,
              FOUND    => 2,
              HIT      => 3,
              FILENAME => 4,
};

sub new
{
    my $class    = shift;
    my $filename = shift;
    my $sortable = defined($_[0]) ? shift : $UNSORTED;
    my $self = [{},
                $sortable,
                0,            # found
                0,            # hit
                $filename,    # for error messaging
    ];
    bless $self, $class;

    return $self;
}

sub filename
{
    my $self = shift;
    return $self->[FILENAME];
}

sub append
{
    # return 1 if we hit something new, 0 if not (count was already non-zero)
    # using $suppressErrMsg to avoid reporting same thing for bot the
    # 'testcase' entry and the 'summary' entry
    my ($self, $key, $count, $suppressErrMsg) = @_;
    my $changed = 0;    # hit something new or not

    if (!Scalar::Util::looks_like_number($count)) {
        lcovutil::report_format_error($lcovutil::ERROR_FORMAT, 'hit', $count,
                                      'line "' . $self->filename() . ":$key\"")
            unless $suppressErrMsg;
        $count = 0;
    } elsif ($count < 0) {
        lcovutil::report_format_error($lcovutil::ERROR_NEGATIVE,
                                      'hit',
                                      $count,
                                      'line ' . $self->filename() . ":$key\""
        ) unless $suppressErrMsg;
        $count = 0;
    } elsif (defined($lcovutil::excessive_count_threshold) &&
             $count > $lcovutil::excessive_count_threshold) {
        lcovutil::report_format_error($lcovutil::ERROR_EXCESSIVE_COUNT,
                                      'hit',
                                      $count,
                                      'line ' . $self->filename() . ":$key\""
        ) unless $suppressErrMsg;
    }
    my $data = $self->[HASH];
    if (!exists($data->{$key})) {
        $changed = 1;             # something new - whether we hit it or not
        $data->{$key} = $count;
        ++$self->[FOUND];                  # found
        ++$self->[HIT] if ($count > 0);    # hit
    } else {
        my $current = $data->{$key};
        if ($count > 0 &&
            $current == 0) {
            ++$self->[HIT];
            $changed = 1;
        }
        $data->{$key} = $count + $current;
    }
    return $changed;
}

sub value
{
    my $self = shift;
    my $key  = shift;

    my $data = $self->[HASH];
    if (!exists($data->{$key})) {
        return undef;
    }
    return $data->{$key};
}

sub remove
{
    my ($self, $key, $check_if_present) = @_;

    my $data = $self->[HASH];
    if (!defined($check_if_present) ||
        exists($data->{$key})) {

        die("$key not found")
            unless exists($data->{$key});
        --$self->[FOUND];    # found;
        --$self->[HIT]       # hit
            if ($data->{$key} > 0);

        delete $data->{$key};
        return 1;
    }

    return 0;
}

sub found
{
    my $self = shift;

    return $self->[FOUND];
}

sub hit
{
    my $self = shift;

    return $self->[HIT];
}

sub keylist
{
    my $self = shift;
    return keys(%{$self->[HASH]});
}

sub entries
{
    my $self = shift;
    return scalar(keys(%{$self->[HASH]}));
}

sub union
{
    my $self = shift;
    my $info = shift;

    my $changed = 0;
    foreach my $key ($info->keylist()) {
        if ($self->append($key, $info->value($key))) {
            $changed = 1;
        }
    }
    return $changed;
}

sub intersect
{
    my $self     = shift;
    my $you      = shift;
    my $changed  = 0;
    my $yourData = $you->[HASH];
    foreach my $key ($self->keylist()) {
        if (exists($yourData->{$key})) {
            # append your count to mine
            if ($self->append($key, $you->value($key))) {
                # returns true if appended count was not zero
                $changed = 1;
            }
        } else {
            $self->remove($key);
            $changed = 1;
        }
    }
    return $changed;
}

sub difference
{
    my $self     = shift;
    my $you      = shift;
    my $changed  = 0;
    my $yourData = $you->[HASH];
    foreach my $key ($self->keylist()) {
        if (exists($yourData->{$key})) {
            $self->remove($key);
            $changed = 1;
        }
    }
    return $changed;
}

#
# get_found_and_hit(hash)
#
# Return the count for entries (found) and entries with an execution count
# greater than zero (hit) in a hash (linenumber -> execution count) as
# a list (found, hit)
#
sub get_found_and_hit
{
    my $self = shift;
    return ($self->[FOUND], $self->[HIT]);
}

package BranchBlock;
# branch element:  index, taken/not-taken count, optional expression
# for baseline or current data, 'taken' is just a number (or '-')
# for differential data: 'taken' is an array [$taken, tla]

use constant {
              ID        => 0,
              TAKEN     => 1,
              EXPR      => 2,
              EXCEPTION => 3,
};

sub new
{
    my ($class, $id, $taken, $expr, $is_exception) = @_;
    # if branchID is not an expression - go back to legacy behaviour
    my $self = [$id, $taken,
                (defined($expr) && $expr eq $id) ? undef : $expr,
                defined($is_exception) && $is_exception ? 1 : 0
    ];
    bless $self, $class;
    my $c = $self->count();
    if (!Scalar::Util::looks_like_number($c)) {
        lcovutil::report_format_error($lcovutil::ERROR_FORMAT,
                                      'taken', $c, 'branch ' . $self->id());
        $self->[TAKEN] = 0;

    } elsif ($c < 0) {
        lcovutil::report_format_error($lcovutil::ERROR_NEGATIVE,
                                      'taken', $c, 'branch ' . $self->id());
        $self->[TAKEN] = 0;
    } elsif (defined($lcovutil::excessive_count_threshold) &&
             $c > $lcovutil::excessive_count_threshold) {
        lcovutil::report_format_error($lcovutil::ERROR_EXCESSIVE_COUNT,
                                      'taken', $c, 'branch ' . $self->id());
    }
    return $self;
}

sub isTaken
{
    my $self = shift;
    return $self->[TAKEN] ne '-';
}

sub id
{
    my $self = shift;
    return $self->[ID];
}

sub data
{
    my $self = shift;
    return $self->[TAKEN];
}

sub count
{
    my $self = shift;
    return $self->[TAKEN] eq '-' ? 0 : $self->[TAKEN];
}

sub expr
{
    my $self = shift;
    return $self->[EXPR];
}

sub exprString
{
    my $self = shift;
    my $e    = $self->[EXPR];
    return defined($e) ? $e : 'undef';
}

sub is_exception
{
    my $self = shift;
    return $self->[EXCEPTION];
}

sub merge
{
    # return 1 if something changed, 0 if nothing new covered or discovered
    my ($self, $that, $filename, $line) = @_;
    # should have called 'iscompatible' first
    die('attempt to merge incompatible expressions for id' .
        $self->id() . ', ' . $that->id() .
        ": '" . $self->exprString() . "' -> '" . $that->exprString() . "'")
        if ($self->exprString() ne $that->exprString());

    if ($self->is_exception() != $that->is_exception()) {
        my $loc = defined($filename) ? "\"$filename\":$line: " : '';
        lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                                  "${loc}mismatched exception tag for id " .
                                      $self->id() . ", " . $that->id() .
                                      ": '" . $self->is_exception() .
                                      "' -> '" . $that->is_exception() . "'");
        # set 'self' to 'not related to exception' - to give a consistent
        #  answer for the merge operation.  Otherwise, we pick whatever
        #  was seen first - which is unpredictable during threaded execution.
        $self->[EXCEPTION] = 0;
    }
    my $t = $that->[TAKEN];
    return 0 if $t eq '-';    # no new news

    my $count = $self->[TAKEN];
    my $changed;
    if ($count ne '-') {
        $count += $t;
        $changed = $count == 0 && $t != 0;
    } else {
        $count   = $t;
        $changed = $t != 0;
    }
    $self->[TAKEN] = $count;
    return $changed;
}

package BranchEntry;
# hash of blockID -> array of BranchBlock refs for each sequential branch ID

sub new
{
    my ($class, $line) = @_;
    my $self = [$line, {}];
    bless $self, $class;
    return $self;
}

sub line
{
    my $self = shift;
    return $self->[0];
}

sub hasBlock
{
    my ($self, $id) = @_;
    return exists($self->[1]->{$id});
}

sub removeBlock
{
    my ($self, $id, $branchData) = @_;
    $self->hasBlock($id) or die("unknown block $id");

    # remove list of branches and adjust counts
    $branchData->removeBranches($self->[1]->{$id});
    delete($self->[1]->{$id});
}

sub getBlock
{
    my ($self, $id) = @_;
    $self->hasBlock($id) or die("unknown block $id");
    return $self->[1]->{$id};
}

sub blocks
{
    my $self = shift;
    return keys %{$self->[1]};
}

sub addBlock
{
    my ($self, $blockId) = @_;

    !exists($self->[1]->{$blockId}) or die "duplicate block $blockId";
    my $blockData = [];
    $self->[1]->{$blockId} = $blockData;
    return $blockData;
}

sub totals
{
    my $self = shift;
    # return (found, hit) counts of coverpoints in this entry
    my $found = 0;
    my $hit   = 0;
    foreach my $blockId ($self->blocks()) {
        my $bdata = $self->getBlock($blockId);

        foreach my $br (@$bdata) {
            my $count = $br->count();
            ++$found;
            ++$hit if (0 != $count);
        }
    }
    return ($found, $hit);
}

package MCDC_Block;

# there may be more than one MCDC groups on a particular line -
#   we hold the groups in a hash, keyed by size (number of MCDC_expressions)
#   The particular group is a sorted list
use constant {
              LINE   => 0,
              GROUPS => 1,
};

sub new
{
    my ($class, $line) = @_;
    my $self = [$line, {}];

    return bless $self, $class;
}

sub insertExpr
{
    my ($self, $filename, $groupSize, $sense, $count, $idx, $expr) = @_;
    my $groups = $self->[GROUPS];
    my $group;
    if (exists($groups->{$groupSize})) {
        $group = $groups->{$groupSize};
    } else {
        $group = [];
        $groups->{$groupSize} = $group;
    }
    my $cond;
    if ($idx < scalar(@$group)) {
        $cond = $group->[$idx];
        if ($cond->expression() ne $expr) {
            lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                 "\"$filename\":" . $self->line() .
                     ": MC/DC group $groupSize expression $idx changed from '" .
                     $cond->expression() . "' to '$expr'");
        }
    } else {
        if ($idx != scalar(@$group)) {
            lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                "\"$filename\":" . '":' . $self->line() .
                    ": MC/DC group $groupSize: non-contiguous expression '$idx' found - should be '"
                    . scalar(@$group)
                    . "'.");
        }
        $cond = MCDC_Expression->new($self, $groupSize, $idx, $expr);
        push(@$group, $cond);
    }
    $cond->set($sense, $count);
}

sub line
{
    return $_[0]->[LINE];
}

sub totals
{
    my $self  = shift;
    my $found = 0;
    my $hit   = 0;
    while (my ($size, $group) = each(%{$self->groups()})) {
        foreach my $expr (@$group) {
            foreach my $sense (0, 1) {
                my $count = $expr->count($sense);
                if ('ARRAY' eq ref($count)) {
                    # differential number - report 'current'
                    next unless defined($count->[2]);    # not in current
                    $count = $count->[2];
                }
                ++$found;
                ++$hit if 0 != $count;
            }
        }
    }
    return ($found, $hit);
}

sub groups
{
    return $_[0]->[GROUPS];
}

sub num_groups
{
    return scalar(keys %{$_[0]->[GROUPS]});
}

sub expressions
{
    my ($self, $size) = @_;
    return exists($self->[GROUPS]->{$size}) ? $self->[GROUPS]->{$size} : undef;
}

sub expr
{
    my ($self, $groupSize, $idx) = @_;
    return $self->[GROUPS]->{$groupSize}->[$idx];
}

sub is_compatible
{
    my ($self, $you) = @_;

    my $yours  = $you->groups();
    my $groups = $self->groups();
    foreach my $size (keys %$groups) {
        next unless exists($yours->{$size});
        my $idx = 0;
        my $m   = $groups->{$size};
        my $y   = $yours->{$size};
        foreach my $e (@$m) {
            my $ye = $y->[$idx++];
            return 0 if $e->expression() ne $ye->expression();
        }
    }
    return 1;
}

sub merge
{
    # merge all groups from you into me
    my ($self, $you) = @_;

    my $mine    = $self->groups();
    my $yours   = $you->groups();
    my $changed = 0;
    while (my ($size, $group) = each(%$yours)) {
        if (exists($mine->{$size})) {
            my $m   = $mine->{$size};
            my $idx = 0;
            foreach my $e (@$m) {
                my $y = $group->[$idx++];
                $changed += $e->set(1, $y->count(1));
                $changed += $e->set(0, $y->count(0));
            }
        } else {
            $mine->{$size} = Storable::dclone($group);
            $changed = 1;
        }
    }
    return $changed;
}

package MCDC_Expression;

use constant {
              PARENT     => 0,    # MCDC_BLOCK
              GROUP_SIZE => 1,    # which group in parent
              INDEX      => 2,    # index of this expression

              EXPRESSION => 3,
              TRUE  => 4,  # hit count of sensitization of 'true' sense of expr
              FALSE => 5,  # hit count of sensitization of 'false' sense of expr
};

sub new
{
    my ($class, $parent, $groupSize, $idx, $expr) = @_;

    my $self = [$parent, $groupSize, $idx, $expr, 0, 0];
    return bless $self, $class;
}

sub set
{
    # 'sense' should be 0 or 1 - for 'false' and 'true' sense, respectively
    my ($self, $sense, $count) = @_;
    return 0 if 0 == $count;

    if ('ARRAY' eq ref($count)) {
        # recording a differential result
        $self->[$sense ? TRUE : FALSE] = $count;
        return 1;    # assumed changed
    }
    my $changed = $count && $self->count($sense) == 0;
    $self->[$sense ? TRUE : FALSE] += $count;
    return $changed;
}

sub parent
{
    return $_[0]->[PARENT];
}

sub groupSize
{
    return $_[0]->[GROUP_SIZE];
}

sub index
{
    return $_[0]->[INDEX];
}

sub expression
{
    return $_[0]->[EXPRESSION];
}

sub count
{
    my ($self, $sense) = @_;
    return $_[0]->[$sense ? TRUE : FALSE];
}

package FunctionEntry;
# keep track of all the functions/all the function aliases
#  at a particular line in the file.  THey must all be the
#  same function - perhaps just templatized differently.

use constant {
              NAME    => 0,
              ALIASES => 1,
              MAP     => 2,
              FIRST   => 3,    # start line
              COUNT   => 4,
              LAST    => 5,
};

sub new
{
    my ($class, $name, $map, $startLine, $endLine) = @_;
    die("unexpected type " . ref($map)) unless 'FunctionMap' eq ref($map);
    my %aliases = ($name => 0);    # not hit, yet
    my $self    = [$name, \%aliases, $map, $startLine, 0, $endLine];

    bless $self, $class;
    return $self;
}

sub cloneWithEndLine
{
    my ($self, $withEnd, $cloneAliases) = @_;
    my $fn = FunctionEntry->new($self->[NAME], $self->[MAP], $self->[FIRST],
                                $withEnd ? $self->[LAST] : undef);
    if ($cloneAliases) {
        my $count = 0;
        while (my ($alias, $hit) = each(%{$self->aliases()})) {
            $fn->[ALIASES]->{$alias} = $hit;
            $count += $hit;
        }
        $fn->[COUNT] = $count;
    }
    return $fn;
}

sub name
{
    my $self = shift;
    return $self->[NAME];
}

sub filename
{
    my $self = shift;
    return $self->[MAP]->filename();
}

sub hit
{
    # this is the hit count across all the aliases of the function
    my $self = shift;
    return $self->[COUNT];
}

sub isLambda
{
    my $self = shift;
    # jacoco may show both a lambda and a function on the same line - which
    # lcov then associates as an alias
    # alias name selection above ensures that the 'master' name is lambda
    # only if every alias is a lambda.
    # -> this is a lambda only if there is only one alias
    return ((TraceFile::is_language('c', $self->filename()) &&
                 $self->name() =~ /{lambda\(/) ||
                (TraceFile::is_language('java', $self->filename()) &&
                 $self->name() =~ /\.lambda\$/));
}

sub count
{
    my ($self, $alias, $merged) = @_;

    exists($self->aliases()->{$alias}) or
        die("$alias is not an alias of " . $self->name());

    return $self->[COUNT]
        if (defined($merged) && $merged);

    return $self->aliases()->{$alias};
}

sub aliases
{
    my $self = shift;
    return $self->[ALIASES];
}

sub numAliases
{
    my $self = shift;
    return scalar(keys %{$self->[ALIASES]});
}

sub file
{
    my $self = shift;
    return $self->[MAP]->filename();
}

sub line
{
    my $self = shift;
    return $self->[FIRST];
}

sub set_line
{
    my ($self, $line) = @_;
    return $self->[FIRST] = $line;
}

sub end_line
{
    my $self = shift;
    return $self->[LAST];
}

sub set_end_line
{
    my ($self, $line) = @_;
    if ($line < $self->line()) {
        my $suffix =
            lcovutil::explain_once('derive_end_line',
                      "  See lcovrc man entry for 'derive_function_end_line'.");
        lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                                '"' . $self->file() . '":' . $self->line() .
                                    ': function ' . $self->name() .
                                    " end line $line less than start line " .
                                    $self->line() .
                                    ".  Cannot derive function end line.$suffix"
        );
        return;
    }
    $self->[LAST] = $line;
}

sub _format_error
{
    my ($self, $errno, $name, $count) = @_;
    my $alias =
        $name ne $self->name() ? " (alias of '" . $self->name() . "'" : "";
    lcovutil::report_format_error($errno, 'hit', $count,
            "function '$name'$alias in " . $self->file() . ':' . $self->line());
}

sub addAlias
{
    my ($self, $name, $count) = @_;

    if (!Scalar::Util::looks_like_number($count)) {
        $self->_format_error($lcovutil::ERROR_FORMAT, $name, $count);
        $count = 0;
    } elsif ($count < 0) {
        $self->_format_error($lcovutil::ERROR_NEGATIVE, $name, $count);
        $count = 0;
    } elsif (defined($lcovutil::excessive_count_threshold) &&
             $count > $lcovutil::excessive_count_threshold) {
        $self->_format_error($lcovutil::ERROR_EXCESSIVE_COUNT, $name, $count)
            unless grep({ $name =~ $_ || $self->name() =~ $_ }
                        @lcovutil::suppress_function_patterns);
    }
    my $changed;
    my $aliases = $self->[ALIASES];
    if (exists($aliases->{$name})) {
        $changed = 0 == $aliases->{$name} && 0 != $count;
        $aliases->{$name} += $count;
    } else {
        $aliases->{$name} = $count;
        $changed = 1;
        # keep track of the shortest name as the function representative
        my $curlen = length($self->[NAME]);
        my $len    = length($name);
        # penalize lambda functions so that their name is not chosen
        #  (java workaround or ugly hack, depending on your perspective)
        $curlen += 1000 if $self->[NAME] =~ /(\{lambda\(|\.lambda\$)/;
        $len    += 1000 if $name         =~ /(\{lambda\(|\.lambda\$)/;
        $self->[NAME] = $name
            if ($len < $curlen ||    # alias is shorter
                ($len == $curlen &&   # alias is same length but lexically first
                 $name lt $self->[NAME]));
    }
    $self->[COUNT] += $count;
    # perhaps should remove lambda aliases, if they exist -
    #   - Issue is that jacoco will show normal function and lambda on the
    #     same line - which lcov takes to mean that they are aliases
    # could just delete the lambda in that case..pretend it doesn't exist.
    return $changed;
}

sub merge
{
    my ($self, $that) = @_;
    lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                              $self->name() . " has different location than " .
                                  $that->name() . " during merge")
        if ($self->line() != $self->line());
    while (my ($name, $count) = each(%{$that->[ALIASES]})) {
        $self->addAlias($name, $count);
    }
}

sub removeAliases
{
    my $self    = shift;
    my $aliases = $self->[ALIASES];
    my $rename  = 0;
    foreach my $name (@_) {
        exists($aliases->{$name}) or die("removing non-existent alias $name");

        my $count = $aliases->{$name};
        delete($aliases->{$name});
        $self->[COUNT] -= $count;
        if ($self->[NAME] eq $name) {
            $rename = 1;
        }
    }
    if ($rename &&
        %$aliases) {
        my $name;
        foreach my $alias (keys %$aliases) {
            $name = $alias if !defined($name) || length($alias) < length($name);
        }
        $self->[NAME] = $name;
    }
    return %$aliases;    # true if this function still exists
}

sub addAliasDifferential
{
    my ($self, $name, $data) = @_;
    die("alias $name exists")
        if exists($self->[ALIASES]->{$name}) && $name ne $self->name();
    die("expected array")
        unless ref($data) eq "ARRAY" && 2 == scalar(@$data);
    $self->[ALIASES]->{$name} = $data;
}

sub setCountDifferential
{
    my ($self, $data) = @_;
    die("expected array")
        unless ref($data) eq "ARRAY" && 2 == scalar(@$data);
    $self->[COUNT] = $data;
}

sub findMyLines
{
    # use my start/end location to find my list of line coverpoints within
    # this function.
    # return sorted list of [ [lineNo, hitCount], ...]
    my ($self, $lineData) = @_;
    return undef unless $self->end_line();
    my @lines;
    for (my $lineNo = $self->line(); $lineNo <= $self->end_line(); ++$lineNo) {
        my $hit = $lineData->value($lineNo);
        push(@lines, [$lineNo, $hit])
            if (defined($hit));
    }
    return \@lines;
}

sub _findConditionals
{
    my ($self, $data) = @_;
    return undef unless $self->end_line();
    my @list;
    for (my $lineNo = $self->line(); $lineNo <= $self->end_line(); ++$lineNo) {
        my $entry = $data->value($lineNo);
        push(@list, $entry)
            if (defined($entry));
    }
    return \@list;
}

sub findMyBranches
{
    # use my start/end location to list of branch entries within this function
    # return sorted list [ branchEntry, ..] sorted by line
    my ($self, $branchData) = @_;
    die("expected BranchData") unless ref($branchData) eq "BranchData";
    return $self->_findConditionals($branchData);
}

sub findMyMcdc
{
    # use my start/end location to list of MC/DC entries within this function
    # return list [ MCDC_Block, ..] sorted by line
    my ($self, $mcdcData) = @_;
    die("expected MCDC_Data") unless ref($mcdcData) eq "MCDC_Data";
    return $self->_findConditionals($mcdcData);
}

package FunctionMap;

sub new($$)
{
    my ($class, $filename) = @_;
    my $self = [{}, {}, $filename];    # [locationMap, nameMap]
    bless $self, $class;
}

sub filename
{
    my $self = shift;
    return $self->[2];
}

sub keylist
{
    # return list of file:lineNo keys..
    my $self = shift;
    return keys(%{$self->[0]});
}

sub valuelist
{
    # return list of FunctionEntry elements we know about
    my $self = shift;
    return values(%{$self->[0]});
}

sub list_functions
{
    # return list of all the functions/function aliases that we know about
    my $self = shift;
    return keys(%{$self->[1]});
}

sub define_function
{
    my ($self, $fnName, $start_line, $end_line, $location) = @_;
    #lcovutil::info("define: $fnName " . $self->$filename() . ":$start_line->$end_line\n");
    # could check that function ranges within file are non-overlapping
    my ($locationMap, $nameMap) = @$self;

    my $data = $self->findName($fnName);
    if (defined($data) &&
        #TraceFile::is_language('c', $self->filename()) &&
        $data->line() != $start_line
    ) {
        $location = '"' . $self->filename() . '":' . $start_line
            unless defined($location);
        lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                   "$location: duplicate function '$fnName' starts on line \"" .
                       $data->filename() .
                       "\":$start_line but previous definition started on " .
                       $data->line() . MessageContext::context() . '.')
            unless
            grep({ $fnName =~ $_ } @lcovutil::suppress_function_patterns);
        # if ignored, just return the function we already have -
        # record the function location as the smallest line number we saw
        if ($start_line < $data->line()) {
            delete $self->[0]->{$data->line()};
            $data->set_line($start_line);
            $self->[0]->{$start_line} = $data;
        }
        return $data;
    }

    if (exists($locationMap->{$start_line})) {
        $data = $locationMap->{$start_line};
        unless ((defined($end_line) &&
                 defined($data->end_line()) &&
                 $end_line == $data->end_line()) ||
                (!defined($end_line) && !defined($data->end_line()))
        ) {
            lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                                      "mismatched end line for $fnName at " .
                                          $self->filename() . ":$start_line: "
                                          .
                                          (defined($data->end_line()) ?
                                               $data->end_line() : 'undef') .
                                          " -> "
                                          .
                                          (defined($end_line) ? $end_line :
                                               'undef') .
                                          MessageContext::context())
                unless
                grep({ $fnName =~ $_ } @lcovutil::suppress_function_patterns);
            # pick the highest end line if we didn't error out
            $data->set_end_line($end_line)
                if (defined($end_line) &&
                    (!defined($data->end_line()) ||
                     $end_line > $data->end_line()));
        }
    } else {
        $data = FunctionEntry->new($fnName, $self, $start_line, $end_line);
        $locationMap->{$start_line} = $data;
    }
    if (!exists($nameMap->{$fnName})) {
        $nameMap->{$fnName} = $data;
        $data->addAlias($fnName, 0);
    }
    return $data;
}

sub findName
{
    my ($self, $name) = @_;
    my $nameMap = $self->[1];
    return exists($nameMap->{$name}) ? $nameMap->{$name} : undef;
}

sub findKey
{
    my ($self, $key) = @_;    # key is the start line of the function
    my $locationMap = $self->[0];
    return exists($locationMap->{$key}) ? $locationMap->{$key} : undef;
}

sub numFunc
{
    my ($self, $merged) = @_;

    if (defined($merged) && $merged) {
        return scalar($self->keylist());
    }
    my $n = 0;
    foreach my $key ($self->keylist()) {
        my $data = $self->findKey($key);
        $n += $data->numAliases();
    }
    return $n;
}

sub numHit
{
    my ($self, $merged) = @_;

    my $n = 0;
    foreach my $key ($self->keylist()) {
        my $data = $self->findKey($key);
        if (defined($merged) && $merged) {
            ++$n
                if $data->hit() > 0;
        } else {
            my $aliases = $data->aliases();
            foreach my $alias (keys(%$aliases)) {
                my $c = $aliases->{$alias};
                ++$n if $c > 0;
            }
        }
    }
    return $n;
}

sub get_found_and_hit
{
    my $self = shift;
    my $merged =
        defined($lcovutil::cov_filter[$lcovutil::FILTER_FUNCTION_ALIAS]);
    return ($self->numFunc($merged), $self->numHit($merged));
}

sub add_count
{
    my ($self, $fnName, $count) = @_;
    my $nameMap = $self->[1];
    if (exists($nameMap->{$fnName})) {
        my $data = $nameMap->{$fnName};
        $data->addAlias($fnName, $count);
    } else {
        lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                                  "unknown function '$fnName'");
    }
}

sub union
{
    my ($self, $that) = @_;

    my $changed  = 0;
    my $myData   = $self->[0];
    my $yourData = $that->[0];
    while (my ($key, $thatData) = each(%$yourData)) {
        my $thisData;
        if (!exists($myData->{$key})) {
            $thisData =
                $self->define_function($thatData->name(),
                                      $thatData->line(), $thatData->end_line());
            $changed = 1;    # something new...
        } else {
            $thisData = $myData->{$key};
            if (!($thisData->line() == $thatData->line()
                  && ($thisData->file() eq $thatData->file() ||
                      ($lcovutil::case_insensitive &&
                        lc($thisData->file()) eq lc($thatData->file())))
            )) {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                               "function data mismatch at " .
                                   $thatData->file() . ":" . $thatData->line());
                next;
            }
        }
        # merge in all the new aliases
        while (my ($alias, $count) = each(%{$thatData->aliases()})) {
            if ($thisData->addAlias($alias, $count)) {
                $changed = 1;
            }
        }
    }
    return $changed;
}

sub intersect
{
    my ($self, $that) = @_;

    my $changed   = 0;
    my $myData    = $self->[0];
    my $myNames   = $self->[1];
    my $yourData  = $that->[0];
    my $yourNames = $that->[1];
    foreach my $key (keys %$myData) {
        my $me = $myData->{$key};
        if (exists($yourData->{$key})) {
            my $yourFn = $yourData->{$key};
            # intersect operation:  keep only the common aliases
            my @remove;
            my $yourAliases = $yourFn->aliases();
            while (my ($alias, $count) = each(%{$me->aliases()})) {
                if (exists($yourAliases->{$alias})) {
                    if ($me->addAlias($alias, $yourAliases->{$alias})) {
                        $changed = 1;
                    }
                } else {
                    # remove this alias from me..
                    push(@remove, $alias);
                    delete($myNames->{$alias});
                    $changed = 1;
                }
            }
            if (!$me->removeAliases(@remove)) {
                # no aliases left (no common aliases) - so remove this function
                delete($myData->{$key});
            }
        } else {
            $self->remove($me);
            $changed = 1;
        }
    }
    return $changed;
}

sub difference
{
    my ($self, $that) = @_;

    my $changed  = 0;
    my $myData   = $self->[0];
    my $yourData = $that->[0];
    foreach my $key (keys %$myData) {
        if (exists($yourData->{$key})) {
            # just remove the common aliases...
            my $me  = $myData->{$key};
            my $you = $yourData->{$key};
            my @remove;
            while (my ($alias, $count) = each(%{$you->aliases()})) {
                if (exists($me->aliases()->{$alias})) {
                    push(@remove, $alias);
                    $changed = 1;
                }
            }
            if (!$me->removeAliases(@remove)) {
                # no aliases left (no disjoint aliases) - so remove this function
                delete($myData->{$key});
            }
        }
    }
    return $changed;
}

sub remove
{
    my ($self, $entry) = @_;
    die("expected FunctionEntry - " . ref($entry))
        unless 'FunctionEntry' eq ref($entry);
    my ($locationMap, $nameMap) = @$self;
    my $key = $entry->line();
    foreach my $alias (keys %{$entry->aliases()}) {
        delete($nameMap->{$alias});
    }
    delete($locationMap->{$key});
}

package BranchMap;

use constant {
              DATA  => 0,
              FOUND => 1,
              HIT   => 2,
};

sub new
{
    my $class = shift;
    my $self = [{},    #  hash of lineNo -> BranchEntry/MCDC_Element
                       #   BranchEntry:
                       #      hash of blockID ->
                       #         array of 'taken' entries for each sequential
                       #           branch ID
                       #  MCDC_Element:
                0,     # branches found
                0,     # branches executed
    ];
    return bless $self, $class;
}

sub remove
{
    my ($self, $line, $check_if_present) = @_;
    my $data = $self->[DATA];

    return 0 if ($check_if_present && !exists($data->{$line}));

    my $branch = $data->{$line};
    my ($f, $h) = $branch->totals();
    $self->[FOUND] -= $f;
    $self->[HIT]   -= $h;

    delete($data->{$line});
    return 1;
}

sub found
{
    my $self = shift;

    return $self->[FOUND];
}

sub hit
{
    my $self = shift;

    return $self->[HIT];
}

# return BranchEntry struct (or undef)
sub value
{
    my ($self, $lineNo) = @_;

    my $map = $self->[DATA];
    return exists($map->{$lineNo}) ? $map->{$lineNo} : undef;
}

# return list of lines which contain branch data
sub keylist
{
    my $self = shift;
    return keys(%{$self->[DATA]});
}

sub get_found_and_hit
{
    my $self = shift;

    return ($self->[FOUND], $self->[HIT]);
}

package BranchData;

use base 'BranchMap';

sub new
{
    my $class = shift;
    my $self  = $class->SUPER::new();
    return $self;
}

sub append
{
    my ($self, $line, $block, $br, $filename) = @_;
    # HGC:  might be good idea to pass filename so we could give better
    #   error message if the data is inconsistent.
    # OTOH:  unclear what a normal user could do about it anyway.
    #   Maybe exclude that file?
    my $data = $self->[BranchMap::DATA];
    $filename = '<stdin>' if (defined($filename) && $filename eq '-');
    if (!defined($br)) {
        lcovutil::ignorable_error($lcovutil::ERROR_BRANCH,
                            (defined $filename ? "\"$filename\":$line: " : "")
                                . "expected 'BranchEntry' or 'integer, BranchBlock'"
        ) unless ('BranchEntry' eq ref($block));

        die("line $line already contains element")
            if exists($data->{$line});
        # this gets called from 'apply_diff' method:  the new line number
        # which was assigned might be different than the original - so we
        # have to fix up the branch entry.
        $block->[0] = $line;
        my ($f, $h) = $block->totals();
        $self->[BranchMap::FOUND] += $f;
        $self->[BranchMap::HIT]   += $h;
        $data->{$line} = $block;
        return 1;    # we added something
    }

    # this cannot happen unless inconsistent branch data was generated by gcov
    die((defined $filename ? "\"$filename\":$line: " : "") .
        "BranchData::append expected BranchBlock got '" .
        ref($br) .
        "'.\nThis may be due to mismatched 'gcc' and 'gcov' versions.\n")
        unless ('BranchBlock' eq ref($br));

    my $branch = $br->id();
    my $branchElem;
    my $changed = 0;
    if (exists($data->{$line})) {
        $branchElem = $data->{$line};
        $line == $branchElem->line() or die("wrong line mapping");
    } else {
        $branchElem    = BranchEntry->new($line);
        $data->{$line} = $branchElem;
        $changed       = 1;                         # something new
    }

    if (!$branchElem->hasBlock($block)) {
        $branch == 0
            or
            lcovutil::ignorable_error($lcovutil::ERROR_BRANCH,
                                      "unexpected non-zero initial branch");
        $branch = 0;
        my $l = $branchElem->addBlock($block);
        push(@$l,
             BranchBlock->new($branch, $br->data(),
                              $br->expr(), $br->is_exception()));
        ++$self->[BranchMap::FOUND];                       # found one
        ++$self->[BranchMap::HIT] if 0 != $br->count();    # hit one
        $changed = 1;                                      # something new..
    } else {
        $block = $branchElem->getBlock($block);

        if ($branch > scalar(@$block)) {
            lcovutil::ignorable_error($lcovutil::ERROR_BRANCH,
                (defined $filename ? "\"$filename\":$line: " : "") .
                    "unexpected non-sequential branch ID $branch for block $block"
                    . (defined($filename) ? "" : " of line $line: ")
                    . ": found " .
                    scalar(@$block) . " blocks");
            $branch = scalar(@$block);
        }

        if (!exists($block->[$branch])) {
            $block->[$branch] =
                BranchBlock->new($branch, $br->data(), $br->expr(),
                                 $br->is_exception());
            ++$self->[BranchMap::FOUND];                       # found one
            ++$self->[BranchMap::HIT] if 0 != $br->count();    # hit one

            $changed = 1;
        } else {
            my $me = $block->[$branch];
            if (0 == $me->count() && 0 != $br->count()) {
                ++$self->[BranchMap::HIT];                     # hit one
                $changed = 1;
            }
            if ($me->merge($br, $filename, $line)) {
                $changed = 1;
            }
        }
    }
    return $changed;
}

sub removeBranches
{
    my ($self, $branchList) = @_;

    foreach my $b (@$branchList) {
        --$self->[BranchMap::FOUND];
        --$self->[BranchMap::HIT] if 0 != $b->count();
    }
}

sub _checkCounts
{
    # some consistency checking
    my $self = shift;

    my $data  = $self->[BranchMap::DATA];
    my $found = 0;
    my $hit   = 0;

    while (my ($line, $branch) = each(%$data)) {
        $line == $branch->line() or die("lost track of line");
        my ($f, $h) = $branch->totals();
        $found += $f;
        $hit   += $h;
    }
    die("invalid counts: found:" . $self->[BranchMap::FOUND] .
        "->$found, hit:" . $self->[BranchMap::HIT] . "->$hit")
        unless ($self->[BranchMap::FOUND] == $found &&
                $self->[BranchMap::HIT] == $hit);
}

sub compatible($$)
{
    my ($myBr, $yourBr) = @_;

    # same number of branches
    return 0 unless ($#$myBr == $#$yourBr);
    for (my $i = 0; $i <= $#$myBr; ++$i) {
        my $me  = $myBr->[$i];
        my $you = $yourBr->[$i];
        if ($me->exprString() ne $you->exprString()) {
            # this one doesn't match
            return 0;
        }
    }
    return 1;
}

sub union
{
    my ($self, $info, $filename) = @_;
    my $changed = 0;

    my $mydata = $self->[BranchMap::DATA];
    while (my ($line, $yourBranch) = each(%{$info->[BranchMap::DATA]})) {
        # check if self has corresponding line:
        #  no: just copy all the data for this line, from 'info'
        #  yes: check for matching blocks
        my $myBranch = $self->value($line);
        if (!defined($myBranch)) {
            $mydata->{$line} = Storable::dclone($yourBranch);
            my ($f, $h) = $yourBranch->totals();
            $self->[BranchMap::FOUND] += $f;
            $self->[BranchMap::HIT]   += $h;
            $changed = 1;
            next;
        }
        # keep track of which 'myBranch' blocks have already been merged in
        #  this pass.  We don't want to merge multiple distinct blocks from $info
        #  into the same $self block (even if it appears compatible) - because
        #  those blocks were distinct in the input data
        my %merged;

        # we don't expect there to be a huge number of distinct blocks
        #  in each branch:  most often, just one -
        # Thus, we simply walk the list to find a matching block, if one exists
        # The matching block will have the same number of branches, and the
        #  branch expressions will be the same.
        #    - expression only used in Verilog code at the moment -
        #      other languages will just have a (matching) integer
        #      branch index

        # first:  merge your blocks which seem to exist in me:
        my @yourBlocks = sort($yourBranch->blocks());
        foreach my $yourId (@yourBlocks) {
            my $yourBr = $yourBranch->getBlock($yourId);

            # Do I have a block with matching name, which is compatible?
            my $myBr = $myBranch->getBlock($yourId)
                if $myBranch->hasBlock($yourId);
            if (defined($myBr) &&    # I have this one
                compatible($myBr, $yourBr)
            ) {
                foreach my $br (@$yourBr) {
                    if ($self->append($line, $yourId, $br, $filename)) {
                        $changed = 1;
                    }
                }
                $merged{$yourId} = 1;
                $yourId = undef;
            }
        }
        # now look for compatible blocks that aren't identical
        BLOCK: foreach my $yourId (@yourBlocks) {
            next unless defined($yourId);
            my $yourBr = $yourBranch->getBlock($yourId);

            # See if we can find a compatible block in $self
            #   if found: merge.
            #   no match:  this is a different block - assign new ID

            foreach my $myId ($myBranch->blocks()) {
                next if exists($merged{$myId});

                my $myBr = $myBranch->getBlock($myId);
                if (compatible($myBr, $yourBr)) {
                    # we match - so merge our data
                    $merged{$myId} = 1;    # used this one
                    foreach my $br (@$yourBr) {
                        if ($self->append($line, $myId, $br, $filename)) {
                            $changed = 1;
                        }
                    }
                    next BLOCK;            # merged this one - go to next
                }
            }    # end search for your block in my blocklist
                 # we didn't find a match - so this needs to be a new block
            my $newID = scalar($myBranch->blocks());
            $merged{$newID} = 1;    # used this one
            foreach my $br (@$yourBr) {
                if ($self->append($line, $newID, $br, $filename)) {
                    $changed = 1;
                }
            }
        }
    }
    if ($lcovutil::debug) {
        $self->_checkCounts();    # some paranoia
    }
    return $changed;
}

sub intersect
{
    my ($self, $info, $filename) = @_;
    my $changed = 0;

    my $mydata   = $self->[BranchMap::DATA];
    my $yourdata = $info->[BranchMap::DATA];
    foreach my $line (keys %$mydata) {
        if (exists($yourdata->{$line})) {
            # look at all my blocks.  If you have a compatible block, merge them
            #   - else delete mine
            my $myBranch   = $mydata->{$line};
            my $yourBranch = $yourdata->{$line};
            my @myBlocks   = $myBranch->blocks();
            foreach my $myId (@myBlocks) {
                my $myBr = $myBranch->getBlock($myId);

                # Do you have a block with matching name, which is compatible?
                my $yourBlock = $yourBranch->getBlock($myId)
                    if $yourBranch->hasBlock($myId);
                if (defined($yourBlock) &&    # you have this one
                    compatible($myBr, $yourBlock)
                ) {
                    foreach my $br (@$yourBlock) {
                        if ($self->append($line, $myId, $br, $filename)) {
                            $changed = 1;
                        }
                    }
                } else {
                    # block not found...remove this one
                    $myBranch->removeBlock($myId, $self);
                    $changed = 1;
                }
            }    # foreach block
        } else {
            # my line not found in your data - so remove this one
            $changed = 1;
            $self->remove($line);
        }
    }
    return $changed;
}

sub difference
{
    my ($self, $info, $filename) = @_;
    my $changed = 0;

    my $mydata   = $self->[BranchMap::DATA];
    my $yourdata = $info->[BranchMap::DATA];
    foreach my $line (keys %$mydata) {
        # keep everything here if you don't have this line
        next unless exists($yourdata->{$line});

        #  look at all my blocks.  If you have a compatible block, remove it:
        my $myBranch   = $mydata->{$line};
        my $yourBranch = $yourdata->{$line};
        my @myBlocks   = $myBranch->blocks();
        foreach my $myId (@myBlocks) {
            my $myBr = $myBranch->getBlock($myId);

            # Do you have a block with matching name, which is compatible?
            my $yourBlock = $yourBranch->getBlock($myId)
                if $yourBranch->hasBlock($myId);
            if (defined($yourBlock) &&    # you have this one
                compatible($myBr, $yourBlock)
            ) {
                # remove common block
                $myBranch->removeBlock($myId, $self);
                $changed = 1;
            }
        }    # foreach block
    }
    return $changed;
}

package MCDC_Data;

use base 'BranchMap';

sub new
{
    my $class = shift;
    my $self  = $class->SUPER::new();
    return $self;
}

sub append_mcdc
{
    my ($self, $mcdc) = @_;
    my $line = $mcdc->line();
    die("MCDC already defined for $line")
        if exists($self->[BranchMap::DATA]->{$line});
    $self->[BranchMap::DATA]->{$line} = $mcdc;
}

sub new_mcdc
{
    my ($self, $fileData, $line) = @_;

    return $self->[BranchMap::DATA]->{$line}
        if exists($self->[BranchMap::DATA]->{$line});

    my $mcdc = MCDC_Block->new($line);
    $self->[BranchMap::DATA]->{$line} = $mcdc;
    return $mcdc;
}

sub close_mcdcBlock
{
    my ($self, $mcdc) = @_;
    my $found = 0;
    my $hit   = 0;
    while (my ($groupSize, $exprs) = each(%{$mcdc->groups()})) {
        foreach my $e (@$exprs) {
            $found += 2;
            ++$hit if $e->count(0);
            ++$hit if $e->count(1);
        }
    }
    $self->[BranchMap::FOUND] += $found;
    $self->[BranchMap::HIT]   += $hit;
}

sub _calculate_counts
{
    my $self  = shift;
    my $found = 0;
    my $hit   = 0;
    while (my ($line, $block) = each(%{$self->[BranchMap::DATA]})) {
        my ($f, $h) = $block->totals();
        $found += $f;
        $hit   += $h;
    }
    $self->[BranchMap::FOUND] = $found;
    $self->[BranchMap::HIT]   = $hit;
}

sub union
{
    my ($self, $info) = @_;
    my $changed = 0;

    my $mydata = $self->[BranchMap::DATA];
    while (my ($line, $yourBranch) = each(%{$info->[BranchMap::DATA]})) {
        # check if self has corresponding line:
        #  no: just copy all the data for this line, from 'info'
        #  yes: check for matching blocks
        my $myBranch = $self->value($line);
        if (!defined($myBranch)) {
            my $c = Storable::dclone($yourBranch);
            $mydata->{$line} = $c;
            $self->close_mcdcBlock($c);
            $changed = 1;
            next;
        }

        # check if we are compatible.
        if ($myBranch->is_compatible($yourBranch)) {
            $changed += $myBranch->merge($yourBranch);
        } else {
            lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                                      "cannot merge iconsistent MC/DC record");
            # possibly remove this record?
        }
    }
    $self->_calculate_counts();
    return $changed;
}

sub intersect
{
    my ($self, $info, $filename) = @_;
    my $changed = 0;

    my $yourData = $info->[BranchMap::DATA];
    my $mydata   = $self->[BranchMap::DATA];
    foreach my $line (keys %$mydata) {
        if (exists($yourData->{$line})) {
            # append your count to mine
            my $yourBranch = $yourData->{$line};
            my $myBranch   = $mydata->{$line};

            if ($myBranch->is_compatible($yourBranch)) {
                $changed += $myBranch->merge($yourBranch);
            } else {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                                       "cannot merge iconsistent MC/DC record");
                # possibly remove this record?
            }
        } else {
            $self->remove($line);
            $changed = 1;
        }
    }
    $self->_calculate_counts();
    return $changed;
}

sub difference
{
    my ($self, $info, $filename) = @_;
    my $changed = 0;

    my $yourData = $info->[BranchMap::DATA];
    my $mydata   = $self->[BranchMap::DATA];
    foreach my $line (keys %$mydata) {
        if (exists($yourData->{$line})) {
            $self->remove($line);
            $changed = 1;
        }
    }
    $self->_calculate_counts();
    return $changed;
}

package FilterBranchExceptions;

use constant {
              EXCEPTION_f => 0,
              ORPHAN_f    => 1,
              REGION_f    => 2,
              BRANCH_f    => 3    # branch filter
};

sub new
{
    my $class = shift;
    my $self = [$lcovutil::cov_filter[$lcovutil::FILTER_EXCEPTION_BRANCH],
                $lcovutil::cov_filter[$lcovutil::FILTER_ORPHAN_BRANCH],
                $lcovutil::cov_filter[$lcovutil::FILTER_EXCLUDE_REGION],
                $lcovutil::cov_filter[$lcovutil::FILTER_EXCLUDE_BRANCH]
    ];
    bless $self, $class;
    return grep({ defined($_) } @$self) ? $self : undef;
}

sub removeBranches
{
    my ($self, $line, $branches, $filter, $unreachable, $isMasterData) = @_;

    my $brdata = $branches->value($line);
    return 0 unless defined($brdata);
    # 'unreachable' and 'excluded' branches have already been removed
    #   by 'region' filter along with their parent line - so no need to
    #   do anything here
    die("unexpected unreachable branch")
        if ($unreachable && 0 != $brdata->count());
    my $modified = 0;
    my $count    = 0;
    foreach my $block_id ($brdata->blocks()) {
        my $blockData = $brdata->getBlock($block_id);
        my @replace;
        foreach my $br (@$blockData) {
            if (defined($filter) && $br->is_exception()) {
                --$branches->[BranchMap::FOUND];
                --$branches->[BranchMap::HIT] if 0 != $br->count();
                #lcovutil::info($srcReader->fileanme() . ": $line: remove exception branch\n");
                $modified = 1;
                ++$count;
            } else {
                push(@replace, $br);
            }
        }
        if ($count) {
            @$blockData = @replace;
            ++$filter->[-2] if $isMasterData;
            lcovutil::info(2,
                           "$line: remove $count exception branch" .
                               (1 == $count ? '' : 'es') . "\n")
                if $isMasterData;
            $filter->[-1] += $count;
        }
        # If there is only one branch left - then this is not a conditional
        if (0 == scalar(@replace)) {
            lcovutil::info(2, "$line: remove exception block $block_id\n");
            lcovutil::info("$line: remove exception block $block_id\n");
            $brdata->removeBlock($block_id, $branches);
        } elsif (1 == scalar(@replace) &&
                 defined($self->[ORPHAN_f])) {    # filter orphan
            lcovutil::info(2,
                           "$line: remove orphan exception block $block_id\n");
            $brdata->removeBlock($block_id, $branches);

            ++$self->[ORPHAN_f]->[-2]
                if $isMasterData;
            ++$self->[ORPHAN_f]->[-1];
        }
    }
    if (0 == scalar($brdata->blocks())) {
        lcovutil::info(2, "$line: no branches remain\n");
        $branches->remove($line);
        $modified = 1;
    }
    return $modified;
}

sub applyFilter
{
    my ($self, $filter, $line, $branches, $perTestBranches, $unreachable) = @_;
    my $modified =
        $self->removeBranches($line, $branches, $filter, $unreachable, 1);
    foreach my $tn ($perTestBranches->keylist()) {
        # want to remove matching branches everytwhere - so we don't want short-circuit evaluation
        my $m = $self->removeBranches($line, $perTestBranches->value($tn),
                                      $filter, $unreachable, 0);
        $modified ||= $m;
    }
    return $modified;
}

sub filter
{
    my ($self, $line, $srcReader, $branches, $perTestBranches) = @_;

    my $reason;
    if (0 != ($reason = $srcReader->isExcluded($line, $srcReader->e_EXCEPTION)))
    {
        # exception branch excluded..
        if (defined($self->[REGION_f])) {    # exclude region
                # don't filter out if this line is "unreachable" and
                #  some branch here is hit
            return
                $self->applyFilter($self->[REGION_f],
                                   $line,
                                   $branches,
                                   $perTestBranches,
                                   0 != ($reason & $srcReader->e_UNREACHABLE));
        } elsif (defined($self->[BRANCH_f])) {    # exclude branches
                # filter out bogus branches - even if this region is unreachable
            return
                $self->applyFilter($self->[BRANCH_f], $line, $branches,
                                   $perTestBranches, 0);
        }
    }
    # apply if filtering exceptions, orphans, or both
    if (defined($self->[EXCEPTION_f]) || defined($self->[ORPHAN_f])) {
        # filter exceptions and orphans - even if the region is "unreachable"
        return
            $self->applyFilter($self->[EXCEPTION_f], $line, $branches,
                               $perTestBranches, 0);
    }
    return 0;
}

package TraceInfo;
#  coveage data for a particular source file
use constant {
              VERSION       => 0,
              LOCATION      => 1,
              FILENAME      => 2,
              CHECKSUM      => 3,
              LINE_DATA     => 4,    # per-testcase data
              BRANCH_DATA   => 5,
              FUNCTION_DATA => 6,
              MCDC_DATA     => 7,

              UNION      => 0,
              INTERSECT  => 1,
              DIFFERENCE => 2,
};

sub new
{
    my ($class, $filename) = @_;
    my $self = [];
    bless $self, $class;

    $self->[VERSION] = undef;    # version ID from revision control (if any)

    # keep track of location in .info file that this file data was found
    #  - useful in error messages
    $self->[LOCATION] = [];    # will fill with file/line

    $self->[FILENAME] = $filename;
    # _checkdata   : line number  -> source line checksum
    $self->[CHECKSUM] = MapData->new();
    # each line/branch/function element is a list of [summaryData, perTestcaseData]

    # line: [ line number  -> execution count - merged over all testcases,
    #         testcase_name -> CountData -> line_number -> execution_count ]
    $self->[LINE_DATA] =
        [CountData->new($filename, $CountData::SORTED), MapData->new()];

    # branch: [ BranchData:  line number  -> branch coverage - for all tests
    #           testcase_name -> BranchData]
    $self->[BRANCH_DATA] = [BranchData->new(), MapData->new()];

    # function: [FunctionMap:  function_name->FunctionEntry,
    #            tescase_name -> FucntionMap ]
    $self->[FUNCTION_DATA] = [FunctionMap->new($filename), MapData->new()];

    $self->[MCDC_DATA] = [MCDC_Data->new(), MapData->new()];

    return $self;
}

sub filename
{
    my $self = shift;
    return $self->[FILENAME];
}

sub set_filename
{
    my ($self, $name) = @_;
    $self->[FILENAME] = $name;
}

# return true if no line, branch, or function coverage data
sub is_empty
{
    my $self = shift;
    return ($self->test()->is_empty()       &&    # line cov
                $self->testbr()->is_empty() && $self->testfnc()->is_empty());
}

sub location
{
    my ($self, $filename, $lineNo) = @_;
    my $l = $self->[LOCATION];
    if (defined($filename)) {
        $l->[0] = $filename;
        $l->[1] = $lineNo;
    }
    return $l;
}

sub version
{
    # return the version ID that we found
    my ($self, $version) = @_;
    (!defined($version) || !defined($self->[VERSION])) or
        die("expected to set version ID at most once: " .
            (defined($version) ? $version : "undef") . " " .
            (defined($self->[VERSION]) ? $self->[VERSION] : "undef"));
    $self->[VERSION] = $version
        if defined($version);
    return $self->[VERSION];
}

# line coverage data
sub test
{
    my ($self, $testname) = @_;

    my $data = $self->[LINE_DATA]->[1];
    if (!defined($testname)) {
        return $data;
    }

    if (!$data->mapped($testname)) {
        $data->append_if_unset($testname, CountData->new($self->filename(), 1));
    }

    return $data->value($testname);
}

sub sum
{
    # return MapData of line -> hit count
    #   data merged over all testcases
    my $self = shift;
    return $self->[LINE_DATA]->[0];
}

sub func
{
    # return FunctionMap of function name or location -> FunctionEntry
    #   data is merged over all testcases
    my $self = shift;
    return $self->[FUNCTION_DATA]->[0];
}

sub found
{
    my $self = shift;
    return $self->sum()->found();
}

sub hit
{
    my $self = shift;
    return $self->sum()->hit();
}

sub function_found
{
    my $self = shift;
    return $self->func()
        ->numFunc(
              defined($lcovutil::cov_filter[$lcovutil::FILTER_FUNCTION_ALIAS]));
}

sub function_hit
{
    my $self = shift;
    return $self->func()
        ->numHit(
              defined($lcovutil::cov_filter[$lcovutil::FILTER_FUNCTION_ALIAS]));
}

sub branch_found
{
    my $self = shift;
    return $self->sumbr()->found();
}

sub branch_hit
{
    my $self = shift;
    return $self->sumbr()->hit();
}

sub mcdc_found
{
    return $_[0]->mcdc()->found();
}

sub mcdc_hit
{
    return $_[0]->mcdc()->hit();
}

sub check
{
    my $self = shift;
    return $self->[CHECKSUM];
}

# function coverage
sub testfnc
{
    my ($self, $testname) = @_;

    my $data = $self->[FUNCTION_DATA]->[1];
    if (!defined($testname)) {
        return $data;
    }

    if (!$data->mapped($testname)) {
        $data->append_if_unset($testname, FunctionMap->new($self->filename()));
    }

    return $data->value($testname);
}

# branch coverage
sub testbr
{
    my ($self, $testname) = @_;

    my $data = $self->[BRANCH_DATA]->[1];
    if (!defined($testname)) {
        return $data;
    }

    if (!$data->mapped($testname)) {
        $data->append_if_unset($testname, BranchData->new());
    }

    return $data->value($testname);
}

sub sumbr
{
    # return BranchData map of line number -> BranchEntry
    #   data is merged over all testcases
    my $self = shift;
    return $self->[BRANCH_DATA]->[0];
}

# MCDC coverage
sub testcase_mcdc
{
    my ($self, $testname) = @_;

    my $data = $self->[MCDC_DATA]->[1];
    if (!defined($testname)) {
        return $data;
    }

    if (!$data->mapped($testname)) {
        $data->append_if_unset($testname, MCDC_Data->new());
    }

    return $data->value($testname);
}

sub mcdc
{
    # return MCDC_Data map of line number -> MCDC_Block
    #   data is merged over all testcases
    my $self = shift;
    return $self->[MCDC_DATA]->[0];
}

#
# check_data
#  some paranoia checks

sub check_data($)
{
    my $self = shift;

    # some paranoia checking...
    if (1 || $lcovutil::debug) {
        my ($brSum, $brTest) = @{$self->[BRANCH_DATA]};
        $brSum->_checkCounts();
        foreach my $t ($brTest->keylist()) {
            $brTest->value($t)->_checkCounts();
        }
    }
}

#
# get_info(hash_ref)
#
# Retrieve data from an entry of the structure generated by TraceFile::_read_info().
# Return a list of references to hashes:
# (test data hash ref, sum count hash ref, funcdata hash ref, checkdata hash
#  ref, testfncdata hash ref, testbranchdata hash ref, branch summary hash ref)
#

sub get_info($)
{
    my $self = shift;
    my ($sumcount_ref, $testdata_ref) = @{$self->[LINE_DATA]};
    my ($funcdata_ref, $testfncdata)  = @{$self->[FUNCTION_DATA]};
    my ($sumbrcount, $testbrdata)     = @{$self->[BRANCH_DATA]};
    my ($mcdccount, $testcasemcdc)    = @{$self->[MCDC_DATA]};
    my $checkdata_ref = $self->[CHECKSUM];

    return ($testdata_ref, $sumcount_ref, $funcdata_ref,
            $checkdata_ref, $testfncdata, $testbrdata,
            $sumbrcount, $mcdccount, $testcasemcdc);
}

sub _merge_checksums
{
    my $self     = shift;
    my $info     = shift;
    my $filename = shift;

    my $mine  = $self->check();
    my $yours = $info->check();
    foreach my $line ($yours->keylist()) {
        if ($mine->mapped($line) &&
            $mine->value($line) ne $yours->value($line)) {
            lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                                      "checksum mismatch at $filename:$line: " .
                                          $mine->value($line),
                                      ' -> ' . $yours->value($line));
        }
        $mine->replace($line, $yours->value($line));
    }
}

sub merge
{
    my ($self, $info, $op, $filename) = @_;

    my $me  = defined($self->version()) ? $self->version() : "<no version>";
    my $you = defined($info->version()) ? $info->version() : "<no version>";

    my ($countOp, $funcOp, $brOp, $mcdcOp);

    if ($op == UNION) {
        $countOp = \&CountData::union;
        $funcOp  = \&FunctionMap::union;
        $brOp    = \&BranchData::union;
        $mcdcOp  = \&MCDC_Data::union;
    } elsif ($op == INTERSECT) {
        $countOp = \&CountData::intersect;
        $funcOp  = \&FunctionMap::intersect;
        $brOp    = \&BranchData::intersect;
        $mcdcOp  = \&MCDC_Data::intersect;
    } else {
        die("unexpected op $op") unless $op == DIFFERENCE;
        $countOp = \&CountData::difference;
        $funcOp  = \&FunctionMap::difference;
        $brOp    = \&BranchData::difference;
        $mcdcOp  = \&MCDC_Data::difference;
    }

    lcovutil::checkVersionMatch($filename, $me, $you, 'merge');
    my $changed = 0;

    foreach my $name ($info->test()->keylist()) {
        if (&$countOp($self->test($name), $info->test($name))) {
            $changed = 1;
        }
    }
    # if intersect and I contain some test that you don't, need to remove my data
    if (&$countOp($self->sum(), $info->sum())) {
        $changed = 1;
    }

    if (&$funcOp($self->func(), $info->func())) {
        $changed = 1;
    }
    $self->_merge_checksums($info, $filename);

    foreach my $name ($info->testfnc()->keylist()) {
        if (&$funcOp($self->testfnc($name), $info->testfnc($name))) {
            $changed = 1;
        }
    }

    foreach my $name ($info->testbr()->keylist()) {
        if (&$brOp($self->testbr($name), $info->testbr($name), $filename)) {
            $changed = 1;
        }
    }
    if (&$brOp($self->sumbr(), $info->sumbr(), $filename)) {
        $changed = 1;
    }

    foreach my $name ($info->testcase_mcdc()->keylist()) {
        if (
            &$mcdcOp($self->testcase_mcdc($name), $info->testcase_mcdc($name),
                     $filename)
        ) {
            $changed = 1;
        }
    }
    if (&$mcdcOp($self->mcdc(), $info->mcdc(), $filename)) {
        $changed = 1;
    }
    return $changed;
}

# this package merely reads sourcefiles as they are found on the current
#  filesystem - ie., the baseline version might have been modified/might
#  have diffs - but the current version does not.
package ReadCurrentSource;

our @source_directories;
our $searchPath;
our @dirs_used;
use constant {
              FILENAME => 0,
              PATH     => 1,
              SOURCE   => 2,
              EXCLUDE  => 3,

              # reasons: (bitfield)
              EXCLUDE_REGION        => 0x10,
              EXCLUDE_BRANCH_REGION => 0x20,
              EXCLUDE_DIRECTIVE     => 0x40,
              OMIT_LINE             => 0x80,

              # recorded exclusion markers
              e_LINE        => 0x1,
              e_BRANCH      => 0x2,
              e_EXCEPTION   => 0x4,
              e_UNREACHABLE => 0x8,
};

sub new
{
    my ($class, $filename) = @_;

    # additional layer of indirection so derived class can hold its own data
    my $self = [[]];
    bless $self, $class;

    $self->open($filename) if defined($filename);
    return $self;
}

sub close
{
    my $self = shift;
    my $data = $self->[0];
    while (scalar(@$data)) {
        pop(@$data);
    }
}

sub resolve_path
{
    my ($filename, $applySubstitutions) = @_;
    $filename = lcovutil::subst_file_name($filename) if $applySubstitutions;
    return $filename
        if (-e $filename ||
            (!@lcovutil::resolveCallback &&
             (File::Spec->file_name_is_absolute($filename) ||
                0 == scalar(@source_directories))));

    # don't pass 'applySubstitutions' flag as we already did that, above
    return $searchPath->resolve($filename, 0);
}

sub warn_sourcedir_patterns
{
    $searchPath->warn_unused(
            @source_directories ? '--source-directory' : 'source_directory = ');
}

sub _load
{
    my ($self, $filename, $version) = @_;
    my $data = $self->[0];

    $version = "" unless defined($version);
    my $path = resolve_path($filename);
    if (open(SRC, "<", $path)) {
        lcovutil::info(1,
                       "read $version$filename" .
                           ($path ne $filename ? " (at $path)" : '') . "\n");
        $data->[PATH] = $path;
        my @sourceLines = <SRC>;
        CORE::close(SRC) or die("unable to close $filename: $!\n");
        $data->[FILENAME] = $filename;
        return \@sourceLines;
    } else {
        lcovutil::ignorable_error($lcovutil::ERROR_SOURCE,
                                  "unable to open $filename: $!\n");
        $self->close();
        return undef;
    }
}

sub open
{
    my ($self, $filename, $version) = @_;

    my $srcLines = $self->_load($filename, $version);
    if (defined($srcLines)) {
        return $self->parseLines($filename, $srcLines);
    }
    return undef;
}

sub path
{
    my $self = shift;
    return $self->[0]->[PATH];
}

sub parseLines
{
    my ($self, $filename, $sourceLines) = @_;

    my @excluded;
    my $exclude_region;
    my $exclude_br_region;
    my $exclude_exception_region;
    my $line              = 0;
    my $excl_start        = qr(\b$lcovutil::EXCL_START\b);
    my $excl_stop         = qr(\b$lcovutil::EXCL_STOP\b);
    my $excl_line         = qr(\b$lcovutil::EXCL_LINE\b);
    my $excl_br_start     = qr(\b$lcovutil::EXCL_BR_START\b);
    my $excl_br_stop      = qr(\b$lcovutil::EXCL_BR_STOP\b);
    my $excl_br_line      = qr(\b$lcovutil::EXCL_BR_LINE\b);
    my $excl_ex_start     = qr(\b$lcovutil::EXCL_EXCEPTION_BR_START\b);
    my $excl_ex_stop      = qr(\b$lcovutil::EXCL_EXCEPTION_BR_STOP\b);
    my $excl_ex_line      = qr(\b$lcovutil::EXCL_EXCEPTION_LINE\b);
    my $unreachable_start = qr(\b$lcovutil::UNREACHABLE_START\b);
    my $unreachable_stop  = qr(\b$lcovutil::UNREACHABLE_STOP\b);
    my $unreachable_line  = qr(\b$lcovutil::UNREACHABLE_LINE\b);
    # @todo:  if we had annotated data here, then we could whine at the
    #   author of the unmatched start, extra end, etc.

    my $exclude_directives =
        qr/^\s*#\s*((else|endif)|((ifdef|ifndef|if|elif|include|define|undef)\s+))/
        if (TraceFile::is_language('c', $filename) &&
            defined($lcovutil::cov_filter[$lcovutil::FILTER_DIRECTIVE]));

    my @excludes;
    if (defined($lcovutil::cov_filter[$lcovutil::FILTER_EXCLUDE_REGION])) {
        push(@excludes,
             [$excl_start, $excl_stop,
              \$exclude_region, e_LINE | e_BRANCH | EXCLUDE_REGION,
              $lcovutil::EXCL_START, $lcovutil::EXCL_STOP
             ]);
        push(@excludes,
             [$unreachable_start, $unreachable_stop,
              \$exclude_region, e_UNREACHABLE | EXCLUDE_REGION,
              $lcovutil::UNREACHABLE_START, $lcovutil::UNREACHABLE_STOP
             ]);
    } else {
        $excl_line        = undef;
        $unreachable_line = undef;
    }

    if (defined($lcovutil::cov_filter[$lcovutil::FILTER_EXCLUDE_BRANCH])) {
        push(@excludes,
             [$excl_ex_start, $excl_ex_stop,
              \$exclude_exception_region, e_EXCEPTION | EXCLUDE_BRANCH_REGION,
              $lcovutil::EXCL_BR_START, $lcovutil::EXCL_BR_STOP,
             ],
             [$excl_br_start,
              $excl_br_stop,
              \$exclude_br_region,
              e_BRANCH | EXCLUDE_BRANCH_REGION,
              $lcovutil::EXCL_EXCEPTION_BR_START,
              $lcovutil::EXCL_EXCEPTION_BR_STOP,
             ]);
    } else {
        $excl_br_line = undef;
        $excl_ex_line = undef;
    }
    LINES: foreach (@$sourceLines) {
        $line += 1;
        my $exclude_branch_line           = 0;
        my $exclude_exception_branch_line = 0
            ; # per-line exception excludion not implemented at present.  Probably unnecessary.
        chomp($_);
        s/\r//;    # remove carriage return
        if (defined($exclude_directives) &&
            $_ =~ $exclude_directives) {
            # line contains compiler directive - exclude everything
            push(@excluded, e_LINE | e_BRANCH | EXCLUDE_DIRECTIVE);
            lcovutil::info(2, "directive '#$1' on $filename:$line\n");
            next;
        }

        foreach my $d (@excludes) {
            # note:  $d->[3] is the exclude reason (mask)
            #        $d->[4] is the 'start' string (not converted to perl regexp)
            #        $d->[5] is the 'stop' string
            my ($start, $stop, $ref, $reason) = @$d;
            if ($_ =~ $start) {
                lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                           "$filename: overlapping exclude directives. Found " .
                               $d->[4] .
                               " at line $line - but no matching " . $d->[5] .
                               ' for ' . $d->[4] . ' at line ' . $$ref->[0])
                    if $$ref;
                $$ref = [$line, $reason, $d->[4], $d->[5]];
                last;
            } elsif ($_ =~ $stop) {
                lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                              "$filename: found " . $d->[5] .
                                  " directive at line $line without matching " .
                                  ($$ref ? $$ref->[2] : $d->[4]) . ' directive')
                    unless $$ref &&
                    $$ref->[2] eq $d->[4] &&
                    $$ref->[3] eq $d->[5];
                $$ref = undef;
                last;
            }
        }
        if (defined($excl_line) &&
            $_ =~ $excl_line) {
            push(@excluded, e_LINE | e_BRANCH | EXCLUDE_REGION)
                ;    #everything excluded
            next;
        } elsif (defined($unreachable_line) &&
                 $_ =~ $unreachable_line) {
            push(@excluded, e_UNREACHABLE | EXCLUDE_REGION)
                ;    #everything excluded
            next;
        } elsif (defined($excl_br_line) &&
                 $_ =~ $excl_br_line) {
            $exclude_branch_line = e_BRANCH | EXCLUDE_BRANCH_REGION;
        } elsif (defined($excl_ex_line) &&
                 $_ =~ $excl_ex_line) {
            $exclude_branch_line = e_EXCEPTION | EXCLUDE_BRANCH_REGION;
        } elsif (0 != scalar(@lcovutil::omit_line_patterns)) {
            foreach my $p (@lcovutil::omit_line_patterns) {
                my $pat = $p->[0];
                if ($_ =~ $pat) {
                    push(@excluded, e_LINE | e_BRANCH | OMIT_LINE)
                        ;    #everything excluded
                     #lcovutil::info("'" . $p->[-2] . "' matched \"$_\", line \"$filename\":"$line\n");
                    ++$p->[-1];
                    next LINES;
                }
            }
        }
        push(@excluded,
             ($exclude_region ? $exclude_region->[1] : 0) |
                 ($exclude_br_region ? $exclude_br_region->[1] : 0) | (
                  $exclude_exception_region ? $exclude_exception_region->[1] : 0
                 ) | $exclude_branch_line | $exclude_exception_branch_line);
    }
    my @dangling;
    if ($exclude_region) {
        if ($exclude_region->[1] & e_UNREACHABLE) {
            push(@dangling,
                 [$exclude_region, $lcovutil::UNREACHABLE_START,
                  $lcovutil::UNREACHABLE_STOP
                 ]);
        } else {
            push(@dangling,
                 [$exclude_region, $lcovutil::EXCL_START, $lcovutil::EXCL_STOP]
            );
        }
    }
    foreach my $t (@dangling,
                   [$exclude_br_region, $lcovutil::EXCL_BR_START,
                    $lcovutil::EXCL_BR_STOP
                   ],
                   [$exclude_exception_region,
                    $lcovutil::EXCL_EXCEPTION_BR_START,
                    $lcovutil::EXCL_EXCEPTION_BR_STOP
                   ]
    ) {
        my ($key, $start, $stop) = @$t;
        lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                                 "$filename: unmatched $start at line " .
                                     $key->[0] .
                                     " - saw EOF while looking for matching $stop"
        ) if ($key);
    }
    my $data = $self->[0];
    $data->[FILENAME] = $filename;
    $data->[SOURCE]   = $sourceLines;
    $data->[EXCLUDE]  = \@excluded;
    return $self;
}

sub notEmpty
{
    my $self = shift;
    return 0 != scalar(@{$self->[0]});
}

sub filename
{
    return $_[0]->[0]->[FILENAME];
}

sub numLines
{
    my $self = shift;
    return scalar(@{$self->[0]->[SOURCE]});
}

sub getLine
{
    my ($self, $line) = @_;

    return $self->isOutOfRange($line) ?
        undef :
        $self->[0]->[SOURCE]->[$line - 1];
}

sub getExpr
{
    my ($self, $startLine, $startCol, $endLine, $endCol) = @_;
    die("bad range [$startLine:$endLine]") unless $endLine >= $startLine;
    return 'NA'                            unless $endLine <= $self->numLines();

    my $line = $self->getLine($startLine);
    my $expr;
    if ($startLine == $endLine) {
        $expr = substr($line, $startCol - 1, $endCol - $startCol);
    } else {
        $expr = substr($line, $startCol - 1);
        for (my $l = $startLine + 1; $l < $endLine; ++$l) {
            $expr .= $self->getLine($l);
        }
        $line = $self->getLine($endLine);
        $expr .= substr($line, 0, $endCol);
    }
    $expr =~ /^\s*(.+?)\s*$/;
    return $1;
}

sub isOutOfRange
{
    my ($self, $lineNo, $context) = @_;
    my $data = $self->[0];
    if (defined($data->[EXCLUDE]) &&
        scalar(@{$data->[EXCLUDE]}) < $lineNo) {

        # Can happen due to version mismatches:  data extracted with
        #   version N of the file, then generating HTML with version M
        #   "--version-script callback" option can be used to detect this.
        # Another case happens due to apparent bugs in some old 'gcov'
        #   versions - which sometimes inserts out-of-range line numbers
        #   when macro is used as last line in file.

        my $filt = $lcovutil::cov_filter[$lcovutil::FILTER_LINE_RANGE];
        if (defined($filt)) {
            my $c = ($context eq 'line') ? 'line' : "$context at line";
            lcovutil::info(2,
                           "filter out-of-range $c $lineNo in " .
                               $self->filename() . " (" .
                               scalar(@{$data->[EXCLUDE]}) .
                               " lines in file)\n");
            ++$filt->[-2];    # applied in 1 location
            ++$filt->[-1];    # one coverpoint suppressed
            return 1;
        }
        my $key = $self->filename();
        $key .= $lineNo unless $lcovutil::warn_once_per_file;
        if (lcovutil::warn_once($lcovutil::ERROR_RANGE, $key)) {
            my $c = ($context eq 'line') ? 'line' : "$context at line";
            my $msg =
                "unknown $c '$lineNo' in " .
                $self->filename() . ": there are only " .
                scalar(@{$data->[EXCLUDE]}) . " lines in the file.";
            if ($lcovutil::verbose ||
                0 == lcovutil::message_count($lcovutil::ERROR_RANGE)) {
                # only print verbose addition on first message
                $msg .= lcovutil::explain_once(
                    'version_script',
                    [   "\n  Issue can be caused by code changes/version mismatch: see the \"--version-script script_file\" discussion in the genhtml man page.",
                        $lcovutil::tool_name ne 'geninfo'
                    ],
                    "\n  Use '$lcovutil::tool_name --filter range' to remove out-of-range lines."
                );
            }
            # some versions of gcov seem to make up lines that do not exist -
            # this appears to be related to macros on last line in file
            lcovutil::store_deferred_message($lcovutil::ERROR_RANGE,
                                             1, $key, $msg);
        }
        # Note:  if user ignored the error, then we return 'not out of range'.
        #   The line is out of range/something is wrong - but the user did not
        #   ask us to filter it out.
    }
    return 0;
}

sub excludeReason
{
    my ($self, $lineNo) = @_;
    my $data = $self->[0];
    die("missing data at $lineNo")
        unless (defined($data->[EXCLUDE]) &&
                scalar(@{$data->[EXCLUDE]}) >= $lineNo);
    return $data->[EXCLUDE]->[$lineNo - 1] & 0xFF0;
}

sub isExcluded
{
    # returns:  the value of the matched flags
    #   - non-zero if the line is excluded (in an excluded or unreachable
    #     region), or if '$flags" is set and the exclusion reason includes
    #     at least one of the flags.
    #   - The latter condition is used to check for branch-only or execption-
    #     only exclusions, as well as to check whether this line is
    #     unreachable (as opposed to excluded).
    my ($self, $lineNo, $flags, $skipRangeCheck) = @_;
    my $data = $self->[0];
    if (!defined($data->[EXCLUDE]) || scalar(@{$data->[EXCLUDE]}) < $lineNo) {
        # this can happen due to version mismatches:  data extracted with
        # version N of the file, then generating HTML with version M
        # "--version-script callback" option can be used to detect this

        # if we are just checking whether this line in in an unreachable region,
        #   then don't check for out-of-range (that check happens later)
        return 0
            if $skipRangeCheck;
        my $key = $self->filename();
        $key .= $lineNo unless ($lcovutil::warn_once_per_file);
        my $suffix = lcovutil::explain_once(
            'version-script',
            [   "\n  Issue can be caused by code changes/version mismatch; see the \"--version-script script_file\" discussion in the genhtml man page.",
                $lcovutil::verbose ||
                    lcovutil::message_count($lcovutil::ERROR_RANGE) == 0
            ]);
        lcovutil::store_deferred_message(
              $lcovutil::ERROR_RANGE,
              1, $key,
              "unknown line '$lineNo' in " . $self->filename()
                  .
                  (
                  defined($data->[EXCLUDE]) ?
                      (" there are only " .
                       scalar(@{$data->[EXCLUDE]}) . " lines in the file.") :
                      "") .
                  $suffix) if lcovutil::warn_once($lcovutil::ERROR_RANGE, $key);
        return 0;    # even though out of range - this is not excluded by filter
    }
    my $reason;
    if ($flags &&
        0 != ($reason = ($data->[EXCLUDE]->[$lineNo - 1] & $flags))) {
        return $reason;
    }
    return $data->[EXCLUDE]->[$lineNo - 1] & (e_LINE | e_UNREACHABLE);
}

sub removeComments
{
    my $line = shift;
    $line =~ s|//.*$||;
    $line =~ s|/\*.*\*/||g;
    return $line;
}

sub isCharacter
{
    my ($self, $line, $char) = @_;

    my $code = $self->getLine($line);
    return 0
        unless defined($code);
    $code = removeComments($code);
    return ($code =~ /^\s*${char}\s*$/);
}

# is line empty
sub isBlank
{
    my ($self, $line) = @_;

    my $code = $self->getLine($line);
    return 0
        unless defined($code);
    $code = removeComments($code);
    return ($code =~ /^\s*$/);
}

sub is_initializerList
{
    my ($self, $line) = @_;
    return 0 unless defined($self->[0]->[SOURCE]) && $line < $self->numLines();
    my $code      = '';
    my $l         = $line;
    my $foundExpr = 0;
    while ($l < $self->numLines()) {
        my $src = $self->getLine($l);
        # append to string until we find close brace...then look for next one...
        $code = removeComments($code . $src);
        # believe that initialization expressions are either numeric or C strings
        while ($code =~
            s/\s+("[^"]*"|0x[0-9a-fA-F]+|[-+]?[0-9]+((\.[0-9]+)([eE][-+][0-9]+)?)?)\s*,?//
        ) {
            $foundExpr = 1;
        }
        # remove matching {} brace pairs - assume a sub-object initializer
        $code             =~ s/\s*{\s*,?\s*}\s*,?\s*//;
        last if $code     =~ /[};]/;   # unmatched close or looks like statement
        last unless $code =~ /^\s*([{}]\s*)*$/;
        ++$l;
    }
    return $foundExpr ? $l - $line : 0;    # return number of consecutive lines
}

sub containsConditional
{
    my ($self, $line) = @_;

    # special case - maybe C++ exception handler on close brace at end of function?
    return 0
        if $self->isCharacter($line, '}');
    my $src = $self->getLine($line);
    return 1
        unless defined($src);

    my $code = "";
    for (my $next = $line + 1;
         defined($src) && ($next - $line) < $lcovutil::source_filter_lookahead;
         ++$next) {

        $src = lcovutil::simplifyCode($src);

        my $bitwiseOperators =
            $lcovutil::source_filter_bitwise_are_conditional ? '&|~' : '';

        return 1
            if ($src =~
            /([?!><$bitwiseOperators]|&&|\|\||==|!=|\b(if|switch|case|while|for)\b)/
            );
        $code = $code . $src;

        if (lcovutil::balancedParens($code)) {
            return 0;    # got to the end and didn't see conditional
        } elsif ($src =~ /[{;]\s*$/) {
            # assume we got to the end of the statement if we see semicolon
            # or brace.
            # parens weren't balanced though - so assume this might be
            # a conditional
            return 1;
        }
        $src = $self->getLine($next);
        $src = '' unless defined($src);
    }
    return 1;    # not sure - so err on side of caution
}

sub containsTrivialFunction
{
    my ($self, $start, $end) = @_;
    return 0
        if (1 + $end - $start >= $lcovutil::trivial_function_threshold);
    my $text = '';
    for (my $line = $start; $line <= $end; ++$line) {
        my $src = $self->getLine($line);
        $src = '' unless defined($src);
        chomp($src);
        $src =~ s/\s+$//;     # whitespace
        $src =~ s#//.*$##;    # remove end-of-line comments
        $text .= $src;
    }
    # remove any multiline comments that were present:
    $text =~ s#/\*.*\*/##g;
    # remove whitespace
    $text =~ s/\s//g;
    # remove :: C++ separator
    $text =~ s/:://g;
    if ($text =~ /:/) {
        return 0;
    }

    # does code end with '{}', '{;}' or '{};'?
    # Or: is this just a close brace?
    if ($text =~ /(\{;?|^)\};?$/) {
        return 1;
    }
    return 0;
}

# check if this line is a close brace with zero hit count that should be
# suppressed.  We want to ignore spurious zero on close brace;  depending
# on what gcov did the last time (zero count, no count, nonzero count) -
# it might be interpreted as UIC - which will violate our coverage criteria.
# We want to ignore this line if:
#   - the line contain only a closing brace and
#    - previous line is hit, OR
#     - previous line is not an open-brace which has no associated
#       count - i.e., this is not an empty block where the zero
#       count is tagged to the closing brace, OR
# is line empty (no code) and
#   - count is zero, and
#   - either previous or next non-blank lines have an associated count
#
sub suppressCloseBrace
{
    my ($self, $lineNo, $count, $lineCountData) = @_;

    my $suppress = 0;
    if ($self->isCharacter($lineNo, '}')) {
        for (my $prevLine = $lineNo - 1; $prevLine >= 0; --$prevLine) {
            my $prev = $lineCountData->value($prevLine);
            if (defined($prev)) {
                # previous line was executable
                $suppress = 1
                    if ($prev == $count ||
                        ($count == 0 &&
                         $prev > 0));

                lcovutil::info(3,
                    "not skipping brace line $lineNo because previous line $prevLine hit count didn't match: $prev != $count"
                ) unless $suppress;
                last;
            } elsif ($count == 0 &&
                     # previous line not executable - was it an open brace?
                     $self->isCharacter($prevLine, '{')
            ) {
                # look 'up' from the open brace to find the first
                #   line which has an associated count -
                my $code = "";
                for (my $l = $prevLine - 1; $l >= 0; --$l) {
                    $code = $self->getLine($l) . $code;
                    my $prevCount = $lineCountData->value($l);
                    if (defined($prevCount)) {
                        # don't suppress if previous line not hit either
                        last
                            if $prevCount == 0;
                        # if first non-whitespace character is a colon -
                        #  then this looks like a C++ initialization list.
                        #  suppress.
                        if ($code =~ /^\s*:(\s|[^:])/) {
                            $suppress = 1;
                        } else {
                            $code = lcovutil::filterStringsAndComments($code);
                            $code = lcovutil::simplifyCode($code);
                            # don't suppress if this looks like a conditional
                            $suppress = 1
                                unless (
                                     $code =~ /\b(if|switch|case|while|for)\b/);
                        }
                        last;
                    }
                }    # for each prior line (looking for statement before block)
                last;
            }    # if (line was an open brace)
        }    # foreach prior line
    }    # if line was close brace
    return $suppress;
}

package TraceFile;

our $ignore_testcase_name;    # use default name, if set
use constant {
              FILES    => 0,
              COMMENTS => 1,
              STATE    => 2,    # operations performed: don't do them again

              DID_FILTER => 1,
              DID_DERIVE => 2,
};

sub load
{
    my ($class, $tracefile, $readSource, $verify_checksum,
        $ignore_function_exclusions)
        = @_;
    my $self    = $class->new();
    my $context = MessageContext->new("loading $tracefile");

    $self->_read_info($tracefile, $readSource, $verify_checksum);

    $self->applyFilters($readSource);
    return $self;
}

sub new
{
    my $class = shift;
    my $self  = [{}, [], 0];
    bless $self, $class;

    return $self;
}

sub serialize
{
    my ($self, $filename) = @_;

    my $data = Storable::store($self, $filename);
    die("serialize failed") unless defined($data);
}

sub deserialize
{
    my ($class, $file) = @_;
    my $self = Storable::retrieve($file) or
        die("unable to deserialize $file\n");
    ref($self) eq $class or die("did not deserialize a $class");
    return $self;
}

sub empty
{
    my $self = shift;

    return !keys(%{$self->[FILES]});
}

sub files
{
    my $self = shift;

    # for case-insensitive support:  need to store the file keys in
    #  lower case (so they can be found) - but return the actual
    #  names of the files (mixed case)

    return keys %{$self->[FILES]};
}

sub directories
{
    my $self = shift;
    # return hash of directories which contain source files
    my %dirs;
    foreach my $f ($self->files()) {
        my $d = File::Basename::dirname($f);
        $dirs{$d} = [] unless exists($dirs{$d});
        push(@{$dirs{$d}}, $f);
    }
    return \%dirs;
}

sub file_exists
{
    my ($self, $name) = @_;
    $name = lc($name) if $lcovutil::case_insensitive;
    return exists($self->[FILES]->{$name});
}

sub count_totals
{
    my $self = shift;
    # return list of (number files, [#lines, #hit], [#branches, #hit], [#functions,#hit])
    my @data = (0, [0, 0], [0, 0], [0, 0], [0, 0]);
    foreach my $filename ($self->files()) {
        my $entry = $self->data($filename);
        ++$data[0];
        $data[1]->[0] += $entry->found();             # lines
        $data[1]->[1] += $entry->hit();
        $data[2]->[0] += $entry->branch_found();      # branch
        $data[2]->[1] += $entry->branch_hit();
        $data[3]->[0] += $entry->function_found();    # function
        $data[3]->[1] += $entry->function_hit();

        if ($lcovutil::mcdc_coverage) {
            $data[4]->[0] += $entry->mcdc_found();    # mcdc
            $data[4]->[1] += $entry->mcdc_hit();
        }
    }
    return @data;
}

sub check_fail_under_criteria
{
    my ($self, $type) = @_;
    my @types;
    if (!defined($type)) {
        push(@types, 'line');
        push(@types, 'branch', 'condition') if $lcovutil::br_coverage;
    } else {
        push(@types, $type);
    }

    foreach my $t (@types) {
        my ($rate, $plural, $idx);
        if ($t eq 'line') {
            next unless defined($lcovutil::fail_under_lines);
            $rate   = $lcovutil::fail_under_lines;
            $idx    = 1;                             # lines
            $plural = 'lines';
        } else {
            next unless defined($lcovutil::fail_under_branches);
            $rate   = $lcovutil::fail_under_branches;
            $idx    = 2;
            $plural = 'branches';
        }
        next if $rate <= 0;
        my @counts = $self->count_totals();
        my ($found, $hit) = @{$counts[$idx]};
        if ($found == 0) {
            lcovutil::info(1, "No $plural found\n");
            return "No $plural found";
        }
        my $actual_rate   = ($hit / $found);
        my $expected_rate = $rate / 100;
        if ($actual_rate < $expected_rate) {
            my $msg =
                sprintf("Failed '$t' coverage criteria: %0.2f < %0.2f",
                        $actual_rate, $expected_rate);
            lcovutil::info("$msg\n");
            return $msg;
        }
    }
    return 0;
}

sub checkCoverageCriteria
{
    my $self = shift;

    CoverageCriteria::check_failUnder($self);

    return unless defined($CoverageCriteria::criteriaCallback);

    my $perFile = 0 == scalar(@CoverageCriteria::criteriaCallbackLevels) ||
        grep(/file/, @CoverageCriteria::criteriaCallbackLevels);
    my %total = ('line' => {
                            'found' => 0,
                            'hit'   => 0
                 },
                 'branch' => {
                              'found' => 0,
                              'hit'   => 0
                 },
                 'condition' => {
                                 'found' => 0,
                                 'hit'   => 0
                 },
                 'function' => {
                                'found' => 0,
                                'hit'   => 0
                 });
    my %data;
    foreach my $filename ($self->files()) {
        my $entry = $self->data($filename);
        my @data = ($entry->found(), $entry->hit(),
                    $entry->branch_found(), $entry->branch_hit(),
                    $entry->function_found(), $entry->function_hit());
        my $idx = 0;
        foreach my $t ('line', 'branch', 'function') {
            foreach my $x ('found', 'hit') {
                $data{$t}->{$t} = $data[$idx] if $perFile;
                $total{$t}->{$x} += $data[$idx++];
            }
        }
        if ($perFile) {
            CoverageCriteria::executeCallback('file', $filename, \%data);
        }
    }
    CoverageCriteria::executeCallback('top', 'top', \%total);
}

#
# print_summary(fn_do, br_do)
#
# Print overall coverage rates for the specified coverage types.
#   $countDat is the array returned by 'TraceFile->count_totals()'

sub print_summary
{
    my ($self, $fn_do, $br_do, $mcdc_do) = @_;

    $br_do   = $lcovutil::br_coverage   unless defined($br_do);
    $mcdc_do = $lcovutil::mcdc_coverage unless defined($mcdc_do);
    $fn_do   = $lcovutil::func_coverage unless defined($fn_do);
    my @counts = $self->count_totals();
    lcovutil::info("Summary coverage rate:\n");
    lcovutil::info("  source files: %d\n", $counts[0]);
    lcovutil::info("  lines.......: %s\n",
                   lcovutil::get_overall_line(
                                        $counts[1]->[0], $counts[1]->[1], "line"
                   ));
    lcovutil::info("  functions...: %s\n",
                   lcovutil::get_overall_line(
                                    $counts[3]->[0], $counts[3]->[1], "function"
                   )) if ($fn_do);
    lcovutil::info("  branches....: %s\n",
                   lcovutil::get_overall_line(
                                      $counts[2]->[0], $counts[2]->[1], "branch"
                   )) if ($br_do);
    lcovutil::info("  conditions..: %s\n",
                   lcovutil::get_overall_line(
                                  $counts[4]->[0], $counts[4]->[1], "conditions"
                   )) if ($mcdc_do);
}

sub skipCurrentFile
{
    my $filename = shift;

    my $filt = $lcovutil::cov_filter[$lcovutil::FILTER_MISSING_FILE];
    if ($filt) {
        my $missing = !-r $filename;
        if ($missing &&
            $lcovutil::resolveCallback) {

            my $path = SearchPath::resolveCallback($filename, 0, 1);
            $missing = !defined($path) || '' eq $path;
        }

        if ($missing) {
            lcovutil::info(
                   "Excluding \"$filename\": does not exist/is not readable\n");
            ++$filt->[-2];
            ++$filt->[-1];
            return 1;
        }
    }

    # check whether this file should be excluded or not...
    foreach my $p (@lcovutil::exclude_file_patterns) {
        my $pattern = $p->[0];
        if ($filename =~ $pattern) {
            lcovutil::info(1, "exclude $filename: matches '" . $p->[1] . "\n");
            ++$p->[-1];
            return 1;    # all done - explicitly excluded
        }
    }
    if (@lcovutil::include_file_patterns) {
        foreach my $p (@lcovutil::include_file_patterns) {
            my $pattern = $p->[0];
            if ($filename =~ $pattern) {
                lcovutil::info(1,
                              "include: $filename: matches '" . $p->[1] . "\n");
                ++$p->[-1];
                return 0;    # explicitly included
            }
        }
        lcovutil::info(1, "exclude $filename: no include matches\n");
        return 1;            # not explicitly included - so exclude
    }
    return 0;
}

sub comments
{
    my $self = shift;
    return @{$self->[COMMENTS]};
}

sub add_comments
{
    my $self = shift;
    foreach (@_) {
        push(@{$self->[COMMENTS]}, $_);
    }
}

sub data
{
    my $self                  = shift;
    my $file                  = shift;
    my $checkMatchingBasename = shift;

    my $key   = $lcovutil::case_insensitive ? lc($file) : $file;
    my $files = $self->[FILES];
    if (!exists($files->{$key})) {
        if (defined $checkMatchingBasename) {
            # check if there is a file in the map that has the same basename
            #  as the lone we are looking for.
            # this can happen if the 'udiff' file refers to paths in the repo
            #  whereas the .info files refer to paths in the build area.
            my $base = File::Basename::basename($file);
            $base = lc($base) if $lcovutil::case_insensitive;
            my $count = 0;
            my $found;
            foreach my $f (keys %$files) {
                my $b = File::Basename::basename($f);
                $b = lc($b) if $lcovutil::case_insensitive;
                if ($b eq $base) {
                    $count++;
                    $found = $files->{$f};
                }
            }
            return $found
                if $count == 1;
        }
        $files->{$key} = TraceInfo->new($file);
    }

    return $files->{$key};
}

sub contains
{
    my ($self, $file) = @_;
    my $key   = $lcovutil::case_insensitive ? lc($file) : $file;
    my $files = $self->[FILES];
    return exists($files->{$key});
}

sub remove
{
    my ($self, $filename) = @_;
    $filename = lc($filename) if $lcovutil::case_insensitive;
    $self->file_exists($filename) or
        die("remove nonexistent file $filename");
    delete($self->[FILES]->{$filename});
}

sub insert
{
    my ($self, $filename, $data) = @_;
    $filename = lc($filename) if $lcovutil::case_insensitive;
    die("insert existing file $filename")
        if $self->file_exists($filename);
    die("expected TraceInfo got '" . ref($data) . "'")
        unless (ref($data) eq 'TraceInfo');
    $self->[FILES]->{$filename} = $data;
}

sub merge_tracefile
{
    my ($self, $trace, $op) = @_;
    die("expected TraceFile")
        unless (defined($trace) && 'TraceFile' eq ref($trace));

    my $changed = 0;
    my $mine    = $self->[FILES];
    my $yours   = $trace->[FILES];
    foreach my $filename (keys %$mine) {

        if (exists($yours->{$filename})) {
            # this file in both me and you...merge as appropriate
            #lcovutil::info(1, "merge common $filename\n");
            if ($self->data($filename)
                ->merge($yours->{$filename}, $op, $filename)) {
                $changed = 1;
            }
        } else {
            # file in me and not you - remove mine if intersect operation
            if ($op == TraceInfo::INTERSECT) {
                #lcovutil::info(1, "removing my $filename: intersect\n");
                delete $mine->{$filename};
                $changed = 1;
            }
        }
    }
    if ($op == TraceInfo::UNION) {
        # now add in any files from you that are not present in me...
        while (my ($filename, $data) = each(%$yours)) {
            if (!exists($mine->{$filename})) {
                $mine->{$filename} = $data;
                $changed = 1;
            }
        }
    }
    $self->add_comments($trace->comments());
    return $changed;
}

sub _eraseFunction
{
    my ($fcn, $name, $end_line, $source_file, $functionMap,
        $lineData, $branchData, $mcdcData, $checksum) = @_;
    if (defined($end_line)) {
        for (my $line = $fcn->line(); $line <= $end_line; ++$line) {

            if (defined($checksum)) {
                $checksum->remove($line, 1);    # remove if present
            }
            if ($lineData->remove($line, 1)) {
                lcovutil::info(2,
                            "exclude DA in FN '$name' on $source_file:$line\n");
            }
            if (defined($branchData) && $branchData->remove($line, 1)) {
                lcovutil::info(2,
                          "exclude BRDA in FN '$name' on $source_file:$line\n");
            }
            if (defined($mcdcData) && $mcdcData->remove($line, 1)) {
                lcovutil::info(2,
                          "exclude MCDC in FN '$name' on $source_file:$line\n");
            }
        }    # foreach line
    }
    # remove this function and all its aliases...
    $functionMap->remove($fcn);
}

sub _eraseFunctions
{
    my ($source_file, $srcReader, $functionMap, $lineData, $branchData,
        $mcdcData, $checksum, $state, $isMasterList) = @_;

    my $modified      = 0;
    my $removeTrivial = $cov_filter[$FILTER_TRIVIAL_FUNCTION];
    FUNC: foreach my $key ($functionMap->keylist()) {
        my $fcn      = $functionMap->findKey($key);
        my $end_line = $fcn->end_line();
        my $name     = $fcn->name();
        if (!defined($end_line)) {
            ++$state->[0]->[1];    # mark that we don't have an end line
                # we can skip out of processing if we don't know the end line
                # - there is no way for us to remove line and branch points in
                #   the function region
                # Or we can keep going and at least remove the matched function
                #   coverpoint.
                #last; # at least for now:  keep going
            lcovutil::info(1, "no end line for '$name' at $key\n");
        } elsif (
               defined($removeTrivial) &&
               is_language('c', $source_file) &&
               (defined($srcReader) &&
                $srcReader->containsTrivialFunction($fcn->line(), $end_line))
        ) {
            # remove single-line functions which has no body
            # Only count what we removed from the top level/master list -
            #   - otherwise, we double count for every testcase.
            ++$removeTrivial->[-2] if $isMasterList;
            foreach my $alias (keys %{$fcn->aliases()}) {
                lcovutil::info(1,
                      "\"$source_file\":$end_line: filter trivial FN $alias\n");
                _eraseFunction($fcn, $alias, $end_line,
                               $source_file, $functionMap, $lineData,
                               $branchData, $mcdcData, $checksum);
                ++$removeTrivial->[-1] if $isMasterList;
            }
            $modified = 1;
            next FUNC;
        }
        foreach my $p (@lcovutil::exclude_function_patterns) {
            my $pat = $p->[0];
            my $a   = $fcn->aliases();
            foreach my $alias (keys %$a) {
                if ($alias =~ $pat) {
                    ++$p->[-1] if $isMasterList;
                    if (defined($end_line)) {
                        # if user ignored the unsupported message, then the
                        # best we can do is to remove the matched function -
                        # and leave the lines and branches in place
                        lcovutil::info(
                                  1 + (0 == $isMasterList),
                                  "exclude FN $name line range $source_file:[" .
                                      $fcn->line() .
                                      ":$end_line] due to '" . $p->[-2] . "'\n"
                        );
                    }
                    _eraseFunction($fcn, $alias, $end_line,
                                   $source_file, $functionMap, $lineData,
                                   $branchData, $mcdcData, $checksum);
                    $modified = 1;
                    next FUNC;
                }    # if match
            }    # foreach alias
        }    # foreach pattern
             # warn if the function is in an unreachable region but is hit -
             #  easiest to check here so we emit only one message per function
        my $line;
        my $reason;
        if ($srcReader &&
            0 != ($reason =
                      $srcReader->isExcluded(($line = $fcn->line()),
                                             $srcReader->e_UNREACHABLE, 1)) &&
            0 != ($reason & $srcReader->e_UNREACHABLE) &&
            0 != $fcn->hit()
        ) {

            lcovutil::ignorable_error($lcovutil::ERROR_UNREACHABLE,
                "\"$source_file\":$line:  function $name is executed but was marked unreachable."
            );
            next
                if $lcovutil::retainUnreachableCoverpointIfHit;
        }

    }    # foreach function
    return $modified;
}

sub _deriveFunctionEndLines
{
    my $traceInfo = shift;
    my $modified  = 0;

    my $start    = Time::HiRes::gettimeofday();
    my $lineData = $traceInfo->sum();
    my @lines    = sort { $a <=> $b } $lineData->keylist();
    # sort functions by start line number
    # ignore lambdas - which we don't process correctly at the moment
    #   (would need to do syntactic search for the end line)
    my @functions = sort { $a->line() <=> $b->line() }
        grep({ !$_->isLambda() } $traceInfo->func()->valuelist());

    my $currentLine = @lines ? shift(@lines) : 0;
    my $funcData    = $traceInfo->testfnc();
    FUNC: while (@functions) {
        my $func  = shift(@functions);
        my $first = $func->line();
        my $end   = $func->end_line();
        #unless (defined($lineData->value($first))) {
        #    lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
        #                              '"' . $func->filename() .
        #                "\":$first: first line of function has no linecov.");
        #    $lineData->append($first, $func->hit());
        #}
        while ($first > $currentLine) {
            if (@lines) {
                last if $lines[0] > $first;
                $currentLine = shift @lines;
            } else {
                if (!defined($end)) {
                    my $suffix =
                        lcovutil::explain_once('derive_end_line',
                        "  See lcovrc man entry for 'derive_function_end_line'."
                        );
                    lcovutil::ignorable_error(
                        $lcovutil::ERROR_INCONSISTENT_DATA,
                        '"' . $traceInfo->filename() .
                            "\":$first:  function " . $func->name() .
                            " found on line but no corresponding 'line' coverage data point.  Cannot derive function end line."
                            . $suffix);
                }
                next FUNC;
            }
        }
        if (!defined($end)) {
            # where is the next function?  Find the last 'line' coverpoint
            #   less than the start line of that function..
            if (@lines) {
                # if there are no more lines in this file - then everything
                # must be ending on the last line we saw
                if (@functions) {
                    my $next_func = $functions[0];
                    my $start     = $next_func->line();
                    while (@lines &&
                           $lines[0] < $start) {
                        $currentLine = shift @lines;
                    }
                } else {
                    # last line in the file must be the last line
                    #  of this function
                    if (@lines) {
                        $currentLine = $lines[-1];
                    } else {
                        my $suffix = lcovutil::explain_once('derive_end_line',
                            "  See lcovrc man entry for 'derive_function_end_line'."
                        );
                        lcovutil::ignorable_error(
                            $lcovutil::ERROR_INCONSISTENT_DATA,
                            '"' . $traceInfo->filename() .
                                "\":$first:  function " . $func->name() .
                                ": last line in file is not last line of function.$suffix"
                        );
                        next FUNC;
                    }
                }
            } elsif ($currentLine < $first) {
                # we ran out of lines in the data...check for inconsistency
                my $suffix =
                    lcovutil::explain_once('derive_end_line',
                      "  See lcovrc man entry for 'derive_function_end_line'.");
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                    '"' . $traceInfo->filename() .
                        "\":$first:  function " . $func->name() .
                        " found on line but no corresponding 'line' coverage data point.  Cannot derive function end line."
                        . $suffix);

                # last FUNC; # quit looking here - all the other functions after this one will have same issue
                next FUNC;    # warn about them all
            }
            lcovutil::info(1,
                           '"' . $traceInfo->filename() .
                               "\":$currentLine: assign end_line " .
                               $func->name() . "\n");
            # warn that we are deriving end lines
            _generate_end_line_message();
            $func->set_end_line($currentLine);
            $modified = 1;
        }
        # we may not have set the end line above due to inconsistency
        #  but we also might not have line data
        #  - see .../tests/lcov/extract with gcc/4.8
        if (!defined($func->end_line())) {
            my $suffix =
                lcovutil::explain_once('derive_end_line',
                      "  See lcovrc man entry for 'derive_function_end_line'.");
            lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                                '"' . $func->filename() . '":' . $func->line() .
                                    ': failed to set end line for function ' .
                                    $func->name() . '.' . $suffix);
            next FUNC;
        }

        # now look for this function in each testcase -
        #  set the same endline (if not already set)
        my $key = $first;
        foreach my $tn ($funcData->keylist()) {
            my $d = $funcData->value($tn);
            my $f = $d->findKey($key);
            if (defined($f)) {
                if (!defined($f->end_line())) {
                    $f->set_end_line($func->end_line());
                    $modified = 1;
                } else {
                    if ($f->end_line() != $func->end_line()) {
                        lcovutil::ignorable_error(
                                       $lcovutil::ERROR_INCONSISTENT_DATA,
                                       '"' . $func->file() .
                                           '":' . $first . ': function \'' .
                                           $func->name() . ' last line is ' .
                                           $func->end_line() . ' but is ' .
                                           $f->end_line() . " in testcase '$tn'"
                        );
                    }
                }
            }
        }    #foreach testcase
    }    # for each function
    my $end = Time::HiRes::gettimeofday();
    $lcovutil::profileData{derive_end}{$traceInfo->filename()} = $end - $start;
    return $modified;
}

sub _consistencySuffix
{
    return lcovutil::explain_once('consistency_check',
        "\n\tTo skip consistency checks, see the 'check_data_consistency' section in man lcovrc(5)."
    );
}

sub _fixFunction
{
    my ($traceInfo, $func, $count) = @_;

    my @fix          = ($func);
    my $line         = $func->line();
    my $per_testcase = $traceInfo->testfnc();
    foreach my $testname ($per_testcase->keylist()) {
        my $data = $traceInfo->testfnc($testname);
        my $f    = $data->findKey($line);
        push(@fix, $f) if defined($f);
    }

    foreach my $f (@fix) {
        $f->[FunctionEntry::COUNT] = $count;

        # and mark that each alias was hit...
        my $aliases = $f->aliases();
        foreach my $alias (keys %$aliases) {
            $aliases->{$alias} += $count;
        }
    }
}

sub _checkConsistency
{
    return unless $lcovutil::check_data_consistency;
    my $traceInfo = shift;
    my $modified  = 0;

    my $start = Time::HiRes::gettimeofday();

    my @functions = sort { $a->line() <=> $b->line() }
        grep({ defined($_->end_line()) } $traceInfo->func()->valuelist());
    my $lineData = $traceInfo->sum();
    my @lines    = sort { $a <=> $b } $lineData->keylist()
        if @functions;
    my $currentLine = @lines ? shift(@lines) : 0;
    FUNC: while (@functions) {
        my $func    = shift(@functions);
        my $first   = $func->line();
        my $end     = $func->end_line();
        my $imHit   = $func->hit() != 0;    # I'm hit if any aliases is hit
        my $lineHit = 0;
        while ($first > $currentLine) {
            # skip until we find the first line of the current function
            if (@lines) {
                $currentLine = shift(@lines);
            } else {
                # can only get here with really inconsistent data...would have
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                    '"' . $func->filename() .
                        "\":$first: file linecov does not match function cov data - skipping checks."
                );
                last FUNC;
            }
        }
        while ($end >= $currentLine) {
            # look for first covered line in this function -
            #   sufficient to just look at the such line
            die("bug: " . $func->filename() . " [$first:$end]: $currentLine")
                unless $first <= $currentLine && $currentLine <= $end;
            my $hit = $lineData->value($currentLine);
            $lineHit = 1 if $hit;
            if ($hit && !$imHit) {
                # don't warn about the first line of a lambda:
                #  - the decl may executed even if the lambda function itself is
                #    not called
                #  - if no other lines are hit, then then the function is not
                #    covered, but the coverage DB is consistent
                #  - if some other line _is_ hit, then, the data is inconsistent
                if ($func->isLambda() && $currentLine == $first) {
                    $lineHit = 0;
                    last unless @lines;
                    $currentLine = shift(@lines);
                    next;
                }
                my $suffix =
                    ($lcovutil::fix_inconsistency && lcovutil::is_ignored(
                                             $lcovutil::ERROR_INCONSISTENT_DATA)
                    ) ? ": function marked 'hit'" :
                    '';
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                           '"' . $func->filename() .
                               "\":$first: function '" . $func->name() .
                               "' is not hit but line $currentLine is$suffix." .
                               _consistencySuffix());
                if ($lcovutil::fix_inconsistency) {
                    # if message was ignored, then mark the function and all
                    #  its aliases hit
                    $imHit    = 1;
                    $modified = 1;
                    _fixFunction($traceInfo, $func, $hit);
                }
                last;    # only warn on the first hit line in the function
            }
            last if $lineHit && $hit;    # can stop looking at this function now
            last unless (@lines);
            $currentLine = shift @lines;
        }
        if ($imHit && !$lineHit) {
            my $suffix =
                ($lcovutil::fix_inconsistency &&
                 lcovutil::is_ignored($lcovutil::ERROR_INCONSISTENT_DATA)) ?
                ": function marked 'not hit'" :
                '';
            lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                         '"' . $traceInfo->filename() .
                             "\":$first: function '" . $func->name() .
                             "' is hit but no contained lines are hit$suffix." .
                             _consistencySuffix());
            if ($lcovutil::fix_inconsistency) {
                # if message was ignored, then mark the function and its aliases
                #  not hit
                $modified = 1;
                _fixFunction($traceInfo, $func, 0);
            }
        }
    }

    # check MC/DC consistency -
    #   Note that we might have an MC/DC block on a line which has no
    #     linecov data
    #   This can happen for template functions (and similar) where the
    #     expression is statically determned to be true or false - and elided
    #     by the compiler.  In that case, generate a new line coverpoint
    if ($lcovutil::mcdc_coverage) {
        my $mcdc          = $traceInfo->mcdc();
        my $testcase_mcdc = $traceInfo->testcase_mcdc();
        foreach my $line ($mcdc->keylist()) {
            my $lineHit = $lineData->value($line);
            next if defined($lineHit);

            lcovutil::info(1,
                           '"' . $traceInfo->filename() .
                               "\":$line: generating DA entry for orphan MC/DC\n"
            );
            my $block = $mcdc->value($line);
            my ($found, $hit) = $block->totals();
            $lineData->append($line, $hit);

            # create the entry in the per-testcase data
            foreach my $testcase ($testcase_mcdc->keylist()) {
                my $m = $testcase_mcdc->value($testcase);
                if ($m->value($line)) {
                    $traceInfo->test($testcase)->append($line, $hit);
                }
            }
        }
    }

    # also check branch data consistency...should not have non-zero branch hit
    # count if line is not hit - and vice versa
    my $checkBranchConsistency =
        !TraceFile::is_language('perl', $traceInfo->filename());
    if ($lcovutil::br_coverage) {
        my $brData = $traceInfo->sumbr();

        foreach my $line ($brData->keylist()) {
            # we expect to find a line everywhere there is a branch

            my $lineHit = $lineData->value($line);
            unless (defined($lineHit)) {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                      '"' . $traceInfo->filename() .
                          "\":$line: location has branchcov but no linecov data"
                          . _consistencySuffix());
            }

            my $brHit = 0;
            my $brd   = $brData->value($line);
            BLOCK: foreach my $id ($brd->blocks()) {
                my $block = $brd->getBlock($id);
                foreach my $br (@$block) {
                    if (0 != $br->count()) {
                        $brHit = 1;
                        last BLOCK;
                    }
                }
            }
            if (!defined($lineHit)) {
                # must have ignored the above error - so build fake line data here
                #  (maybe should delete the branch instead?)
                $lineData->append($line, $brHit);
                next;
            }
            if ($lineHit && !$brHit) {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                    '"' . $traceInfo->filename() .
                        "\":$line: line is hit but no branches on line have been evaluated."
                        . _consistencySuffix())
                    if $checkBranchConsistency;
            } elsif (!$lineHit && $brHit) {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                    '"' . $traceInfo->filename() .
                        "\":$line: line is not hit but at least one branch on line has been evaluated."
                        . _consistencySuffix());
            }
        }
    }

    # @todo expect to have a branch everywhere we have an MCDC -
    #  further, expect the number of branches and conditions to match

    my $end = Time::HiRes::gettimeofday();
    $lcovutil::profileData{check_consistency}{$traceInfo->filename()} =
        $end - $start;
    return $modified;
}

sub _filterFile
{
    my ($traceInfo, $source_file, $actions, $srcReader, $state) = @_;

    my $modified = 0;
    if (0 != ($actions & DID_DERIVE)) {
        $modified = _deriveFunctionEndLines($traceInfo);
        $modified ||= _checkConsistency($traceInfo);
        if (0 == ($actions & DID_FILTER)) {
            return [$traceInfo, $modified];
        }
    }
    # @todo: if MCDC has just one expression, then drop it -
    #  it is equivalent to branch coverage.
    my $region           = $cov_filter[$FILTER_EXCLUDE_REGION];
    my $branch_region    = $cov_filter[$FILTER_EXCLUDE_BRANCH];
    my $range            = $cov_filter[$lcovutil::FILTER_LINE_RANGE];
    my $branch_histogram = $cov_filter[$FILTER_BRANCH_NO_COND]
        if (is_language('c', $source_file));
    my $brace_histogram = $cov_filter[$FILTER_LINE_CLOSE_BRACE]
        if (is_language('c', $source_file));
    my $blank_histogram          = $cov_filter[$FILTER_BLANK_LINE];
    my $function_alias_histogram = $cov_filter[$FILTER_FUNCTION_ALIAS];
    my $trivial_histogram        = $cov_filter[$FILTER_TRIVIAL_FUNCTION];
    my $filter_initializer_list  = $cov_filter[$FILTER_INITIALIZER_LIST]
        if (is_language('c', $source_file));
    my $directive = $cov_filter[$FILTER_DIRECTIVE];
    my $omit      = $cov_filter[$FILTER_OMIT_PATTERNS]
        if defined($FILTER_OMIT_PATTERNS);
    my $mcdc_single = $cov_filter[$FILTER_MCDC_SINGLE]
        if defined($FILTER_MCDC_SINGLE && $lcovutil::mcdc_coverage);

    my $context = MessageContext->new("filtering $source_file");
    if (lcovutil::is_filter_enabled()) {
        lcovutil::info(1, "reading $source_file for lcov filtering\n");
        $srcReader->open($source_file);
    } else {
        $srcReader->close();
    }
    my $path = ReadCurrentSource::resolve_path($source_file);
    lcovutil::info(1, "extractVersion($path) for $source_file\n")
        if $path ne $source_file;
    # Note:  this is checking the version of the 'current' file - even if
    #   we are actually reading the baseline version.
    #   - This is what we want, as the 'baseline read' is actually recovering/
    #     recreating the baseline source from the current source and the diff.
    #   - We already checked that the diff and the coverage DB baseline/current
    #     version data is consistent - so filtering will be accurate as long as
    #     we see the right 'current' source version.
    my $fileVersion = lcovutil::extractFileVersion($path)
        if $srcReader->notEmpty();
    if (defined($fileVersion) &&
        defined($traceInfo->version())
        &&
        !lcovutil::checkVersionMatch($source_file, $traceInfo->version(),
                                     $fileVersion, 'filter')
    ) {
        lcovutil::info(1,
                      '$source_file: skip filtering due to version mismatch\n');
        return ($traceInfo, 0);
    }

    if (defined($lcovutil::func_coverage) &&
        (0 != scalar(@lcovutil::exclude_function_patterns) ||
            defined($trivial_histogram) ||
            defined($region))
    ) {
        # filter excluded function line ranges
        my $funcData   = $traceInfo->testfnc();
        my $lineData   = $traceInfo->test();
        my $branchData = $traceInfo->testbr();
        my $mcdcData   = $traceInfo->testcase_mcdc();
        my $checkData  = $traceInfo->check();
        my $reader     = (defined($trivial_histogram) || defined($region)) &&
            $srcReader->notEmpty() ? $srcReader : undef;

        foreach my $tn ($lineData->keylist()) {
            my $m =
                _eraseFunctions($source_file, $reader,
                                $funcData->value($tn), $lineData->value($tn),
                                $branchData->value($tn), $mcdcData->value($tn),
                                $checkData->value($tn), $state,
                                0);
            $modified ||= $m;
        }
        my $m =
            _eraseFunctions($source_file, $reader,
                            $traceInfo->func(), $traceInfo->sum(),
                            $traceInfo->sumbr(), $traceInfo->mcdc(),
                            $traceInfo->check(), $state,
                            1);
        $modified ||= $m;
    }

    return
        unless ($srcReader->notEmpty() &&
                lcovutil::is_filter_enabled());

    my $filterExceptionBranches = FilterBranchExceptions->new();

    my ($testdata, $sumcount, $funcdata, $checkdata, $testfncdata,
        $testbrdata, $sumbrcount, $mcdc, $testmcdc) = $traceInfo->get_info();

    foreach my $testname (sort($testdata->keylist())) {
        my $testcount    = $testdata->value($testname);
        my $testfnccount = $testfncdata->value($testname);
        my $testbrcount  = $testbrdata->value($testname);
        my $mcdc_count   = $testmcdc->value($testname);

        my $reason;
        my $functionMap = $testfncdata->{$testname};
        if ($lcovutil::func_coverage &&
            $functionMap &&
            ($region || $range)) {
            # Write function related data - sort  by line number

            foreach my $key ($functionMap->keylist()) {
                my $data = $functionMap->findKey($key);
                my $line = $data->line();

                my $remove;
                if ($srcReader->isOutOfRange($line, 'line')) {
                    $remove = 1;
                    lcovutil::info(1,
                                   "filter FN " . $data->name() .
                                       ' ' . $data->file() . ":$line\n");
                    ++$range->[-2];    # one location where this applied
                } elsif (0 != ($reason = $srcReader->isExcluded($line))) {
                    # we already warned about this one
                    next
                        if (0 != ($reason & $srcReader->e_UNREACHABLE) &&
                            0 != $data->hit() &&
                            $lcovutil::retainUnreachableCoverpointIfHit);

                    $remove = 1;
                    my $r = $srcReader->excludeReason($line);
                    foreach my $f ([ReadCurrentSource::EXCLUDE_REGION, $region],
                                   [ReadCurrentSource::OMIT_LINE, $omit]) {
                        if ($r & $f->[0]) {
                            $f->[1]->[-2] += scalar(keys %{$data->aliases()});
                            last;
                        }
                    }
                }
                if ($remove) {
                    #remove this function from everywhere
                    foreach my $tn ($testfncdata->keylist()) {
                        my $d = $testfncdata->value($tn);
                        my $f = $d->findKey($key);
                        next unless $f;
                        $d->remove($f);
                    }
                    # and remove from the master table
                    $funcdata->remove($funcdata->findKey($key));
                    $modified = 1;
                    next;
                }    # if excluded
            }    # foreach function
        }    # if func_coverage
             # $testbrcount is undef if there are no branches in the scope
        if (($lcovutil::br_coverage || $lcovutil::mcdc_coverage) &&
            (defined($testbrcount)  ||
                defined($mcdc_count)) &&
            ($branch_histogram ||
                $region                  ||
                $branch_region           ||
                $range                   ||
                $filterExceptionBranches ||
                $omit)
        ) {
            my %uniq;
            # check MC/DC lines which are not also branch lines
            foreach
                my $line (defined($mcdc_count) ? $mcdc_count->keylist() : (),
                         defined($testbrcount) ? $testbrcount->keylist() : ()) {
                next if exists($uniq{$line});
                $uniq{$line} = 1;

                # for counting: keep track filter which triggered exclusion -
                my $remove;
                # omit if line excluded or branches excluded on this line
                if ($srcReader->isOutOfRange($line, 'branch')) {
                    # only counting line coverpoints that got excluded
                    die("inconsistent state") unless $range;
                    $remove = $range;
                } elsif (
                     0 != (
                         $reason =
                             $srcReader->isExcluded($line, $srcReader->e_BRANCH)
                     )
                ) {
                    # all branches here
                    my $r = $srcReader->excludeReason($line);
                    foreach my $f ([ReadCurrentSource::EXCLUDE_REGION, $region],
                                   [ReadCurrentSource::OMIT_LINE, $omit],
                                   [ReadCurrentSource::EXCLUDE_DIRECTIVE,
                                    $directive
                                   ],
                                   [ReadCurrentSource::EXCLUDE_BRANCH_REGION,
                                    $branch_region
                                   ]
                    ) {
                        if ($r & $f->[0]) {
                            $remove = $f->[1];
                            last;
                        }
                    }
                    die("inconsistent reason $reason") unless $remove;
                } elsif ($branch_histogram &&
                         !$srcReader->containsConditional($line)) {
                    $remove = $branch_histogram;
                }
                if ($remove) {
                    foreach my $t ([$testbrdata, $sumbrcount, 'BRDA'],
                                   [$testmcdc, $mcdc, 'MCDC']) {
                        my ($testCount, $sumCount, $str) = @$t;
                        next unless $sumCount;
                        my $brdata = $sumCount->value($line);
                        # might not be MCDC here, even if there is a branch
                        next unless $brdata;

                        if ($reason &&
                            0 != ($reason & $srcReader->e_UNREACHABLE) &&
                            0 != ($brdata->totals())[1]) {
                            lcovutil::ignorable_error(
                                $lcovutil::ERROR_UNREACHABLE,
                                "\"$source_file\":$line: $str record in 'unreachable' region has non-zero hit count."
                            );
                            next
                                if $lcovutil::retainUnreachableCoverpointIfHit;
                        }
                        ++$remove->[-2];    # one line where we skip
                        $remove->[-1] += ($brdata->totals())[0];
                        lcovutil::info(2,
                                       "filter $str '"
                                           .
                                           ($line < $srcReader->numLines() ?
                                                $srcReader->getLine($line) :
                                                '<-->') .
                                           "' $source_file:$line\n");
                        # now remove this branch everywhere...
                        foreach my $tn ($testCount->keylist()) {
                            my $d = $testCount->value($tn);
                            $d->remove($line, 1);    # remove if present
                        }
                        # remove at top
                        $sumCount->remove($line);
                        $modified = 1;
                    }
                } elsif (defined($filterExceptionBranches) &&
                         defined($sumbrcount) &&
                         defined($sumbrcount->value($line))) {
                    # exclude exception branches here
                    my $m =
                        $filterExceptionBranches->filter($line, $srcReader,
                                  $sumbrcount, $testbrdata, $mcdc, $mcdc_count);
                    $modified ||= $m;
                }
            }    # foreach line
        }    # if branch_coverage
        if ($mcdc_single) {
            # find single-expression MC/DC's - if there is a matching branch
            #  expression on the same line, then remove the MC/DC
            foreach my $line ($mcdc_count->keylist()) {
                my $block  = $mcdc_count->value($line);
                my $groups = $block->groups();
                if (exists($groups->{1}) &&
                    scalar(keys %$groups) == 1) {
                    my $branch = $testbrcount->value($line);
                    next unless $branch && ($branch->totals())[0] == 2;
                    $mcdc_count->remove($line);
                    ++$mcdc_single->[-2];    # one MC/DC skipped

                    $mcdc->remove($line);    # remove at top
                    $modified = 1;
                }
            }
        }
        next
            unless $region    ||
            $range            ||
            $brace_histogram  ||
            $branch_histogram ||
            $directive        ||
            $omit             ||
            $filter_initializer_list;

        # Line related data
        my %initializerListRange;
        foreach my $line ($testcount->keylist()) {

            # warn about inconsistency if executed line is marked unreachable
            my $l_hit = $testcount->value($line);
            if ($l_hit &&
                0 != ($reason =
                          $srcReader->isExcluded(
                                             $line, $srcReader->e_UNREACHABLE, 1
                          )) &&
                0 != ($reason & $srcReader->e_UNREACHABLE)
            ) {
                lcovutil::ignorable_error($lcovutil::ERROR_UNREACHABLE,
                    "\"$source_file\":$line:  'unreachable' line has non-zero hit count."
                );
                next
                    if $lcovutil::retainUnreachableCoverpointIfHit;
            }

            # don't suppresss if this line has associated branch or MC/DC data
            next
                if (
                 (defined($sumbrcount) && defined($sumbrcount->value($line))) ||
                 (defined($mcdc_count) &&
                    defined($mcdc_count->value($line))));

            my $is_initializer;
            my $is_filtered = undef;
            if (exists($initializerListRange{$line})) {
                $is_initializer = 1;
                $is_filtered    = $filter_initializer_list;
                delete $initializerListRange{$line};
            } elsif ($filter_initializer_list) {
                # check if this line looks like a complete statement (balanced
                #   parens, ending with semicolon, etc -
                #   or whether subsequent lines are required for completion.
                #   If those subsequent lines have associated coverpoints,
                #   then those points should be filtered out (see issue #1222)
                my $count = $srcReader->is_initializerList($line);
                if (0 != $count) {
                    $is_initializer = 1;
                    $is_filtered    = $filter_initializer_list;
                    for (my $l = $line + $count - 1; $l > $line; --$l) {
                        # record start of range
                        $initializerListRange{$l} = $line;
                    }
                }
            }

            my $outOfRange = $srcReader->isOutOfRange($line, 'line')
                unless $is_filtered;
            $is_filtered = $lcovutil::cov_filter[$lcovutil::FILTER_LINE_RANGE]
                if !defined($is_filtered) &&
                defined($outOfRange) &&
                $outOfRange;
            my $excluded = $srcReader->isExcluded($line)
                unless $is_filtered;
            if (defined($excluded) && $excluded) {
                my $reason = $srcReader->excludeReason($line);
                foreach my $f ([ReadCurrentSource::EXCLUDE_REGION, $region],
                               [ReadCurrentSource::OMIT_LINE, $omit],
                               [ReadCurrentSource::EXCLUDE_DIRECTIVE,
                                $directive
                               ]
                ) {
                    if ($reason & $f->[0]) {
                        $is_filtered = $f->[1];
                        last;
                    }
                }
            }
            my $isCloseBrace =
                ($brace_histogram &&
                 $srcReader->suppressCloseBrace($line, $l_hit, $testcount))
                unless $is_filtered;
            $is_filtered = $brace_histogram
                if !defined($is_filtered) &&
                defined($isCloseBrace) &&
                $isCloseBrace;
            my $isBlank =
                ($blank_histogram &&
                 ($lcovutil::filter_blank_aggressive || $l_hit == 0) &&
                 $srcReader->isBlank($line))
                unless $is_filtered;
            $is_filtered = $blank_histogram
                if !defined($is_filtered) && defined($isBlank) && $isBlank;

            next unless $is_filtered;

            $modified = 1;
            lcovutil::info(2,
                           'filter DA (' . $is_filtered->[0] . ') '
                               .
                               ($line < $srcReader->numLines() ?
                                    ("'" . $srcReader->getLine($line) . "'") :
                                    "") .
                               " $source_file:$line\n");

            unless (defined($outOfRange) && $outOfRange) {
                # some filters already counted...
                ++$is_filtered->[-2];    # one location where this applied
                ++$is_filtered->[-1];    # one coverpoint suppressed
            }

            # now remove everywhere
            foreach my $tn ($testdata->keylist()) {
                my $d = $testdata->value($tn);
                $d->remove($line, 1);    # remove if present
            }
            $sumcount->remove($line);
            if (exists($checkdata->{$line})) {
                delete($checkdata->{$line});
            }
        }    # foreach line
    }    #foreach test
         # count the number of function aliases..
    if ($function_alias_histogram) {
        $function_alias_histogram->[-2] += $funcdata->numFunc(1);
        $function_alias_histogram->[-1] += $funcdata->numFunc(0);
    }
    return ($traceInfo, $modified);
}

sub _mergeParallelChunk
{
    # called from parent
    my ($self, $tmp, $child, $children, $childstatus, $store, $worklist,
        $childRetryCounts)
        = @_;

    my ($chunk, $forkAt, $chunkId) = @{$children->{$child}};
    my $dumped   = File::Spec->catfile($tmp, "dumper_$child");
    my $childLog = File::Spec->catfile($tmp, "filter_$child.log");
    my $childErr = File::Spec->catfile($tmp, "filter_$child.err");

    lcovutil::debug(1, "merge:$child ID $chunkId\n");
    my $start = Time::HiRes::gettimeofday();
    foreach my $f ($childLog, $childErr) {
        if (!-f $f) {
            $f = '';    # there was no output
            next;
        }
        if (open(RESTORE, "<", $f)) {
            # slurp into a string and eval..
            my $str = do { local $/; <RESTORE> };    # slurp whole thing
            close(RESTORE) or die("unable to close $f: $!\n");
            unlink $f;
            $f = $str;
        } else {
            $f = "unable to open $f: $!";
            if (0 == $childstatus) {
                lcovutil::report_parallel_error('filter',
                              $ERROR_PARALLEL, $child, 0, $f, keys(%$children));
            }
        }
    }
    my $signal = $childstatus & 0xFF;
    print(STDOUT $childLog)
        if ((0 != $childstatus &&
             $signal != POSIX::SIGKILL &&
             $lcovutil::max_fork_fails != 0) ||
            $lcovutil::verbose);
    print(STDERR $childErr);
    my $data = Storable::retrieve($dumped)
        if (-f $dumped && $childstatus == 0);
    if (defined($data)) {
        my ($updates, $save, $state, $childFinish, $update) = @$data;

        lcovutil::update_state(@$update);
        #my $childCpuTime = $lcovutil::profileData{filt_child}{$chunkId};
        #$totalFilterCpuTime    += $childCpuTime;
        #$intervalFilterCpuTime += $childCpuTime;

        my $now = Time::HiRes::gettimeofday();
        $lcovutil::profileData{filt_undump}{$chunkId} = $now - $start;

        foreach my $patType (@{$store->[0]}) {
            my $svType = shift(@{$save->[0]});
            foreach my $p (@$patType) {
                $p->[-1] += shift(@$svType);
            }
        }
        for (my $i = scalar(@{$store->[1]}) - 1; $i >= 0; --$i) {
            $store->[1]->[$i]->[-2] += $save->[1]->[$i]->[0];
            $store->[1]->[$i]->[-1] += $save->[1]->[$i]->[1];
        }
        foreach my $d (@$updates) {
            $self->_updateModifiedFile(@$d, $state);
        }

        my $final = Time::HiRes::gettimeofday();
        $lcovutil::profileData{filt_merge}{$chunkId} = $final - $now;
        $lcovutil::profileData{filt_queue}{$chunkId} = $start - $childFinish;

        #$intervalMonitor->checkUpdate($processedFiles);

    } else {
        if (!-f $dumped ||
            POSIX::SIGKILL == $signal) {

            if (exists($childRetryCounts->{$chunkId})) {
                $childRetryCounts->{$chunkId} += 1;
            } else {
                $childRetryCounts->{$chunkId} = 1;
            }
            lcovutil::report_fork_failure(
                           "filter segment $chunkId",
                           (POSIX::SIGKILL == $signal ?
                                "killed by OS - possibly due to out-of-memory" :
                                "serialized data $dumped not found"),
                           $childRetryCounts->{$chunkId});
            push(@$worklist, $chunk);
        } else {
            lcovutil::report_parallel_error('filter',
                                        $ERROR_PARALLEL, $child, $childstatus,
                                        "unable to filter segment $chunkId: $@",
                                        keys(%$children));
        }
    }
    foreach my $f ($dumped) {
        unlink $f
            if -f $f;
    }
    my $to = Time::HiRes::gettimeofday();
    $lcovutil::profileData{filt_chunk}{$chunkId} = $to - $forkAt;
}

sub _generate_end_line_message
{
    # don't generate gcov warnings for tools that don't use gcov
    return if grep({ /(llvm|perl|py|xml)2lcov/ } $lcovutil::tool_name);
    if (lcovutil::warn_once('compiler_version', 1)) {
        my $msg =
            'Function begin/end line exclusions not supported with this version of GCC/gcov; require gcc/9 or newer';
        if ((defined($lcovutil::derive_function_end_line) &&
             $lcovutil::derive_function_end_line != 0) ||
            (defined($lcovutil::derive_function_end_line_all_files) &&
                $lcovutil::derive_function_end_line_all_files != 0)
        ) {
            lcovutil::ignorable_warning($lcovutil::ERROR_UNSUPPORTED,
                $msg .
                    ": attempting to derive function end lines - see lcovrc man entry for 'derive_function_end_line'."
            );
        } else {
            lcovutil::ignorable_error($lcovutil::ERROR_UNSUPPORTED,
                     $msg .
                         ".  See lcovrc man entry for 'derive_function_end_line'."
            );
        }
    }
}

sub _updateModifiedFile
{
    my ($self, $name, $traceFile, $state) = @_;
    $self->[FILES]->{$name} = $traceFile;

    _generate_end_line_message()
        if $state->[0]->[1] != 0;
}

sub _processParallelChunk
{
    # called from child
    my $childStart = Time::HiRes::gettimeofday();
    my ($tmp, $chunk, $srcReader, $save, $state, $forkAt, $chunkId) = @_;
    # clear profile - want only my contribution
    my $currentState = lcovutil::initial_state();
    my $stdout_file  = File::Spec->catfile($tmp, "filter_$$.log");
    my $stderr_file  = File::Spec->catfile($tmp, "filter_$$.err");
    my $childInfo;
    # set count to zero so we know how many got created in
    # the child process
    my $now    = Time::HiRes::gettimeofday();
    my $status = 0;

    # clear current status so we see updates from this child
    # pattern counts
    foreach my $l (@{$save->[0]}) {
        foreach my $p (@$l) {
            $p->[-1] = 0;
        }
    }
    # filter counts
    foreach my $f (@{$save->[1]}) {
        $f->[-1] = 0;
        $f->[-2] = 0;
    }
    # using 'capture' here so that we can both capture/redirect geninfo
    #   messages from a child process during parallel execution AND
    #   redirect stdout/stderr from gcov calls.
    # It does not work to directly open/reopen the STDOUT and STDERR
    #   descriptors due to interactions between the child and parent
    #   processes (see the Capture::Tiny doc for some details)
    my $start = Time::HiRes::gettimeofday();
    my @updates;
    my ($stdout, $stderr, $code) = Capture::Tiny::capture {

        eval {
            foreach my $d (@$chunk) {
                # could keep track of individual file time if we wanted to
                my ($data, $modified) = _filterFile(@$d, $srcReader, $state);

                lcovutil::info(1,
                               $d->[1] . ' is ' .
                                   ($modified ? '' : 'NOT ') . "modified\n");
                if ($modified) {
                    push(@updates, [$d->[1], $data]);
                }
            }
        };
        if ($@) {
            print(STDERR $@);
            $status = 1;
        }
    };
    my $end = Time::HiRes::gettimeofday();
    # collect pattern counts
    my @pcounts;
    foreach my $l (@{$save->[0]}) {
        my @c = map({ $_->[-1] } @$l);    # grab the counts
        push(@pcounts, \@c);
    }
    $save->[0] = \@pcounts;
    # filter counts
    foreach my $f (@{$save->[1]}) {
        $f = [$f->[-2], $f->[-1]];
    }

    # parent might have already caught an error, cleaned up and
    #  removed the tempdir and exited.
    lcovutil::check_parent_process();

    # print stdout and stderr ...
    foreach my $d ([$stdout_file, $stdout], [$stderr_file, $stderr]) {
        next unless ($d->[1]);    # only print if there is something to print
        my $f = InOutFile->out($d->[0]);
        my $h = $f->hdl();
        print($h $d->[1]);
    }
    my $dumpf = File::Spec->catfile($tmp, "dumper_$$");
    my $then  = Time::HiRes::gettimeofday();
    $lcovutil::profileData{filt_proc}{$chunkId}  = $then - $forkAt;
    $lcovutil::profileData{filt_child}{$chunkId} = $end - $start;
    my $data;
    eval {
        $data = Storable::store([\@updates, $save, $state, $then,
                                 lcovutil::compute_update($currentState)
                                ],
                                $dumpf);
    };
    if ($@ || !defined($data)) {
        lcovutil::ignorable_error($lcovutil::ERROR_PARALLEL,
                              "Child $$ serialize failed" . ($@ ? ": $@" : ''));
    }
    return $status;
}

# chunkID is only used for uniquification and as a key in profile data.
#  We want this umber to be unique - even if we process more than one TraceFile
our $masterChunkID = 0;

sub _processFilterWorklist
{
    my ($self, $srcReader, $fileList) = @_;

    my $chunkSize;
    my $parallel = $lcovutil::lcov_filter_parallel;
    # not much point in parallel calculation if the number of files is small
    my $workList = $fileList;
    if (exists($ENV{LCOV_FORCE_PARALLEL}) ||
        (scalar(@$fileList) > 50 &&
            $parallel &&
            1 < $lcovutil::maxParallelism)
    ) {

        $parallel = $lcovutil::maxParallelism;

        if (defined($lcovutil::lcov_filter_chunk_size)) {
            if ($lcovutil::lcov_filter_chunk_size =~ /^(\d+)\s*(%?)$/) {
                if (defined($2) && $2) {
                    # a percentage
                    $chunkSize = int(scalar(@$fileList) * $1 / 100);
                } else {
                    # an absolute value
                    $chunkSize = $1;
                }
            } else {
                lcovutil::ignorable_warning($lcovutil::ERROR_FORMAT,
                    "lcov_filter_chunk_size '$lcovutil::lcov_filter_chunk_size not recognized - ignoring\n"
                );
            }
        }

        if (!defined($chunkSize)) {
            $chunkSize =
                $maxParallelism ?
                (int(0.8 * scalar(@$fileList) / $lcovutil::maxParallelism)) :
                1;
            if ($chunkSize > 100) {
                $chunkSize = 100;
            } elsif ($chunkSize < 2) {
                $chunkSize = 1;
            }
        }
        if ($chunkSize != 1 ||
            exists($ENV{LCOV_FORCE_PARALLEL})) {
            $workList = [];
            my $idx     = 0;
            my $current = [];
            # maybe sort files by number of lines, then distribute larger ones
            #   across chunks?  Or sort so total number of lines is balanced
            foreach my $f (@$fileList) {
                push(@$current, $f);
                if (++$idx == $chunkSize) {
                    $idx = 0;
                    push(@$workList, $current);
                    $current = [];
                }
            }
            push(@$workList, $current) if (@$current);
            lcovutil::info("Filter: chunkSize $chunkSize nChunks " .
                           scalar(@$workList) . "\n");
        }
    }

    my @state = (['saw_unsupported_end_line', 0],);
    # keep track of patterns application counts before we fork children
    my @pats = grep { @$_ }
        (\@lcovutil::exclude_function_patterns, \@lcovutil::omit_line_patterns);
    # and also filter application counts
    my @filters = grep { defined($_) } @lcovutil::cov_filter;
    my @save    = (\@pats, \@filters);

    my $processedChunks = 0;
    my $currentParallel = 0;
    my %children;
    my $tmp = File::Temp->newdir(
                          "filter_datXXXX",
                          DIR     => $lcovutil::tmp_dir,
                          CLEANUP => !defined($lcovutil::preserve_intermediates)
        )
        if (exists($ENV{LCOV_FORCE_PARALLEL}) ||
            $parallel > 1);

    my $failedAttempts = 0;
    my %childRetryCounts;
    do {
        CHUNK: while (@$workList) {
            my $d = pop(@$workList);
            ++$processedChunks;
            # save current counts...
            $state[0]->[1] = 0;
            if (ref($d->[0]) eq 'TraceInfo') {
                # serial processing...
                my ($data, $modified) = _filterFile(@$d, $srcReader, \@state);
                $self->_updateModifiedFile($d->[1], $data, \@state)
                    if $modified;
            } else {

                my $currentSize = 0;
                if (0 != $lcovutil::maxMemory) {
                    $currentSize = lcovutil::current_process_size();
                }
                while ($currentParallel >= $lcovutil::maxParallelism ||
                       ($currentParallel > 1 &&
                        (($currentParallel + 1) * $currentSize) >
                        $lcovutil::maxMemory)
                ) {
                    lcovutil::info(1,
                        "memory constraint ($currentParallel + 1) * $currentSize > $lcovutil::maxMemory violated: waiting.  "
                            . (scalar(@$workList) - $processedChunks + 1)
                            . " remaining\n")
                        if ((($currentParallel + 1) * $currentSize) >
                            $lcovutil::maxMemory);
                    my $child       = wait();
                    my $childstatus = $?;
                    unless (exists($children{$child})) {
                        lcovutil::report_unknown_child($child);
                        next;
                    }
                    eval {
                        $self->_mergeParallelChunk($tmp, $child, \%children,
                                                $childstatus, \@save, $workList,
                                                \%childRetryCounts);
                    };
                    if ($@) {
                        $childstatus = 1 << 8 unless $childstatus;
                        lcovutil::report_parallel_error('filter',
                              $lcovutil::ERROR_CHILD, $child, $childstatus, $@);
                    }
                    --$currentParallel;
                }

                # parallel processing...
                $lcovutil::deferWarnings = 1;
                my $now = Time::HiRes::gettimeofday();
                my $pid = fork();
                if (!defined($pid)) {
                    # fork failed
                    ++$failedAttempts;
                    lcovutil::report_fork_failure('process filter chunk',
                                                  $!, $failedAttempts);
                    --$processedChunks;
                    push(@$workList, $d);
                    next CHUNK;
                }
                $failedAttempts = 0;
                if (0 == $pid) {
                    # I'm the child
                    my $status =
                        _processParallelChunk($tmp, $d, $srcReader, \@save,
                                              \@state, $now, $masterChunkID);
                    exit($status);    # normal return
                } else {
                    # parent
                    $children{$pid} = [$d, $now, $masterChunkID];
                    lcovutil::debug(1, "fork:$pid ID $masterChunkID\n");
                    ++$currentParallel;
                }
                ++$masterChunkID;
            }

        }    # while (each segment in worklist)
        while ($currentParallel != 0) {
            my $child       = wait();
            my $childstatus = $?;
            unless (exists($children{$child})) {
                lcovutil::report_unknown_child($child);
                next;
            }
            --$currentParallel;
            eval {
                $self->_mergeParallelChunk($tmp, $child, \%children,
                           $childstatus, \@save, $workList, \%childRetryCounts);
            };
            if ($@) {
                $childstatus = 1 << 8 unless $childstatus;
                lcovutil::report_parallel_error('filter',
                              $lcovutil::ERROR_CHILD, $child, $childstatus, $@);
            }

        }
    } while (@$workList);    # outer do/while - to catch spaceouts
    lcovutil::info("Finished filter file processing\n");
}

sub applyFilters
{
    my $self      = shift;
    my $srcReader = shift;

    $srcReader = ReadCurrentSource->new()
        unless defined($srcReader);

    my $mask = DID_FILTER;
    $mask |= DID_DERIVE
        if (defined($lcovutil::derive_function_end_line) &&
            $lcovutil::derive_function_end_line != 0);
    return
        if ($mask == ($self->[STATE] & $mask));

    # have to look through each file in each testcase; they may be different
    # due to differences in #ifdefs when the corresponding tests were compiled.
    my @filter_workList;

    my $computeEndLine =
        (0 == ($self->[STATE] & DID_DERIVE) &&
         defined($lcovutil::derive_function_end_line) &&
         $lcovutil::derive_function_end_line != 0 &&
         defined($lcovutil::func_coverage));

    foreach my $name ($self->files()) {

        my $traceInfo = $self->data($name);
        die("expected TraceInfo, got '" . ref($traceInfo) . "'")
            unless ('TraceInfo' eq ref($traceInfo));
        my $source_file = $traceInfo->filename();
        if (TraceFile::skipCurrentFile($source_file)) {
            $self->remove($source_file);
            next;
        }
        if (lcovutil::is_external($source_file)) {
            lcovutil::info("excluding 'external' file '$source_file'\n");
            $self->remove($source_file);
            next;
        }
        # derive function end line for C/C++ and java code if requested
        # (not trying to handle python nested functions, etc.)
        # However, see indent handling in the py2lcov script.  Arguably, that
        #   could/should be done here/in Perl rather than in Python.)
        # Jacoco pretends to report function end line - but it appears
        #   to be the last line executed - not the actual last line of
        #   the function - so broken/completely useless.
        my $actions = 0;
        if ($computeEndLine &&
            ($lcovutil::derive_function_end_line_all_files ||
                is_language('c|java|perl', $source_file))
        ) {
            # try to derive end lines if at least one is unknown.
            #   can't compute for lambdas because we can't distinguish
            #   the last line reliably.
            $actions = DID_DERIVE
                if grep({ !($_->isLambda() || defined($_->end_line())) }
                        $traceInfo->func()->valuelist());
        }

        if ((defined($lcovutil::func_coverage) &&
             (0 != scalar(@lcovutil::exclude_function_patterns) ||
                 defined($lcovutil::cov_filter[$FILTER_TRIVIAL_FUNCTION]))) ||
            (is_language('c|perl|python|java', $source_file) &&
                lcovutil::is_filter_enabled())
        ) {
            # we are forking anyway - so also compute end lines there
            $actions |= DID_FILTER;
            push(@filter_workList, [$traceInfo, $name, $actions]);
        } else {
            if (0 != $actions) {
                # all we are doing is deriving function end lines - which doesn't
                # take long enough to be worth forking
                TraceFile::_deriveFunctionEndLines($traceInfo);
            }
            TraceFile::_checkConsistency($traceInfo);
        }

    }    # foreach file
    $self->[STATE] |= DID_DERIVE;

    if (@filter_workList) {
        lcovutil::info("Apply filtering..\n");
        $self->_processFilterWorklist($srcReader, \@filter_workList);
        # keep track - so we don't do this again
        $self->[STATE] |= DID_FILTER;
    }
}

sub is_language
{
    my ($lang, $filename) = @_;
    my $idx = index($filename, '.');
    my $ext = $idx == -1 ? '' : substr($filename, $idx);
    foreach my $l (split('\|', $lang)) {
        die("unknown language '$l'")
            unless exists($lcovutil::languageExtensions{$l});
        my $extensions = $lcovutil::languageExtensions{$l};
        return 1 if ($ext =~ /\.($extensions)$/);
    }
    return 0;
}

# Read in the contents of the .info file specified by INFO_FILENAME. Data will
# be returned as a reference to a hash containing the following mappings:
#
# %result: for each filename found in file -> \%data
#
# %data: "test"  -> \%testdata
#        "sum"   -> \%sumcount
#        "func"  -> \%funcdata
#        "found" -> $lines_found (number of instrumented lines found in file)
#        "hit"   -> $lines_hit (number of executed lines in file)
#        "function_found" -> $fn_found (number of instrumented functions found in file)
#        "function_hit"   -> $fn_hit (number of executed functions in file)
#        "branch_found" -> $br_found (number of instrumented branches found in file)
#        "branch_hit"   -> $br_hit (number of executed branches in file)
#        "check" -> \%checkdata
#        "testfnc" -> \%testfncdata
#        "testbr"  -> \%testbrdata
#        "sumbr"   -> \%sumbrcount
#
# %testdata   : name of test affecting this file -> \%testcount
# %testfncdata: name of test affecting this file -> \%testfnccount
# %testbrdata:  name of test affecting this file -> \%testbrcount
#
# %testcount   : line number   -> execution count for a single test
# %testfnccount: function name -> execution count for a single test
# %testbrcount : line number   -> branch coverage data for a single test
# %sumcount    : line number   -> execution count for all tests
# %sumbrcount  : line number   -> branch coverage data for all tests
# %funcdata    : FunctionMap: function name -> FunctionEntry
# %checkdata   : line number   -> checksum of source code line
# $brdata      : BranchData vector of items: block, branch, taken
#
# Note that .info file sections referring to the same file and test name
# will automatically be combined by adding all execution counts.
#
# Note that if INFO_FILENAME ends with ".gz", it is assumed that the file
# is compressed using GZIP. If available, GUNZIP will be used to decompress
# this file.
#
# Die on error.
#
sub _read_info
{
    my ($self, $tracefile, $readSourceCallback, $verify_checksum) = @_;
    $verify_checksum = 0 unless defined($verify_checksum);

    if (!defined($readSourceCallback)) {
        $readSourceCallback = ReadCurrentSource->new();
    }

    # per file data
    my %perfile;
    my $sumcount;      # line total counts in this file
    my $funcdata;      # function total counts in this file
    my $sumbrcount;    # branch total counts
    my $mcdcCount;     # MD/DC total counts

    my $checkdata;     # line checksums
    my %perTestData;
    my %summaryData;
    # hash of per-testcase coverage data per testcase, in this file
    my $testdata;      # hash of testname -> line coverage
    my $testfncdata;   # hash of testname -> function coverage
    my $testbrdata;    # hash of testname -> branch data
    my $testMcdc;      #     -> MC/DC data

    my $testcount;     # line coverage for particular testcase
    my $testfnccount;  # func coverage   "    "
    my $testbrcount;   # branch coverage "   "
    my $testcase_mcdc; # MC/DC coverage  "   "

    my $testname;            # Current test name
    my $filename;            # Current filename
    my $current_mcdc;
    my $changed_testname;    # If set, warn about changed testname

    lcovutil::info(1, "Reading data file $tracefile\n");

    # Check if file exists and is readable
    stat($tracefile);
    if (!(-r _)) {
        die("cannot read file $tracefile!\n");
    }

    # Check if this is really a plain file
    if (!(-f _)) {
        die("not a plain file: $tracefile!\n");
    }

    # Check for .gz extension
    my $inFile  = InOutFile->in($tracefile, $lcovutil::demangle_cpp_cmd);
    my $infoHdl = $inFile->hdl();

    $testname = "";
    my $fileData;
    # HGC:  somewhat of a hack.
    # There are duplicate lines in the geninfo output result - for example,
    #   line '2095' may have multiple DA (line) entries, and may have multiple
    #   'BRDA' entries - each with a different number of branches and different
    #   count
    # The hack is to put branches into a hash keyed by branch ID - and
    #   merge elements with the same key if we run into them in the multiple
    #   times in the same 'file' data (within an SF entry).
    my %nextBranchId;    # line -> integer ID
    my ($currentBranchLine, $skipBranch);
    my $functionMap;
    my %excludedFunction;
    my $skipCurrentFile = 0;
    my %fnIdxMap;
    while (<$infoHdl>) {
        chomp($_);
        my $line = $_;
        $line =~ s/\s+$//;    # whitespace

        next if $line =~ /^#/;    # skip comment

        if ($line =~ /^[SK]F:(.*)/) {
            # Filename information found
            if ($1 =~ /^\s*$/) {
                lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                    "\"$tracefile\":$.: unexpected empty file name in record '$line'"
                );
                $skipCurrentFile = 1;
                next;
            }
            #if ($self->contains($filename)) {
            #    # we expect there to be only one entry for each source file in each section
            #    lcovutil::ignorable_warning($lcovutil::ERROR_FORMAT,
            #                                  "Duplicate entries for \"$filename\""
            #                                  . ($testname ? " in testcase '$testname'" : '') . '.');
            #}
            $filename = ReadCurrentSource::resolve_path($1, 1);
            # should this one be skipped?
            $skipCurrentFile = skipCurrentFile($filename);
            if ($skipCurrentFile) {
                if (!exists($lcovutil::excluded_files{$filename})) {
                    $lcovutil::excluded_files{$filename} = 1;
                    lcovutil::info("Excluding $filename\n");
                }
                next;
            }

            # Retrieve data for new entry
            %nextBranchId     = ();
            %excludedFunction = ();
            %fnIdxMap         = ();

            if ($verify_checksum) {
                # unconditionally 'close' the current file - in case we don't
                #   open a new one.  If that happened, then we would be looking
                #   at the source for some previous file.
                $readSourceCallback->close();
                undef $currentBranchLine;
                if (is_language('c', $filename)) {
                    $readSourceCallback->open($filename);
                }
            }
            $fileData = $self->data($filename);
            # record line number where file entry found - can use it in error messages
            $fileData->location($tracefile, $.);
            ($testdata, $sumcount, $funcdata,
             $checkdata, $testfncdata, $testbrdata,
             $sumbrcount, $mcdcCount, $testMcdc) = $fileData->get_info();

            if (defined($testname)) {
                $testcount     = $fileData->test($testname);
                $functionMap   = $fileData->testfnc($testname);
                $testbrcount   = $fileData->testbr($testname);
                $testcase_mcdc = $fileData->testcase_mcdc($testname);
            } else {
                $testcount     = CountData->new($filename, 1);
                $testfnccount  = CountData->new($filename, 0);
                $testbrcount   = BranchData->new();
                $testcase_mcdc = MCDC_Data->new();
                $functionMap   = FunctionMap->new($filename);
            }
            next;
        }
        next if $skipCurrentFile;

        # Switch statement
        # Please note:  if you add or change something here (lcov info file format) -
        #   then please make corresponding changes to the 'write_info' method, below
        #   and update the format description found in .../man/geninfo.1.
        foreach ($line) {
            next if $line =~ /^#/;    # skip comment

            /^VER:(.+)$/ && do {
                # revision control version string found
                # we might try to set the version multiple times if the
                #  file appears multiple times in the .info file
                if (defined($fileData->version()) &&
                    $fileData->version() eq $1) {
                    # this is OK -
                    #  we might try to set the version multiple times if the
                    #  file appears multiple times in the .info file.
                    # This can happen, with some translators
                    last;
                }
                $fileData->version($1);
                last;
            };

            /^TN:([^,]*)(,diff)?/ && do {
                # Test name information found
                $testname = defined($1) ? $1 : "";
                my $orig = $testname;
                if ($testname =~ s/\W/_/g) {
                    $changed_testname = $orig;
                }
                $testname .= $2 if (defined($2));
                if (defined($ignore_testcase_name) &&
                    $ignore_testcase_name) {
                    lcovutil::debug(1,
                        "using default  testcase rather than $testname at $tracefile:$.\n"
                    );

                    $testname = '';
                }
                last;
            };

            /^DA:(\d+),([^,]+)(,([^,\s]+))?/ && do {
                my ($line, $count, $checksum) = ($1, $2, $4);
                if ($line <= 0) {
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: unexpected line number '$line' in .info file record '$_'"
                    );
                    # just keep invalid number - if error ignored
                    # last;
                }
                if ($readSourceCallback->notEmpty()) {
                    # does the source checksum match the recorded checksum?
                    if ($verify_checksum) {
                        if (defined($checksum)) {
                            my $content = $readSourceCallback->getLine($line);
                            my $chk =
                                defined($content) ?
                                Digest::MD5::md5_base64($content) :
                                0;
                            if ($chk ne $checksum) {
                                lcovutil::ignorable_error(
                                    $lcovutil::ERROR_VERSION,
                                    "checksum mismatch at between source $filename:$line and $tracefile: $checksum -> $chk"
                                );
                            }
                        } else {
                            # no checksum there
                            lcovutil::ignorable_error($lcovutil::ERROR_VERSION,
                                 "no checksum for $filename:$line in $tracefile"
                            );
                        }
                    }
                }

                # hold line, count and testname for postprocessing?
                my $linesum = $fileData->sum();

                # Execution count found, add to structure
                # Add summary counts
                $linesum->append($line, $count);

                # Add test-specific counts
                if (defined($testname)) {
                    $fileData->test($testname)->append($line, $count, 1);
                }

                # Store line checksum if available
                if (defined($checksum) &&
                    $lcovutil::verify_checksum) {
                    # Does it match a previous definition
                    if ($fileData->check()->mapped($line) &&
                        ($fileData->check()->value($line) ne $checksum)) {
                        lcovutil::ignorable_error($lcovutil::ERROR_VERSION,
                            "checksum mismatch at $filename:$line in $tracefile"
                        );
                    }
                    $fileData->check()->replace($line, $checksum);
                }
                last;
            };

            /^FN:(\d+),((\d+),)?(.+)$/ && do {
                last if (!$lcovutil::func_coverage);
                # Function data found, add to structure
                my $lineNo   = $1;
                my $fnName   = $4;
                my $end_line = $3;
                if (!grep({ $fnName =~ $_ }
                          @lcovutil::suppress_function_patterns) &&
                    ($lineNo <= 0 ||
                        (defined($end_line) && $end_line <= 0))
                ) {
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: unexpected function line '$lineNo' in .info file record '$_'"
                    ) if $lineNo <= 0;
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: unexpected function end line '$end_line' in .info file record '$_'"
                    ) if defined($end_line) && $end_line <= 0;
                }
                # the function may already be defined by another testcase
                #  (for the same file)
                $functionMap->define_function($fnName, $lineNo,
                                              $end_line ? $end_line : undef,
                                              , "\"$tracefile\":$.");
                last;
            };

            # Hit count may be float if Perl decided to convert it
            /^FNDA:([^,]+),(.+)$/ && do {
                last if (!$lcovutil::func_coverage);
                my $fnName = $2;
                my $hit    = $1;
                # error checking is in the addAlias method
                $functionMap->add_count($fnName, $hit);
                last;
            };

            # new format...
            /^FNL:(\d+),(\d+)(,(\d+))?$/ && do {
                last if (!$lcovutil::func_coverage);
                my $fnIndex  = $1;
                my $lineNo   = $2;
                my $end_line = $4;
                die("unexpected duplicate index $fnIndex")
                    if exists($fnIdxMap{$fnIndex});
                $fnIdxMap{$fnIndex} = [$lineNo, $end_line];
                last;
            };

            /^FNA:(\d+),([^,]+),(.+)$/ && do {
                last if (!$lcovutil::func_coverage);
                my $fnIndex = $1;
                my $hit     = $2;
                my $alias   = $3;
                die("unknown index $fnIndex")
                    unless exists($fnIdxMap{$fnIndex});
                my ($lineNo, $end_line) = @{$fnIdxMap{$fnIndex}};
                my $fn =
                    $functionMap->define_function($alias, $lineNo, $end_line,
                                                  "\"$tracefile\":$.");
                $fn->addAlias($alias, $hit);
                last;
            };

            /^BRDA:(\d+),(e?)(\d+),(.+)$/ && do {
                last if (!$lcovutil::br_coverage);

                # Branch coverage data found
                # line data is "lineNo,blockId,(branchIdx|branchExpr),taken
                #   - so grab the last two elements, split on the last comma,
                #     and check whether we found an integer or an expression
                my ($line, $is_exception, $block, $d) =
                    ($1, defined($2) && 'e' eq $2, $3, $4);

                if ($line <= 0) {
                    # Python coverage.py emits line number 0 (zero) for branches
                    #  - which is bogus, as there is no line number zero,
                    #    and the corresponding branch expression is not there in
                    #    any case.
                    # Meantime:  this confuses the lcov DB - so we simply skip
                    # such data.
                    # Note that we only need to check while reading .info files.
                    #   - if we wrote one from geninfo, then we will not have
                    #     produced bogus data - so no need to check.
                    #   - only some (broken) external tool could have the issue
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: unexpected line number '$line' in .info file record '$_'"
                    );
                    # just keep invalid line number if error ignored
                    # last;
                }

                last if $is_exception && $lcovutil::exclude_exception_branch;
                my $comma = rindex($d, ',');
                my $taken = substr($d, $comma + 1);
                my $expr  = substr($d, 0, $comma);

                # Notes:
                #   - there may be other branches on the same line (..the next
                #     contiguous BRDA entry).
                #     There should always be at least 2.
                #   - $block is generally '0' - but is used to distinguish cases
                #     where different branch constructs appear on the same line -
                #     e.g., due to template instantiation or funky macro usage -
                #     see .../tests/lcov/branch
                #   - $taken can be a number or '-'
                #     '-' means that the first clause of the branch short-circuited -
                #     so this branch was not evaluated at all.
                #     In any branch pair, either all should have a 'taken' of '-'
                #     or at least one should have a non-zero taken count and
                #     the others should be zero.
                #   - in order to support Verilog expressions, we treat the
                #     'branchId' as an arbitrary string (e.g., ModelSim will
                #     generate an CNF or truth-table like entry corresponding
                #     to the branch.

                my $key = "$line,$block";
                my $branch =
                    exists($nextBranchId{$key}) ? $nextBranchId{$key} :
                    0;
                $nextBranchId{$key} = $branch + 1;

                my $br =
                    BranchBlock->new($branch, $taken, $expr, $is_exception);
                $fileData->sumbr()->append($line, $block, $br, $filename);

                # Add test-specific counts
                if (defined($testname)) {
                    $fileData->testbr($testname)
                        ->append($line, $block, $br, $filename);
                }
                last;
            };

            /^MCDC:(\d+),(\d+),([tf]),(\d+),(\d+),(.+)$/ && do {
                # line number, groupSize, sense, count, index, expression
                # 'sense' is t/f: was this expression sensitized
                last unless $lcovutil::mcdc_coverage;

                my ($line, $groupSize, $sense, $count, $idx, $expr) =
                    ($1, $2, $3, $4, $5, $6);
                if ($line <= 0) {
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: unexpected line number '$line' in condition data record '$_'."
                    );
                    # keep invalid line number
                    #last;
                }

                if (!defined($current_mcdc) ||
                    $current_mcdc->line() != $line) {
                    if ($current_mcdc) {
                        $fileData->mcdc()->close_mcdcBlock($current_mcdc);

                        $fileData->testcase_mcdc($testname)
                            ->append_mcdc(Storable::dclone($current_mcdc))
                            if (defined($testname));
                    }
                    $current_mcdc =
                        $fileData->mcdc()->new_mcdc($fileData, $line);
                }
                $current_mcdc->insertExpr($filename, $groupSize, $sense eq 't',
                                          $count, $idx, $expr);
                last;
            };

            /^end_of_record/ && do {
                # Found end of section marker
                if ($filename) {
                    if (!defined($fileData->version()) &&
                        $lcovutil::compute_file_version &&
                        @lcovutil::extractVersionScript) {
                        my $version = lcovutil::extractFileVersion($filename);
                        $fileData->version($version)
                            if (defined($version) && $version ne "");
                    }
                    if ($lcovutil::func_coverage) {

                        if ($funcdata != $functionMap) {
                            $funcdata->union($functionMap);
                        }
                    }
                    if ($current_mcdc) {
                        # close the current expression in case the next file
                        # has an expression on the same line
                        $fileData->mcdc()->close_mcdcBlock($current_mcdc);
                        $fileData->testcase_mcdc($testname)
                            ->append_mcdc(Storable::dclone($current_mcdc))
                            if (defined($testname));
                        $current_mcdc = undef;
                    }

                    # some paranoic checks
                    $self->data($filename)->check_data();
                    last;
                }
            };
            /^(FN|BR|L|MC)[HF]/ && do {
                last;    # ignore count records
            };
            /^\s*$/ && do {
                last;    # ignore empty line
            };

            lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: unexpected .info file record '$_'");
            # default
            last;
        }
    }

    # Calculate lines_found and lines_hit for each file
    foreach $filename ($self->files()) {
        #$data = $result{$filename};

        ($testdata, $sumcount, undef, undef, $testfncdata, $testbrdata,
         $sumbrcount) = $self->data($filename)->get_info();

        # Filter out empty files
        if ($self->data($filename)->sum()->entries() == 0) {
            delete($self->[FILES]->{$filename});
            next;
        }
        my $filedata = $self->data($filename);
        # Filter out empty test cases
        foreach $testname ($filedata->test()->keylist()) {
            if (!$filedata->test()->mapped($testname) ||
                scalar($filedata->test($testname)->keylist()) == 0) {
                $filedata->test()->remove($testname);
                $filedata->testfnc()->remove($testname);
                $filedata->testbr()->remove($testname);
                $filedata->testcase_mcdc()->remove($testname);
            }
        }
    }

    if (scalar($self->files()) == 0) {
        lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                              "no valid records found in tracefile $tracefile");
    }
    if (defined($changed_testname)) {
        lcovutil::ignorable_warning($lcovutil::ERROR_FORMAT,
                    "invalid characters removed from testname in " .
                        "tracefile $tracefile: '$changed_testname'->'$testname'\n"
        );
    }
}

# write data to filename (stdout if '-')
# returns nothing
sub write_info_file($$$)
{
    my ($self, $filename, $do_checksum) = @_;

    if ($self->empty()) {
        lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                                  "coverage DB is empty");
    }
    my $file = InOutFile->out($filename);
    my $hdl  = $file->hdl();
    $self->write_info($hdl, $do_checksum);
}

#
# write data in .info format
# returns array of (lines found, lines hit, functions found, functions hit,
#                   branches found, branches_hit)

sub write_info($$$)
{
    my $self = $_[0];
    local *INFO_HANDLE = $_[1];
    my $verify_checksum = defined($_[2]) ? $_[2] : 0;
    my $br_found;
    my $br_hit;

    my $srcReader = ReadCurrentSource->new()
        if ($verify_checksum);
    foreach my $comment ($self->comments()) {
        print(INFO_HANDLE '#', $comment, "\n");
    }
    foreach my $filename (sort($self->files())) {
        my $entry       = $self->data($filename);
        my $source_file = $entry->filename();
        die("expected to have have filtered $source_file out")
            if lcovutil::is_external($source_file);
        die("expected TraceInfo, got '" . ref($entry) . "'")
            unless ('TraceInfo' eq ref($entry));

        my ($testdata, $sumcount, $funcdata,
            $checkdata, $testfncdata, $testbrdata,
            $sumbrcount, $sum_mcdc, $testmcdc) = $entry->get_info();
        # munge the source file name, if requested
        $source_file = ReadCurrentSource::resolve_path($source_file, 1);

        # Please note:  if you add or change something here (lcov info file format) -
        #   then please make corresponding changes to the '_read_info' method, above
        #   and update the format description found in .../man/geninfo.1.
        foreach my $testname (sort($testdata->keylist())) {
            my $testcount    = $testdata->value($testname);
            my $testfnccount = $testfncdata->value($testname);
            my $testbrcount  = $testbrdata->value($testname);
            my $mcdc         = $testmcdc->value($testname);

            print(INFO_HANDLE "TN:$testname\n");
            print(INFO_HANDLE "SF:$source_file\n");
            print(INFO_HANDLE "VER:" . $entry->version() . "\n")
                if defined($entry->version());
            if (defined($srcReader)) {
                lcovutil::info(1, "reading $source_file for lcov checksum\n");
                $srcReader->open($source_file);
            }

            my $functionMap = $testfncdata->{$testname};
            if ($lcovutil::func_coverage &&
                $functionMap) {
                # Write function related data - sort  by line number then
                #  by name (compiler-generated functions may have same line)
                # sort enables diff of output data files, for testing
                my @functionOrder =
                    sort({ $functionMap->findKey($a)->line()
                                 cmp $functionMap->findKey($b)->line() or
                                 $a cmp $b } $functionMap->keylist());

                my $fnIndex = -1;
                my $f_found = 0;
                my $f_hit   = 0;
                foreach my $key (@functionOrder) {
                    my $data    = $functionMap->findKey($key);
                    my $aliases = $data->aliases();
                    my $line    = $data->line();

                    if ($line <= 0) {
                        my $alias = (sort keys %$aliases)[0];
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$source_file\": unexpected line number '$line' for function $alias"
                        );
                        # if message is ignored, leave bogus entry in the data
                    }
                    ++$fnIndex;
                    my $endLine =
                        defined($data->end_line()) ?
                        ',' . $data->end_line() :
                        '';
                    # print function leader
                    print(INFO_HANDLE "FNL:$fnIndex,$line$endLine\n");
                    ++$f_found;
                    my $counted = 0;
                    foreach my $alias (sort keys %$aliases) {
                        my $hit = $aliases->{$alias};
                        ++$f_hit if $hit > 0 && !$counted;
                        $counted ||= $hit > 0;
                        # print the alias
                        print(INFO_HANDLE "FNA:$fnIndex,$hit,$alias\n");
                    }
                }
                print(INFO_HANDLE "FNF:$f_found\n");
                print(INFO_HANDLE "FNH:$f_hit\n");
            }
            # $testbrcount is undef if there are no branches in the scope
            if ($lcovutil::br_coverage &&
                defined($testbrcount)) {
                # Write branch related data
                my $br_found = 0;
                my $br_hit   = 0;

                foreach my $line (sort({ $a <=> $b } $testbrcount->keylist())) {

                    if ($line <= 0) {
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$source_file\": unexpected line number '$line' in branch data record."
                        );
                        # keep bogus data if error ignored
                        # last;
                    }
                    my $brdata = $testbrcount->value($line);
                    # want the block_id to be treated as 32-bit unsigned integer
                    #  (need masking to match regression tests)
                    my $mask = (1 << 32) - 1;
                    foreach my $block_id (sort(($brdata->blocks()))) {
                        my $blockData = $brdata->getBlock($block_id);
                        $block_id &= $mask;
                        foreach my $br (@$blockData) {
                            my $taken       = $br->data();
                            my $branch_id   = $br->id();
                            my $branch_expr = $br->expr();
                            # mostly for Verilog:  if there is a branch expression: use it.
                            printf(INFO_HANDLE "BRDA:%u,%s%u,%s,%s\n",
                                   $line,
                                   $br->is_exception() ? 'e' : '',
                                   $block_id,
                                   defined($branch_expr) ? $branch_expr :
                                       $branch_id,
                                   $taken);
                            $br_found++;
                            $br_hit++
                                if ($taken ne '-' && $taken > 0);
                        }
                    }
                }
                if ($br_found > 0) {
                    print(INFO_HANDLE "BRF:$br_found\n");
                    print(INFO_HANDLE "BRH:$br_hit\n");
                }
            }
            if ($mcdc &&
                $lcovutil::mcdc_coverage) {

                my $mcdc_found = 0;
                my $mcdc_hit   = 0;
                foreach my $line (sort({ $a <=> $b } $mcdc->keylist())) {
                    if ($line <= 0) {
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$source_file\": unexpected line number '$line' in MC/DC data record."
                        );
                    }
                    my $m      = $mcdc->value($line);
                    my $groups = $m->groups();
                    foreach my $groupSize (sort keys %$groups) {
                        my $exprs = $groups->{$groupSize};
                        my $index = -1;
                        foreach my $e (@$exprs) {
                            $mcdc_found += 2;
                            ++$index;
                            foreach my $sense ('t', 'f') {
                                my $count = $e->count($sense eq 't');
                                ++$mcdc_hit if 0 != $count;
                                print(INFO_HANDLE
                                     "MCDC:$line,$groupSize,$sense,$count,$index,"
                                     . $e->expression(),
                                 "\n");
                            }
                        }
                    }
                }
                if ($mcdc_found != 0) {
                    print(INFO_HANDLE "MCF:$mcdc_found\n");
                    print(INFO_HANDLE "MCH:$mcdc_hit\n");
                }
            }
            # Write line related data
            my $found = 0;
            my $hit   = 0;
            foreach my $line (sort({ $a <=> $b } $testcount->keylist())) {
                if ($line <= 0) {
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$source_file\": unexpected line number '$line' in 'line' data record."
                    );
                }
                my $l_hit = $testcount->value($line);
                my $chk   = '';
                if ($verify_checksum) {
                    if (exists($checkdata->{$line})) {
                        $chk = $checkdata->{$line};
                    } elsif (defined($srcReader) &&
                             $srcReader->notEmpty()) {
                        my $content = $srcReader->getLine($line);
                        $chk =
                            defined($content) ?
                            Digest::MD5::md5_base64($content) :
                            0;
                    }
                    $chk = ',' . $chk if ($chk);
                }
                print(INFO_HANDLE "DA:$line,$l_hit$chk\n");
                $found++;
                $hit++
                    if ($l_hit > 0);
            }
            print(INFO_HANDLE "LF:$found\n");
            print(INFO_HANDLE "LH:$hit\n");
            print(INFO_HANDLE "end_of_record\n");
        }
    }
}

package AggregateTraces;
# parse sna merge TraceFiles - possibly in parallel
#  - common utility, used by lcov 'add_trace' and genhtml multi-file read

# If set, create map of unique function to list of testcase/info
#   files which hit that function at least once
our $function_mapping;
# need a static external segment index lest the exe aggregate multiple groups of data
our $segmentIdx = 0;

sub find_from_glob
{
    my @merge;
    die("no files specified") unless (@_);
    foreach my $pattern (@_) {

        if (-f $pattern) {
            # this is a glob match...
            push(@merge, $pattern);
            next;
        }
        $pattern =~ s/([^\\]) /$1\\ /g          # explicitly escape spaces
            unless $^O =~ /Win/;

        my @files = glob($pattern);   # perl returns files in ASCII sorted order

        lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                                  "no files matching pattern $pattern")
            unless scalar(@files);
        for (my $i = 0; $i <= $#files; ++$i) {
            my $f = $files[$i];
            if (-d $f) {
                my $cmd =
                    "find '$f' -name '$lcovutil::info_file_pattern' -type f";
                my ($stdout, $stderr, $code) = Capture::Tiny::capture {
                    system($cmd);
                };
                # can fail due to unreadable entry - but might still
                #  have returned data to process
                lcovutil::ignorable_error($lcovutil::ERROR_UTILITY,
                                          "error in \"$cmd\": $stderr")
                    if $code;
                my @found = split(' ', $stdout);
                lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                    "no files matching '$lcovutil::info_file_pattern' found in $f"
                ) unless (@found);
                push(@files, @found);
                next;
            }

            unless (-r $f || -f $f) {
                lcovutil::ignorable_error($lcovutil::ERROR_MISSING,
                     "'$f' found from pattern '$pattern' is not a readable file"
                );
                next;
            }
            push(@merge, $f);
        }
    }
    lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                        "no matching file found in '['" . join(', ', @_) . "]'")
        unless (@merge);

    return @merge;
}

sub _process_segment($$$)
{
    my ($total_trace, $readSourceFile, $segment) = @_;

    my @interesting;
    my $total = scalar(@$segment);
    foreach my $tracefile (@$segment) {
        my $now = Time::HiRes::gettimeofday();
        --$total;
        lcovutil::info("Merging $tracefile..$total remaining"
                           .
                           ($lcovutil::debug ?
                                (' mem:' . lcovutil::current_process_size()) :
                                '') .
                           "\n"
        ) if (1 != scalar(@$segment));    # ...in segment $segId
        my $context = MessageContext->new("merging $tracefile");
        if (!-f $tracefile ||
            -z $tracefile) {
            lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                                      "trace file '$tracefile' "
                                          .
                                          (-z $tracefile ? 'is empty' :
                                               'does not exist'));
            next;
        }
        my $current;
        eval {
            $current = TraceFile->load($tracefile, $readSourceFile,
                                       $lcovutil::verify_checksum, 1);
            lcovutil::debug("after load $tracefile: memory: " .
                            lcovutil::current_process_size() . "\n")
                if $lcovutil::debug;    # predicate to avoid function call...
        };
        my $then = Time::HiRes::gettimeofday();
        $lcovutil::profileData{parse}{$tracefile} = $then - $now;
        if ($@) {
            lcovutil::ignorable_error($lcovutil::ERROR_CORRUPT,
                                  "unable to read trace file '$tracefile': $@");
            next;
        }
        if ($function_mapping) {
            foreach my $srcFileName ($current->files()) {
                my $traceInfo = $current->data($srcFileName);
                my $funcData  = $traceInfo->func();
                foreach my $funcKey ($funcData->keylist()) {
                    my $funcEntry = $funcData->findKey($funcKey);
                    if (0 != $funcEntry->hit()) {
                        # function is hit in this file
                        my $key = $funcEntry->file() . ":$funcKey";
                        $function_mapping->{$key} = [$funcEntry->name(), []]
                            unless exists($function_mapping->{$key});
                        die("mismatched function name for " .
                            $funcEntry->name() .
                            " at $funcKey in $tracefile")
                            unless $funcEntry->name() eq
                            $function_mapping->{$key}->[0];
                        push(@{$function_mapping->{$key}->[1]}, $tracefile);
                    }
                }
            }
        } else {
            if ($total_trace->merge_tracefile($current, TraceInfo::UNION)) {
                push(@interesting, $tracefile);
            }
        }
        my $end = Time::HiRes::gettimeofday();
        $lcovutil::profileData{append}{$tracefile} = $end - $then;
    }
    return @interesting;
}

sub merge
{
    my $readSourceFile;
    my $t = ref($_[0]);
    if (!defined($_[0]) || '' eq $t) {
        # backward compatibility - arg is undefined or is a filename
        $readSourceFile = ReadCurrentSource->new();
        shift unless defined($_[0]);
    } else {
        $readSourceFile = shift;
        die("unexpected arg $t")
            unless grep(/^$t$/, ('ReadCurrentSource', 'ReadBaselineSource'));
    }
    my $nTests = scalar(@_);
    if (1 < $nTests) {
        lcovutil::info("Combining tracefiles.\n");
    } else {
        lcovutil::info("Reading tracefile $_[0].\n");
    }

    $lcovutil::profileData{parse} = {}
        unless exists($lcovutil::profileData{parse});
    $lcovutil::profileData{append} = {}
        unless exists($lcovutil::profileData{append});

    my @effective;
    # source-based filters are somewhat expensive - so we turn them
    #   off for file read and only re-enable when we write the data back out
    my $save_filters = lcovutil::disable_cov_filters();

    my $total_trace = TraceFile->new();
    if (!(defined($lcovutil::maxParallelism) && defined($lcovutil::maxMemory)
    )) {
        lcovutil::init_parallel_params();
    }
    if (0 != $lcovutil::maxMemory &&
        1 != $lcovutil::maxParallelism) {
        # estimate the number of processes we think we can run..
        my $currentSize = lcovutil::current_process_size();
        # guess that the data size is no smaller than one of the files we will be reading
        # which one is largest?
        my $fileSize = 0;
        foreach my $n (@_) {
            my $s = (stat($n))[7];
            $fileSize = $s if $s > $fileSize;
        }
        my $size = $currentSize + $fileSize;
        my $num  = int($lcovutil::maxMemory / $size);
        lcovutil::debug(
            "Sizes: self:$currentSize file:$fileSize total:$size num:$num paralled:$lcovutil::maxParallelism\n"
        );
        if ($num < $lcovutil::maxParallelism) {
            $num = $num > 1 ? $num : 1;
            lcovutil::info(
                  "Throttling to '--parallel $num' due to memory constraint\n");
            $lcovutil::maxParallelism = $num;
        }
    }
    # use a particular file sort order - to somewhat minimize order effects
    my $filelist = \@_;
    my @sorted_filelist;
    if ($lcovutil::sort_inputs) {
        @sorted_filelist = sort({ $a cmp $b } @_);
        $filelist        = \@sorted_filelist;
    }

    if (1 != $lcovutil::maxParallelism &&
        (exists($ENV{LCOV_FORCE_PARALLEL}) ||
            1 < $nTests)
    ) {
        # parallel implementation is to segment the file list into N
        #  segments, then parse-and-merge scalar(@merge)/N files in each slave,
        #  then merge the slave result.
        # The reasoning is that one of our examples appears to take 1.3s to
        #   load the trace file, and 0.8s to merge it into the master list.
        # We thus want to parallelize both the load and the merge, as much as
        #   possible.
        # Note that we try to keep the files in the order they were specified
        #   in the segments (i.e., so adjacent files go in order, into the same
        #   segment).  This plays more nicely with the "--prune-tests" option
        #   because we expect that files with similar names (e.g., as returned
        #   by 'glob' have similar coverage profiles and are thus not likely to
        #   all be 'effective'.  If we had put them into different segments,
        #   then each segment might think that their variant is 'effective' -
        #   whereas we will notice that only one is effective if they are all
        #   in the same segment.

        my @segments;
        my $testsPerSegment =
            ($nTests > $lcovutil::maxParallelism) ?
            int(($nTests + $lcovutil::maxParallelism - 1) /
                $lcovutil::maxParallelism) :
            1;
        my $idx = 0;
        foreach my $tracefile (@$filelist) {
            my $seg = $idx / $testsPerSegment;
            $seg -= 1 if $seg == $lcovutil::maxParallelism;
            push(@segments, [])
                if ($seg >= scalar(@segments));
            push(@{$segments[$seg]}, $tracefile);
            ++$idx;
        }
        lcovutil::info("Using " .
                       scalar(@segments) .
                       ' segment' . (scalar(@segments) > 1 ? 's' : '') .
                       " of $testsPerSegment test" .
                       ($testsPerSegment > 1 ? 's' : '') . "\n");
        $lcovutil::profileData{config} = {}
            unless exists($lcovutil::profileData{config});
        $lcovutil::profileData{config}{segments} = scalar(@segments);

        # kind of a hack...write to the named directory that the user gave
        #   us rather than to a funny generated name
        my $tempDir = defined($lcovutil::tempdirname) ? $lcovutil::tempdirname :
            lcovutil::create_temp_dir();
        my %children;
        my @pending;
        my $patterns;
        my $failedAttempts = 0;
        my %childRetryCounts;
        do {
            while (my $segment = pop(@segments)) {
                $lcovutil::deferWarnings = 1;
                my $now = Time::HiRes::gettimeofday();
                my $pid = fork();
                if (!defined($pid)) {
                    ++$failedAttempts;
                    lcovutil::report_fork_failure('process segment',
                                                  $!, $failedAttempts);
                    push(@segments, $segment);
                    next;
                }
                $failedAttempts = 0;

                if (0 == $pid) {
                    # I'm the child
                    my $stdout_file =
                        File::Spec->catfile($tempDir, "lcov_$$.log");
                    my $stderr_file =
                        File::Spec->catfile($tempDir, "lcov_$$.err");

                    my $currentState = lcovutil::initial_state();
                    my $status       = 0;
                    my @interesting;
                    my ($stdout, $stderr, $code) = Capture::Tiny::capture {
                        eval {
                            @interesting =
                                _process_segment($total_trace,
                                                 $readSourceFile, $segment);
                        };
                        if ($@) {
                            print(STDERR $@);
                            $status = 1;
                        }

                        my $then = Time::HiRes::gettimeofday();
                        $lcovutil::profileData{$segmentIdx}{total} =
                            $then - $now;
                    };
                    # print stdout and stderr ...
                    foreach
                        my $d ([$stdout_file, $stdout], [$stderr_file, $stderr])
                    {
                        next
                            unless ($d->[1])
                            ;    # only print if there is something to print
                        my $f = InOutFile->out($d->[0]);
                        my $h = $f->hdl();
                        print($h $d->[1]);
                    }
                    my $file = File::Spec->catfile($tempDir, "dumper_$$");
                    my $data;
                    eval {
                        $data =
                            Storable::store(
                                        [$total_trace,
                                         \@interesting,
                                         $function_mapping,
                                         lcovutil::compute_update($currentState)
                                        ],
                                        $file);
                    };
                    if ($@ || !defined($data)) {
                        lcovutil::ignorable_error($lcovutil::ERROR_PARALLEL,
                              "Child $$ serialize failed" . ($@ ? ": $@" : ''));
                    }
                    exit($status);
                } else {
                    $children{$pid} = [$now, $segmentIdx, $segment];
                    push(@pending, $segment);
                }
                $segmentIdx++;
            }
            # now wait for all the children to finish...
            foreach (@pending) {
                my $child       = wait();
                my $now         = Time::HiRes::gettimeofday();
                my $childstatus = $? >> 8;
                unless (exists($children{$child})) {
                    lcovutil::report_unknown_child($child);
                    next;
                }
                my ($start, $idx, $segment) = @{$children{$child}};
                lcovutil::info(
                          1,
                          "Merging segment $idx, status $childstatus"
                              .
                              (
                              $lcovutil::debug ?
                                  (' mem:' . lcovutil::current_process_size()) :
                                  '') .
                              "\n");
                my $dumpfile = File::Spec->catfile($tempDir, "dumper_$child");
                my $childLog = File::Spec->catfile($tempDir, "lcov_$child.log");
                my $childErr = File::Spec->catfile($tempDir, "lcov_$child.err");

                foreach my $f ($childLog, $childErr) {
                    if (!-f $f) {
                        $f = '';    # there was no output
                        next;
                    }
                    if (open(RESTORE, "<", $f)) {
                        # slurp into a string and eval..
                        my $str =
                            do { local $/; <RESTORE> };    # slurp whole thing
                        close(RESTORE) or die("unable to close $f: $!\n");
                        unlink $f
                            unless ($str && $lcovutil::preserve_intermediates);
                        $f = $str;
                    } else {
                        $f = "unable to open $f: $!";
                        if (0 == $childstatus) {
                            lcovutil::report_parallel_error('aggregate',
                                                 $ERROR_PARALLEL, $child, 0, $f,
                                                 keys(%children));
                        }
                    }
                }
                my $signal = $childstatus & 0xFF;

                print(STDOUT $childLog)
                    if ((0 != $childstatus &&
                         $signal != POSIX::SIGKILL &&
                         $lcovutil::max_fork_fails != 0) ||
                        $lcovutil::verbose);
                print(STDERR $childErr);

                # undump the data
                my $data = Storable::retrieve($dumpfile)
                    if (-f $dumpfile && 0 == $childstatus);
                if (defined($data)) {
                    eval {
                        my ($current, $changed, $func_map, $update) = @$data;
                        my $then = Time::HiRes::gettimeofday();
                        $lcovutil::profileData{$idx}{undump} = $then - $now;
                        lcovutil::update_state(@$update);
                        if ($function_mapping) {
                            if (!defined($func_map)) {
                                lcovutil::report_parallel_error(
                                    'aggregate',
                                    $ERROR_PARALLEL,
                                    $child,
                                    0,
                                    "segment $idx returned empty function data",
                                    keys(%children));
                                next;
                            }
                            while (my ($key, $data) = each(%$func_map)) {
                                $function_mapping->{$key} = [$data->[0], []]
                                    unless exists($function_mapping->{$key});
                                die("mismatched function name '" .
                                    $data->[0] . "' at $key")
                                    unless ($data->[0] eq
                                            $function_mapping->{$key}->[0]);
                                push(@{$function_mapping->{$key}->[1]},
                                     @{$data->[1]});
                            }
                        } else {
                            if (!defined($current)) {
                                lcovutil::report_parallel_error(
                                    'aggregate',
                                    $ERROR_PARALLEL,
                                    $child,
                                    0,
                                    "segment $idx returned empty trace data",
                                    keys(%children));
                                next;
                            }
                            if ($total_trace->merge_tracefile(
                                                      $current, TraceInfo::UNION
                            )) {
                                # something in this segment improved coverage...so save
                                #   the effective input files from this one
                                push(@effective, @$changed);
                            }
                        }
                    };    # end eval
                    if ($@) {
                        $childstatus = 1 << 8 unless $childstatus;
                        lcovutil::report_parallel_error(
                            'aggregate',
                            $ERROR_PARALLEL,
                            $child,
                            $childstatus,
                            "unable to deserialize segment $idx $dumpfile:$@",
                            keys(%children));
                    }
                }
                if (!defined($data) || 0 != $childstatus) {
                    if (!-f $dumpfile ||
                        POSIX::SIGKILL == $signal) {

                        if (exists($childRetryCounts{$idx})) {
                            $childRetryCounts{$idx} += 1;
                        } else {
                            $childRetryCounts{$idx} = 1;
                        }
                        lcovutil::report_fork_failure(
                             "aggregate segment $idx",
                             (POSIX::SIGKILL == $signal ?
                                  "killed by OS - possibly due to out-of-memory"
                              :
                                  "serialized data $dumpfile not found"),
                             $childRetryCounts{$idx});
                        push(@segments, $segment);
                    } else {

                        lcovutil::report_parallel_error('aggregate',
                                             $ERROR_CHILD, $child, $childstatus,
                                             "while processing segment $idx",
                                             keys(%children));
                    }
                }
                my $end = Time::HiRes::gettimeofday();
                $lcovutil::profileData{$idx}{merge} = $end - $start;
                unlink $dumpfile
                    if -f $dumpfile;
            }
        } while (@segments);
    } else {
        # sequential
        @effective = _process_segment($total_trace, $readSourceFile, $filelist);
    }
    if (defined($lcovutil::tempdirname) &&
        !$lcovutil::preserve_intermediates) {
        # won't remove if directory not empty...probably what I want, for debugging
        rmdir($lcovutil::tempdirname);
    }
    #...and turn any enabled filters back on...
    lcovutil::reenable_cov_filters($save_filters);
    # filters had been disabled - need to explicitly exclude function bodies
    $total_trace->applyFilters($readSourceFile);

    return ($total_trace, \@effective);
}

# call the common initialization functions

lcovutil::define_errors();
lcovutil::init_filters();

1;
