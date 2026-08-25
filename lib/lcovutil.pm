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
use IO::Handle;    # 'input_line_number' - see 'TraceFile::_read_info'
use Devel::StackTrace;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw($tool_name $tool_dir $lcov_version $lcov_url $VERSION
     @temp_dirs set_tool_name
     info warn_once set_info_callback init_verbose_flag $verbose
     debug $debug
     append_tempdir create_temp_dir temp_cleanup $tmp_dir $default_tmp_dir
     $preserve_intermediates
     summarize_messages define_errors
     parse_ignore_errors ignorable_error ignorable_warning
     is_ignored message_count explain_once
     die_handler warn_handler abort_handler

     $maxParallelism $maxMemory init_parallel_params current_process_size
     $memoryPercentage $max_fork_fails $fork_fail_timeout
     save_profile merge_child_profile save_cmd_line record_profile_memory

     @opt_rc apply_rc_params $split_char parseOptions
     strip_directories
     @file_subst_patterns subst_file_name
     @comments

     $br_coverage $func_coverage $mcdc_coverage
     @cpp_demangle do_mangle_check $demangle_cpp_cmd
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
     warn_pattern_list
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

# get_version.sh lives beside the tools in bin/, so $tool_dir finds it whenever
# we are loaded by one of them.  When we are loaded some other way - a
# diagnostic one-liner, or lib/LcovUtil/Makefile.PL deriving the error ids -
# $FindBin::RealBin is the caller's directory instead, and running the script
# from there would print a bare 'No such file or directory' to stderr and leave
# $VERSION empty.  Look beside this file as well before giving up, so the
# version is right and nothing is logged in either case.
#
# Keep the '$VERSION =' assignment on one line:  'make install' runs bin/fix.pl,
# which replaces the remainder of that line with a literal version string.
sub _find_version
{
    foreach my $dir ($tool_dir,
                     File::Spec->catdir(File::Basename::dirname(
                                                   File::Spec->rel2abs(__FILE__)
                                        ),
                                        File::Spec->updir(),
                                        'bin')
    ) {
        my $script = File::Spec->catfile($dir, 'get_version.sh');
        return `"$script" --full` if -x $script;
    }
    return '';
}
our $VERSION = _find_version();
chomp($VERSION);
our $lcov_version = 'LCOV version ' . $VERSION;
our $lcov_url     = "https://github.com/linux-test-project/lcov";
our @temp_dirs;
# The parent directory that temporary/intermediate data is written under:
#   every consumer creates a uniquely named subdirectory of it rather than
#   writing here directly.  Set by the rc option 'lcov_tmp_dir' or by
#   '--tempdir'.  Default is whatever the platform says:  $TMPDIR, $TEMP or
#   $TMP if one of them names a writeable directory, else '/tmp' on Unix or
#   'C:\temp' on Windows.
our $tmp_dir         = File::Spec->tmpdir();
our $default_tmp_dir = $tmp_dir;    # so 'lcov' knows whether to pass it on
our $created_tmp_dir;               # set if we created '$tmp_dir'
our $preserve_intermediates;        # this is useful only for debugging
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
# list of callbacks which support save/restore
our @callback_save_restore;
# list of callbacks which support 'finalize'
our @callback_finalize;
# list of callbacks which implement 'start' - which gets called when
#  child process starts
our @callback_start_list;
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

# version extract may be expensive - so only do it once
our %versionCache;
our @extractVersionScript;    # script/callback to find version ID of file
our $versionCallback;
our $verify_checksum;    # compute and/or check MD5 sum of source code lines
our $compute_file_version
    ;    # enable per-file version computation via version_script

our $check_file_existence_before_callback = 1;
our $check_data_consistency               = 1;

# Specify coverage rate default precision
our $default_precision = 1;

# undef indicates not set by command line or RC option - so default to
# sequential processing
our $maxParallelism;
our $max_fork_fails    = 5;     # consecutive failures
our $fork_fail_timeout = 10;    # how long to wait, in seconds
# Fault injection for the parallel failure paths - see 'fork_child', and
#   'ForkManager::fork_one' for the one which makes the dump fail.  These are
#   environment variables rather than options because they are only used
#   by the regression framework so we can test various failure and recovery
#   paths - "fork() failed", "the OS killed my child", "that process was
#   not mine", etc. - which are otherwise reachable only if something
#   bad actually happens on the machine (out of process slots, exhausted
#   system memory - or whatever).  That isn't repeatable - so isn't
#   otherwise testable.
our $forceForkFail =
    exists($ENV{LCOV_FORCE_FORK_FAIL}) ? $ENV{LCOV_FORCE_FORK_FAIL} : 0;
our $forceChildKill =
    exists($ENV{LCOV_FORCE_CHILD_KILL}) ? $ENV{LCOV_FORCE_CHILD_KILL} : 0;
our $forceNoDump =
    exists($ENV{LCOV_FORCE_NO_DUMP}) ? $ENV{LCOV_FORCE_NO_DUMP} : 0;
our $forceOrphan =
    exists($ENV{LCOV_FORCE_ORPHAN}) ? $ENV{LCOV_FORCE_ORPHAN} : 0;
our $forceOomMsg =
    exists($ENV{LCOV_FORCE_OOM_MSG}) ? $ENV{LCOV_FORCE_OOM_MSG} : 0;
our $forceBadData =
    exists($ENV{LCOV_FORCE_BAD_DATA}) ? $ENV{LCOV_FORCE_BAD_DATA} : 0;
our $forceStoreFail =
    exists($ENV{LCOV_FORCE_STORE_FAIL}) ? $ENV{LCOV_FORCE_STORE_FAIL} : 0;
our $maxMemory;    # zero indicates no memory limit to parallelism
our $memoryPercentage;
our $in_child_process   = 0;
our $max_tasks_per_core = 20;    # maybe default to 0?

# This process's job label - '<phase>_<jobId>', or '' in the top-level parent -
#   and the prefix which a worker forked from HERE must qualify its own job id
#   with, so that a job id is unique across the whole run.
# The qualification is needed because the per-worker job id counters (e.g.
#   $TraceFile::masterChunkID) are ordinary process globals which fork() copies,
#   and a forked worker can itself fork workers:  an lcov aggregate segment and
#   a geninfo capture chunk each filter their own data in parallel.  Two sibling
#   children which each fork a filter worker would otherwise both call it chunk
#   0, and their profile data would collide when merged back into the parent.
#   Qualified, the two are 'aggregate_0_0' and 'aggregate_1_0'.
# Both are set by initial_state();  the label is what record_profile_memory()
#   keys the per-job memory by, and the id is what the per-job timing data is
#   keyed by, so that memory{filter_aggregate_0_0} still lines up with
#   filt_child{aggregate_0_0}.  In the top-level parent the prefix is empty, so
#   the ids there are the plain numbers they have always been.
# Note that unique does not mean reported only once:  a job whose worker died is
#   rescheduled under the same id, and each attempt reports.  The durations of
#   the attempts are summed and their peak memory maxed - see
#   merge_child_profile() and merge_profile_memory().
our $jobLabel    = '';
our $jobIdPrefix = '';

# A file predicted to run at least this long (seconds) is given its own
#   dedicated segment (and scheduled first) rather than being batched behind
#   up to $max_tasks_per_core other files - so a single very large file does
#   not serialize the tail of a parallel genhtml run.
# The prediction is exact when '--history-script' profile data is available;
#   otherwise it is estimated from the instrumented-line count (see
#   $dedicate_segment_line_estimate) and only for files large enough to matter.
our $dedicate_segment_threshold = 5;    # seconds; 0 disables the feature
# When no history is available, treat a file with at least this many
#   instrumented lines as "large" and estimate its runtime as
#   (lines / this) seconds - i.e. this is a rough lines-per-second rate that
#   also serves as the minimum size below which we never bother estimating.
our $dedicate_segment_line_estimate = 50000;
# geninfo analog of the above:  at scheduling time the .gcno/.gcda files have
#   not been parsed yet, so the only non-history signal for how much work a
#   compilation unit will take is its on-disk size.  A history-less coverage
#   file at least this large (bytes) is given its own dedicated *forked* chunk
#   (scheduled first) so a single huge CU does not serialize the tail of a
#   parallel geninfo run.  0 disables the feature.
# NOTE: this is distinct from '--large-file', which runs a matching file
#   serially in the parent to avoid a memory spaceout - a memory-safety knob,
#   not a latency one.  A file matched by '--large-file' is never also given a
#   dedicated forked chunk.
our $dedicate_segment_size = 50000000;    # 50 MB

our $lcov_filter_parallel = 1;            # enable by default
our $lcov_filter_chunk_size;

# 'AggregateTraces::merge' otherwise divides its inputs by file:  one child per
#   input file, so a single input is read serially no matter how large it is, and
#   a set of them is divided by file count rather than by work.  A large enough
#   set is instead scanned for its 'end_of_record' boundaries and split into
#   chunks - each of which may span several of the inputs - read by several
#   children at once; see 'TraceFile::scan_sections' and
#   'AggregateTraces::_parallel_parse'.
# The unit is lines rather than bytes because lines are the better predictor of
#   parse time:  measured across captures of one project at three cover levels,
#   lines/second varied by 1.10x where MB/second varied by 1.83x (a 'DA:' record
#   averages 10 bytes and a 'BRDA:'/'MCDC:' record 20, but since the record
#   dispatch below is a tag lookup they cost nearly the same to read).
# The count is the total over every input, because that is the work being
#   divided:  many small inputs are split when their sum is large enough, and
#   none of them would be on its own.
# The default is roughly 3x the measured break-even point:  below ~3 MB on 32
#   cores the pre-scan and the forks cost more than the parse they save.  0
#   disables the feature.
our $parallel_parse_min_lines = 500000;
# Chunks per worker.  More chunks than workers costs nothing and buys two
#   things:  a shorter tail (the last chunk to finish is 1/this of a worker's
#   share rather than all of it), and a bound on how much of the parsed data is
#   resident in children at once - with this many chunks per worker the parse
#   phase peak is (final data + 1/this of it) rather than twice the final data.
our $parallel_parse_chunks_per_worker = 4;

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
# merge functions which appear on same file/line - guess that
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

# should we ignore exclusion tags in the input .info file or not
# by default: do not ignore
# we don't expect user to want to change - so only changed via the RC file
our $ignore_unreachable_flag = 0;

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
                 'EUC' => 'white',     # use same background as boring text
                 'ECC' => 'white',
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
                     'EUC' => 'black',
                     'ECC' => 'black',
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
our $profile;    # the 'enable' flag/name of output file
# historical profile - optimize performance by somewhat carefully sorting
# job list - use callback mechanism to provide more configurable support
# for complex build environments
our @profileHistoryCallback;
our $profileHistoryCallback;

our @excludeCoverpointCallback;
our $excludeCoverpointCallback;

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
    # '--preserve' means the user wants to look at the intermediate data, so
    #   leave everything where it is.  'create_temp_dir' already told
    #   'File::Temp' not to clean up; this is the second half of that.
    return if $lcovutil::preserve_intermediates;
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
    if (defined($created_tmp_dir)) {
        # We made the parent, so delete it if it is empty.
        #   'rmdir' rather than 'rmtree' so that anything we did not put there
        #   survives.
        rmdir($created_tmp_dir);
        $created_tmp_dir = undef;
    }
}

END {
    # Get here on fatal error which doesn't get to 'temp_cleanup()'
    # if we created '$tmp_dir' and it is empty: delete.
    #   'rmdir' rather than 'rmtree', so this fails harmlessly if
    #   anything is still there - which is what happens on the
    #   normal path, where 'temp_cleanup' has already done the job.
    rmdir($created_tmp_dir)
        if (defined($created_tmp_dir) &&
            !$preserve_intermediates &&
            !$in_child_process);
}

#
# create_tmp_dir()
#
# Make sure '$tmp_dir' - the parent that all the generated temp directories
#   are created under - exists.  Called once, from 'parseOptions', so that
#   every tool behaves the same way whether the directory came from
#   '--tempdir' or from the rc option 'lcov_tmp_dir'.
#

sub create_tmp_dir()
{
    my $err;
    if (!-d $tmp_dir) {
        # remember that it was ours, so 'temp_cleanup' can remove it again
        $created_tmp_dir = $tmp_dir;
        # 'error' makes 'make_path' collect the reason instead of dying, so that
        #   an unwriteable parent is one usage error rather than an unhandled
        #   'mkdir' failure
        File::Path::make_path($tmp_dir, {error => \$err});
    }
    if (!-d $tmp_dir) {
        my $why = $!;
        if ($err && @$err) {
            my (undef, $msg) = %{$err->[0]};
            $why = $msg if $msg;
        }
        ignorable_error($ERROR_USAGE,
                       "unable to create temporary directory '$tmp_dir': $why");
    } elsif (!-w $tmp_dir) {
        ignorable_error($ERROR_USAGE,
                        "temporary directory '$tmp_dir' is not writeable");
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

    my $details = $ENV{LCOV_SHOW_LOCATION}
        if exists($ENV{LCOV_SHOW_LOCATION});

    $msg =~ s/ at \S+ line \d+\.$//
        unless ($debug || $verbose > 0 || defined($details));
    # stacktrace in developer mode if LCOV_SHOW_LOCATION set to 2 or higher
    $msg .=
        ("\n" ne substr($msg, -1) ? "\n" : '') .
        Devel::StackTrace->new->as_string
        if (defined($error) && $error > 1 && defined($details) && $details > 1);

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
    die(_msg_handler(@_, 2));
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

# Return this process's peak memory as ($peakRss, $peakVsize) in bytes, from
# the kernel high-water marks VmHWM (peak resident set) and VmPeak (peak
# virtual size).  These are true lifetime peaks, unlike current_process_size()
# which samples the instantaneous virtual size.  Returns (0,0) when the kernel
# does not expose them (e.g. non-Linux); callers must tolerate that.
sub read_proc_peak_memory
{
    if (open(PROC, "<", '/proc/self/status')) {
        my ($rss, $vsize) = (0, 0);
        while (<PROC>) {
            if (/^VmHWM:\s+(\d+)\s+kB/) {
                $rss = $1 * 1024;
            } elsif (/^VmPeak:\s+(\d+)\s+kB/) {
                $vsize = $1 * 1024;
            }
            last if $rss && $vsize;
        }
        close(PROC) or die("unable to close /proc/self/status: $!\n");
        return ($rss, $vsize);
    } else {
        # not fatal - memory profiling is best-effort
        return (0, 0);
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

# Record this process's peak memory into the profile data under
#   $profileData{memory}{$who} = { rss => ..., vsize => ..., pid => ... }
# so that --profile output carries a per-process memory breakdown (both peak
# resident-set and peak virtual size) alongside the per-phase timing.
#
# $who identifies the job rather than the process: 'parent' for the top-level
# process, and otherwise the same job/segment id the timing data is keyed by,
# so that memory{'segment_26'} lines up with child{26} and segment{26} in the
# same profile.  Because the numeric id spaces of the different worker kinds
# overlap (geninfo uses child{N} for capture chunks and filt_child{N} for
# filter workers, with the same N), the id must be prefixed with its phase --
# and, for a worker which was itself forked by a worker, with the label of the
# job which forked it, so that the label is unique across the whole run:  see
# $jobIdPrefix.  The pid is retained as a field for fork debugging; it is
# deliberately NOT the key, since it conveys nothing about which job ran.
#
# Best-effort: does nothing when profiling is disabled or the kernel does not
# expose the peaks (read_proc_peak_memory returns 0,0).
sub record_profile_memory
{
    my $who = shift // 'parent';
    return unless defined($lcovutil::profile);
    my ($rss, $vsize) = read_proc_peak_memory();
    return unless ($rss || $vsize);    # not available (non-Linux) - skip
    merge_profile_memory($lcovutil::profileData{memory}{$who} //= {},
                         {rss => $rss, vsize => $vsize, pid => $$});
}

# Fold one memory entry into another, keeping the larger of each peak.
#
# Job labels are unique across the run (see $jobIdPrefix), so this is not the
# place that resolves a namespace collision.  What it does handle is a job which
# legitimately ran more than once:  a worker which died - killed by the OS for
# running out of memory, say - is rescheduled under the same job id, so both
# attempts report their peak.  Neither number is wrong and the interesting one
# is the largest, so take the max.  (The corresponding durations are summed - see
# the additive key list in merge_child_profile.)  The 'pid' is informational
# only - keep the one belonging to the larger peak.
sub merge_profile_memory
{
    my ($slot, $add) = @_;
    if (!defined($slot->{rss}) || ($add->{rss} // 0) > $slot->{rss}) {
        $slot->{pid} = $add->{pid} if exists($add->{pid});
    }
    foreach my $k ('rss', 'vsize') {
        next unless defined($add->{$k});
        $slot->{$k} = $add->{$k}
            if (!defined($slot->{$k}) || $slot->{$k} < $add->{$k});
    }
    $slot->{pid} = $add->{pid} if (!defined($slot->{pid}) && $add->{pid});
}

sub merge_child_profile($)
{
    my $profile = shift;
    while (my ($key, $d) = each(%$profile)) {
        if ('HASH' eq ref($d)) {
            while (my ($f, $t) = each(%$d)) {
                if ('HASH' eq ref($t)) {
                    if ($key eq 'memory') {
                        # a job which was rescheduled after its worker died
                        # reports its peak once per attempt - keep the largest,
                        # rather than treating it as a duplicate key.  See
                        # merge_profile_memory.
                        merge_profile_memory(
                                        $lcovutil::profileData{$key}{$f} //= {},
                                        $t);
                        next;
                    }
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
                                 'filt_proc', 'filt_child',
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
        # Which implementation of the coverage data classes actually ran:  1 if
        # the C++ XS extension loaded, 0 if we fell back to (or were forced to)
        # pure Perl.  The fallback is silent and affects only speed, so a
        # profile with unexpectedly long times is otherwise hard to explain.
        $lcovutil::profileData{config}{xs} = $lcovutil::XS_LOADED ? 1 : 0;
        foreach my $var ('USER', 'HOSTNAME', 'MACHTYPE', 'PWD') {
            $lcovutil::profileData{config}{$var} = $ENV{$var}
                if exists($ENV{$var});
        }
        foreach my $t ('date', 'uname -a', 'hostname') {
            my $v = `$t`;
            chomp($v);
            $lcovutil::profileData{config}{(split(' ', $t))[0]} = $v;
        }
        my $save = $maxParallelism;
        count_cores();
        $lcovutil::profileData{config}{cores} = $maxParallelism;
        $maxParallelism = $save;

        # record the parent process's own peak memory, then publish top-level
        # peaks (max over the parent and every worker that reported one) for
        # easy consumption by profile readers: peakRss (physical) and
        # peakVsize (virtual), both in bytes.  Note that only the 'rss' and
        # 'vsize' fields are folded into the max - the per-entry 'pid' is
        # informational only.
        record_profile_memory('parent');
        if (exists($lcovutil::profileData{memory})) {
            my ($peakRss, $peakVsize) = (0, 0);
            foreach my $m (values(%{$lcovutil::profileData{memory}})) {
                $peakRss = $m->{rss}
                    if (defined($m->{rss}) && $m->{rss} > $peakRss);
                $peakVsize = $m->{vsize}
                    if (defined($m->{vsize}) && $m->{vsize} > $peakVsize);
            }
            $lcovutil::profileData{memoryPeak} = {
                                                  rss   => $peakRss,
                                                  vsize => $peakVsize
            };
        }

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
            close(PROF) or die("unable to close $html: $!");
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
            $lcovutil::cpp_demangle[0] = 'c++filt';
        }
    }
    # Extra flag necessary on OS X so that symbols listed by gcov get demangled
    # properly.
    push(@lcovutil::cpp_demangle, '--no-strip-underscores')
        if ($^O eq "darwin");

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
            die("callback constructor returned 'undef'")
                unless defined($$cb);
            if (exists($ENV{LCOV_FORCE_PARALLEL}) ||
                (defined($lcovutil::maxParallelism) &&
                    1 != $lcovutil::maxParallelism)
            ) {
                # don't set up for parallel processing if we aren't going to fork
                if ($$cb->can('save')) {
                    if ($$cb->can('restore')) {
                        push(@callback_save_restore, [$class, $$cb]);
                        push(@callback_start_list, [$class, $$cb])
                            if ($$cb->can('start'));
                    } else {
                        lcovutil::ignorable_error($lcovutil::ERROR_PACKAGE,
                                 "$class implements 'save' but not 'restore'.");
                        return;
                    }
                }
            }
            # implement 'finalize', regardless of parallel/not parallel
            push(@callback_finalize, [$class, $$cb])
                if ($$cb->can('finalize'));
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
    push(@configured_callbacks, $cb)
        if defined($$cb);
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
            die('unexpected context callback result: expected hash ref')
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
my (@rc_filter, @rc_ignore,
    @rc_exclude_patterns, @rc_include_patterns,
    @rc_subst_patterns, @rc_omit_patterns,
    @rc_erase_patterns, @rc_version_script,
    @unsupported_config, @rc_source_directories,
    @rc_build_dir, %unsupported_rc,
    $keepGoing, $help,
    @rc_resolveCallback, @rc_excludeCoverpointCallback,
    @rc_expected_msg_counts, @rc_criteria_script,
    @rc_contextCallback, $rc_no_branch_coverage,
    $rc_no_func_coverage, $rc_no_checksum,
    $version);
my $quiet = 0;

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
                     'lcov_func_coverage'          => "function_coverage",
                     'lcov_br_coverage'            => 'branch_coverage');

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
             "ignore_unreachable_flag" => \$lcovutil::ignore_unreachable_flag,
             "ignore_errors"           => \@rc_ignore,
             "max_message_count"       => \$lcovutil::suppressAfter,
             "message_log"             => \$lcovutil::message_log,
             'expected_message_count'  => \@rc_expected_msg_counts,
             'stop_on_error'           => \$lcovutil::stop_on_error,
             'treat_warning_as_error'  => \$lcovutil::treat_warning_as_error,
             'warn_once_per_file'      => \$lcovutil::warn_once_per_file,
             'check_data_consistency'  => \$lcovutil::check_data_consistency,
             "rtl_file_extensions"     => \$rtlExtensions,
             "c_file_extensions"       => \$cExtensions,
             "perl_file_extensions"    => \$perlExtensions,
             "python_file_extensions"  => \$pythonExtensions,
             "java_file_extensions"    => \$javaExtensions,
             'info_file_pattern'       => \$info_file_pattern,
             "filter_lookahead"        => \$lcovutil::source_filter_lookahead,
             "filter_bitwise_conditional" =>
        \$lcovutil::source_filter_bitwise_are_conditional,
             'filter_blank_aggressive' => \$filter_blank_aggressive,
             "profile"                 => \$lcovutil::profile,
             "parallel"                => \$lcovutil::maxParallelism,
             "memory"                  => \$lcovutil::maxMemory,
             "memory_percentage"       => \$lcovutil::memoryPercentage,
             "max_fork_fails"          => \$lcovutil::max_fork_fails,
             "max_tasks_per_core"      => \$lcovutil::max_tasks_per_core,
             "dedicate_segment_threshold" => \$lcovutil::dedicate_segment_threshold,
             "dedicate_segment_line_estimate" =>
        \$lcovutil::dedicate_segment_line_estimate,
             'parallel_parse_min_lines' => \$lcovutil::parallel_parse_min_lines,
             'parallel_parse_chunks_per_worker' =>
        \$lcovutil::parallel_parse_chunks_per_worker,
             "fork_fail_timeout" => \$lcovutil::fork_fail_timeout,
             'source_directory'  => \@rc_source_directories,
             'build_directory'   => \@rc_build_dir,

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
             'criteria_script'    => \@rc_criteria_script,
             'unreachable_script' => \@rc_excludeCoverpointCallback,

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
our $rc_auto_base    = 1;
our $rc_intermediate = "auto";
our $geninfo_captureAll;    # look for both .gcda and lone .gcno files

our %geninfo_rc_opts = (
                  "geninfo_gcov_tool"         => \@rc_gcov_tool,
                  "geninfo_adjust_testname"   => \$geninfo_adjust_testname,
                  "geninfo_compat_libtool"    => \$opt_compat_libtool,
                  "geninfo_external"          => \$opt_external,
                  "geninfo_follow_symlinks"   => \$opt_follow,
                  "geninfo_follow_file_links" => \$opt_follow_file_links,
                  "geninfo_gcov_all_blocks"   => \$opt_gcov_all_blocks,
                  "geninfo_unexecuted_blocks" => \$opt_adjust_unexecuted_blocks,
                  "geninfo_compat"            => \$geninfo_opt_compat,
                  "geninfo_auto_base"         => \$rc_auto_base,
                  "geninfo_intermediate"      => \$rc_intermediate,
                  'geninfo_chunk_size'        => \$defaultChunkSize,
                  'geninfo_dedicate_segment_size' => \$dedicate_segment_size,
                  'geninfo_interval_update'       => \$defaultInterval,
                  'geninfo_capture_all'           => \$geninfo_captureAll);

our %argCommon = ("tempdir=s"         => \$lcovutil::tmp_dir,
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

                  'resolve-script=s'     => \@lcovutil::resolveCallback,
                  'context-script=s'     => \@lcovutil::contextCallback,
                  'unreachable-script=s' =>
                      \@lcovutil::excludeCoverpointCallback,
                  "filter=s"               => \@opt_filter,
                  "demangle-cpp:s"         => \@lcovutil::cpp_demangle,
                  "ignore-errors=s"        => \@opt_ignore_errors,
                  "expect-message-count=s" => \@opt_expected_message_counts,
                  'msg-log:s'              => \$message_log,
                  "keep-going"             => \$keepGoing,
                  "config-file=s"          => \@unsupported_config,
                  "rc=s%"                  => \%unsupported_rc,
                  "profile:s"              => \$lcovutil::profile,
                  'history-script=s'  => \@lcovutil::profileHistoryCallback,
                  "exclude=s"         => \@lcovutil::exclude_file_patterns,
                  "include=s"         => \@lcovutil::include_file_patterns,
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
    push(@deferred_rc_errors,
         [1,
          $lcovutil::ERROR_DEPRECATED,
          "RC option '$key' is deprecated.  Please use '$replacement' instead."
         ]);
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
    my $set_value = 0;
    info(1, "read_config: $filename\n");
    my $f;
    eval { $f = InOutFile->in($filename); };
    if ($@) {
        lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                              "cannot read configuration file '$filename': $!");
        # this line is unreachable as we can't ignore the 'usage' error
        #   because it is generated when we parse the config-file options
        #   but the '--ignore-errors' option isn't parsed until later, after
        #   the GetOptions call.
        # This could be fixed by doing some early processing on the command
        #   line (similar to how config file options are handled) - but that
        #   seems like overkill.  Just force the user to fix the issues.
        return 0;    # didn't set anything
    }
    my $path = abs_path($filename);
    die("abs_path returned undef for $filename") unless defined($path);
    if (exists($included_config_files{$path})) {
        lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
                                  'config file inclusion loop detected: "' .
                                      join('" -> "', @include_stack) .
                                      '" -> "' . $filename . '"');
        return 0;
    }
    $included_config_files{$path} = 1;
    push(@include_stack, $filename);

    local *HANDLE = $f->hdl();
    VAR: while (<HANDLE>) {
        chomp;
        # Skip comments
        s/#.*//;
        # Remove leading blanks
        s/^\s+//;
        # Remove trailing blanks
        s/\s+$//;
        next unless length;
        my ($key, $value) = split(/\s*=\s*/, $_, 2);
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
            $value =~ s/\$ENV\{$varname\}/$ENV{$varname}/g;
        }
        if (defined($key) &&
            exists($deprecated_rc{$key})) {
            warnDeprecated($key, $deprecated_rc{$key});
            next;
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
                    "\"$filename\": $.: malformed configuration file statement '$_':  expected \"key = value\""
                ]);
        }
    }
    delete $included_config_files{$path};
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
        # can't complain about deprecated uses here because the user
        #  might have suppressed that message - but we haven't looked at
        #  the suppressions in the parameter list yet.
        if (exists($deprecated_rc{$key})) {
            warnDeprecated($key, $deprecated_rc{$key});
            next;
        }
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
                    [\@lcovutil::excludeCoverpointCallback,
                     \@rc_excludeCoverpointCallback
                    ],
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

    # Determine which errors the user wants us to ignore
    parse_ignore_errors(@opt_ignore_errors);

    # Make sure the parent directory that intermediate data goes under exists.
    #   Do this before the 'lcov --capture' early return below:  'lcov' calls
    #   'create_temp_dir' itself during capture (see 'copy_gcov_dir').
    create_tmp_dir();

    # if lcov --capture:  no further initialization required - is handled
    #   in geninfo call
    return 1 if $lcov_capture;

    foreach my $cb ([\$versionCallback, \@extractVersionScript],
                    [\$resolveCallback, \@resolveCallback],
                    [\$CoverageCriteria::criteriaCallback,
                     \@CoverageCriteria::coverageCriteriaScript
                    ],
                    [\$contextCallback, \@contextCallback],
                    [\$profileHistoryCallback, \@profileHistoryCallback],
                    [\$excludeCoverpointCallback, \@excludeCoverpointCallback],
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

    if ($lcovutil::compute_file_version &&
        !defined($versionCallback)) {
        lcovutil::ignorable_warning($lcovutil::ERROR_USAGE,
            "'compute_file_version=1' option has no effect without either '--version-script' or 'version_script=...'."
        );
    }
    lcovutil::munge_file_patterns();
    lcovutil::init_parallel_params();
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
                               $lcovutil::case_insensitive);

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
                    ["lcov_unreachable_line", \$lcovutil::UNREACHABLE_LINE],
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

sub warn_pattern_list
{
    my ($type, $patterns) = @_;
    my $unused = 0;
    foreach my $pat (@$patterns) {
        my $count = $pat->[-1];
        if (0 == $count) {
            my $str = $pat->[-2];
            lcovutil::ignorable_error($ERROR_UNUSED,
                                      "'$type' pattern '$str' is unused.");
            ++$unused;
        }
    }
    if ($unused) {
        lcovutil::ignorable_error($ERROR_UNUSED,
                                  "$unused of " .
                                      scalar(@$patterns) .
                                      " '$type' pattern" .
                                      (scalar(@$patterns) == 1 ? '' : 's') .
                                      ' were never applied.');
    }
}

sub warn_file_patterns
{
    # a bit of a hack...we need a place to call the 'finalize' methods
    #  (if any are registered) - and this method is called very late in
    #  the game, by lcov/genhtml/geninfo - so is a workable location
    for (my $i = 0; $i <= $#lcovutil::callback_finalize; ++$i) {
        my ($class, $cb) = @{$lcovutil::callback_finalize[$i]};
        eval { $cb->finalize(); };
        if ($@) {
            lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                      "\"$class->finalize()\" failed: $@");
        }
    }

    foreach my $p (['include', \@include_file_patterns],
                   ['exclude', \@exclude_file_patterns],
                   ['substitute', \@file_subst_patterns],
                   ['omit-lines', \@omit_line_patterns],
                   ['exclude-functions', \@exclude_function_patterns],
    ) {
        warn_pattern_list(@$p);
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
        my $leader =
            $header . '  ' . $total{$type} . " $type message" .
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
        if ($c =~ /^\s*(\S+?)\s*:\s*((\d+)|(.+?))\s*$/) {
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

sub _serialization_format_hint
{
    # The XS acceleration layer and the pure-Perl implementation serialize the
    # coverage classes (BranchData/MCDC_Data/CountData/...) incompatibly, and
    # the format is chosen implicitly by whether the XS module loaded (governed
    # by the LCOV_PURE_PERL environment variable).  There is intentionally no
    # in-format tag; instead we tell the user how to switch THIS process to
    # match the file that was written by some earlier execution.
    return $lcovutil::XS_LOADED ?
        "the file appears to have been written by a pure-Perl execution; re-run with LCOV_PURE_PERL=1 set in the environment"
        :
        "the file appears to have been written by an XS (accelerated) execution; re-run with LCOV_PURE_PERL unset (or =0) in the environment";
}

sub deserialize_checked
{
    # Storable::retrieve() wrapper that turns a cross-format mismatch (data
    # written by an XS build read back by a pure-Perl build, or vice versa)
    # into a friendly ERROR_FORMAT rather than a cryptic internal failure.
    #
    # This is only for cross-execution persistence (files written by a
    # *previous* lcov invocation).  The parallel-fork "dumper_$$" restore paths
    # are deliberately not routed through here: parent and child share one
    # process image within a single run, so their format is always consistent.
    my ($file) = @_;

    my $self = eval { Storable::retrieve($file) };
    if ($@) {
        # A cross-format read can fail in two distinct ways:
        #  Mode A:  dies INSIDE Storable::retrieve.  This happens when the
        #     stream contains an object of a class that carries a STORABLE
        #     hook in one implementation but not (or incompatibly) in the
        #     other
        #   * XS-written data read by pure-Perl: Storable sees the per-object
        #     hook flag, tries to load the class as a module to find
        #     STORABLE_thaw, and dies "Can't locate BranchData.pm" -- pure-Perl
        #     defines those classes inline, with no .pm file.
        #   * pure-Perl-written data read by XS (e.g. a whole TraceFile, which
        #     always contains hook-bearing CountData/MapData leaves): the XS
        #     thaw tries to treat the pure-Perl arrayref as its inner-IV scalar
        #     and dies "Can't coerce HASH to integer".
        # A genuinely corrupt/short file also lands here; the format hint is
        # still the first thing worth trying, and the raw $@ is preserved so a
        # real-corruption diagnosis is not lost.
        ignorable_error($lcovutil::ERROR_FORMAT,
                        "unable to deserialize '$file': $@" .
                            _serialization_format_hint());
        return undef;
    }
    return undef unless defined $self;

    # Mode B: Storable::retrieve SUCCEEDS SILENTLY, then the mismatch
    #   happened later when an XS method dereferences an inner IV that isn't
    #   there.
    #   This is the dangerous case the exception catch above cannot see:
    #   it occurs when every serialized leaf is a class without a STORABLE
    #   hook (BranchData/MCDC_Data are plain blessed arrayrefs in pure-Perl),
    #   so XS Storable happily rebuilds the pure-Perl tree verbatim.
    # We detect it by checking the ref *shape*: an XS coverage object is a
    #   blessed scalar ref (its inner IV holds a C++ pointer), whereas
    #   a pure-Perl one is a blessed array (or hash) ref.
    #    - if WE are the XS build but a coverage leaf came back as a
    #      non-scalar ref, the writer was pure-Perl.
    #    - vice versa: XS-written hookless data read by pure-Perl --
    #      is mode A, because XS DOES install per-object hooks, so it never
    #      reaches here.)
    #
    # NOTE: a whole TraceFile always carries hook-bearing CountData/MapData
    # leaves, so a cross-format TraceFile read fails as mode A in practice.
    # This check fires if deserialize_checked() is ever pointed at a payload
    # whose only coverage objects are the hookless BranchData/MCDC_Data.
    if ($lcovutil::XS_LOADED) {
        my $leaf = _first_coverage_leaf($self);
        if (defined($leaf) &&
            Scalar::Util::blessed($leaf) &&
            Scalar::Util::reftype($leaf) ne 'SCALAR') {
            ignorable_error($lcovutil::ERROR_FORMAT,
                "unable to deserialize '$file': content is not in the expected XS binary format - "
                    . _serialization_format_hint());
            return undef;
        }
    }
    return $self;
}

sub _first_coverage_leaf
{
    # Best-effort: reach into a deserialized TraceFile and return one leaf
    # coverage object (BranchData/CountData/...) whose ref *shape* reveals
    # which implementation wrote the file.  Returns undef if the structure
    # doesn't look like a TraceFile (nothing to probe -> skip the check).
    my ($self) = @_;
    return undef unless Scalar::Util::reftype($self) eq 'ARRAY';
    # Fully-qualified constant calls (not barewords): the constants are
    # declared further down the file, so they are not yet known as barewords
    # at this sub's compile point, but the constant subs resolve at runtime.
    my $files = $self->[TraceFile::FILES()];
    return undef unless Scalar::Util::reftype($files) eq 'HASH';
    foreach my $entry (values %$files) {
        # TraceInfo::LINE_DATA slot 0 is a CountData; that is the cheapest,
        # always-present leaf to inspect.
        next unless Scalar::Util::reftype($entry) eq 'ARRAY';
        my $line = $entry->[TraceInfo::LINE_DATA()];
        return $line->[0]
            if (Scalar::Util::reftype($line) eq 'ARRAY' &&
                Scalar::Util::blessed($line->[0]));
    }
    return undef;
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
    my ($phase, $jobId) = @_;
    # a bit of a hack:   this method is called at the start of each
    #  child process - so use it to record that we are executing in a
    #  child.
    # The flag is used to reduce verbosity from children - and possibly
    #  for other things later
    $lcovutil::in_child_process = 1;

    # This job's label, and the prefix for the id of anything WE fork - see
    #  $jobIdPrefix.  Our caller already qualified $jobId, so use it as-is.
    $lcovutil::jobLabel    = $phase . '_' . $jobId;
    $lcovutil::jobIdPrefix = $lcovutil::jobLabel . '_';

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

    for (my $i = 0; $i <= $#lcovutil::callback_start_list; ++$i) {
        my ($class, $cb) = @{$lcovutil::callback_start_list[$i]};
        eval { $cb->start(); };
        if ($@) {
            lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                      "\"$class->start()\" failed: $@");
        }
    }

    return Storable::dclone([\@message_count, \%versionCache, \%resolveCache]);
}

sub compute_update
{
    my ($state) = @_;
    my ($initialCount, $initialVersionCache, $initialResolveCache) = @$state;

    # Capture this worker's peak memory before its profile data is packaged
    # for the parent (it rides the existing profileData channel home via
    # merge_child_profile).  Every forked worker returns through here, so this
    # single call covers geninfo capture chunks, filter workers, genhtml
    # segments, and lcov aggregate groups.  $jobLabel is this job's fully
    # qualified id (e.g. 'capture_3', 'aggregate_1_filter_0'), as computed by
    # the initial_state() call this worker started with, so the memory entry
    # can be lined up with that job's timing data.
    lcovutil::record_profile_memory($lcovutil::jobLabel);

    my @new_count;
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
    my @cbData;
    for (my $i = 0; $i <= $#lcovutil::callback_save_restore; ++$i) {
        my ($class, $cb) = @{$lcovutil::callback_save_restore[$i]};
        eval {
            my $data = $cb->save();
            push(@cbData, $data);
        };
        if ($@) {
            lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                      "\"$class->save(...)\" failed: $@");
        }
    }
    my @rtn = (\@cbData,
               \@new_count,
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
    my $callbackData = shift;
    for (my $i = 0; $i <= $#$callbackData; ++$i) {
        my ($class, $cb) = @{$lcovutil::callback_save_restore[$i]};
        eval { $cb->restore($callbackData->[$i]); };
        if ($@) {
            lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                      "\"$class->restore(...)\" failed: $@");
        }
    }
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

sub fork_child
{
    # 'fork()', with the fault injections which the testsuite needs in order to
    #   reach the recovery code in the reap loops:
    #     LCOV_FORCE_FORK_FAIL=N   the next N calls report that the syscall
    #                              failed, without forking anything
    #     LCOV_FORCE_CHILD_KILL=N  the next N children kill themselves with
    #                              SIGKILL before they do any work - which is
    #                              what the parent sees when the OS kills a
    #                              worker for using too much memory
    #     LCOV_FORCE_NO_DUMP=N     the next N children exit successfully
    #                              without doing any work, so the parent finds
    #                              no serialized data to merge
    #     LCOV_FORCE_ORPHAN=N      the next N calls leave an extra process
    #                              behind which the caller does not know about -
    #                              which is what a callback module that forgot
    #                              to wait for its own child looks like
    #     LCOV_FORCE_OOM_MSG=N     the next N children complain that they could
    #                              not allocate memory and exit non-zero,
    #                              without being signalled - which is what a
    #                              child whose gcov ran out of memory looks
    #                              like.  Needs '$tempDir'/'$prefix' to name the
    #                              log the parent will read, so a caller which
    #                              does not pass them cannot use it.
    #     LCOV_FORCE_BAD_DATA=N    the next N children report success and leave
    #                              data behind which the parent can read but
    #                              cannot use - which is what a child that was
    #                              built differently, or interrupted mid-dump,
    #                              looks like.  Needs '$tempDir' as above.
    #   These are used only for regression tests.
    # The counters are decremented in the parent, so N is a count of injected
    #   failures and not a count per child.
    my ($tempDir, $prefix) = @_;
    if ($lcovutil::forceOrphan) {
        --$lcovutil::forceOrphan;
        my $orphan = fork();
        # '_exit', not 'exit':  this is a copy of the parent, so it must not run
        #   the parent's END blocks or flush the parent's buffers
        POSIX::_exit(0) if (defined($orphan) && 0 == $orphan);
    }
    if ($lcovutil::forceForkFail) {
        --$lcovutil::forceForkFail;
        $! = POSIX::EAGAIN;
        return undef;
    }
    my $fate = 0;
    if ($lcovutil::forceChildKill) {
        --$lcovutil::forceChildKill;
        $fate = 'kill';
    } elsif ($lcovutil::forceNoDump) {
        --$lcovutil::forceNoDump;
        $fate = 'quit';
    } elsif ($lcovutil::forceOomMsg && defined($tempDir)) {
        --$lcovutil::forceOomMsg;
        $fate = 'oom';
    } elsif ($lcovutil::forceBadData && defined($tempDir)) {
        --$lcovutil::forceBadData;
        $fate = 'baddata';
    }
    my $pid = fork();
    if ($fate && defined($pid) && 0 == $pid) {
        if ('baddata' eq $fate) {
            # data the parent can read but not unpack, and a success status:  the
            #   parent has to blame the failure on something, and a child which
            #   said that it succeeded gave it nothing is the obvious culprit
            Storable::store([], File::Spec->catfile($tempDir, "dumper_$$"));
            exit(0);
        }
        if ('oom' eq $fate) {
            # write the complaint where the parent looks for the child's stderr,
            #   then fail the way a tool which gave up on an allocation does
            my $f = File::Spec->catfile($tempDir, "${prefix}_$$.err");
            if (open(OOM_INJECT, '>', $f)) {
                print(OOM_INJECT "gcov: std::bad_alloc\n");
                close(OOM_INJECT);
            }
            exit(1);
        }
        kill(POSIX::SIGKILL, $$) if 'kill' eq $fate;
        exit(0);
    }
    return $pid;
}

sub report_unknown_child
{
    my $child = shift;
    # this can happen if the user loads a callback module which starts a child
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

sub report_retry
{
    # A child failed in a way which is worth another try - it was killed by the
    #   OS (almost always: out of memory) or it left no data behind - so the job
    #   it was running is about to go back on the worklist.
    # Count how many times this same job has now failed and let
    #   'report_fork_failure' decide whether to keep retrying:  it escalates to
    #   a hard error once one job has failed 'max_fork_fails' times, which is
    #   the only thing standing between a job which fails every time and an
    #   infinite retry loop.  Every caller has to pass that count, so keep the
    #   counting here rather than open-coded at each of them.
    my ($counts, $id, $when, $reason) = @_;
    report_fork_failure($when, $reason, ++$counts->{$id});
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
            "$prefix died due to signal $signal (SIG" .
            (split(' ', $Config{sig_name}))[$signal] .
            ')' . MessageContext::context() .
            ': possibly killed by OS due to out-of-memory';
        $explain .=
            lcovutil::explain_once('out_of_memory',
                       ' - see --memory and --parallel options for throttling');
    }
    ignorable_error($errType, "$message: $explain$suffix");
}

sub report_child_output
{
    # Print whatever a forked child wrote to the stdout/stderr files it was
    #   captured into - '$tempDir/$prefix_<pid>.log' and '.err' - and remove
    #   them.
    # The child's stdout is interesting only if the child failed (or if the user
    #   asked to see everything, or if '$showStdout' says that this child was
    #   doing work the user would otherwise have seen the messages from - see
    #   'AggregateTraces::_parallel_parse'); its stderr always is.
    # '$rawStatus' is the wait status exactly as $? had it:  the exit status and
    #   the signal are pulled out here, and the signal is returned because
    #   '$retryOnOOM' can change it - see below.
    # '@siblings' is the other children still running, to be killed if this one
    #   turns out to have left us data we cannot read.
    my ($tempDir, $prefix, $child, $rawStatus, $operation, $showStdout,
        $retryOnOOM, @siblings)
        = @_;

    my $childstatus = $rawStatus >> 8;
    my $signal      = $rawStatus & 0xFF;
    my @text;
    foreach my $suffix ('log', 'err') {
        my $f = File::Spec->catfile($tempDir, "${prefix}_$child.$suffix");
        if (!-f $f) {
            push(@text, '');    # there was no output
            next;
        }
        if (open(RESTORE, "<", $f)) {
            # slurp into a string
            my $str = do { local $/; <RESTORE> };    # slurp whole thing
            close(RESTORE) or die("unable to close $f: $!\n");
            unlink $f
                unless ($str && $lcovutil::preserve_intermediates);
            push(@text, $str);
        } else {
            push(@text, "unable to open $f: $!");
            report_parallel_error($operation, $ERROR_PARALLEL, $child, 0,
                                  $text[-1], @siblings)
                if (0 == $rawStatus);
        }
    }
    print(STDOUT $text[0])
        if ($showStdout ||
            (0 != $rawStatus &&
             $signal != POSIX::SIGKILL &&
             $lcovutil::max_fork_fails != 0) ||
            $lcovutil::verbose);
    print(STDERR $text[1]);

    if ($retryOnOOM                                 &&
        0 == $signal                                &&
        0 != $childstatus                           &&
        0 != $lcovutil::max_fork_fails              &&
        lcovutil::is_ignored($lcovutil::ERROR_FORK) &&
        grep(
            { /(std::bad_alloc|annot allocate memory|out of memory|integrity check failed for compressed file)/
            } @text)
    ) {
        # The child said that it ran out of memory rather than being killed for
        #   it, so tell the caller what it would have seen if the OS had done
        #   the killing:  this job is worth retrying with less parallelism.
        $signal = POSIX::SIGKILL;
    }
    return $signal;
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

{
    # The fork/join loop, once.
    #
    # Every parallel phase in the product used to write this out by hand:  the
    #   filter worklist and the two aggregate paths in this file, geninfo's
    #   compute chunks and genhtml's job scheduler.  They used a common sequence
    #   - throttle, fork, run the unit in the child, dump, reap, merge, retry
    #   the tasks which died - but had different specific actions.
    #
    # Post-refactoring, the client keeps is its queue, its payload and its
    # words, but uses common bookkeeping.
    # The required callbacks are:
    #
    #     next    -> ($unit, $id), or () when the queue is dry.  It is also where
    #                a client which sometimes does the work itself (a chunk too
    #                small to be worth a process) does it.
    #     child   -> ($payload, $status);  runs in the child, inside the
    #                stdout/stderr capture.  '$payload' is the arrayref which is
    #                serialized for the parent, or undef for "nothing to send".
    #     merge   -> ($unit, $id, $payload, $ctx);  runs in the parent.
    #     requeue -> ($unit, $id);  put a unit whose child died back on the queue.
    #     more    -> true while the queue could still produce work:  a requeued
    #                unit arrives after 'next' has already gone dry.
    #
    # Optional:
    #     childInit  -> (in the child, before 'initial_state'),
    #    jobId       -> (the id 'initial_state' is to label this job with, for
    #                   a client whose merge order and whose profile namespace
    #                   are not the same thing),
    #   validate     -> (in the parent, on the payload, before it is merged),
    #   preMerge and postReap -> (the per-unit progress and profile lines),
    #   postStore    -> (the child's own view of its dump),
    #   remaining    -> (how much work is left, for the throttle's message)
    #   unitWeight   -> (how big a unit is, for the memory throttle - see
    #                   'throttle').
    #
    #  The four message callbacks - 'forkFailWhen', 'retryWhen',
    #    'mergeFailMessage', 'childFailMessage' - exist because each client
    #    names its unit of work differently, and the words are the user's.
    #
    # A client which cannot use 'run' - genhtml, whose queue is dependency
    #   ordered and which reaps from three places - drives 'fork_one',
    #   'reap_one' and 'throttle' itself.

    package lcovutil::ForkManager;

    sub new
    {
        my ($class, %opts) = @_;

        my $self = {
             # what the messages call this phase, and the '.log'/'.err'/'dumper_'
             #   files this client's children write
             operation => 'parallel',
             phase     => 'parallel',
             prefix    => 'child',
             # print the child's stdout even when it succeeded:  for a client
             #   whose children do work the user would otherwise have watched
             showStdout => 0,
             # believe a child which says in its log that it could not allocate
             #   memory, rather than only one which the OS killed
             retryOnOOM => 0,
             # merge in dispatch order rather than completion order:  ids must be
             #   0 .. N-1 in the order 'next' hands them out
             ordered => 0,
             # a child of this client can legitimately finish without dumping
             #   anything (everything it was given was excluded)
             mayNotDump => 0,
             # how many children may run at once;  '--parallel' unless the client
             #   knows better (it will never have more work than that)
             maxInFlight => undef,
             # also wait when the children we have are using too much memory:
             #   only for the clients whose children are the big ones
             memoryThrottle => 0,
             # how big a unit of work is, in whatever the client counts (records,
             #   input bytes, ..).  Only asked for by the clients which throttle
             #   on memory, and only to be compared with itself:  the throttle
             #   turns a weight into bytes with a rate it measures - see
             #   '_estimate'
             unitWeight => undef,
             %opts,
             children       => {},  # pid -> [$unit, $id, $forkAt]
             retryCounts    => {},  # id -> times this unit has been retried
             failedAttempts => 0,   # consecutive fork() failures
             ready          => {},  # 'ordered': id -> payload awaiting its turn
             nextToMerge    => 0,
             delay          => 0,   # seconds spent inside wait()
                 # what we predicted the children now running would cost:
                 #   pid -> [$bytes, $weight, $baseAtFork] - see '_estimate'
             reserved => {},
             # the marginal cost the children which have finished really had,
             #   and the weight they had it for:  the ratio is the rate
             learnedBytes  => 0,
             learnedWeight => 0,
        };
        foreach my $required ('tempDir', 'next',
                              'child', 'merge',
                              'requeue', 'forkFailWhen',
                              'retryWhen', 'mergeFailMessage',
                              'childFailMessage'
        ) {
            die("ForkManager: '$required' is required")
                unless exists($self->{$required});
        }
        # The caller's temp directory is often a File::Temp object, whose
        #   destructor removes the directory - so keep the name, and let the
        #   caller keep the object for as long as it wants the directory.
        #   It can be undefined for a client whose work all turned out to be
        #   small enough to do here:  then there is no child, and no dump.
        $self->{tempDir} = defined($self->{tempDir}) ? '' . $self->{tempDir} :
            '';
        return bless($self, $class);
    }

    sub count
    {
        # children forked and not yet reaped
        return scalar(keys(%{$_[0]->{children}}));
    }

    sub delay_timer
    {
        return $_[0]->{delay};
    }

    sub _dumpfile
    {
        my ($self, $pid) = @_;
        return File::Spec->catfile($self->{tempDir}, "dumper_$pid");
    }

    sub _estimate
    {
        # What a child running this unit will cost us, in bytes:  a copy of us
        #   as we are now, plus what the unit itself adds.  Returns
        #   ($bytes, $weight, $base) - the parts the throttle's message needs.
        #
        # The unit's own cost is its weight - the client's count of the work in
        #   it (records, input bytes, ..) - times the bytes per unit of weight
        #   the children which have already finished really used.  That is,
        #   what a worker holds scales with how many records it was given, not
        #   with how big the parent happens to be at the moment it is forked.
        #
        # Until a child has finished, and for a client which cannot weigh its
        #   units, there is no rate - and then the estimate is just our own
        #   size.  This used to be the metric used by all the parallel-fork
        #   clients.
        my ($self, $unit, $id) = @_;

        my $base = lcovutil::current_process_size();
        my $weight =
            ($self->{unitWeight} && defined($unit)) ?
            $self->{unitWeight}->($unit, $id) :
            0;
        # The weight is reported either way:  it is what '_learn' will divide
        #   the first child's real cost by, so a rate can only ever be measured
        #   if the weight survives the fork with no rate in hand.
        return ($base, $weight, $base)
            unless ($weight && $self->{learnedWeight});
        return (
               $base + $weight * $self->{learnedBytes} / $self->{learnedWeight},
               $weight, $base);
    }

    sub _learn
    {
        # What this child really cost, against the size we were when we forked
        #   it:  the difference is what its unit added, which is the quantity the
        #   estimate needs.  '$peak' is the child's peak - it is the peak the
        #   ceiling has to hold, not whatever the child happened to be using when
        #   it finished.
        #
        # Accumulated as a total rather than kept as the largest ratio seen:  a
        #   single small unit which grew for some other reason would otherwise fix
        #   the rate at its own ratio forever and throttle everything behind it to
        #   one child at a time.
        my ($self, $reserved, $peak) = @_;

        my ($weight, $base) = @{$reserved}[1, 2];
        return unless ($weight && $peak && $peak > $base);
        $self->{learnedBytes}  += $peak - $base;
        $self->{learnedWeight} += $weight;
    }

    sub fork_one
    {
        # Fork one unit.  Returns the child's pid, or 0 if the fork failed - in
        #   which case the unit has already been requeued and the failure
        #   reported, and the caller should just carry on:  'report_fork_failure'
        #   is what escalates to a hard error once one unit has failed too often.
        my ($self, $unit, $id) = @_;

        $lcovutil::deferWarnings = 1;
        my $forkAt = Time::HiRes::gettimeofday();
        # 'LCOV_FORCE_STORE_FAIL=N':  the next N children cannot write the data
        #   they computed - which is what a full or read-only filesystem looks
        #   like.  Taken here, in the parent, so N is a count of injected
        #   failures rather than a count per child;  the child inherits the
        #   decision because it is a copy of us.  Same rule as the knobs in
        #   'fork_child' - see there for why none of these is an option.
        my $failStore = 0;
        if ($lcovutil::forceStoreFail) {
            --$lcovutil::forceStoreFail;
            $failStore = 1;
        }
        # the temp directory and prefix are for the fault injections, which need
        #   to know where this child's output and data would have gone
        my $pid = lcovutil::fork_child($self->{tempDir}, $self->{prefix});
        if (!defined($pid)) {
            my $err = $!;    # before anything else can overwrite it
            ++$self->{failedAttempts};
            lcovutil::report_fork_failure($self->{forkFailWhen}->($id, $unit),
                                          $err, $self->{failedAttempts});
            $self->{requeue}->($unit, $id);
            return 0;
        }
        $self->{failedAttempts} = 0;
        if (0 == $pid) {
            # I'm the child.  This does not return.
            exit($self->_run_child($unit, $id, $forkAt, $failStore));
        }
        $self->{children}->{$pid} = [$unit, $id, $forkAt];
        # Hold what we predicted this one costs until it is reaped:  the throttle
        #   adds the reservations up rather than assuming that every child is the
        #   size we happen to be right now - which is the "wrong in when it is
        #   taken" half of section 11.6's finding.
        $self->{reserved}->{$pid} = [$self->_estimate($unit, $id)]
            if $self->{memoryThrottle};
        $self->{postFork}->($unit, $id, $pid) if $self->{postFork};
        return $pid;
    }

    sub _run_child
    {
        my ($self, $unit, $id, $forkAt, $failStore) = @_;

        $self->{childInit}->($unit, $id) if $self->{childInit};
        # The job label has to be unique across the whole run - see
        #   'initial_state' - which is not the same requirement as the merge
        #   order's "0 .. N-1, in dispatch order".  A client whose ids are
        #   positions in its own queue says here what to call this job instead.
        my $jobId  = $self->{jobId} ? $self->{jobId}->($unit, $id) : $id;
        my $state  = lcovutil::initial_state($self->{phase}, $jobId);
        my $tmp    = $self->{tempDir};
        my $prefix = $self->{prefix};
        my $status = 0;
        my $payload;
        # 'capture' rather than reopening STDOUT/STDERR:  a child may itself run
        #   a subprocess (gcov) whose output has to be redirected too, and
        #   reopening the descriptors does not survive that - see the
        #   Capture::Tiny documentation
        my ($stdout, $stderr, $code) = Capture::Tiny::capture {
            my $childStatus;
            eval {
                ($payload, $childStatus) =
                    $self->{child}->($unit, $id, $forkAt, $jobId);
            };
            if ($@) {
                print(STDERR $@);
                $status = 1;
            } elsif (defined($childStatus)) {
                $status = $childStatus;
            }
        };
        # the parent may already have caught an error, removed the temp directory
        #   and exited
        lcovutil::check_parent_process();
        foreach
            my $d (["${prefix}_$$.log", $stdout], ["${prefix}_$$.err", $stderr])
        {
            next unless ($d->[1]);    # only if there is something to say
            my $f = InOutFile->out(File::Spec->catfile($tmp, $d->[0]));
            my $h = $f->hdl();
            print($h $d->[1]);
        }
        if (defined($payload)) {
            # the injected failure writes to a directory which is not there, so
            #   that the arm below is reached by 'Storable' failing rather than by
            #   this code pretending that it did
            my $dumpf =
                $failStore ?
                File::Spec->catfile($tmp, 'no_such_directory', "dumper_$$") :
                $self->_dumpfile($$);
            my $dumpStart = Time::HiRes::gettimeofday();
            my $data;
            # What I really cost, for the parent's memory estimate - see
            #   'ForkManager::_learn'.  Read here rather than taken out of the
            #   profile data, which carries the same number home but only when
            #   '--profile' asked for it, and the throttle has to work either
            #   way.  The peak of the same measure the parent throttles on, so
            #   that the two are comparable;  zero where the OS will not say
            #   (see 'read_proc_peak_memory'), which the parent reads as "no
            #   measurement" and falls back from.
            my $peak = (lcovutil::read_proc_peak_memory())[1];
            eval {
                $data =
                    Storable::store([@$payload,
                                     lcovutil::compute_update($state), $peak
                                    ],
                                    $dumpf);
            };
            if ($@ || !defined($data)) {
                lcovutil::ignorable_error($lcovutil::ERROR_PARALLEL,
                              "Child $$ serialize failed" . ($@ ? ": $@" : ''));
                # a child whose data did not get written must not tell the parent
                #   that it succeeded:  the parent would read a file which is not
                #   there, or is half written, instead of running the unit again
                $status = 1;
            }
            $self->{postStore}->($unit, $id, $dumpf, $dumpStart)
                if $self->{postStore};
        }
        return $status;
    }

    sub reap_one
    {
        # Wait for one of our children and merge what it left behind.  Returns
        #   the number of our children which stopped running, which is 1 or 0:
        #   a process we did not fork says nothing about the ones we are waiting
        #   for, so it is reported and otherwise ignored.  A caller which counted
        #   it would call 'wait()' again for a child which does not exist.
        my ($self, $blocking) = @_;

        my $children = $self->{children};
        while (1) {
            my $waitStart = Time::HiRes::gettimeofday();
            my $child     = $blocking ? wait() : waitpid(-1, POSIX::WNOHANG);
            my $rawStatus = $?;
            my $reapAt    = Time::HiRes::gettimeofday();
            $self->{delay} += $reapAt - $waitStart;
            return 0 if ($child <= 0);    # nothing (more) to reap
            unless (exists($children->{$child})) {
                lcovutil::report_unknown_child($child);
                # keep looking for one of ours:  blocking or not, the next call
                #   is the one which decides - 'waitpid' returns -1 when there is
                #   nothing left, and we return 0 then
                next;
            }
            if ($self->{wrapReap}) {
                # a client which reports a failed merge itself, once, at the
                #   outside - rather than having each thing which can go wrong
                #   report it where it happened
                eval { $self->_reap($child, $rawStatus, $reapAt); };
                $self->{wrapReap}->($child, $rawStatus, $@) if $@;
            } else {
                $self->_reap($child, $rawStatus, $reapAt);
            }
            return 1;
        }
    }

    sub _reap
    {
        my ($self, $child, $rawStatus, $reapAt) = @_;

        my $children = $self->{children};
        my ($unit, $id, $forkAt) = @{delete($children->{$child})};
        # this one is not running any more, so the memory we were holding for it
        #   is available to whatever we fork next
        my $reserved    = delete($self->{reserved}->{$child});
        my $childstatus = $rawStatus >> 8;
        my $dumpfile    = $self->_dumpfile($child);
        # the still-running children, for the messages:  a failure here can be a
        #   symptom of something which is about to happen to them too
        my $ctx = {
                   child     => $child,
                   id        => $id,
                   unit      => $unit,
                   forkAt    => $forkAt,
                   reapAt    => $reapAt,
                   dumpfile  => $dumpfile,
                   status    => $childstatus,
                   rawStatus => $rawStatus,
                   siblings  => [keys(%$children)],
        };
        $self->{preMerge}->($ctx) if $self->{preMerge};
        my $signal =
            lcovutil::report_child_output(
                            $self->{tempDir}, $self->{prefix}, $child,
                            $rawStatus, $self->{operation}, $self->{showStdout},
                            $self->{retryOnOOM}, @{$ctx->{siblings}});
        my $data = Storable::retrieve($dumpfile)
            if (-f $dumpfile && 0 == $childstatus);
        if (defined($data)) {
            eval {
                my @payload = @$data;
                # the two things the framework itself appended, innermost last
                my $peak   = pop(@payload);
                my $update = pop(@payload);
                lcovutil::update_state(@$update);
                $self->_learn($reserved, $peak) if $reserved;
                $ctx->{payload} = \@payload;
                # 'validate' returning false means "I have said what is wrong
                #   with this data, do not merge it" - and it is not an error
                #   here, so nothing else is reported
                my $ok =
                    $self->{validate} ?
                    $self->{validate}->(\@payload, $ctx) :
                    1;
                $self->_merge_payload($ok ? \@payload : undef, $ctx);
            };
            if ($@) {
                $ctx->{error} = $@;
                # a client with a 'wrapReap' says what went wrong out there
                die($@) if $self->{rethrowMergeFailure};
                # the reporters take the wait status apart themselves, so hand
                #   them '$?' as we got it:  an already shifted value turns "exit
                #   status 1" into "died due to signal 1 (SIGHUP)".  '1 << 8' is
                #   the raw status of "exited with 1", which is what we blame the
                #   failure on when the child thought it had succeeded.
                $rawStatus = 1 << 8 unless $rawStatus;
                lcovutil::report_parallel_error(
                    $self->{operation},
                    (exists($self->{mergeFailError}) ? $self->{mergeFailError} :
                         $lcovutil::ERROR_PARALLEL),
                    $child,
                    $rawStatus,
                    $self->{mergeFailMessage}->($ctx),
                    @{$ctx->{siblings}});
            }
        }
        if (!defined($data) || 0 != $childstatus) {
            if ((!-f $dumpfile && !$self->{mayNotDump}) ||
                POSIX::SIGKILL == $signal) {
                lcovutil::report_retry(
                           $self->{retryCounts},
                           $id,
                           $self->{retryWhen}->($ctx),
                           (POSIX::SIGKILL == $signal ?
                                "killed by OS - possibly due to out-of-memory" :
                                "serialized data $dumpfile not found"));
                $self->{requeue}->($unit, $id);
            } elsif (0 != $childstatus) {
                lcovutil::report_parallel_error(
                                              $self->{operation},
                                              (exists($self->{childFailError}) ?
                                                   $self->{childFailError} :
                                                   $lcovutil::ERROR_CHILD),
                                              $child,
                                              $rawStatus,
                                              $self->{childFailMessage}->($ctx),
                                              @{$ctx->{siblings}});
            }
        }
        $self->{postReap}->($ctx) if $self->{postReap};
        unlink($dumpfile) if -f $dumpfile;
    }

    sub _merge_payload
    {
        my ($self, $payload, $ctx) = @_;

        if (!$self->{ordered}) {
            $self->{merge}->($ctx->{unit}, $ctx->{id}, $payload, $ctx)
                if defined($payload);
            return;
        }
        # Merge in the order the units were dispatched rather than the order the
        #   children happen to finish in:  a file level comment is held in a list
        #   whose order is the order it was merged in, and the user gets to see
        #   their own order.  A finished unit waits its turn.
        $self->{ready}->{$ctx->{id}} = [$payload, $ctx];
        $self->drain_ready();
    }

    sub drain_ready
    {
        # Merge whatever is now next in line.  Public because a retried unit can
        #   be the last one to arrive, after the loop has already finished.
        my $self  = shift;
        my $ready = $self->{ready};
        while (exists($ready->{$self->{nextToMerge}})) {
            my ($payload, $ctx) = @{delete($ready->{$self->{nextToMerge}})};
            ++$self->{nextToMerge};
            # a unit whose data we rejected still had its turn:  otherwise
            #   everything behind it waits for a merge which will never happen
            $self->{merge}->($ctx->{unit}, $ctx->{id}, $payload, $ctx)
                if defined($payload);
        }
    }

    sub throttle
    {
        # Reap while we are oversubscribed:  too many children, or - for the
        #   clients which ask - too much memory for the one we are about to add.
        #   '$unit' is that one, when the caller knows it:  then the memory
        #   question is asked about the work it actually holds rather than about
        #   an average unit.  Returns how many we reaped.
        my ($self, $unit, $id) = @_;
        my $reaped = 0;

        my $limit = defined($self->{maxInFlight}) ? $self->{maxInFlight} :
            $lcovutil::maxParallelism;
        while (1) {
            my $running = $self->count();
            my $tooBig  = 0;
            my $message;
            if ($self->{memoryThrottle} && 0 != $lcovutil::maxMemory) {
                # Everything which will be alive once we fork:  us, the children
                #   we are already holding memory for, and the one we are about
                #   to add.  Each child's own size covers a copy of us, so the
                #   parent's size appears in each of them as well as on its own -
                #   as it did in the '(children + 1) * <our size>' estimate this
                #   replaces.
                my $mySize   = lcovutil::current_process_size();
                my $inFlight = 0;
                $inFlight += $_->[0] foreach (values(%{$self->{reserved}}));
                my ($next, $weight) = $self->_estimate($unit, $id);
                my $total = $mySize + $inFlight + $next;
                $tooBig = ($running > 1 && $total > $lcovutil::maxMemory);
                $message =
                    "memory constraint $mySize (me) + $inFlight ($running running) + "
                    . int($next)
                    . ' (next'
                    .
                    (($weight && $self->{learnedWeight}) ?
                         sprintf(': %d units at %0.1f bytes each',
                                 $weight,
                                 $self->{learnedBytes} / $self->{learnedWeight})
                     :
                         '') .
                    ") > $lcovutil::maxMemory"
                    if $tooBig;
            }
            last unless ($running >= $limit || $tooBig);
            lcovutil::info(1,
                           "$message violated: waiting.  "
                               .
                               ($self->{remaining} ? $self->{remaining}->() :
                                    $running) .
                               " remaining\n") if $tooBig;
            last unless $self->reap_one(1);
            ++$reaped;
        }
        return $reaped;
    }

    sub run
    {
        # The whole sequence, for a client whose queue is just a list:  dispatch
        #   until it is dry, drain, and go round again in case a unit which died
        #   was put back.
        my $self = shift;

        do {
            while (1) {
                # Take the unit before waiting for room for it, rather than
                #   waiting for room for an average one:  'throttle' estimates
                #   what the unit it is given will cost.  'next' is also where a
                #   client does the units which are too small to fork, and doing
                #   those while the children we have are finishing is no worse
                #   than doing them before we wait.
                my ($unit, $id) = $self->{next}->();
                last unless defined($id);
                $self->throttle($unit, $id);
                $self->fork_one($unit, $id);
            }
            while ($self->count()) {
                $self->reap_one(1);
            }
        } while ($self->{more}->());
        $self->drain_ready() if $self->{ordered};
    }
}

sub is_filter_enabled
{
    # return true of there is an opportunity for filtering
    return (grep({ defined($_) } @lcovutil::cov_filter) ||
            0 != scalar(@lcovutil::omit_line_patterns)        ||
            0 != scalar(@lcovutil::exclude_function_patterns) ||
            defined($lcovutil::excludeCoverpointCallback));
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
            $points =
                '    ' . $histogram->[-1] . ' coverpoint' .
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
    unless ($silent) {
        lcovutil::ignorable_error($ERROR_VERSION,
                          (defined($reason) ? ($reason . ' ') : '') .
                              "$filename: revision control version mismatch: " .
                              (defined($me) ? $me : 'undef') . ' <- ' .
                              (defined($you) ? $you : 'undef'));
        return 1;                   # ignore the mismatch
    }
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

# ----------------------------------------------------------------------
# Shared HTML/source-rendering definitions.
#
# genhtml renders source into HTML (escaping entities and expanding tabs);
# html2lcov screen-scrapes that HTML back into source.  The escape map, the
# tab-expansion algorithm, and the default tab width / HTML extension must be
# identical in the writer and the reader or the recovered source will not
# match.  Keeping them here (used by both tools) is the single source of truth.
# ----------------------------------------------------------------------

# default number of spaces a tab is expanded to when rendering source to HTML
our $default_tab_size = 8;
# default filename extension for generated HTML files (no leading dot)
our $default_html_extension = 'html';

# The four HTML special characters genhtml escapes when rendering source.
#   Declared with a BEGIN initializer because callers (genhtml's escape_html)
#   may reference it before this point is reached at run time.
our %html_escape_map;

BEGIN {
    %html_escape_map = ('&' => '&amp;',
                        '<' => '&lt;',
                        '>' => '&gt;',
                        '"' => '&quot;',);
}

# Expand tabs to the next tab stop, matching how source is rendered to HTML.
#   $tabSize <= 0 disables expansion (returns the string unchanged).
sub expand_tabs
{
    my ($string, $tabSize) = @_;
    return $string if $tabSize <= 0 || index($string, "\t") < 0;
    my $col = 0;
    my $out = '';
    foreach my $piece (split(/(\t)/, $string, -1)) {
        if ($piece eq "\t") {
            my $pad = $tabSize - ($col % $tabSize);
            $out .= ' ' x $pad;
            $col += $pad;
        } else {
            $out .= $piece;
            $col += length($piece);
        }
    }
    return $out;
}

# Reverse the entity escaping applied when source was rendered to HTML.
#   '&amp;' must be decoded LAST so that e.g. '&amp;lt;' round-trips to '&lt;'
#   rather than to '<'.
sub unescape_html
{
    my $string = $_[0];
    return $string unless defined($string);
    $string =~ s/&lt;/</g;
    $string =~ s/&gt;/>/g;
    $string =~ s/&quot;/"/g;
    $string =~ s/&amp;/&/g;
    return $string;
}

package SavedReport;

# Single source of truth for the 'genhtml --save' layout:  the naming of the
#   .info/diff files that genhtml --save copies into the top level of an HTML
#   report directory, and the logic to find them again.
#
# genhtml --save (the writer) and html2lcov (the reader) both go through this
#   package so the two can never disagree about where the files live or how
#   they are named.
#
# Layout contract:
#   - files are written to the top level of the report output directory
#   - each saved file keeps the basename of its source file, with a role
#     prefix:
#         current  data  -> 'current_'  . basename
#         baseline data  -> 'baseline_' . basename
#         diff file      -> (no prefix) . basename
#   - EXCEPTION: when the report has no baseline, the 'current_' prefix is
#     suppressed and current data keeps its plain basename.  (There is no
#     baseline or diff file in that case.)

use strict;
use warnings;

# roles
use constant {
              CURRENT  => 'current',
              BASELINE => 'baseline',
              DIFF     => 'diff',
};

# saved basename for one input file, given its role and whether the report
#   has a baseline.
sub saved_basename
{
    my ($role, $from, $hasBaseline) = @_;
    my $base = File::Basename::basename($from);
    if ($role eq BASELINE) {
        return 'baseline_' . $base;
    } elsif ($role eq DIFF) {
        return $base;
    } elsif ($role eq CURRENT) {
        # current data is prefixed only when a baseline is also present
        return ($hasBaseline ? 'current_' : '') . $base;
    } else {
        die("unknown saved-report role '$role'");
    }
}

# full destination path for one saved file.
sub saved_path
{
    my ($outputDirectory, $role, $from, $hasBaseline) = @_;
    return
        File::Spec->catfile($outputDirectory,
                            saved_basename($role, $from, $hasBaseline));
}

# Writer entry point used by 'genhtml --save':  copy the current/baseline/diff
#   inputs into the report directory using the naming contract above.
#   Existing files are not overwritten.
sub save_inputs
{
    my ($outputDirectory, $info_filenames, $base_filenames, $diff_filename) =
        @_;
    require File::Copy;
    my $hasBaseline = ($base_filenames && scalar(@$base_filenames)) ? 1 : 0;
    foreach my $d ([BASELINE, $base_filenames],
                   [DIFF, defined($diff_filename) ? [$diff_filename] : []],
                   [CURRENT, $info_filenames]) {
        my ($role, $list) = @$d;
        next unless $list;
        foreach my $from (@$list) {
            next unless defined($from);
            my $to = saved_path($outputDirectory, $role, $from, $hasBaseline);
            File::Copy::copy($from, $to) unless -f $to;
        }
    }
}

# Reader entry point used by html2lcov:  return the list of saved 'current'
#   coverage files found at the top level of a report directory.  Matches both
#   the baseline form ('current_*.info[.gz]') and the no-baseline form
#   (plain '*.info[.gz]' that is not a 'baseline_' file).  Returns full paths.
sub find_current_info
{
    my ($outputDirectory) = @_;
    opendir(my $dh, $outputDirectory) or
        return ();
    my @found;
    while (my $e = readdir($dh)) {
        my $p = File::Spec->catfile($outputDirectory, $e);
        next unless -f $p;
        # only .info or .info.gz files
        next unless $e =~ /\.info(\.gz)?$/;
        # baseline files are not 'current' data
        next if $e =~ /^baseline_/;
        push(@found, $p);
    }
    closedir($dh);
    return @found;
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
            # frame tags have no anchor fragment; $3 from a prior <a href> match
            # would be stale, so pass undef explicitly
            push(@{$self->[HREFS]}, [$., $1, undef]); # lineNo, filename, anchor
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
        if (exists($context{$key})) {
            $context{$key} .= "\n" . $value;
        } else {
            $context{$key} = $value;
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

sub history
{
    my ($self, $item) = @_;

    my $time;
    my $pipe = $self->pipe('history', $item);
    die("broken 'history' callback")
        unless ($pipe &&
                ($time = $pipe->next()));
    chomp($time);
    $time =~ s/\r//;
    lcovutil::info(1, "  history: $item = $time\n");
    return $time eq '' ? undef : $time;
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
            die("No Perl JSON module found on your system.  Please install one of the following supported modules: "
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
    my ($self, $key, $check_if_present, $retainElement) = @_;

    my $data = $self->[HASH];
    if (!defined($check_if_present) ||
        exists($data->{$key})) {

        die("$key not found")
            unless exists($data->{$key});
        --$self->[FOUND];    # found;
        --$self->[HIT]       # hit
            if ($data->{$key} > 0);

        delete $data->{$key} unless $retainElement;
        return 1;
    }
    return 0;
}

sub _checkCounts
{
    # Assert that the cached found/hit still equal what a full walk of the data
    #   says they should be.  'append' and 'remove' maintain them incrementally,
    #   so any path which mutates the same map twice - which is what happens if
    #   an aliased summary is treated as an object independent of the
    #   per-testcase map it aliases - drives them away from the truth silently.
    #   This is the counterpart of 'BranchData::_checkCounts', and like it is
    #   run unconditionally from 'TraceInfo::check_data'.
    my $self  = shift;
    my $found = 0;
    my $hit   = 0;

    foreach my $count (values(%{$self->[HASH]})) {
        ++$found;
        ++$hit if $count > 0;
    }
    my $name = $self->[FILENAME];
    die("invalid line counts for $name: found:" .
        "$self->[FOUND]->$found, hit:$self->[HIT]->$hit")
        unless ($self->[FOUND] == $found &&
                $self->[HIT] == $hit);
}

sub found
{
    return $_[0]->[FOUND];
}

sub hit
{
    return $_[0]->[HIT];
}

sub keylist
{
    return keys(%{$_[0]->[HASH]});
}

sub entries
{
    return scalar(keys(%{$_[0]->[HASH]}));
}

sub union
{
    my $self = shift;
    my $info = shift;

    my $changed = 0;
    while (my ($key, $value) = each(%{$info->[HASH]})) {
        if ($self->append($key, $value)) {
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
    # if exclusion filter not enabled, then count everything
    #   else, walk the structure to find only the elements which
    #   aren't excluded
    return ($self->[FOUND], $self->[HIT]);
}

package BranchElement;
# branch element:  index, taken/not-taken count, optional expression
# for baseline or current data, 'taken' is just a number (or '-')
# for differential data: 'taken' is an array [$taken, tla]

use constant {
              ID       => 0,
              TAKEN    => 1,
              EXPR     => 2,
              TYPE     => 3,
              EXCLUDED => 4,
              # 'genhtml' appends some additional data onto the element -
              #   for differential coverage reporting
              TLA        => 5,
              DIFF_COUNT => 6,    # [base_count, currentCount]

              # possible branch types
              VANILLA     => 0,
              EXCEPT      => 1,
              FALLTHROUGH => 2,
};

sub new
{
    my ($class, $id, $taken, $expr, $type, $excluded) = @_;
    # if branchID is not an expression - go back to legacy behaviour
    my $self = [$id,
                $taken,
                (defined($expr) && $expr eq $id) ? undef : $expr,
                defined($type) ? $type : VANILLA,
                defined($excluded) && $excluded ? 1 : 0,
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

sub type
{
    return $_[0]->[TYPE];
}

sub type_name
{
    my $type = $_[0]->type();
    return $type == VANILLA ? '' :
        ($type == EXCEPT ? 'exception' : 'fallthrough');
}

sub signature
{
    my $t = $_[0]->type();
    return $t == VANILLA ? 'b' : ($t == EXCEPT ? 'e' : 'f');
}

sub is_exception
{
    return $_[0]->type() == EXCEPT;
}

sub is_excluded
{
    my $self = shift;
    return $self->[EXCLUDED];
}

sub write_data
{
    # Batch accessor for the '.info' writer, which uses all the fields.
    # Returns  ($taken, $id, $expr, $signature, $excluded)
    # A Perl method call costs on the order of 100ns, so amortizing one frame
    # is measurably faster.
    #  Direct slot access at the call site would be faster still, but is
    #  forbidden: under the XS backend these objects are opaque scalar refs, so
    #  the win has to come through a method.
    # The scalar access methods are retained, as other callers use them.
    my $self = shift;
    my $t    = $self->[TYPE];
    return ($self->[TAKEN], $self->[ID],
            $self->[EXPR], $t == VANILLA ? 'b' : ($t == EXCEPT ? 'e' : 'f'),
            $self->[EXCLUDED]);
}

sub set_excluded
{
    my $self = shift;
    if (!$self->[EXCLUDED]) {
        $self->[EXCLUDED] = 1;
        return 1;
    }
    return 0;
}

sub isDifferential
{
    my $self = shift;

    return $#$self == DIFF_COUNT;
}

sub tla
{
    my $self = shift;
    die("unexpected tla() call with non-differential data")
        unless $self->isDifferential();
    return $self->[TLA];
}

sub diff_count
{
    my $self = shift;
    die("unexpected diff_count() call with non-differential data")
        unless $self->isDifferential();
    return @{$self->[DIFF_COUNT]};
}

sub render_data
{
    # Batch accessor mirroring the XS BranchElement::render_data -- see the
    # comment there.  genhtml's source-view render loop calls this once per
    # branch element instead of making 8 separate calls;  under XS that is one
    # Perl<->C++ crossing instead of eight, and this pure-Perl version keeps the
    # two backends on a single code path in genhtml.
    #
    # Returns: (data, count, is_excluded, type_name, expr, tla, base_count)
    # tla/base_count are undef when the element does not carry them (rather
    # than dying, as tla()/diff_count() do) because the caller asks for
    # everything at once and decides what to use.
    my $self = shift;
    return ($self->[TAKEN],
            $self->[TAKEN] eq '-' ? 0 : $self->[TAKEN],
            $self->[EXCLUDED],
            $self->type_name(),
            $self->[EXPR],
            $self->[TLA],
            defined($self->[DIFF_COUNT]) ? $self->[DIFF_COUNT]->[0] : undef);
}

sub set_tla
{
    my ($self, $tla) = @_;
    # Same precondition as tla():  a non-differential element has no TLA to set.
    # Without this guard, filling the TLA slot alone would leave the element
    # self-contradictory -- isDifferential() (which tests the array's length) still
    # false, so tla() dies on the value just stored -- and the XS backend, whose
    # isDifferential() asks "is the differential payload allocated?", would answer
    # true for the same call.  set_differential() is the way to make an element
    # differential.  Only genhtml's TLA-remap loop calls set_tla, and it reads
    # tla() first, so the element is always already differential there.
    die("unexpected set_tla() call with non-differential data")
        unless $self->isDifferential();
    $self->[TLA] = $tla;
}

sub set_differential
{
    my ($self, $tla, $base, $curr) = @_;
    $self->[TLA]        = $tla;
    $self->[DIFF_COUNT] = [$base, $curr];
}

sub merge
{
    # return 1 if something changed, 0 if nothing new covered or discovered
    my ($self, $that, $filename, $line) = @_;
    # should have called 'iscompatible' first
    # LCOV_EXCL_START
    if (0) {
        # keep track of code->block list - then pick the compatible
        #  block, or add new one
        lcovutil::ignorable_warning($lcovutil::ERROR_MISMATCH,
             "$filename:$line: attempt to merge incompatible expressions for id"
                 . $self->id()
                 . ', ' . $that->id() . ": '" .
                 $self->exprString() . "' -> '" . $that->exprString() . "'.")
            if ($self->exprString() ne $that->exprString());
    }
    # LCOV_EXCL_STOP

    # LCOV_EXCL_START
    if ($self->type() != $that->type()) {
        my $loc = defined($filename) ? "\"$filename\":$line: " : '';
        lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                                  "${loc}mismatched exception tag for id " .
                                      $self->id() . ", " . $that->id() .
                                      ": '" . $self->is_exception() .
                                      "' -> '" . $that->is_exception() . "'");
        # set 'self' to 'not related to exception' - to give a consistent
        #  answer for the merge operation.  Otherwise, we pick whatever
        #  was seen first - which is unpredictable during threaded execution.
        $self->[TYPE] = VANILLA;
        die("this is no longer reachable...we split hold multiple blocks");
    }
    # LCOV_EXCL_STOP

    my $changed = 0;
    if ($self->is_excluded() != $that->is_excluded()) {
        # if 'ignore_unreachable_flag' is disabled, then 'unreachable' flag is
        #   set when info file is read - or is set when --unreachable
        #   callback is called - so the two expressions will have both be
        #   unset unless we really are trying to compare
        # an empty filename is as useless a label as an absent one:  '"":10:'
        #   tells the reader nothing, so suppress the prefix for both
        my $loc =
            (defined($filename) && '' ne $filename) ?
            "\"$filename\":$line: " :
            '';
        lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                           "${loc}mismatched 'unreachable' tag for branch id " .
                               $self->id() . ", " .
                               $that->id() . ": '" . $self->is_excluded() .
                               "' -> '" . $that->is_excluded() . "'");
        # set 'self' to 'excluded'
        $changed = $self->[EXCLUDED] != 1;
        $self->[EXCLUDED] = 1;
    }
    my $t = $that->[TAKEN];
    return $changed if $t eq '-';    # no new news

    my $count = $self->[TAKEN];
    if ($count ne '-') {
        $changed = 1 if $count == 0 && $t != 0;
        $count += $t;
    } else {
        $count   = $t;
        $changed = 1 if $t != 0;
    }
    $self->[TAKEN] = $count;
    return $changed;
}

package BranchBlock;

# container for list of branch elements + some data
use constant {
              IDX       => 0,
              SIGNATURE => 1,
              LIST      => 2,
};

sub new
{
    my $class = shift;

    my $self = [undef, '', []];
    return bless $self, $class;
}

sub idx
{
    return $_[0]->[IDX];
}

sub signature
{
    return $_[0]->[SIGNATURE];
}

sub empty
{
    return !@{$_[0]->[LIST]};
}

sub elements
{
    return $_[0]->[LIST];
}

sub getElement
{
    my ($self, $idx) = @_;
    die("index out of range") if $idx > $#{$self->[LIST]};
    return $self->[LIST]->[$idx];
}

sub setIdx
{
    my ($self, $idx) = @_;
    # moving block from one list to another - index may or may not
    #  be the same in the new list as the old.
    $self->[IDX] = $idx;
}

sub appendElement
{
    my ($self, $element) = @_;
    # 'element' is either a BranchElement instance or
    #    an array ref containing categorized coverage: (TLA, count differences)
    push(@{$self->[LIST]}, $element);
    die("unexpected element type") unless ('BranchElement' eq ref($element));
    $self->[SIGNATURE] .= $element->signature();
}

sub appendNew
{
    my $self = shift;
    # Construct the element and append it, for the caller which wants only the
    #   append - as reading a '.info' file does, for every branch coverpoint in
    #   it.  The XS implementation of this builds the element directly inside
    #   the block, with no intermediate object and no blessed wrapper for it,
    #   which is the whole point of having the method:  keep the two in step.
    my $element = BranchElement->new(@_);
    push(@{$self->[LIST]}, $element);
    $self->[SIGNATURE] .= $element->signature();
}

sub merge
{
    my ($self, $you, $filename, $line) = @_;

    my $m = $self->elements();
    my $y = $you->elements();
    die("expected identical block")
        unless ($#$m == $#$y &&
                $self->signature() eq $you->signature());
    my $changed = 0;

    for (my $idx = 0; $idx <= $#$m; ++$idx) {
        my $e = $m->[$idx];
        my $f = $y->[$idx];
        $changed = 1
            if $e->merge($f, $filename, $line);
    }
    return $changed;
}

package BranchLocation;
# hash of blockID -> array of BranchElement refs for each sequential branch ID

use constant {
              LINE  => 0,
              INDEX => 1,    # list of BranchBlock
              CODE  => 2,    # code -> list of BranchBlock
};

sub new
{
    my ($class, $line) = @_;
    my $self = [$line, [], {}];
    bless $self, $class;
    return $self;
}

sub line
{
    my $self = shift;
    return $self->[LINE];
}

sub containsCode
{
    my ($self, $code) = @_;
    return exists($self->[CODE]->{$code});
}

sub hasBlock
{
    my ($self, $id) = @_;
    # A block ID is a subscript into the block list, so it has a lower bound as
    #   well as an upper one:  '$#list >= $id' alone is true for any negative
    #   $id (even on an empty list), and the caller then indexes with it and
    #   silently gets a block counted from the END of the list.
    return $id >= 0 && $id <= $#{$self->[INDEX]};
}

sub removeBlock
{
    my ($self, $block, $branchData) = @_;
    'BranchBlock' eq ref($block) or die("expected block - got " . ref($block));
    my $list = $self->[INDEX];
    my $id   = $block->idx();
    $id <= $#$list && $list->[$id] == $block or
        die("remove:  unknown block ID '$id'");

    my @removed = splice(@$list, $id, 1);
    $block == $removed[0] or die("huh?");
    for (my $i = $id; $i <= $#$list; ++$i) {
        $list->[$i]->setIdx($i);
    }
    my $code  = $block->signature();
    my $table = $self->[CODE];
    my @list  = grep({ $_->idx() != $id } @{$table->{$code}});
    if (@list) {
        $table->{$code} = \@list;
    } else {
        delete($table->{$code});
    }
    # adjust counts
    $branchData->removeBranches($block);
}

sub getList
{
    my ($self, $code) = @_;
    my $table = $self->[CODE];
    die("$code not found") unless exists($table->{$code});
    return $table->{$code};
}

sub numBlocks
{
    return scalar(@{$_[0]->[INDEX]});
}

sub getBlock
{
    my ($self, $id) = @_;
    my $list = $self->[INDEX];
    # see the note in hasBlock():  a negative $id passes an upper-bound-only
    #   check and then indexes from the end of the list
    $id >= 0 && $id <= $#$list or die("getBlock: unknown block $id");

    return $list->[$id];
}

sub blocks
{
    my ($self, $sort) = @_;
    my $list = $self->[INDEX];

    if (defined($sort) && $sort) {
        # shortest code first, lowest block number first - in order
        # of appearance
        return
            sort({
                     my $codeA = $a->signature();
                     my $codeB = $b->signature();
                     length($codeA) <=> length($codeB) or
                         $codeA cmp $codeB or
                         $a->idx() <=> $b->idx();
            } @$list);
    }
    return @$list;
}

sub codes
{
    my ($self, $sort) = @_;
    my @keys = keys(%{$self->[CODE]});
    # shortest code first
    return $sort ?
        sort({ length($a) <=> length($b) or $a cmp $b } @keys) :
        @keys;
}

sub insertBlock
{
    my ($self, $branchBlock) = @_;
    my $list     = $self->[INDEX];
    my $blockIdx = $#$list + 1;
    die('unexpected empty block') if $branchBlock->empty();
    $branchBlock->setIdx($blockIdx);
    push(@$list, $branchBlock);

    my $code  = $branchBlock->signature();
    my $table = $self->[CODE];

    if (exists($table->{$code})) {
        $list = $table->{$code};
    } else {
        $list = [];
        $table->{$code} = $list;
    }
    push(@$list, $branchBlock);
}

sub totals
{
    my ($self, $countExcluded) = @_;
    # return (found, hit) counts of coverpoints in this entry
    my $found = 0;
    my $hit   = 0;
    foreach my $blk ($self->blocks()) {
        my $elements = $blk->elements();
        foreach my $br (@$elements) {
            next
                if ($br->is_excluded() &&
                    !(defined($countExcluded) && $countExcluded));
            my $count = $br->count();
            ++$found;
            ++$hit if (0 != $count);
        }
    }
    return ($found, $hit);
}

sub hasHitElement
{
    # Is any element on this line evaluated at least once?
    # This is the question '0 != ($self->totals($countExcluded))[1]' answers,
    #   but totals() has to visit every element of every block to produce the
    #   count it then throws away, whereas this returns on the first hit.
    #   _checkConsistency asks it once per branch line, so on a large report
    #   the difference is a few million element visits.
    my ($self, $countExcluded) = @_;
    my $skipExcluded = !(defined($countExcluded) && $countExcluded);
    foreach my $blk ($self->blocks()) {
        foreach my $br (@{$blk->elements()}) {
            next if ($skipExcluded && $br->is_excluded());
            return 1 if 0 != $br->count();
        }
    }
    return 0;
}

sub merge
{
    my ($self, $that, $filename) = @_;

    my $changed   = 0;
    my $numBlocks = $self->numBlocks();
    # walk the list of signatures at this location
    foreach my $code ($that->codes()) {
        my $yourList = $that->getList($code);
        if ($self->containsCode($code)) {
            # I contain this code...walk the set of blocks with the
            # matching code and merge in order.
            # If you have more blocks than me, then simply copy the
            # additional blocks
            my $myList = $self->getList($code);
            for (my $idx = 0; $idx <= $#$yourList; ++$idx) {
                my $yourBlock = $yourList->[$idx];
                if ($idx <= $#$myList) {
                    # I have this block index...just merge
                    my $myBlock = $myList->[$idx];
                    $changed = 1
                        if $myBlock->merge($yourBlock, $filename,
                                           $self->line());
                } else {
                    # I don't have this block..copy it and assign new index
                    $changed = 1;
                    my $myBlock = Storable::dclone($yourBlock);
                    $self->insertBlock($myBlock);
                }
            }
        } else {
            # I don't have this code...clone all the blocks
            $changed = 1;
            foreach my $yourBlock (@$yourList) {
                my $myBlock = Storable::dclone($yourBlock);
                $self->insertBlock($myBlock);
            }
        }
    }
    return $changed;
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
    my ($self, $filename, $groupSize, $sense, $count, $idx, $expr, $excluded) =
        @_;
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
                "\"$filename\":" . $self->line() .
                    ": MC/DC group $groupSize: non-contiguous expression '$idx' found - should be '"
                    . scalar(@$group)
                    . "'.");
        }
        $cond = MCDC_Expression->new($self, $groupSize, $idx, $expr);
        push(@$group, $cond);
    }
    $cond->set($sense, $count, $excluded);
}

sub line
{
    return $_[0]->[LINE];
}

sub totals
{
    # sometimes, we want to keep excluded branches in the count - e.g.,
    # when we are checking consistency between branch- and line coverage.
    # We don't want to complain about inconsistency, if some branches are
    # excluded
    my ($self, $countExcluded) = @_;
    my $found = 0;
    my $hit   = 0;
    while (my ($size, $group) = each(%{$self->groups()})) {
        foreach my $expr (@$group) {
            foreach my $sense (0, 1) {
                next
                    if ($expr->is_excluded($sense) &&
                        !(defined($countExcluded) && $countExcluded));
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
    # Requested expression is expected to exist:  the caller
    #   (e.g. scripts/unreach.pm exclude_cond) names a group and an index that
    #   its own annotation claims exist, so anything out of range is an error.
    die("expr: unknown group size $groupSize")
        unless exists($self->[GROUPS]->{$groupSize});
    my $list = $self->[GROUPS]->{$groupSize};
    die("expr: invalid expression index $idx in group $groupSize")
        unless $idx >= 0 && $idx <= $#$list;
    return $list->[$idx];
}

sub is_compatible
{
    my ($self, $you) = @_;

    my $yours  = $you->groups();
    my $groups = $self->groups();
    foreach my $size (keys %$groups) {
        next unless exists($yours->{$size});
        my $m = $groups->{$size};
        my $y = $yours->{$size};
        # merge() walks the two lists index-wise, so a shared group of unequal
        #   length leaves my trailing expressions with nothing to merge
        #   against:  that is an incompatible record not an error.
        return 0 if scalar(@$m) != scalar(@$y);
        my $idx = 0;
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
    my ($self, $you, $filename) = @_;

    my $mine    = $self->groups();
    my $yours   = $you->groups();
    my $changed = 0;
    while (my ($size, $group) = each(%$yours)) {
        if (exists($mine->{$size})) {
            my $m   = $mine->{$size};
            my $idx = 0;
            foreach my $e (@$m) {
                my $y = $group->[$idx++];
                foreach my $sense (0, 1) {
                    my $e_excl = $e->is_excluded($sense);
                    my $y_excl = $y->is_excluded($sense);
                    lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                        "$filename:" . $self->line() .
                            ":mismatched 'unreachable' tag for MC/DC element $idx of group $size sense "
                            . ($sense ? 'true' : 'false')
                            . ": '$e_excl' -> '$y_excl'.")
                        if ($e_excl != $y_excl);
                    $changed = 1 if $e->set($sense, $y->count($sense), $y_excl);
                }
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

              EXPRESSION     => 3,
              EXCLUDED_true  => 4,    # could use negative count to indicate
              EXCLUDED_false => 5,
              TRUE  => 6,  # hit count of sensitization of 'true' sense of expr
              FALSE => 7,  # hit count of sensitization of 'false' sense of expr
};

sub new
{
    my ($class, $parent, $groupSize, $idx, $expr) = @_;
    my $self = [$parent, $groupSize, $idx, $expr, 0, 0, 0, 0];
    return bless $self, $class;
}

sub set
{
    # 'sense' should be 0 or 1 - for 'false' and 'true' sense, respectively
    my ($self, $sense, $count, $excluded) = @_;
    my $changed = 0;
    if (defined($excluded) && $excluded) {
        $changed = $self->[$sense ? EXCLUDED_true : EXCLUDED_false] != 1;
        $self->[$sense ? EXCLUDED_true : EXCLUDED_false] = 1;
    }
    # An undefined count means "no count supplied" - only the 'excluded' flag
    #   above was being set.  Check defined() first:  falling through to the
    #   numeric comparison behaves the same but warns about an uninitialized
    #   value (the XS implementation is silent here).
    return $changed if !defined($count) || 0 == $count;

    if ('ARRAY' eq ref($count)) {
        # recording a differential result
        $self->[$sense ? TRUE : FALSE] = $count;
        return 1;    # assumed changed
    }
    $changed = 1 if $count && $self->count($sense) == 0;
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

sub is_excluded
{
    my ($self, $sense) = @_;
    return $self->[$sense ? EXCLUDED_true : EXCLUDED_false];
}

sub set_excluded
{
    my ($self, $sense) = @_;
    my $idx = $sense ? EXCLUDED_true : EXCLUDED_false;
    if (!$self->[$idx]) {
        $self->[$idx] = 1;
        return 1;
    }
    return 0;
}

sub count
{
    my ($self, $sense) = @_;
    return $_[0]->[$sense ? TRUE : FALSE];
}

sub write_data
{
    # Batch accessor for the '.info' writer - see BranchElement::write_data.
    # Returns
    #   ($count_false, $count_true, $excluded_false, $excluded_true, $expr)
    my $self = shift;
    return ($self->[FALSE], $self->[TRUE],
            $self->[EXCLUDED_false],
            $self->[EXCLUDED_true],
            $self->[EXPRESSION]);
}

sub render_data
{
    # Batch accessor mirroring the XS MCDC_Expression::render_data -- see the
    # comment there.  Returns everything genhtml's MC/DC render loop needs for
    # one (expression, sense) in a single call:
    #   (count, expression, is_excluded, multi_group)
    # Under XS this replaces 5 crossings, two of which (parent() then
    # num_groups()) allocated an SV for the parent block just to ask how many
    # groups it has.
    my ($self, $sense) = @_;
    return ($self->[$sense ? TRUE : FALSE],
            $self->[EXPRESSION],
            $self->[$sense ? EXCLUDED_true : EXCLUDED_false],
            $self->[PARENT]->num_groups() > 1 ? 1 : 0);
}

package FunctionEntry;
# keep track of all the functions/all the function aliases
#  at a particular line in the file.  They must all be the
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
        $name ne $self->name() ? (" (alias of '" . $self->name() . "')") : "";
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
                              $self->name() .
                                  " has different location than " .
                                  $that->name() . " during merge")
        if ($self->line() != $that->line());
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
            my $alen = length($alias);
            $alen += 1000 if $alias =~ /(?:\{lambda\(|\.lambda\$)/;
            my $curlen = defined($name) ? length($name) : 1_000_000;
            $curlen += 1000
                if defined($name) && $name =~ /(?:\{lambda\(|\.lambda\$)/;
            $name = $alias if $alen < $curlen;
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
                                          $self->filename() .
                                          ":$start_line: "
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
        return scalar(my @_keys = $self->keylist());
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
                $self->define_function($thatData->name(), $thatData->line(),
                                       $thatData->end_line());
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
    my $self = [{},    #  hash of lineNo -> BranchLocation/MCDC_Element
                       #   BranchLocation:
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

    # Without $check_if_present the caller is asserting the line is there;
    #   say so explicitly rather than dying inside totals() on undef - and
    #   match CountData::remove, which likewise dies on an absent key.
    die("$line not found") unless exists($data->{$line});

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

# return BranchLocation struct (or undef)
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

sub adjust_counts
{
    my ($self, $dFound, $dHit) = @_;
    $self->[FOUND] += $dFound;
    $self->[HIT]   += $dHit;
}

package BranchData;

use base 'BranchMap';

sub new
{
    my $class = shift;
    my $self  = $class->SUPER::new();
    return $self;
}

sub findOrCreate
{
    my ($self, $line) = @_;
    my $data = $self->[BranchMap::DATA];
    unless (exists($data->{$line})) {
        $data->{$line} = BranchLocation->new($line);
    }
    return $data->{$line};
}

sub insertBlock
{
    my ($self, $branchBlock, $line) = @_;

    my $branchLocation = $self->findOrCreate($line);
    $branchLocation->insertBlock($branchBlock);
}

sub removeBranches
{
    my ($self, $block) = @_;

    foreach my $b (@{$block->elements()}) {
        --$self->[BranchMap::FOUND];
        --$self->[BranchMap::HIT] if 0 != $b->count();
    }
}

sub updateCounts
{
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
    $self->[BranchMap::FOUND] = $found;
    $self->[BranchMap::HIT]   = $hit;
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

sub union
{
    my ($self, $info, $filename) = @_;
    my $changed = 0;

    my $mydata   = $self->[BranchMap::DATA];
    my $yourdata = $info->[BranchMap::DATA];
    # Keeping the cached found/hit up to date costs, per line you bring, about
    #   two totals() walks of that line - one before the merge and one after,
    #   since merge() reports only whether something changed and not by how
    #   much.  Rebuilding it from scratch afterwards instead costs one totals()
    #   walk per line *I* hold.  Neither is always cheaper, and the choice can
    #   be made before doing any work:
    #     - accumulating many files into one growing map (lcov -a f1 ... -aN)
    #       is the case the blanket rescan made quadratic in the total number of
    #       lines;  there the incremental cost is a rounding error.
    #     - merging two maps that cover the same lines touches everything I
    #       hold anyway, so the single rescan is the cheaper of the two.
    my $rescan = 2 * scalar(keys %$yourdata) > scalar(keys %$mydata);
    while (my ($line, $yourLocation) = each(%$yourdata)) {
        # check if self has corresponding line:
        #  no: just copy all the data for this line, from 'info'
        #  yes: check for matching blocks
        my $myLocation = $mydata->{$line}
            if exists($mydata->{$line});
        if (!defined($myLocation)) {
            $mydata->{$line} = Storable::dclone($yourLocation);
            # the copy is identical to yours, so its contribution to our
            #   cached found/hit is just your totals
            $self->adjust_counts($yourLocation->totals()) unless $rescan;
            $changed = 1;
        } elsif ($rescan) {
            $changed = 1
                if $myLocation->merge($yourLocation, $filename);
        } else {
            my ($oldFound, $oldHit) = $myLocation->totals();
            my $changedHere = $myLocation->merge($yourLocation, $filename);
            my ($newFound, $newHit) = $myLocation->totals();
            $self->adjust_counts($newFound - $oldFound, $newHit - $oldHit);
            $changed = 1 if $changedHere;
        }
    }
    $self->updateCounts() if ($rescan && $changed);
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
            my $myLoc   = $mydata->{$line};
            my $yourLoc = $yourdata->{$line};

            # Remember what this line contributes to the cached found/hit
            #   before the merges below mutate my blocks in place.
            # remove() can't do the subtraction because it subtracts the
            #   block totals which exists when called - by then it is the
            #   merged value rather than the original value
            my ($oldFound, $oldHit) = $myLoc->totals();
            my $replace     = BranchLocation->new($line);
            my $changedHere = 0;
            foreach my $code ($myLoc->codes(1)) {
                if ($yourLoc->containsCode($code)) {
                    my $myList   = $myLoc->getList($code);
                    my $yourList = $yourLoc->getList($code);
                    my $idx      = 0;
                    foreach my $yours (@$yourList) {
                        last if ($idx > $#$myList);
                        my $mine = $myList->[$idx++];
                        $changedHere = 1
                            if $mine->merge($yours, $filename, $line);
                        my $catBlock = Storable::dclone($mine);
                        $replace->insertBlock($catBlock);
                    }
                } else {
                    # remove all these blocks...
                    $changedHere = 1;
                }
            }
            if ($changedHere) {
                $changed = 1;
                delete($mydata->{$line});
                $self->adjust_counts(-$oldFound, -$oldHit);
                if ($replace->numBlocks() != 0) {
                    $mydata->{$line} = $replace;
                    # this is the count-add the blanket rescan used to supply:
                    #   the replacement was installed without ever telling the
                    #   cache about it
                    $self->adjust_counts($replace->totals());
                }
            }
            # No 'else' branch:  $changedHere is 0 only when every one of
            #   my codes was matched and every element merge reported no
            #   change: a no-change merge cannot have moved this line's
            #   found/hit.
        } else {
            # my line not found in your data - so remove this one
            $changed = 1;
            # nothing mutated here - remove() subtracts the right totals
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

        # look at all my blocks.  If you have a compatible block, remove it
        #   - else keep mine
        my $myLoc   = $mydata->{$line};
        my $yourLoc = $yourdata->{$line};

        my $replace     = BranchLocation->new($line);
        my $changedHere = 0;
        foreach my $code ($myLoc->codes(1)) {
            if ($yourLoc->containsCode($code)) {
                my $myList    = $myLoc->getList($code);
                my $yourCount = scalar(@{$yourLoc->getList($code)});
                $changedHere = 1;
                # ignore all the leading common blocks...
                for (my $idx = $yourCount; $idx <= $#$myList; ++$idx) {
                    my $mine     = $myList->[$idx];
                    my $catBlock = Storable::dclone($mine);
                    $replace->insertBlock($catBlock);
                }
            } else {
                # keep these blocks..
                foreach my $mine (@{$myLoc->getList($code)}) {
                    my $catBlock = Storable::dclone($mine);
                    $replace->insertBlock($catBlock);
                }
            }
        }
        if ($changedHere) {
            $changed = 1;
            # nothing above mutated my blocks - only clones were taken - so
            #   remove() subtracts correctly
            $self->remove($line);
            if ($replace->numBlocks() != 0) {
                $mydata->{$line} = $replace;
                # the count-add the blanket rescan used to supply
                $self->adjust_counts($replace->totals());
            }
        }
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
    my ($self, $mcdc, $filename) = @_;
    my $line = $mcdc->line();
    my $data = $self->[BranchMap::DATA];
    unless (exists($data->{$line})) {
        # Store a copy, as union() does:  the caller keeps ownership of the
        #   block it passed in, so later mutations of it must not silently
        #   change the data we just recorded.
        my $c = Storable::dclone($mcdc);
        $data->{$line} = $c;
        my ($found, $hit) = $c->totals();
        $self->[BranchMap::FOUND] += $found;
        $self->[BranchMap::HIT]   += $hit;
        return;
    }
    # Merging into an existing block:  only the delta this merge produced may
    #   be added to the cached totals.  Adding $mcdc->totals() unconditionally
    #   double-counted every expression the two blocks have in common, which
    #   left FOUND/HIT above the true totals and made _checkCounts() die.
    my $myBlock = $data->{$line};
    my ($oldFound, $oldHit) = $myBlock->totals();
    $myBlock->merge($mcdc, $filename);
    my ($newFound, $newHit) = $myBlock->totals();
    $self->[BranchMap::FOUND] += $newFound - $oldFound;
    $self->[BranchMap::HIT]   += $newHit - $oldHit;
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
    # Add the totals of a just-completed block to our cached found/hit.
    my ($self, $mcdc) = @_;
    $self->adjust_counts($mcdc->totals());
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

sub _checkCounts
{
    # MC/DC consistency checking:  similar to the 'branch' version
    my $self  = shift;
    my $found = 0;
    my $hit   = 0;

    while (my ($line, $block) = each(%{$self->[BranchMap::DATA]})) {
        $line == $block->line() or die("lost track of line");
        my ($f, $h) = $block->totals();
        $found += $f;
        $hit   += $h;
    }
    die("invalid MC/DC counts: found:" . $self->[BranchMap::FOUND] .
        "->$found, hit:" . $self->[BranchMap::HIT] . "->$hit")
        unless ($self->[BranchMap::FOUND] == $found &&
                $self->[BranchMap::HIT] == $hit);
}

sub union
{
    my ($self, $info, $filename) = @_;
    my $changed = 0;

    my $mydata   = $self->[BranchMap::DATA];
    my $yourdata = $info->[BranchMap::DATA];
    # incremental vs. rescan - see BranchData::union for the cost model
    my $rescan = 2 * scalar(keys %$yourdata) > scalar(keys %$mydata);
    while (my ($line, $yourBranch) = each(%$yourdata)) {
        # check if self has corresponding line:
        #  no: just copy all the data for this line, from 'info'
        #  yes: check for matching blocks
        my $myBranch = $self->value($line);
        if (!defined($myBranch)) {
            my $c = Storable::dclone($yourBranch);
            $mydata->{$line} = $c;
            $self->close_mcdcBlock($c) unless $rescan;
            $changed = 1;
            next;
        }

        # check if we are compatible.
        if ($myBranch->is_compatible($yourBranch)) {
            # '= 1' rather than '+= ': the return value is a boolean
            #   'did anything change', and a running sum of per-line merge
            #   results would depend on hash iteration order (a new line
            #   contributes 1, a changed line contributes 1 as well, so the
            #   total is not even a well-defined count of anything).
            if ($rescan) {
                $changed = 1
                    if $myBranch->merge($yourBranch, $filename);
            } else {
                my ($oldFound, $oldHit) = $myBranch->totals();
                my $changedHere = $myBranch->merge($yourBranch, $filename);
                my ($newFound, $newHit) = $myBranch->totals();
                $self->adjust_counts($newFound - $oldFound, $newHit - $oldHit);
                $changed = 1 if $changedHere;
            }
        } else {
            lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                                      "cannot merge inconsistent MC/DC record");
            # possibly remove this record?
        }
    }
    $self->_calculate_counts() if $rescan;
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
                # bracket the merge - see union() above
                my ($oldFound, $oldHit) = $myBranch->totals();
                my $changedHere = $myBranch->merge($yourBranch, $filename);
                my ($newFound, $newHit) = $myBranch->totals();
                $self->adjust_counts($newFound - $oldFound, $newHit - $oldHit);
                $changed = 1 if $changedHere;
            } else {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                                      "cannot merge inconsistent MC/DC record");
                # possibly remove this record?
            }
        } else {
            # remove() is already incremental
            $self->remove($line);
            $changed = 1;
        }
    }
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
            # remove() subtracts the removed line's totals from the cached
            #   found/hit, and nothing else here mutates the map - so there is
            #   nothing left for a recalculation to fix up
            $self->remove($line);
            $changed = 1;
        }
    }
    return $changed;
}

package FilterBranchExceptions;

use constant {
              EXCEPTION_f       => 0,
              ORPHAN_f          => 1,
              REGION_f          => 2,
              BRANCH_f          => 3,    # branch filter
              SRC_READER        => 4,
              BRANCHES          => 5,
              PER_TEST_BRANCHES => 6,
              ALIASED           => 7,    # BRANCHES is one of PER_TEST_BRANCHES
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
    # check case that no filters are defines
    return undef unless grep({ defined($_) } @$self);
    push(@$self, @_);
    return $self;
}

sub removeBranches
{
    # '$weight' is how many passes this one call stands in for:  2 when the
    #   summary and the single testcase's map are the same object, so that the
    #   coverpoint tally below is what two separate passes would have produced.
    my ($self, $line, $branches, $filter, $unreachable, $isMasterData, $weight)
        = @_;
    $weight = 1 unless defined($weight);

    my $brdata = $branches->value($line);
    return 0 unless defined($brdata);
    # 'unreachable' and 'excluded' branches have already been removed
    #   by 'region' filter along with their parent line - so no need to
    #   do anything here
    my $filename = $self->[SRC_READER]->filename();
    die("$filename:$line: unexpected unreachable branch")
        if ($unreachable && 0 != $brdata->count());
    my $modified = 0;
    my $blkIdx   = 0;
    # Walk the blocks by position rather than over a snapshot from blocks():
    # this loop can call removeBlock, which renumbers the surviving blocks, and
    # under the XS backend a BranchBlock handed out by blocks() is a borrowed
    # pointer into the location's block container -- a container that removeBlock
    # mutates, dangling every other borrow still held by the loop.  (Pure Perl
    # can use the snapshot because it holds real block references.)
    # Fetching the block for the current position on each iteration keeps no
    # handle alive across a mutation, and reproduces the pure-Perl visit order
    # exactly: removeBlock only shifts blocks at positions above the one it
    # drops, so on removal the next unvisited block lands at the position just
    # vacated and $pos must NOT advance.
    my $pos = 0;
    while ($pos < $brdata->numBlocks()) {
        my $block    = $brdata->getBlock($pos);
        my $elements = $block->elements();
        my $nElems   = 0;
        my $count    = 0;
        for (my $idx = 0; $idx <= $#$elements; ++$idx) {
            my $br = $elements->[$idx];
            next if $br->is_excluded();
            ++$nElems;
            if (defined($filter) && $br->is_exception()) {
                next
                    unless $br->set_excluded();
                $modified = 1;
                lcovutil::info(2, "$filename:$line: remove exception branch\n");
                ++$count;
                # Previous 'fallthrough' element is related to this exception.
                # We expect the exception branch to have a predecessor -
                #  but it is possible that other tools have a different idea.
                if ($idx != 0) {
                    my $prev = $elements->[$idx - 1];
                    if ($prev->type() == BranchElement::FALLTHROUGH &&
                        $prev->set_excluded()) {
                        ++$count;
                    }
                }
            }
        }
        if ($count) {
            ++$filter->[-2] if $isMasterData;
            lcovutil::info(2,
                           "$filename:$line: remove $count exception branch" .
                               (1 == $count ? '' : 'es') . "\n")
                if $isMasterData;
            $filter->[-1] += $count * $weight;
        }
        my $remaining = $nElems - $count;
        # If there is only one branch left - then this is not a conditional
        my $removed = 0;
        if (0 == $remaining) {
            lcovutil::info(2,
                           "$filename:$line: remove exception block $blkIdx\n");
            $brdata->removeBlock($block, $branches);
            $removed = 1;
        } elsif (1 == $remaining &&
                 defined($self->[ORPHAN_f])) {    # filter orphan
            lcovutil::info(2,
                    "$filename:$line: remove orphan exception block $blkIdx\n");
            $brdata->removeBlock($block, $branches);
            $removed = 1;
            ++$self->[ORPHAN_f]->[-2]
                if $isMasterData;
            $self->[ORPHAN_f]->[-1] += $weight;
        }
        # $blkIdx counts blocks as originally numbered (for the messages above);
        # $pos tracks the live container, so it only advances when nothing was
        # spliced out from under it.
        ++$pos unless $removed;
        ++$blkIdx;
    }
    if (0 == $brdata->numBlocks()) {
        lcovutil::info(2, "$filename:$line: no branches remain\n");
        $branches->remove($line);
        $modified = 1;
    }
    return $modified;
}

sub applyFilter
{
    my ($self, $filter, $line, $unreachable) = @_;
    # When the summary is aliased to the single testcase's map, the summary pass
    #   and that testcase's pass are the same pass over the same object:  do it
    #   once.  'removeBranches' counts every coverpoint it excludes into
    #   '$filter->[-1]' on both passes, so the one remaining pass carries the
    #   weight of the two it replaces and the reported total does not change.
    #   ('[-2]', the number of locations, is only counted for the master pass,
    #   so it is unaffected either way.)
    my $aliased = $self->[ALIASED];
    my $modified =
        $self->removeBranches($line, $self->[BRANCHES], $filter, $unreachable,
                              1, $aliased ? 2 : 1);
    my $perTestBranches = $self->[PER_TEST_BRANCHES];
    foreach my $tn ($perTestBranches->keylist()) {
        next
            if $aliased &&
            Scalar::Util::refaddr($perTestBranches->value($tn)) ==
            Scalar::Util::refaddr($self->[BRANCHES]);
        # want to remove matching branches everywhere - so we don't want short-circuit evaluation
        $modified = 1
            if $self->removeBranches($line, $perTestBranches->value($tn),
                                     $filter, $unreachable, 0, 1);
    }
    return $modified;
}

sub filter
{
    my ($self, $line) = @_;
    my $srcReader = $self->[SRC_READER];
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
                                   0 != ($reason & $srcReader->e_UNREACHABLE));
        } elsif (defined($self->[BRANCH_f])) {    # exclude branches
                # filter out bogus branches - even if this region is unreachable
            return $self->applyFilter($self->[BRANCH_f], $line, 0);
        }
    }
    # apply if filtering exceptions, orphans, or both
    if (defined($self->[EXCEPTION_f]) || defined($self->[ORPHAN_f])) {
        # filter exceptions and orphans - even if the region is "unreachable"
        return $self->applyFilter($self->[EXCEPTION_f], $line, 0);
    }
    return 0;
}

package TraceInfo;
#  coverage data for a particular source file
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

# The slots whose summary is allowed to be an alias of a per-testcase map - see
#   'isAliased'.  This is the single point of control:  '_installSection' will
#   only install an alias for a slot named here, and 'materializeAggregates'
#   breaks the alias for exactly the same set.  The two must agree - an alias
#   installed for a slot this list omits would never be broken.
use constant ALIASED_SLOTS =>
    (LINE_DATA, FUNCTION_DATA, BRANCH_DATA, MCDC_DATA);
# ...and the same set as a lookup, for the per-slot test in '_installSection'
our %MAY_ALIAS_SLOT = map({ ($_ => 1) } ALIASED_SLOTS);

# Every coverage type this file holds, as [slot, name], where the name is the one
#   the type goes by in user-facing messages.  Report order.
use constant COVERAGE_TYPES => ([LINE_DATA, 'line'],
                                [FUNCTION_DATA, 'function'],
                                [BRANCH_DATA, 'branch'],
                                [MCDC_DATA, 'MC/DC']);

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
    #            testcase_name -> FunctionMap ]
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
    # return BranchData map of line number -> BranchLocation
    #   data is merged over all testcases
    my $self = shift;
    return $self->[BRANCH_DATA]->[0];
}

sub isAliased
{
    # True when the summary map for $slot is the very object that one testcase's
    #   map is, rather than an independent copy of it.  When a section is the
    #   only one holding data for $slot, the summary would be a bit-identical
    #   copy of that one testcase's map, so the reader aliases the two rather
    #   than keeping both - see '_installSection'.
    # Code which mutates the summary and the per-testcase data as two separate
    #   steps needs to know:  with an alias in place both steps act on one
    #   object, so the second is redundant at best and fatal at worst.
    # $slot is one of ALIASED_SLOTS:  each holds [summary, per-testcase map],
    #   and the alias has the same shape in each.
    #
    # Ask per slot, not once for the whole TraceInfo.
    #   In all normal cases, a single testname means every coverage type
    #     present is aliased.  This is true of all 'capture' data...there is
    #     only one testname per capture, and all data is aliased.
    #   In weird cases, this might not be true after 'merge' - specifically
    #     if one 'testname' contains both MC/DC and branch data (say) and
    #     another contains only branch data...then MC/DC data will be
    #     aliased, but branch data won't be.
    #     This probably makes no sense in practice - only an artifact of
    #     a bloody-minded user.
    # '_installSection' installs one only when that type's per-testcase map
    #    and summary are both still empty - and a merge can leave the types
    #   in different states.
    my ($self, $slot)   = @_;
    my ($sum, $perTest) = @{$self->[$slot]};
    my $addr = Scalar::Util::refaddr($sum);
    foreach my $testname ($perTest->keylist()) {
        return 1
            if Scalar::Util::refaddr($perTest->value($testname)) == $addr;
    }
    return 0;
}

sub _materialize_aggregate
{
    # Break the alias described in 'isAliased', by giving the summary a copy of
    #   its own contents, for callers which really do need two independent
    #   objects - see 'TraceInfo::merge', which merges another TraceInfo's data
    #   into each per-testcase map and then into the summary, and which can end
    #   up with more testcases than the one an alias is valid for.
    # Where the two mutations are the same mutation, prefer 'isAliased' and just
    #   do it once:  that is cheaper than this, which copies the whole map.
    # The alias is detected rather than tracked in a flag, so this is safe to
    #   call unconditionally and callers need not know whether one is in place.
    #   It is also idempotent:  after the copy, nothing aliases the summary.
    my ($self, $slot) = @_;
    return 0 unless $self->isAliased($slot);
    # leave the per-testcase map alone and give the summary the copy:  the
    #   summary is the merge over all testcases, which for one testcase is
    #   exactly a copy of its map
    $self->[$slot]->[0] = Storable::dclone($self->[$slot]->[0]);
    return 1;
}

sub materializeAggregates
{
    # Break every alias this TraceInfo holds, whichever coverage types happen to
    #   have one - for callers which mutate the summary and the per-testcase data
    #   as independent objects and do not care which types are present.  Saves
    #   them naming the slots, so a coverage type which gains an alias later is
    #   picked up here rather than at each call site.
    my $self    = shift;
    my $changed = 0;
    foreach my $slot (ALIASED_SLOTS) {
        $changed = 1 if $self->_materialize_aggregate($slot);
    }
    return $changed;
}

sub _installSection
{
    # Install one coverage type's data, just read for one '.info' file section.
    #   Common to every type:  $slot selects which, and the reader calls this
    #   once per type per section.
    #
    # The reader accumulates a section's records into a scratch map - 'DA:',
    #   'FN:'/'FNDA:', 'BRDA:' or 'MCDC:' according to $slot - and then has to
    #   get that data to two places:  the map for this testname and the summary
    #   map merged over all testcases.  'union' deep-copies every line the
    #   destination does not already hold, so the obvious pair of unions copies
    #   each coverpoint twice - and then keeps both copies for the life of the
    #   run.
    #
    # Both costs are avoidable in the case nearly every '.info' file is:  a
    #   single section for a single testname.
    #   - A union into an empty destination is by definition just that copy, so
    #     hand the scratch map to the per-testcase data instead of copying it.
    #   - If the summary is empty as well, and this is the only testname, then
    #     the summary would be a bit-identical copy of that one map:  alias
    #     them.  '_materialize_aggregate' breaks the alias again if the two ever
    #     have to diverge.
    #
    # The caller must not write to $map after this returns:  it now belongs to
    #   the per-testcase data, and possibly to the summary too.
    my ($self, $slot, $testname, $map, $filename) = @_;

    # Break any alias already in place first, so that what follows can treat
    #   the summary as an ordinary independent map and decide on its own terms
    #   whether to install a new alias.  A no-op unless an alias exists.
    $self->_materialize_aggregate($slot);
    my $perTest = $self->[$slot]->[1];
    my $sum     = $self->[$slot]->[0];

    my $mine = $perTest->value($testname);
    if (defined($mine) && 0 != scalar($mine->keylist())) {
        # A second section for a testname we have already seen - so the
        #   hand-over is not available and both destinations take a merge.
        #   ('$filename' is passed only for MC/DC, whose union uses it in
        #   diagnostics; every other type's union ignores a second argument.)
        $mine->union($map, $filename);
        $sum->union($map, $filename);
        return;
    }
    # the map for this testname is absent, or is one we can discard because it
    #   holds nothing
    $perTest->replace($testname, $map);
    if ($MAY_ALIAS_SLOT{$slot} &&
        0 == scalar($sum->keylist()) &&
        1 == $perTest->entries()) {
        # the only testname, and nothing in the summary yet
        $self->[$slot]->[0] = $map;
        return;
    }
    $sum->union($map, $filename);
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
        # Every type whose map maintains its cached found/hit incrementally, so
        #   that the cache can be checked against a full walk of the data - the
        #   assertion that an unbroken alias violates, since a map merged twice
        #   ends up with counts no walk of it agrees with.  Line data is the one
        #   this catches most quietly:  a line count merged twice is still 'hit',
        #   so every rate still reads right and only the count is wrong.
        # FUNCTION_DATA is absent deliberately, not by omission:  'FunctionMap'
        #   caches nothing and computes found/hit on demand, so it has nothing to
        #   check and no '_checkCounts' to call.
        foreach my $slot (LINE_DATA, BRANCH_DATA, MCDC_DATA) {
            my ($sum, $perTest) = @{$self->[$slot]};
            $sum->_checkCounts();
            foreach my $t ($perTest->keylist()) {
                $perTest->value($t)->_checkCounts();
            }
        }
    }
}

sub checkTestcaseData
{
    # Complain about a source file whose coverage types disagree about which
    #   testcases have data for it:  two or more testcases contributed to some
    #   type, but another type - which does have data - is missing one of them.
    #   That is the weird case 'isAliased' talks about:  it can only be produced
    #   by merging tracefiles which were captured with different coverage types
    #   enabled, and it makes the per-testcase tables of the same file
    #   incomparable.  Nothing here changes the data - it is only a diagnostic.
    # Called on the final merge result, not per input file:  a type missing from
    #   one input is entirely normal and may well be supplied by the next one.
    my $self     = shift;
    my $filename = $self->filename();

    my @types;    # [covertype, [testnames]] for each type which has any data
    my %all;      # every testname any type has data for
    foreach my $t (COVERAGE_TYPES) {
        my ($slot, $covertype) = @$t;
        next if $slot == FUNCTION_DATA && !$lcovutil::func_coverage;
        next if $slot == BRANCH_DATA   && !$lcovutil::br_coverage;
        next if $slot == MCDC_DATA     && !$lcovutil::mcdc_coverage;
        my $perTest = $self->[$slot]->[1];
        # an entry which is present but holds nothing counts as absent
        my @names = grep({
                             my $m = $perTest->value($_);
                             defined($m) && 0 != scalar($m->keylist());
        } $perTest->keylist());
        # A type with no data at all anywhere in this file is not an
        #   inconsistency - a tracefile with no branch data, say, is ordinary.
        next unless @names;
        push(@types, [$covertype, \@names]);
        $all{$_} = 1 foreach (@names);
    }
    # One testcase (or none) - there is nothing for the types to disagree about,
    #   since every type which has data has it for that one name.  A shortcut,
    #   not a special case:  the loop below would find nothing either.
    return unless 1 < scalar(keys(%all));

    foreach my $t (@types) {
        my ($covertype, $names) = @$t;
        my %have = map({ ($_ => 1) } @$names);
        foreach my $testname (sort(keys(%all))) {
            next if exists($have{$testname});
            # once per sourcefile per covertype per testname
            next
                unless lcovutil::warn_once($lcovutil::ERROR_INCONSISTENT_DATA,
                                           "$filename:$covertype:$testname");
            lcovutil::ignorable_warning($lcovutil::ERROR_INCONSISTENT_DATA,
                               "no $covertype data for $testname in $filename");
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

    # Below, each per-testcase map is merged and then the summary is merged
    #   separately - so if my summary is an alias of one of my per-testcase
    #   maps, the same object would be merged twice and its counts would
    #   silently double.  ('$info' needs no such treatment:  it is only ever a
    #   source here, and none of the set operations mutate their source.)
    $self->materializeAggregates();

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
              FILENAME       => 0,
              PATH           => 1,
              SOURCE         => 2,
              EXCLUDE        => 3,
              BRANCH_EXCLUDE => 4,

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

sub isRecoveredBaselineFile
{
    return undef;
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
             [$excl_ex_start,
              $excl_ex_stop,
              \$exclude_exception_region,
              e_EXCEPTION | EXCLUDE_BRANCH_REGION,
              $lcovutil::EXCL_EXCEPTION_BR_START,
              $lcovutil::EXCL_EXCEPTION_BR_STOP,
             ],
             [$excl_br_start, $excl_br_stop,
              \$exclude_br_region, e_BRANCH | EXCLUDE_BRANCH_REGION,
              $lcovutil::EXCL_BR_START, $lcovutil::EXCL_BR_STOP,
             ]);
    } else {
        $excl_br_line = undef;
        $excl_ex_line = undef;
    }
    LINES: foreach (@$sourceLines) {
        $line += 1;
        my $exclude_branch_line           = 0;
        my $exclude_exception_branch_line = 0
            ; # per-line exception exclusion not implemented at present.  Probably unnecessary.
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
                               " at line $line - but no matching " .
                               $d->[5] .
                               ' for ' . $d->[4] . ' at line ' . $$ref->[0])
                    if $$ref;
                $$ref = [$line, $reason, $d->[4], $d->[5]];
                last;
            } elsif ($_ =~ $stop) {
                lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                              "$filename: found " . $d->[5] .
                                  " directive at line $line without matching " .
                                  ($$ref ? $$ref->[2] : $d->[4]) .
                                  ' directive')
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
    #   - The latter condition is used to check for branch-only or exception-
    #     only exclusions, as well as to check whether this line is
    #     unreachable (as opposed to excluded).
    my ($self, $lineNo, $flags, $skipRangeCheck) = @_;
    my $data = $self->[0];
    if (!defined($data->[EXCLUDE]) || scalar(@{$data->[EXCLUDE]}) < $lineNo) {
        # this can happen due to version mismatches:  data extracted with
        # version N of the file, then generating HTML with version M
        # "--version-script callback" option can be used to detect this

        # if we are just checking whether this line is in an unreachable region,
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
                                    (defined($data->[EXCLUDE]) ?
                                         (" there are only " .
                                          scalar(@{$data->[EXCLUDE]}) .
                                          " lines in the file.") :
                                         "") .
                                    $suffix
        ) if lcovutil::warn_once($lcovutil::ERROR_RANGE, $key);
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

# '.info' record dispatch, for '_read_info' below.
#
# The obvious way to recognize a record is a chain of anchored regular
#   expressions, one per record type, tried in turn - but then every line pays
#   for every type ahead of its own:  in a chain ordered as the format
#   description is, a 'BRDA:' record costs 11 match attempts and an 'MCDC:'
#   record 12, and all but the last of them are known to fail before they are
#   run.  Since a record is identified entirely by the tag before its first
#   ':', take the tag with one index()/substr() and look the case up here
#   instead;  the only regular expression which then runs is the one belonging
#   to the case that matched, for the capture groups its handler needs.
#   Measured over a 132 MB MC/DC '.info' file (7.6 M records), dispatch alone
#   goes from 5.32 s to 3.41 s.
#
# A tag which is NOT in this table falls to the slow path in '_read_info',
#   which keeps every test the chain used to end with - comment, blank line,
#   'end_of_record', the ignored count records, and finally the
#   malformed-record error - so a line which used to be accepted is still
#   accepted, and one which used to be an error is still that same error.
use constant {
              REC_UNKNOWN => 0,     # not a tag this table carries
              REC_FILE    => 1,     # 'SF:' or 'KF:'
              REC_TN      => 2,
              REC_VER     => 3,
              REC_DA      => 4,
              REC_FN      => 5,
              REC_FNDA    => 6,
              REC_FNL     => 7,
              REC_FNA     => 8,
              REC_BRDA    => 9,
              REC_MCDC    => 10,
              REC_SUMMARY => 11,    # 'LF:', 'LH:', 'FNF:', ... - ignored
              REC_SKIP    => 12,    # a cover type which is turned off
};

# The tags, and the case each maps to when every cover type is enabled.  This
#   is the master table:  '%recordDispatch' below is what '_read_info' actually
#   looks records up in.
my %recordCase = (
                 'SF'   => REC_FILE,
                 'KF'   => REC_FILE,
                 'TN'   => REC_TN,
                 'VER'  => REC_VER,
                 'DA'   => REC_DA,
                 'FN'   => REC_FN,
                 'FNDA' => REC_FNDA,
                 'FNL'  => REC_FNL,
                 'FNA'  => REC_FNA,
                 'BRDA' => REC_BRDA,
                 'MCDC' => REC_MCDC,
                 map({ ($_ => REC_SUMMARY) } qw(LF LH FNF FNH BRF BRH MCF MCH)),
);

# Which tags belong to which cover type, for the REC_SKIP redirection below.
my %recordCoverType = ('FN'   => \$lcovutil::func_coverage,
                       'FNDA' => \$lcovutil::func_coverage,
                       'FNL'  => \$lcovutil::func_coverage,
                       'FNA'  => \$lcovutil::func_coverage,
                       'BRDA' => \$lcovutil::br_coverage,
                       'MCDC' => \$lcovutil::mcdc_coverage,);

# '%recordCase', with the tags of the cover types which are turned off
#   redirected to REC_SKIP:  '_read_info' drops those records as soon as it has
#   identified the tag, without running the record's regular expression.  The
#   regular expression is most of what reading such a record costs and all of
#   what validating it costs, so this is both the whole saving and the whole
#   behaviour change - see the note in the 'TRACEFILE FORMAT' section of
#   geninfo(1).
#
# Built on first use rather than at load time because the cover type flags are
#   not final until the command line and the config files have been parsed.
#   They are written only during option parsing - see 'postParseArgs' here, and
#   the toolchain capability checks in 'geninfo' - and never afterwards, so one
#   snapshot serves the whole run.  If some future caller does need to change a
#   flag after a '.info' file has been read, it has to clear this table so that
#   the next read rebuilds it.
my %recordDispatch;

sub _init_record_dispatch()
{
    %recordDispatch = %recordCase;
    while (my ($tag, $enabled) = each(%recordCoverType)) {
        $recordDispatch{$tag} = REC_SKIP unless $$enabled;
    }
}

sub load
{
    # '$chunk' is the part of the file to read rather than all of it - see
    #   '_read_info' and 'AggregateTraces::_partition_sections'
    my ($class, $tracefile, $readSource, $verify_checksum,
        $ignore_function_exclusions, $chunk)
        = @_;
    my $self    = $class->new();
    my $context = MessageContext->new("loading $tracefile");

    $self->_read_info($tracefile, $readSource, $verify_checksum, $chunk);

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
    # deserialize_checked() turns a cross-format (XS vs pure-Perl) mismatch
    # into an ERROR_FORMAT with a hint; a genuinely corrupt file also lands
    # there.  It returns undef on any such failure.
    my $self = lcovutil::deserialize_checked($file);
    defined($self)       or die("unable to deserialize $file\n");
    ref($self) eq $class or die("did not deserialize a $class");
    return $self;
}

sub empty
{
    my $self = shift;

    my @totals = $self->count_totals();
    foreach my $d (['function', $lcovutil::func_coverage, 3],
                   ['branch', $lcovutil::br_coverage, 2],
                   ['MC/DC', $lcovutil::mcdc_coverage, 4]
    ) {
        my ($type, $flag, $idx) = @$d;
        next unless $flag;
        lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
               "$type coverage enabled but no corresponding coverpoints found.")
            if 0 == $totals[$idx]->[0];
    }
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

sub checkTestcaseData
{
    # Warn about any file whose coverage types disagree about which testcases
    #   have data - see 'TraceInfo::checkTestcaseData'.  Call this only on a
    #   final merge result:  the check is meaningless on a partial one.
    my $self = shift;
    foreach my $name ($self->files()) {
        $self->data($name)->checkTestcaseData();
    }
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
                    $entry->mcdc_found(), $entry->mcdc_hit(),
                    $entry->function_found(), $entry->function_hit());
        my $idx = 0;
        foreach my $t ('line', 'branch', 'condition', 'function') {
            foreach my $x ('found', 'hit') {
                $data{$t}->{$x} = $data[$idx] if $perFile;
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
                                   $counts[4]->[0], $counts[4]->[1], "condition"
                   )) if ($mcdc_do);
}

sub skipCurrentFile
{
    my ($filename, $fileTypeName) = @_;

    if (defined($fileTypeName)) {
        $fileTypeName .= ' ';
    } else {
        $fileTypeName = '';
    }
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
                "Excluding $fileTypeName\"$filename\": does not exist/is not readable\n"
            );
            ++$filt->[-2];
            ++$filt->[-1];
            return 1;
        }
    }

    # check whether this file should be excluded or not...
    foreach my $p (@lcovutil::exclude_file_patterns) {
        my $pattern = $p->[0];
        if ($filename =~ $pattern) {
            lcovutil::info(1,
                  "exclude $fileTypeName$filename: matches '" . $p->[1] . "\n");
            ++$p->[-1];
            return 1;    # all done - explicitly excluded
        }
    }
    if (@lcovutil::include_file_patterns) {
        foreach my $p (@lcovutil::include_file_patterns) {
            my $pattern = $p->[0];
            if ($filename =~ $pattern) {
                lcovutil::info(1,
                               "include: $fileTypeName$filename: matches '" .
                                   $p->[1] . "\n");
                ++$p->[-1];
                return 0;    # explicitly included
            }
        }
        lcovutil::info(1,
                       "exclude $fileTypeName$filename: no include matches\n");
        return 1;    # not explicitly included - so exclude
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
                                      $fcn->line() . ":$end_line] due to '" .
                                      $p->[-2] . "'\n");
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
                                  '"' .
                                      $func->filename() . '":' . $func->line() .
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

    # The count is assigned, but each alias is ADDED to - so an entry reached
    #   twice ends up with double the alias counts it should have.  $func comes
    #   from the summary map, which for a single testcase is that testcase's map
    #   itself, so it can turn up again in the loop below:  collect by address
    #   and fix each entry exactly once.
    my $line         = $func->line();
    my %fix          = (Scalar::Util::refaddr($func) => $func);
    my $per_testcase = $traceInfo->testfnc();
    foreach my $testname ($per_testcase->keylist()) {
        my $data = $traceInfo->testfnc($testname);
        my $f    = $data->findKey($line);
        $fix{Scalar::Util::refaddr($f)} = $f if defined($f);
    }
    my @fix = values(%fix);

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
                #  - if no other lines are hit, then the function is not
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
    #     expression is statically determined to be true or false - and elided
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

            # create the entry in the per-testcase data - but not a second time
            #   in the map we just wrote to.  For a single testcase the summary
            #   IS that testcase's map, and 'append' adds, so fabricating the
            #   line in both would give it twice the hit count of the MC/DC it
            #   was derived from.
            my $sumAddr = Scalar::Util::refaddr($lineData);
            foreach my $testcase ($testcase_mcdc->keylist()) {
                my $m = $testcase_mcdc->value($testcase);
                if ($m->value($line)) {
                    my $t = $traceInfo->test($testcase);
                    next if Scalar::Util::refaddr($t) == $sumAddr;
                    $t->append($line, $hit);
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

            my $lineHit  = $lineData->value($line);
            my $location = $brData->value($line);
            unless (defined($lineHit)) {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                      '"' . $traceInfo->filename() .
                          "\":$line: location has branchcov but no linecov data"
                          . _consistencySuffix());
                # must have ignored the above error - so build fake line data
                #  here (maybe should delete the branch instead?)
                # This arm wants the actual hit COUNT, so it is the one caller
                #   that needs the full totals() walk - and it runs only when
                #   the error above was ignored.
                $lineData->append($line, ($location->totals(1))[1]);
                next;
            }

            # Everything below only asks whether ANY branch here was evaluated,
            #   so use the short-circuiting predicate rather than counting every
            #   element on the line and discarding the count.
            my $brHit = $location->hasHitElement(1);

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
        $modified = 1 if _checkConsistency($traceInfo);
        if (0 == ($actions & DID_FILTER)) {
            return [$traceInfo, $modified];
        }
    }
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
        if defined($FILTER_MCDC_SINGLE) && $lcovutil::mcdc_coverage;

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
    # This only checks the file version if we are checking the 'current'
    #   file:  either we are reading the 'current' .info and checking the
    #   current file, or we are looking for the 'baseline' version and that
    #   version has not changed between baseline and current (i.e., this
    #   file is not in the 'diff-file').
    # If the file _has_ changed between 'baseline' and current, then we
    #   don't have a way to independently verify that what we see in
    #   'ReadBaselineSource' is really the previous version of the file.
    my $fileVersion = lcovutil::extractFileVersion($path)
        if $srcReader->notEmpty();
    if (defined($fileVersion) &&
        !$srcReader->isRecoveredBaselineFile($path) &&
        defined($traceInfo->version())
        &&
        !lcovutil::checkVersionMatch($source_file, $traceInfo->version(),
                                     $fileVersion, 'filter')
    ) {
        lcovutil::info(1,
                      "$source_file: skip filtering due to version mismatch\n");
        return ($traceInfo, 0);
    }

    if (defined($lcovutil::func_coverage) &&
        (0 != scalar(@lcovutil::exclude_function_patterns) ||
            defined($trivial_histogram) ||
            defined($region))
    ) {
        # filter excluded function line ranges
        #   This erases from the summary and from each per-testcase map.  Every
        #   removal here is 'remove if present' ('_eraseFunction'), and a
        #   function erased from the master map is no longer in its 'keylist',
        #   so reaching one map twice - which is what an aliased summary means -
        #   costs nothing and cannot corrupt data.
        #   What it does affect is the statistics:  those are counted only on
        #   the master pass ('$isMasterList'), so the master pass has to run
        #   FIRST.  Run the per-testcase maps first and, for an aliased summary,
        #   the function is already gone by the time the master pass looks for
        #   it - nothing matches, and the exclusion pattern is reported unused.
        my $funcData   = $traceInfo->testfnc();
        my $lineData   = $traceInfo->test();
        my $branchData = $traceInfo->testbr();
        my $mcdcData   = $traceInfo->testcase_mcdc();
        my $checkData  = $traceInfo->check();
        my $reader     = (defined($trivial_histogram) || defined($region)) &&
            $srcReader->notEmpty() ? $srcReader : undef;

        $modified = 1
            if _eraseFunctions($source_file, $reader,
                               $traceInfo->func(), $traceInfo->sum(),
                               $traceInfo->sumbr(), $traceInfo->mcdc(),
                               $traceInfo->check(), $state,
                               1);
        foreach my $tn ($lineData->keylist()) {
            $modified = 1
                if _eraseFunctions(
                                 $source_file, $reader,
                                 $funcData->value($tn), $lineData->value($tn),
                                 $branchData->value($tn), $mcdcData->value($tn),
                                 $checkData->value($tn), $state,
                                 0);
        }
    }

    return
        unless ($srcReader->notEmpty() &&
                lcovutil::is_filter_enabled());

    # Every filter below which can drop a coverpoint - of any type - removes it
    #   from each per-testcase map and then from the summary.  When the summary
    #   is aliased to the single testcase's map those are the same object and the
    #   same removal, so doing both would walk the data twice and the second
    #   removal of an already deleted line would die:  in 'BranchMap::remove'
    #   for branches, in 'CountData::remove' for lines, and in
    #   'FunctionMap::remove' for functions, which is handed the undef that
    #   'findKey' returns for a function already gone.
    # Rather than break the alias - which means copying the whole map, the very
    #   copy the alias exists to avoid - just ask, and remove once.  Filtering
    #   does not need two independent objects:  it applies the identical change
    #   to both, so one object reached twice is one object filtered once.
    #
    # The one exception is the user coverpoint callback below, which is handed
    #   both maps and may do anything to them - we cannot assume its mutation is
    #   idempotent, so it gets the two independent objects it would have got
    #   before.  That has to happen here, ahead of both the 'isAliased' queries
    #   and the 'get_info' below, whose locals would otherwise be left pointing
    #   at an alias we then discarded.
    # The shipped 'scripts/unreach.pm' would in fact survive an alias, because
    #   it mutates through 'set_excluded', which returns false the second time
    #   and so guards its own 'adjust_counts'.  That is a property of that one
    #   script and not of the interface:  a callback which adjusts counts
    #   unconditionally sees them applied twice to one map, which drives the
    #   cached found/hit negative.  Hence materializing for any callback at all,
    #   rather than trusting the callback to be idempotent.
    $traceInfo->materializeAggregates()
        if defined($lcovutil::excludeCoverpointCallback);
    # Ask once per type, up front:  'isAliased' walks the per-testcase map, and
    #   the answer cannot change under us because nothing below installs an alias
    #   - only the callback above breaks them, and it has already run.  Keyed by
    #   slot rather than four named scalars so that a type which gains an alias
    #   later needs no new local here.
    my %aliased =
        map({ ($_ => $traceInfo->isAliased($_)) } TraceInfo::ALIASED_SLOTS);

    my ($testdata, $sumcount, $funcdata, $checkdata, $testfncdata,
        $testbrdata, $sumbrcount, $mcdc, $testmcdc) = $traceInfo->get_info();

    my $filterExceptionBranches =
        FilterBranchExceptions->new($srcReader, $sumbrcount, $testbrdata,
                                    $aliased{TraceInfo::BRANCH_DATA});

    foreach my $testname (sort($testdata->keylist())) {
        my $testcount    = $testdata->value($testname);
        my $testfnccount = $testfncdata->value($testname);
        my $testbrcount  = $testbrdata->value($testname);
        my $mcdc_count   = $testmcdc->value($testname);

        my $reason;
        my $functionMap = $testfncdata->value($testname);
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
                    # and remove from the master table - unless it IS one of
                    #   the per-testcase tables above, in which case the
                    #   function is already gone and 'findKey' would hand
                    #   'remove' an undef
                    $funcdata->remove($funcdata->findKey($key))
                        unless $aliased{TraceInfo::FUNCTION_DATA};
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
                $omit                    ||
                defined($lcovutil::excludeCoverpointCallback))
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
                    foreach my $t ([$testbrdata, $sumbrcount,
                                    'BRDA', $aliased{TraceInfo::BRANCH_DATA}
                                   ],
                                   [$testmcdc, $mcdc,
                                    'MCDC', $aliased{TraceInfo::MCDC_DATA}
                                   ]
                    ) {
                        my ($testCount, $sumCount, $str, $isAliased) = @$t;
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
                        # ...and at the top, unless the summary is the map we
                        #   just removed it from
                        $sumCount->remove($line) unless $isAliased;
                        $modified = 1;
                    }
                    next;
                }
                if (defined($filterExceptionBranches) &&
                    defined($sumbrcount) &&
                    defined($sumbrcount->value($line))) {
                    # exclude exception branches here
                    $modified = 1
                        if $filterExceptionBranches->filter($line);
                }
            }    # foreach line
            if ($modified) {
                $sumbrcount->updateCounts();
                foreach my $tn ($testbrdata->keylist()) {
                    $testbrdata->value($tn)->updateCounts();
                }
            }
        }    # if branch_coverage

        # $mcdc_count is undef when this testcase has no MC/DC data at all -
        #   the surrounding block is entered for branch data alone
        if ($mcdc_single && defined($mcdc_count)) {
            # find single-expression MC/DC's - if there is a matching branch
            #  expression on the same line, then remove the MC/DC
            foreach my $line ($mcdc_count->keylist()) {
                my $block  = $mcdc_count->value($line);
                my $groups = $block->groups();
                if (exists($groups->{1}) &&
                    scalar(keys %$groups) == 1) {
                    # $testbrcount is undef when this testcase has no branch
                    #   data at all - '--mcdc' without '--branch', say.  The
                    #   filter is looking for a matching branch expression, so
                    #   with no branch data there is nothing to match and
                    #   nothing to remove.  (Note 8712 and 8726 above already
                    #   guard the same way.)
                    next unless defined($testbrcount);
                    my $branch = $testbrcount->value($line);
                    next unless $branch && ($branch->totals())[0] == 2;
                    $mcdc_count->remove($line);
                    ++$mcdc_single->[-2];    # one MC/DC skipped
                    ++$mcdc_single->[-1];    # one coverpoint

                    # Remove at top, unless that is the map we just removed it
                    #   from - see the aliasing note at the head of this sub.
                    # The present-check matters independently of aliasing:  this
                    #   loop runs once per testcase, so with two testcases
                    #   carrying the same single-condition MC/DC line the second
                    #   pass would otherwise find the summary entry already gone
                    #   and die in 'BranchMap::remove'.  The per-testcase removal
                    #   just above is present-checked for the same reason.
                    $mcdc->remove($line, 1)
                        unless $aliased{TraceInfo::MCDC_DATA};
                    $modified = 1;
                }
            }
        }

        if (defined($lcovutil::excludeCoverpointCallback)) {
            die("expected srcReader")
                unless defined($srcReader) && $srcReader->notEmpty();

            # call user callback to see if MC/DCs or branches are excluded

            foreach my $t ([$lcovutil::br_coverage, 'branch',
                            $testbrdata, $sumbrcount
                           ],
                           [$lcovutil::mcdc_coverage, 'mcdc', $testmcdc, $mcdc]
            ) {
                my ($enable, $str, $testCount, $sumCount) = @$t;
                next unless $enable && $sumCount;
                eval {
                    $modified = 1
                        if $lcovutil::excludeCoverpointCallback->exclude($str,
                                             $srcReader, $testCount, $sumCount);
                };
                if ($@) {
                    lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                        '"unreachable" callback ' .
                            ref($lcovutil::excludeCoverpointCallback) .
                            "->exclude($str, readSrc, summaryDB, perTestDB) failed: $@"
                    );
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

            # don't suppress if this line has associated branch or MC/DC data
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
            # ...and from the summary, unless that is the same map we just
            #   removed it from:  'CountData::remove' dies on a line that is
            #   not there
            $sumcount->remove($line) unless $aliased{TraceInfo::LINE_DATA};
            if ($checkdata->mapped($line)) {
                $checkdata->remove($line);
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
    # called from child, by 'lcovutil::ForkManager':  the capture of my output,
    #   my initial state and the dump of what I return are its business
    my ($chunk, $srcReader, $save, $state, $forkAt, $chunkId) = @_;

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
    my $start = Time::HiRes::gettimeofday();
    my @updates;
    eval {
        foreach my $d (@$chunk) {
            # could keep track of individual file time if we wanted to
            my ($data, $modified) = _filterFile(@$d, $srcReader, $state);

            lcovutil::info(1,
                   $d->[1] . ' is ' . ($modified ? '' : 'NOT ') . "modified\n");
            if ($modified) {
                push(@updates, [$d->[1], $data]);
            }
        }
    };
    if ($@) {
        print(STDERR $@);
        $status = 1;
    }
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

    my $then = Time::HiRes::gettimeofday();
    $lcovutil::profileData{filt_proc}{$chunkId}  = $then - $forkAt;
    $lcovutil::profileData{filt_child}{$chunkId} = $end - $start;
    # '$then' is when I finished:  the parent subtracts it from the time it got
    #   round to me, which is how long my data sat in the queue
    return ([\@updates, $save, $state, $then], $status);
}

# chunkID is only used for uniquification and as a key in profile data.
#  We want this number to be unique - even if we process more than one TraceFile
#  ...and even if we are ourselves a forked worker which is filtering its own
#  data:  our sibling workers have the same counter value, having inherited it
#  across the fork, so the id is qualified with our own job label.  See
#  $lcovutil::jobIdPrefix.
our $masterChunkID = 0;

sub _filterChunkId
{
    return $lcovutil::jobIdPrefix . $masterChunkID;
}

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
                    "lcov_filter_chunk_size '$lcovutil::lcov_filter_chunk_size' not recognized - ignoring\n"
                );
            }
        }

        if (!defined($chunkSize)) {
            $chunkSize =
                $lcovutil::maxParallelism ?
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
    my $tmp = File::Temp->newdir(
                          "filter_datXXXX",
                          DIR     => $lcovutil::tmp_dir,
                          CLEANUP => !defined($lcovutil::preserve_intermediates)
        )
        if (exists($ENV{LCOV_FORCE_PARALLEL}) ||
            $parallel > 1);

    lcovutil::ForkManager->new(
                 operation => 'filter',
                 phase     => 'filter',
                 tempDir   => $tmp,
                 prefix    => 'filter',
                 # the filter workers hold a copy of the data for their own chunk, so
                 #   this is a place where the process count has to answer to the memory
                 #   the children are actually using
                 memoryThrottle => 1,
                 # ..and what a worker holds is the records of the files in its chunk
                 unitWeight => sub {
                     my $chunk  = shift;
                     my $weight = 0;
                     foreach my $d (@$chunk) {
                         $weight += $d->[0]->found() + $d->[0]->branch_found();
                     }
                     return $weight;
                 },
                 remaining => sub { return scalar(@$workList); },
                 next      => sub {
                     # A chunk which is small enough to filter here is filtered here:
                     #   there is no point forking for it.  Keep going until there is
                     #   something worth a process, or nothing left at all.
                     while (@$workList) {
                         my $d = pop(@$workList);
                         ++$processedChunks;
                         # save current counts...
                         $state[0]->[1] = 0;
                         if (ref($d->[0]) eq 'TraceInfo') {
                             # serial processing...
                             my ($data, $modified) =
                                 _filterFile(@$d, $srcReader, \@state);
                             $self->_updateModifiedFile($d->[1], $data, \@state)
                                 if $modified;
                             next;
                         }
                         return ($d, _filterChunkId());
                     }
                     return ();
                 },
                 more     => sub { return scalar(@$workList); },
                 postFork => sub {
                     my ($d, $chunkId, $pid) = @_;
                     lcovutil::debug(1, "fork:$pid ID $chunkId\n");
                     # the id this chunk was given is now used up - see '_filterChunkId'
                     ++$masterChunkID;
                 },
                 child => sub {
                     my ($d, $chunkId, $forkAt) = @_;
                     return
                         _processParallelChunk($d, $srcReader, \@save, \@state,
                                               $forkAt, $chunkId);
                 },
                 preMerge => sub {
                     my $ctx = shift;
                     lcovutil::debug(1, "merge:$ctx->{child} ID $ctx->{id}\n");
                 },
                 merge => sub {
                     my ($d, $chunkId, $payload, $ctx)            = @_;
                     my ($updates, $counts, $state, $childFinish) = @$payload;
                     my $now = Time::HiRes::gettimeofday();
                     $lcovutil::profileData{filt_undump}{$chunkId} =
                         $now - $ctx->{reapAt};

                     foreach my $patType (@{$save[0]}) {
                         my $svType = shift(@{$counts->[0]});
                         foreach my $p (@$patType) {
                             $p->[-1] += shift(@$svType);
                         }
                     }
                     for (my $i = scalar(@{$save[1]}) - 1; $i >= 0; --$i) {
                         $save[1]->[$i]->[-2] += $counts->[1]->[$i]->[0];
                         $save[1]->[$i]->[-1] += $counts->[1]->[$i]->[1];
                     }
                     foreach my $u (@$updates) {
                         $self->_updateModifiedFile(@$u, $state);
                     }

                     my $final = Time::HiRes::gettimeofday();
                     $lcovutil::profileData{filt_merge}{$chunkId} =
                         $final - $now;
                     $lcovutil::profileData{filt_queue}{$chunkId} =
                         $ctx->{reapAt} - $childFinish;
                 },
                 postReap => sub {
                     my $ctx = shift;
                     $lcovutil::profileData{filt_chunk}{$ctx->{id}} =
                         Time::HiRes::gettimeofday() - $ctx->{forkAt};
                 },
                 requeue => sub {
                     my ($d, $chunkId, $why) = @_;
                     # a chunk we never managed to fork was counted as processed on the
                     #   way past
                     --$processedChunks if ('fork' eq $why);
                     push(@$workList, $d);
                 },
                 # Whatever went wrong with this child, say it once, out here, the way
                 #   the hand-written loop did:  a die anywhere in the merge is the
                 #   child's fault as far as the user is concerned.
                 rethrowMergeFailure => 1,
                 wrapReap            => sub {
                     my ($child, $rawStatus, $err) = @_;
                     $rawStatus = 1 << 8 unless $rawStatus;
                     lcovutil::report_parallel_error('filter',
                              $lcovutil::ERROR_CHILD, $child, $rawStatus, $err);
                 },
                 forkFailWhen => sub { return 'process filter chunk'; },
                 retryWhen    => sub { return "filter segment $_[0]->{id}"; },
                 mergeFailMessage => sub { return $_[0]->{error}; },
                 # a child which left data we cannot use is a parallelism failure rather
                 #   than a failure of the work it was doing
                 childFailError   => $lcovutil::ERROR_PARALLEL,
                 childFailMessage => sub {
                     return 'unable to filter segment ' . $_[0]->{id};
                 },)->run();
    # ..but not if I am one of the chunks the input set was split into - see
    #   'AggregateTraces::_parallel_parse':  the user's stdout would carry one
    #   copy of this per chunk.
    lcovutil::info("Finished filter file processing\n")
        unless $lcovutil::in_child_process;
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
        lcovutil::info("Apply filtering..\n")
            unless $lcovutil::in_child_process;    # ..once, not once per chunk
        $self->_processFilterWorklist($srcReader, \@filter_workList);
        # keep track - so we don't do this again
        $self->[STATE] |= DID_FILTER;
    }
}

sub is_language
{
    my ($lang, $filename) = @_;
    my $idx = rindex($filename, '.');
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
# The section table which 'scan_sections' below builds, and which
#   'AggregateTraces::_parallel_parse' partitions.  One entry per section.
use constant {
             SEC_START    => 0,   # offset of the section's first byte
             SEC_END      => 1,   # offset just past its 'end_of_record' line
             SEC_LINE     => 2,   # '.info' line number of its first line
             SEC_NLINES   => 3,   # number of lines in it
             SEC_FILE     => 4,   # its 'SF:'/'KF:' name, undef if it has none
             SEC_TESTNAME => 5,   # payload of the 'TN:' in force, undef if none
                # Which input the section came from:  an index into the list of
                #   input files, appended by '_plan_parallel_parse' after this
                #   scan, which sees one file at a time and has no opinion about
                #   where it sits in that list.
             SEC_INPUT => 6,
};

# The source file and testcase a scanned section belongs to:  return
#   ('SF:' name, 'TN:' payload), either of which may be undefined.
#
# The section is delimited by 'end_of_record', and the reader below recovers from
#   a missing one - so a section as this scan sees it can hold more than one file
#   record.  Report no name at all in that case rather than the first of them:
#   the partitioner's contract is that all of one source file's data goes to one
#   child, and it cannot honour that for a section it cannot attribute.  It
#   declines to split - and since a chunk may span inputs, that means the whole
#   set, not just this input - which is the right answer for input this
#   malformed:  the reader then reports it exactly as it always has.
# The testcase name is only taken from before the file record, because that is
#   where the reader takes it:  a 'TN:' which arrives after it is an error, and
#   is ignored rather than changing the name in force.
sub _scan_section_names($)
{
    my $section = shift;

    my $nFiles = () = $section =~ /^[SK]F:/mg;
    return (undef, undef) if (1 != $nFiles);
    $section =~ /^[SK]F:(.*)$/m;
    my $sf   = $1;
    my $head = substr($section, 0, $-[0]);
    my ($tn) = $head =~ /^TN:(.*)$/m;
    return ($sf, $tn);
}

# Find the sections of a '.info' file without parsing it:  return a reference
#   to a list of section descriptors (see the constants above), in file order.
#
# This is the pre-pass of the parallel read.  Sections are self-delimiting, so a
#   reader can be pointed at any one of them - but only if someone has found the
#   boundaries first, and that has to be cheap enough not to eat the parallelism
#   it enables.  Measured on a 132.1 MB / 7.6 M line / 401 section file: 0.175 s,
#   against 15.4 s to parse the same file, and against 0.914 s for the same scan
#   written as a 'readline' loop.
#
# Three things beyond the offsets are recorded, and each of them is needed:
#   - the line count, because it is the unit of work the partitioner balances
#     (see '$lcovutil::parallel_parse_min_lines') and because the reader needs a
#     line number to start counting from, so that its diagnostics stay truthful;
#   - the 'SF:' name, so that every section naming one source file can be given
#     to one child:  that keeps the parent's merge free, keeps
#     '$AggregateTraces::function_mapping' from listing an input twice, and is
#     what makes it sound for a child to filter what it read;
#   - the 'TN:' payload, because a '.info' file may name its testcase once and
#     then rely on it for every section which follows ('TN:' is optional - see
#     the grammar in '_read_info'), so a reader which starts in the middle of the
#     file has to be told the name which is in force there.
#
# Die on error.
sub scan_sections($)
{
    my $tracefile = shift;

    open(my $handle, '<', $tracefile) or
        die("cannot read $tracefile: $!\n");
    binmode($handle);

    # 'end_of_record' closes a section wherever it starts a line - the reader
    #   below tests '/^end_of_record/', so anything else on the line is ignored
    #   rather than being a different record.  Match that exactly:  a scan which
    #   was stricter would run two of the reader's sections together, and this
    #   table would then name only the first one's source file.
    my $needle = 'end_of_record';
    my $nlen   = length($needle);

    my @sections;
    my $offset    = 0;     # offset of the first byte of '$buffer'
    my $start     = 0;     # offset of the first byte of the open section
    my $line      = 1;     # line number of that byte
    my $held      = '';    # the open section's bytes, from earlier buffers
    my $heldLines = 0;
    my $testname;
    my $buffer;

    while (read($handle, $buffer, 4 * 1024 * 1024)) {
        # Complete the buffer to a line boundary, so that no record straddles
        #   two of them:  every offset below is then within one buffer, and one
        #   'index' walk per buffer finds every section end.  One extra
        #   'readline' per 4 MB is not measurable.
        if (substr($buffer, -1) ne "\n") {
            my $rest = <$handle>;
            $buffer .= $rest if defined($rest);
        }
        my $from     = 0;    # where to look for the next 'end_of_record'
        my $bodyFrom = 0;    # where the open section starts, within '$buffer'
        while (1) {
            my $at = index($buffer, $needle, $from);
            if ($at < 0) {
                # no more section ends in this buffer:  carry what is left of
                #   the open section forward
                my $tail = substr($buffer, $bodyFrom);
                $held .= $tail;
                $heldLines += ($tail =~ tr/\n//);
                last;
            }
            if ($at != 0 &&
                substr($buffer, $at - 1, 1) ne "\n") {
                # not at the start of a line, so not a section end:  the text
                #   appears inside some other record, or in a comment
                $from = $at + $nlen;
                next;
            }
            # the section ends at the end of this line
            my $eol = index($buffer, "\n", $at + $nlen);
            $eol = length($buffer) - 1 if ($eol < 0);   # unterminated last line
            my $body  = substr($buffer, $bodyFrom, $eol + 1 - $bodyFrom);
            my $whole = $held . $body;
            my ($sf, $tn) = _scan_section_names($whole);
            $testname = $tn if defined($tn);
            my $nLines = $heldLines + ($body =~ tr/\n//);
            push(@sections,
                 [$start, $offset + $eol + 1, $line, $nLines, $sf, $testname]);
            $line += $nLines;
            $start     = $offset + $eol + 1;
            $held      = '';
            $heldLines = 0;
            $bodyFrom  = $from = $eol + 1;
        }
        $offset += length($buffer);
    }
    close($handle) or die("unable to close $tracefile: $!\n");

    # Anything left after the last 'end_of_record'.
    if (length($held)) {
        # a file whose last line has no newline still has that line
        my $nLines = $heldLines + (substr($held, -1) eq "\n" ? 0 : 1);
        if ($held =~ /^[SK]F:/m) {
            # a section which was never closed - a truncated or corrupt file.
            #   Keep it, running to end of file, so that the reader sees it and
            #   reports it exactly as it would have in an unpartitioned read.
            my ($sf, $tn) = _scan_section_names($held);
            $testname = $tn if defined($tn);
            push(@sections, [$start, $offset, $line, $nLines, $sf, $testname]);
        } elsif (@sections) {
            # trailing comments or blank lines:  legal anywhere, and they
            #   produce nothing.  Hand them to the last section rather than
            #   calling them one, which would leave a section with no file for
            #   the partitioner to attribute and cost the whole file its split.
            $sections[-1]->[SEC_END] = $offset;
            $sections[-1]->[SEC_NLINES] += $nLines;
        }
    }
    return \@sections;
}

# Die on error.
#
sub _read_info
{
    my ($self, $tracefile, $readSourceCallback, $verify_checksum, $chunk) = @_;
    $verify_checksum = 0 unless defined($verify_checksum);

    if (!defined($readSourceCallback)) {
        $readSourceCallback = ReadCurrentSource->new();
    }

    # per file data
    my $sumcount;      # line total counts in this file
    my $funcdata;      # function total counts in this file
    my $sumbrcount;    # branch total counts
    my $mcdcCount;     # MD/DC total counts

    my $checkdata;     # line checksums
        # hash of per-testcase coverage data per testcase, in this file
    my $testdata;       # hash of testname -> line coverage
    my $testfncdata;    # hash of testname -> function coverage
    my $testbrdata;     # hash of testname -> branch data
    my $testMcdc;       #     -> MC/DC data

    my $lineMap;        # line coverage for particular testcase
    my $funcMap;        # func coverage   "    "
    my $branchMap;      # branch coverage "   "
    my $mcdcMap;        # MC/DC coverage  "   "

    my $testname;            # Current test name
    my $filename;            # Current filename
    my $current_mcdc;
    my $changed_testname;    # If set, warn about changed testname

    lcovutil::info(1, "Reading data file $tracefile\n");

    # See '%recordDispatch' above:  first read builds it from the cover type
    #   flags, which are final by now.
    _init_record_dispatch() unless %recordDispatch;

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
    my $inFile = InOutFile->in($tracefile, $lcovutil::demangle_cpp_cmd);
    local *INFO = $inFile->hdl();

    # '$chunk' is a part of the file to read rather than all of it - a list of
    #   runs of consecutive sections, each '[startOffset, endOffset, startLine,
    #   testnamePayload]', as built by 'AggregateTraces::_partition_sections'.
    #   Undefined means the whole file, which is what every caller but the
    #   parallel read passes.  A chunk is only ever built for a seekable input:
    #   gzipped, demangled and stdin input arrives through a pipe.
    # 0 whence SEEK_CUR:  true for a file, false for a pipe
    die("cannot read part of a stream")
        if (defined($chunk) && !seek(INFO, 0, 1));
    my @runs = defined($chunk) ? @$chunk : ([undef, undef, undef, undef]);

    $testname = "";
    my $fileData;
    my $functionMap;
    my $skipCurrentFile = 0;
    my %fnIdxMap;
    my $branchBlock;
    my $currentBlockLine;
    my $currentBlock;
    my $branchIndex;

    # A valid .info file is a sequence of sections:
    #
    #   tracefile := ( comment | blank )*  section*
    #   section   := 'TN:'?  'SF:'  ( coverpoint | 'VER:' | comment | blank )*
    #                'end_of_record'
    #
    # so where a record appears is as much a part of the format as its syntax:
    #   'TN:' names the testcase the section's data belongs to and so has to
    #   precede it, and a coverpoint record only means anything within a
    #   section.  Track whether one is open, so a record which is out of place
    #   is an ERROR_FORMAT rather than being silently attributed to whichever
    #   file happened to be read last.
    my $inSection = 0;
    my $sectionLine;       # .info line of the 'SF:' which opened the section
    my $sectionEndLine;    # .info line of the 'end_of_record' which closed one

    # The format messages below name the source file whose section is involved
    #   and the .info line where that section began or ended, so that a report
    #   points at both ends of the problem.  Either clause is dropped when there
    #   is nothing to name:  no section has been seen yet, or the section was
    #   opened by an 'SF:' record whose file name was empty.
    my $openSection = sub {
        return 'the current section' unless defined($filename);
        return "the section for '$filename'" .
            (defined($sectionLine) ? " beginning at line $sectionLine" : '');
    };
    my $closedSection = sub {
        return ''
            unless defined($filename) && defined($sectionEndLine);
        return " - the section for '$filename' ended at line $sectionEndLine";
    };

    # Adopt a testname, given the payload of the 'TN:' record which names it.
    #   Shared with the run loop below, because a chunk which does not begin at
    #   the beginning of the file has to be told the name which is in force
    #   where it begins - and that name has to be normalized exactly as the
    #   record itself would have been, or the chunk's data lands under a
    #   different testcase than the rest of the file's.
    # '$isRecord' distinguishes the two callers:  only the chunk which actually
    #   contains the record should report that characters were removed from the
    #   name, or every chunk which inherited the name would repeat the warning.
    my $setTestname = sub {
        my ($payload, $isRecord) = @_;
        my ($name, $diff) =
            defined($payload) ? $payload =~ /^([^,]*)(,diff)?/ : ('', undef);
        $name = '' unless defined($name);
        my $orig = $name;
        $changed_testname = $orig if ($name =~ s/\W/_/g && $isRecord);
        $name .= $diff if defined($diff);
        if (defined($ignore_testcase_name) &&
            $ignore_testcase_name) {
            lcovutil::debug(1,
                 "using default testcase rather than $name at $tracefile:$.\n");
            $name = '';
        }
        $testname = $name;
    };

    # Close the section which is open, and note that none is.  Called from the
    #   'end_of_record' which properly ends a section, and from the two places
    #   which have to recover from one that is not properly ended:  a second
    #   'SF:' arriving while a section is open, and end of file.
    my $closeSection = sub {
        # A section whose file was excluded, or whose 'SF:' record had no file
        #   name, has nothing to close:  its records were skipped, and
        #   '$fileData' still refers to whichever file was read before it.
        if ($filename && !$skipCurrentFile) {
            if (!defined($fileData->version()) &&
                $lcovutil::compute_file_version &&
                @lcovutil::extractVersionScript) {
                my $version = lcovutil::extractFileVersion($filename);
                $fileData->version($version)
                    if (defined($version) && $version ne "");
            }
            $fileData->_installSection(TraceInfo::LINE_DATA, $testname,
                                       $lineMap);
            if ($lcovutil::func_coverage) {
                $fileData->_installSection(TraceInfo::FUNCTION_DATA,
                                           $testname, $functionMap);
            }
            if ($lcovutil::br_coverage) {
                if ($branchBlock) {
                    $branchMap->insertBlock($branchBlock, $currentBlockLine);
                    # reset - in case another testcase follows
                    $branchBlock = undef;
                }
                $branchMap->updateCounts();
                $fileData->_installSection(TraceInfo::BRANCH_DATA,
                                           $testname, $branchMap);
            }
            # forget the in-progress block, in case the next section
            #   has an expression on the same line
            $current_mcdc = undef;
            if ($mcdcMap && 0 != scalar($mcdcMap->keylist())) {
                # The blocks in the scratch map were mutated in place as
                #  the records were read, so its cached found/hit are
                #  stale - recompute them, exactly as the branch data
                #  above does with updateCounts().
                $mcdcMap->_calculate_counts();
                $fileData->_installSection(TraceInfo::MCDC_DATA,
                                           $testname, $mcdcMap, $filename);
            }
            # some paranoid checks
            $self->data($filename)->check_data();
        }
        $inSection       = 0;
        $skipCurrentFile = 0;
        $sectionEndLine  = $.;
    };

    # Point the handle at the next run of sections this chunk covers, and tell
    #   the reader where it is:  the line number so that every '"$tracefile":$.'
    #   message below reports the line the record is really on, and the testname
    #   in force there.  Returns false when the chunk is exhausted.
    # Setting the handle's line counter is the whole of the line-number fix -
    #   there is nothing to change in the messages themselves.
    my $runEnd;
    my $startRun = sub {
        my $run = shift;
        return 0 unless defined($run);
        my ($runStart, $runLine, $runTestname);
        ($runStart, $runEnd, $runLine, $runTestname) = @$run;
        return 1 unless defined($runStart);    # reading the whole file
        seek(INFO, $runStart, 0) or
            die("cannot seek to $runStart in $tracefile: $!\n");
        INFO->input_line_number($runLine - 1);
        &$setTestname($runTestname, 0);
        return 1;
    };
    &$startRun(shift(@runs));

    while (<INFO>) {
        chomp($_);
        my $line = $_;
        # Trailing whitespace has to come off - a '\r' left by the chomp of a
        #   CRLF file, or padding - but after that chomp almost no line has any,
        #   so look at the last character rather than running the substitution
        #   over every one of them.  '!' is the lowest printable character, so
        #   anything below it is either whitespace or a control character, and
        #   the substitution leaves control characters alone in any case:  the
        #   guard cannot skip a line the substitution would have changed.
        $line =~ s/\s+$//
            if (length($line) && substr($line, -1) lt '!');

        # Which record is this?  See '%recordDispatch' above:  the tag is
        #   everything up to the first ':', and the case it maps to selects the
        #   single regular expression worth running against this line.
        my $colon = index($line, ':');
        my $case =
            $colon > 0 ? $recordDispatch{substr($line, 0, $colon)} : undef;
        if (!defined($case)) {
            # No tag, or not one the table carries:  a comment, a blank line,
            #   'end_of_record' (which has no ':' - and this is also what keeps
            #   'end_of_record:whatever' working), or something malformed.  Only
            #   a few lines per section come through here, so testing them one
            #   at a time costs nothing.
            next if $line =~ /^#/;       # skip comment
            next if $line =~ /^\s*$/;    # blank line is legal anywhere

            if ($line =~ /^end_of_record/) {
                # Found end of section marker
                if (!$inSection) {
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                             "\"$tracefile\":$.: 'end_of_record' with no open" .
                                 ' section' . &$closedSection());
                    next;
                }
                &$closeSection();
                # Reading a chunk rather than the whole file:  a run ends at a
                #   section end, so this is the only place a chunk can be
                #   finished or a seek to the next run be due.
                if (defined($runEnd) &&
                    tell(INFO) >= $runEnd) {
                    last unless &$startRun(shift(@runs));
                }
                next;
            }
            # Fall through to the switch below, where this lands on the
            #   malformed-record error - as it did when the switch was a chain
            #   of regular expressions which all failed.
            $case = REC_UNKNOWN;
        }

        # Each 'if' below pairs the case with the regular expression whose
        #   capture groups its handler wants.  The case has already told us that
        #   expression matches this line - unless the payload after the tag is
        #   malformed, in which case falling past the test to the error at the
        #   end of the switch is exactly the old behaviour.
        if ($case == REC_FILE && $line =~ /^[SK]F:(.*)/) {
            my $sourceName = $1;
            if ($inSection) {
                lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: file record '$line' found inside " .
                            &$openSection() . " - missing 'end_of_record'");
                # close the section which is open, so its data is kept rather
                #   than dropped when this one replaces it
                &$closeSection();
            }
            $inSection   = 1;
            $sectionLine = $.;
            # Filename information found
            if ($sourceName =~ /^\s*$/) {
                lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                    "\"$tracefile\":$.: unexpected empty file name in record '$line'"
                );
                # there is no file to attribute this section's records to, so
                #   skip them - and forget the previous section's name, so that
                #   nothing reports this section as belonging to that file
                $filename        = undef;
                $skipCurrentFile = 1;
                next;
            }
            #if ($self->contains($filename)) {
            #    # we expect there to be only one entry for each source file in each section
            #    lcovutil::ignorable_warning($lcovutil::ERROR_FORMAT,
            #                                  "Duplicate entries for \"$filename\""
            #                                  . ($testname ? " in testcase '$testname'" : '') . '.');
            #}
            # '$sourceName' rather than '$1':  the error paths above match
            #   further regular expressions, so '$1' no longer holds this
            #   record's file name by the time we get here.
            $filename = ReadCurrentSource::resolve_path($sourceName, 1);
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
            %fnIdxMap         = ();
            $branchBlock      = undef;
            $currentBlockLine = -1;
            $currentBlock     = -1;

            if ($verify_checksum) {
                # unconditionally 'close' the current file - in case we don't
                #   open a new one.  If that happened, then we would be looking
                #   at the source for some previous file.
                $readSourceCallback->close();
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

            die("expected testname") unless defined($testname);

            # An empty scratch map for each coverage type:  records land in a map
            #  holding only THIS section's data, which is then merged into both
            #  the per-testname data and the summary - see '_installSection'.
            #  Writing straight into the per-testcase map instead looks cheaper,
            #  but it is wrong as soon as a second section names the same
            #  testcase (which '--forget-test-names' guarantees, since it forces
            #  every section onto ''):  the counts accumulate - 'CountData::append'
            #  and 'FunctionEntry::addAlias' both add - so the map already holds
            #  the earlier section by the time it is merged into the summary, and
            #  the summary gets that running total rather than this section's
            #  contribution.
            #  MC/DC has the same hazard through a second route:  a block
            #  mutated in place ('MCDC_Expression::set' adds) while it is already
            #  installed in a destination map turns that destination's running
            #  total into this section's starting value.
            $lineMap     = CountData->new($filename, $CountData::SORTED);
            $functionMap = FunctionMap->new($filename);
            $branchMap   = BranchData->new();
            $mcdcMap     = MCDC_Data->new();
            next;
        }

        if ($case == REC_TN && $line =~ /^TN:(.*)/) {
            # Test name information found.  It names the testcase which the
            #   FOLLOWING section's data belongs to, so it has to come before
            #   the 'SF:' record:  by the time a section is open, its data has
            #   already been attached to the testcase named when it opened.
            if ($inSection) {
                lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                         "\"$tracefile\":$.: '$line' record must precede the " .
                             "'SF:' record of its section - in " .
                             &$openSection());
                # ignore it:  the section keeps the testname it was opened with
                next;
            }
            &$setTestname($1, 1);
            next;
        }

        if (!$inSection) {
            # Not a 'TN:', 'SF:', comment or blank - so it is a record which
            #   only means something within a section, and there is no section
            #   for it to belong to.  Discard it rather than attributing it to
            #   whichever file was read last.
            lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                           "\"$tracefile\":$.: unexpected .info file record " .
                               "'$line' outside of a section:  expected 'TN:'" .
                               " or 'SF:'" . &$closedSection());
            next;
        }
        next if $skipCurrentFile;

        # A record belonging to a cover type which is turned off.  There is
        #   nowhere to put its data, so drop it here - before its regular
        #   expression is run, which is the point:  see '%recordDispatch' above.
        #   It is dropped after the checks above, so that a record which is in
        #   the wrong PLACE is still reported as such whether or not its cover
        #   type is enabled;  only the record's own payload goes unexamined.
        next if $case == REC_SKIP;

        # Switch statement
        # Please note:  if you add or change something here (lcov info file format) -
        #   then please make corresponding changes to the 'write_info' method, below
        #   and update the format description found in .../man/geninfo.1.
        # The arms are keyed on the case computed above rather than on the record
        #   regular expression, so only one of those expressions is ever run -
        #   and they are ordered by how often the record appears (DA, BRDA and
        #   MCDC are essentially the whole file), so the common cases are found
        #   after one or two integer comparisons.  Each arm still runs its own
        #   expression, for the capture groups the handler wants:  a record whose
        #   tag is right but whose payload is malformed fails that match and
        #   falls through to the error at the bottom, as it always did.
        # 'foreach' rather than a plain block:  it aliases '$_' to the line for
        #   the expressions below, and it is what every 'last' in here exits.
        foreach ($line) {
            if ($case == REC_DA) {
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
                                my $content =
                                    $readSourceCallback->getLine($line);
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
                                lcovutil::ignorable_error(
                                    $lcovutil::ERROR_VERSION,
                                    "no checksum for $filename:$line in $tracefile"
                                );
                            }
                        }
                    }

                    # Add test-specific counts
                    $lineMap->append($line, $count);

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
            } elsif ($case == REC_BRDA) {
                /^BRDA:(\d+),([ef]?)(U?)(\d+),(.+)$/ && do {
                    # Branch coverage data found
                    # line data is "lineNo,blockId,(branchIdx|branchExpr),taken
                    #   - so grab the last two elements, split on the last comma,
                    #     and check whether we found an integer or an expression
                    # NOTES:
                    #   - we re-derive block IDs such that they start at zero
                    #     and are contiguous.
                    #   - we keep track of the order of appearance of new blocks
                    #     (both when reading the .info file and when parsing
                    #     gcov output).
                    #   - when merging branch data:
                    #      - two blocks are identical if their signature is
                    #        identical AND either
                    #          - there is exactly one block in each DB with
                    #            that signature, OR
                    #          - the two blocks with the same signature appear
                    #            in the same order.
                    #      - that is: within branches with 'code0', the first
                    #        block is merged into the first block, the second
                    #        into the second and so forth.
                    #          - if there is no Nth block in one of the DBs,
                    #            then it is simply copied.
                    #      - This means that there is no way for the tool to
                    #        know that two blocks with identical signatures
                    #        in different DBs are actually different (e.g.,
                    #        due to template instantiation)
                    my ($line, $block, $d) = ($1, $4, $5);
                    my $type;
                    if (!defined($2) || '' eq $2) {
                        $type = BranchElement::VANILLA;
                    } elsif ($2 eq 'f') {
                        $type = BranchElement::FALLTHROUGH;
                    } else {
                        die("unexpected type '$2'") unless $2 eq 'e';
                        $type = BranchElement::EXCEPT;
                    }
                    # open question...if this is an exception branch and is
                    #   excluded - should we keep the mark?  Or only if
                    #   the exception exclusion filter is enabled?
                    # At present:  once the flag is set, then it remains...we
                    #   won't clear it when we read or write the .info file
                    my $unreachable =
                        (!$lcovutil::ignore_unreachable_flag &&
                         defined($3) &&
                         'U' eq $3);
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
                    $unreachable = 1
                        if defined($type) &&
                        $type == BranchElement::EXCEPT &&
                        $lcovutil::exclude_exception_branch;

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

                    if (!defined($branchBlock) ||
                        $block != $currentBlock ||
                        $line != $currentBlockLine) {
                        if (defined($branchBlock)) {
                            $branchMap->insertBlock($branchBlock,
                                                    $currentBlockLine);
                        }
                        $branchBlock      = BranchBlock->new();
                        $currentBlockLine = $line;
                        $currentBlock     = $block;
                        $branchIndex      = 0;
                    }
                    $branchBlock->appendNew($branchIndex++, $taken, $expr,
                                            $type, $unreachable);
                    last;
                };
            } elsif ($case == REC_MCDC) {
                /^MCDC:(\d+),(U?)(\d+),([tf]),(\d+),(\d+),(.+)$/ && do {
                    # lineNum, unreachable groupSize, sense, count, index, expression
                    # 'sense' is t/f: was this expression sensitized
                    # 'filtered' indicates that this particular MC/DC element
                    #    was excluded by
                    my ($line, $groupSize, $sense, $count, $idx, $expr) =
                        ($1, $3, $4, $5, $6, $7);
                    my $unreachable = !$lcovutil::ignore_unreachable_flag &&
                        defined($2) &&
                        'U' eq $2;
                    if ($line <= 0) {
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$tracefile\":$.: unexpected line number '$line' in condition data record '$_'."
                        );
                        # keep invalid line number
                        #last;
                    }

                    if (!defined($current_mcdc) ||
                        $current_mcdc->line() != $line) {
                        # @todo if all the MC/DC elements are excluded, then
                        #   drop this coverpoint
                        # Allocate out of the section-local scratch map above, NOT
                        #  out of $fileData->mcdc().  Counts accumulate
                        #  (MCDC_Expression::set adds), so a block which is mutated
                        #  in place while it is already installed in a destination
                        #  turns that destination's running total into this section's
                        #  starting value.  Keeping the block in a map which holds
                        #  only this section's data also preserves insertExpr()'s
                        #  revisit handling - a line which appears more than once in
                        #  one section lands back in the same block and is checked
                        #  for consistency there.
                        $current_mcdc = $mcdcMap->new_mcdc($fileData, $line);
                    }
                    $current_mcdc->insertExpr($filename, $groupSize,
                                             $sense eq 't',
                                             $count, $idx, $expr, $unreachable);
                    last;
                };
            } elsif ($case == REC_FN) {
                /^FN:(\d+),((\d+),)?(.+)$/ && do {
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
                    $functionMap->define_function($fnName, $lineNo, $end_line,
                                                  "\"$tracefile\":$.");
                    last;
                };
            } elsif ($case == REC_FNDA) {
                # Hit count may be float if Perl decided to convert it
                /^FNDA:([^,]+),(.+)$/ && do {
                    my $fnName = $2;
                    my $hit    = $1;
                    # error checking is in the addAlias method
                    $functionMap->add_count($fnName, $hit);
                    last;
                };
            } elsif ($case == REC_FNL) {
                # new format...
                /^FNL:(\d+),(\d+)(,(\d+))?$/ && do {
                    my $fnIndex  = $1;
                    my $lineNo   = $2;
                    my $end_line = $4;
                    die("unexpected duplicate index $fnIndex")
                        if exists($fnIdxMap{$fnIndex});
                    $fnIdxMap{$fnIndex} = [$lineNo, $end_line];
                    last;
                };
            } elsif ($case == REC_FNA) {
                /^FNA:(\d+),([^,]+),(.+)$/ && do {
                    my $fnIndex = $1;
                    my $hit     = $2;
                    my $alias   = $3;
                    die("unknown index $fnIndex")
                        unless exists($fnIdxMap{$fnIndex});
                    my ($lineNo, $end_line) = @{$fnIdxMap{$fnIndex}};
                    my $fn =
                        $functionMap->define_function($alias, $lineNo,
                                                $end_line, "\"$tracefile\":$.");
                    $fn->addAlias($alias, $hit);
                    last;
                };
            } elsif ($case == REC_VER) {
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
            }

            /^(FN|BR|L|MC)[HF]/ && do {
                last;    # ignore count records
            };

            lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: unexpected .info file record '$_'" .
                            ' in ' . &$openSection());
            # default
            last;
        }
    }
    # Only the last run of a chunk can end at end of file, so runs left over
    #   here mean the file is not the file which was scanned:  it was rewritten
    #   while we were reading it.  Nothing downstream can recover from that.
    die("$tracefile changed while it was being read\n") if (@runs);
    if ($inSection) {
        # end of file with a section still open:  its 'end_of_record' is
        #   missing.  Close it, so the data which was read is kept rather than
        #   dropped.
        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                                 "\"$tracefile\":$.: unexpected end of file: " .
                                     "missing 'end_of_record' for " .
                                     &$openSection());
        &$closeSection();
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
                $filedata->test($testname)->entries() == 0) {
                $filedata->test()->remove($testname);
                $filedata->testfnc()->remove($testname);
                $filedata->testbr()->remove($testname);
                $filedata->testcase_mcdc()->remove($testname);
            }
        }
    }

    # A chunk which read nothing useful is not an empty tracefile:  the rest of
    #   the file went to other chunks.  The parent asks the same question of the
    #   merged result - see 'AggregateTraces::_parallel_parse'.
    if (scalar($self->files()) == 0 &&
        !defined($chunk)) {
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
        die("expected to have filtered $source_file out")
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
            my $lineMap   = $testdata->value($testname);
            my $funcMap   = $testfncdata->value($testname);
            my $branchMap = $testbrdata->value($testname);
            my $mcdc      = $testmcdc->value($testname);

            print(INFO_HANDLE "TN:$testname\n");
            print(INFO_HANDLE "SF:$source_file\n");
            print(INFO_HANDLE "VER:" . $entry->version() . "\n")
                if defined($entry->version());
            if (defined($srcReader)) {
                lcovutil::info(1, "reading $source_file for lcov checksum\n");
                $srcReader->open($source_file);
            }

            my $functionMap = $testfncdata->value($testname);
            if ($lcovutil::func_coverage &&
                $functionMap) {
                # Write function related data - sort  by line number then
                #  by name (compiler-generated functions may have same line)
                # sort enables diff of output data files, for testing
                my @functionOrder =
                    sort({ $functionMap->findKey($a)->line()
                                 <=> $functionMap->findKey($b)->line() or
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
            # $branchMap is undef if there are no branches in the scope
            if ($lcovutil::br_coverage &&
                defined($branchMap)) {
                # Write branch related data
                my $br_found = 0;
                my $br_hit   = 0;

                foreach my $line (sort({ $a <=> $b } $branchMap->keylist())) {
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$source_file\": unexpected line number '$line' in branch data record."
                    ) if ($line <= 0);    # keep bogus data if error ignored
                    my $brdata = $branchMap->value($line);

                    # sort the branch data on each line first by number
                    # of branches and then by type (exception vs normal)
                    my $blockId = 0;
                    foreach my $block ($brdata->blocks(1)) {
                        foreach my $br (@{$block->elements()}) {
                            # one call for all five fields - see
                            #   BranchElement::write_data
                            my ($taken, $branch_id, $branch_expr, $type,
                                $excluded)
                                = $br->write_data();
                            # mostly for Verilog:  if there is a branch expression: use it.
                            $type = '' if 'b' eq $type;
                            printf(INFO_HANDLE "BRDA:%u,%s%s%u,%s,%s\n",
                                   $line,
                                   $type,
                                   $excluded ? 'U' : '',
                                   $blockId,
                                   defined($branch_expr) ? $branch_expr :
                                       $branch_id,
                                   $taken);
                            unless ($excluded) {
                                # count does not include the excluded ones
                                $br_found++;
                                $br_hit++
                                    if ($taken ne '-' && $taken > 0);
                            }
                        }
                        ++$blockId;
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
                            # one call for both senses - see
                            #   MCDC_Expression::write_data
                            my ($countF, $countT, $exclF, $exclT, $expression)
                                = $e->write_data();
                            foreach my $sense ('t', 'f') {
                                my $isTrue = $sense eq 't';
                                my $count  = $isTrue ? $countT : $countF;
                                ++$mcdc_hit if 0 != $count;
                                my $excluded =
                                    ($isTrue ? $exclT : $exclF) ? 'U' : '';
                                print(INFO_HANDLE
                                        "MCDC:$line,$excluded$groupSize,$sense,$count,$index,"
                                        . $expression,
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
            foreach my $line (sort({ $a <=> $b } $lineMap->keylist())) {
                if ($line <= 0) {
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$source_file\": unexpected line number '$line' in 'line' data record."
                    );
                }
                my $l_hit = $lineMap->value($line);
                my $chk   = '';
                if ($verify_checksum) {
                    if ($checkdata->mapped($line)) {
                        $chk = $checkdata->value($line);
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
# parse and merge TraceFiles - possibly in parallel
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

            unless (-f $f && -r $f) {
                lcovutil::ignorable_error($lcovutil::ERROR_MISSING,
                     "'$f' found from pattern '$pattern' is not a readable file"
                );
                next;
            }
            push(@merge, $f);
        }
    }
    lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                         "no matching file found in '[" . join(', ', @_) . "]'")
        unless (@merge);

    return @merge;
}

# Decide how to split the input '.info' files across children, from the section
#   table which 'TraceFile::scan_sections' built for each of them.
# Returns a list of chunks, or undef if the inputs should be read the way they
#   always were - which is not an error and is the answer for most inputs.
#
# A chunk is '[[inputIdx, ...], [[run, ...], ...]]':  the inputs it reads, in
#   input order, and for each of them the 'runs' of consecutive sections to read
#   from that input, each '[startOffset, endOffset, startLine, testcaseName]'.
#   The run list of one input is what 'TraceFile::_read_info' takes as its
#   '$chunk' argument:  a child seeks once per run rather than once per section.
#   Nothing outside this file cares that a chunk can name several inputs - the
#   child reads them one after another, exactly as a serial read of those files
#   would have.
sub _partition_sections($$$)
{
    my ($sections, $nWorkers, $filelist) = @_;

    return undef
        unless ($lcovutil::parallel_parse_min_lines &&
                $nWorkers > 1 &&
                scalar(@$sections) > 1);

    # All the sections naming one source file are one atom of work, wherever
    #   they are and whichever input they are in.  Three reasons, and the third
    #   is the one which makes the fused filtering below legal:
    #   'TraceFile::merge_tracefile' is free when the file is new to the
    #   destination and expensive when it is not (measured: 0.0000s vs 0.4673s
    #   for the same 16 MB), '$function_mapping' would otherwise list the same
    #   input file once per child which saw the function, and a filter must see
    #   all of a file's data before it can decide anything about that file.
    # Grouping across inputs rather than within one input is what extends all
    #   three to a set of inputs:  a source file which several of the inputs
    #   carry is still read, merged and filtered by exactly one child.
    # Sections which the pre-scan could not attribute to exactly one source file
    #   cannot be grouped, so decline the whole set rather than guess - see
    #   'TraceFile::_scan_section_names'.
    # The unit of weight is the number of records in the group, summed over the
    #   inputs which carry it:  what a group costs to read, to hold and to filter
    #   all scale with how many records it has, and a '.info' file is one record
    #   per line.
    my $totalLines = 0;
    my $maxLines   = 0;
    my %groups;    # 'SF:' name -> [record count, [section, ...]]
    foreach my $section (@$sections) {
        my $name = $section->[TraceFile::SEC_FILE];
        return undef unless defined($name);
        my $nLines = $section->[TraceFile::SEC_NLINES];
        $totalLines += $nLines;
        my $group = $groups{$name};
        if (defined($group)) {
            $group->[0] += $nLines;
            push(@{$group->[1]}, $section);
        } else {
            $group = $groups{$name} = [$nLines, [$section]];
        }
        $maxLines = $group->[0] if ($group->[0] > $maxLines);
    }

    # Is it worth it at all?  Splitting a small input loses:  the forks and the
    #   parent-side deserialization cost more than the parse they replace.  The
    #   test is against the whole set, because that is the work being divided.
    #   LCOV_FORCE_PARALLEL overrides the size test - but not an explicit
    #   'parallel_parse_min_lines = 0', which means "never".
    return undef
        if ($totalLines < $lcovutil::parallel_parse_min_lines &&
            !exists($ENV{LCOV_FORCE_PARALLEL}));

    # A section is indivisible, so no number of workers can beat
    #   totalLines/largestGroup.  Real inputs can be badly skewed - one project's
    #   own capture is 29 sections of which the largest is 37.6% of the lines,
    #   a cap of 2.7x however many cores are available - so clamp the worker
    #   count to the cap rather than forking children which can only wait.
    my $cap = int($totalLines / $maxLines);
    return undef if ($cap < 2);
    $nWorkers = $cap if ($cap < $nWorkers);

    # More chunks than workers shortens the tail and bounds child memory - see
    #   '$lcovutil::parallel_parse_chunks_per_worker'.  Two counter-bounds:
    #   there is no point in more chunks than there are groups to put in them,
    #   or in chunks so small that the fork costs more than the chunk
    #   ('$dedicate_segment_line_estimate' is the existing notion of "enough
    #   lines to be worth a child of its own").
    my $nChunks = $nWorkers * $lcovutil::parallel_parse_chunks_per_worker;
    my $nGroups = scalar(keys(%groups));
    $nChunks = $nGroups if ($nGroups < $nChunks);
    if ($lcovutil::dedicate_segment_line_estimate) {
        my $byLoad =
            int($totalLines / $lcovutil::dedicate_segment_line_estimate);
        $nChunks = $byLoad if ($byLoad < $nChunks);
    }
    $nChunks = 2 if ($nChunks < 2);

    # Longest-processing-time-first: the same shape as the genhtml scheduler,
    #   and within 4/3 of the optimal makespan with no parameters to tune.
    #   Because groups arrive in descending order and each goes to the lightest
    #   chunk, a group which is itself larger than a chunk's fair share ends up
    #   alone in one - no special case for it is needed.
    # '@chunks' is kept sorted by load, ascending, so the lightest is [0].
    my @chunks = map({ [0, []] } 1 .. $nChunks);
    foreach my $group (
             sort(
                 { $b->[0] <=> $a->[0] ||
                         $a->[1][0][TraceFile::SEC_INPUT]
                         <=> $b->[1][0][TraceFile::SEC_INPUT] ||
                         $a->[1][0][TraceFile::SEC_START]
                         <=> $b->[1][0][TraceFile::SEC_START] } values(%groups))
    ) {
        my $chunk = shift(@chunks);
        $chunk->[0] += $group->[0];
        push(@{$chunk->[1]}, @{$group->[1]});
        my ($lo, $hi) = (0, scalar(@chunks));
        while ($lo < $hi) {
            my $mid = int(($lo + $hi) / 2);
            if ($chunks[$mid]->[0] < $chunk->[0]) {
                $lo = $mid + 1;
            } else {
                $hi = $mid;
            }
        }
        splice(@chunks, $lo, 0, $chunk);
    }

    # Turn each chunk's sections back into input-and-then-file order and coalesce
    #   the adjacent ones into runs.  A run inherits the testcase name in force
    #   at its first section; sections after that one are contiguous with it, so
    #   they pick up any 'TN:' record themselves - and a run never spans two
    #   inputs, so an inherited name is always the one its own input declared.
    # Reading the inputs of a chunk in input order, and each of them forwards,
    #   is what makes a child's read of them the same read a serial one would
    #   have done:  one open per input, and the same merge order within the
    #   chunk, which is what '@interesting' below is judged by.
    my @result;
    foreach my $chunk (@chunks) {
        my (@inputs, @runs);
        my $currentInput;
        foreach my $section (
              sort(
                  { $a->[TraceFile::SEC_INPUT] <=> $b->[TraceFile::SEC_INPUT] ||
                          $a->[TraceFile::SEC_START]
                          <=> $b->[TraceFile::SEC_START] } @{$chunk->[1]})
        ) {
            my $input = $section->[TraceFile::SEC_INPUT];
            if (!defined($currentInput) ||
                $input != $currentInput) {
                $currentInput = $input;
                push(@inputs, $input);
                push(@runs, []);
            } elsif (@{$runs[-1]} &&
                     $runs[-1]->[-1]->[1] == $section->[TraceFile::SEC_START]) {
                $runs[-1]->[-1]->[1] = $section->[TraceFile::SEC_END];
                next;
            }
            push(@{$runs[-1]},
                 [$section->[TraceFile::SEC_START],
                  $section->[TraceFile::SEC_END],
                  $section->[TraceFile::SEC_LINE],
                  $section->[TraceFile::SEC_TESTNAME]
                 ]);
        }
        # Sort key first, so that the chunks can be ordered by where they begin,
        #   then dropped:  see below.  The chunk carries the weight it was packed
        #   to, which is what the memory throttle scales - see 'CHUNK_LINES'.
        push(@result,
             [$inputs[0], $runs[0]->[0]->[0], [\@inputs, \@runs, $chunk->[0]]])
            if (@inputs);
    }
    # Read the chunks in input order, and within one input in file order:  the
    #   data is merged in the order the children return it, and this keeps that
    #   order as close to the order the user wrote as splitting allows.
    return [
            map({ $_->[2] }
                sort({ $a->[0] <=> $b->[0] || $a->[1] <=> $b->[1] } @result))
    ];
}

# The parts of a chunk - see '_partition_sections'.
use constant {
              CHUNK_INPUTS => 0,    # indices into the input file list
              CHUNK_RUNS   => 1,    # the runs to read from each of them
              CHUNK_LINES  => 2,    # records in it, for the memory throttle
};

# Decide whether the input '.info' files will be split, and how - see
#   '_partition_sections'.  Returns the chunk list, or undef to read the inputs
#   the way they always were:  serially, or one child per input.
sub _plan_parallel_parse($)
{
    my $filelist = shift;

    return undef
        unless ($lcovutil::parallel_parse_min_lines &&
                defined($lcovutil::maxParallelism) &&
                1 != $lcovutil::maxParallelism);
    # Only a seekable input can be split:  gzipped, demangled and stdin data
    #   arrives through a pipe - see 'InOutFile::in'.
    return undef if (defined($lcovutil::demangle_cpp_cmd));

    # One section table for all of the inputs, each section knowing which input
    #   it came from:  the partitioner groups by source file across the whole
    #   set, so it has to see the whole set.
    # Scanning is 0.8 ms per MB, against 120 ms per MB to parse - see
    #   'TraceFile::scan_sections' - so this pre-pass is affordable even when
    #   the answer turns out to be "do not split".
    my @sections;
    my $totalSize = 0;
    foreach my $idx (0 .. scalar(@$filelist) - 1) {
        my $tracefile = $filelist->[$idx];
        # An input which cannot be split costs the whole set its split:  the
        #   contract the rest of this depends on is that all of one source
        #   file's data goes to one child, and an input whose sections cannot be
        #   located may hold data for any source file in the set.  Reading it
        #   whole alongside the chunks is the next step - see section 11.3 of
        #   'lcovPerformanceTest/PARALLEL_PARSE_PLAN.md'.
        return undef
            if (!defined($tracefile) ||
                '-' eq $tracefile ||
                $tracefile =~ /\.gz$/);
        return undef unless (-f $tracefile && !-z $tracefile);
        my $now      = Time::HiRes::gettimeofday();
        my $sections = TraceFile::scan_sections($tracefile);
        $lcovutil::profileData{scan}{$tracefile} =
            Time::HiRes::gettimeofday() - $now;
        # An input with no sections at all is one the reader has something to
        #   say about ("no valid records found") - let it say it, in the order
        #   and the words it always used.
        return undef unless (@$sections);
        push(@$_, $idx) foreach (@$sections);
        $totalSize += $sections->[-1]->[TraceFile::SEC_END];
        push(@sections, @$sections);
    }
    return undef unless (@sections);

    # The memory throttle, as in 'merge' below - but a child of this fork reads
    #   one chunk rather than a whole input, so the estimate has to use the
    #   chunk size or a single large input would throttle itself to
    #   '--parallel 1' and lose the feature exactly where it pays most.
    # Note that a smaller worker count means larger chunks, so this cannot be
    #   solved in one step; iterate down to a fixed point.  It terminates
    #   because each iteration strictly decreases the count.
    my $nWorkers = $lcovutil::maxParallelism;
    if (defined($lcovutil::maxMemory) &&
        0 != $lcovutil::maxMemory) {
        my $currentSize = lcovutil::current_process_size();
        while ($nWorkers > 1) {
            my $chunkSize =
                int($totalSize / (
                         $nWorkers * $lcovutil::parallel_parse_chunks_per_worker
                    ));
            my $num = int($lcovutil::maxMemory / ($currentSize + $chunkSize));
            last if ($num >= $nWorkers);
            $nWorkers = $num > 1 ? $num : 1;
        }
        if ($nWorkers != $lcovutil::maxParallelism) {
            lcovutil::info(
             "Throttling to '--parallel $nWorkers' due to memory constraint\n");
            $lcovutil::maxParallelism = $nWorkers;
        }
    }
    return _partition_sections(\@sections, $nWorkers, $filelist);
}

# Read the input '.info' files with several children at once, each taking one
#   chunk of their sections - see '_partition_sections'.  A chunk can hold
#   sections from more than one of the inputs, and holds all of the sections
#   which name any source file it holds any section for.
# Each child also does what the caller would otherwise do afterwards, to its own
#   share of the data:  the testcase-table check and then the filters.  That is
#   legal because the partitioner puts all of a source file's data in one chunk,
#   and both of those steps look at one source file at a time - so a child's view
#   of a file is the final view of it.  It saves the parent a second fork/join
#   over the merged data, and saves shipping the data the filters remove.
# The order the child does it in is exactly the caller's order - read with the
#   filters off, check, then filter - because the two passes are not
#   interchangeable:  with the filters on, 'TraceFile::_filterFile' checks data
#   consistency only for a file whose function end lines it also had to derive.
# Returns the list of 'effective' input files - those which contributed coverage
#   no other input had - in input order.  A child judges its own chunk, which is
#   sound because it saw all of that chunk's source files in every input:  in
#   fact it is a better answer than the one-child-per-input read gives, where
#   two children can each believe their copy of the same data was the effective
#   one.
sub _parallel_parse($$$$$)
{
    my ($total_trace, $readSourceFile, $filelist, $chunks, $save_filters) = @_;

    my $nChunks  = scalar(@$chunks);
    my $nInputs  = scalar(@$filelist);
    my $inFlight = $lcovutil::maxParallelism;
    $inFlight = $nChunks if ($nChunks < $inFlight);
    lcovutil::info((1 == $nInputs ? "Reading tracefile $filelist->[0]" :
                        "Reading $nInputs tracefiles") .
                       " in $nChunks chunks, $inFlight at a time.\n");
    $lcovutil::profileData{config} = {}
        unless exists($lcovutil::profileData{config});
    $lcovutil::profileData{config}{chunks} = $nChunks;

    my $tempDir = lcovutil::create_temp_dir();

    # The children filter, so they are the ones which count what the filters
    #   did.  Those counts do not ride home in 'lcovutil::compute_update' (the
    #   pattern counts do, the filter counts do not), so collect them the same
    #   way the filter fork does - see 'TraceFile::_processParallelChunk'.
    # The filters are turned off just now, so reach the live objects through the
    #   caller's saved copy rather than through '@lcovutil::cov_filter'.
    my @filters  = grep({ defined($_) } @{$save_filters->[0]});
    my @patterns = (@{$save_filters->[1]}, @{$save_filters->[2]});
    # Now put them back:  each child turns them off again for its own read, so
    #   the parent has no use for the off state - and 'lcovutil::update_state'
    #   insists that the pattern counts a child sends back describe the same
    #   number of patterns the parent knows about, which is not true while the
    #   omit/erase lists are emptied out here.
    lcovutil::reenable_cov_filters($save_filters);

    my @queue = (0 .. $nChunks - 1);
    my %effective;    # input file name -> it contributed something
    my $didFilter = 0;
    # the child's own container and filter state, set up before 'initial_state'
    #   and used by the work below
    my ($chunk_trace, $childFilters);

    lcovutil::ForkManager->new(
        operation => 'aggregate',
        phase     => 'aggregate',
        tempDir   => $tempDir,
        prefix    => 'lcov',
        # Show what the child had to say even when it succeeded:  the user did
        #   not ask for their inputs to be split, so they should still see the
        #   'Excluding ...' and similar messages which the unsplit read would
        #   have printed.
        showStdout => 1,
        # Merge the chunks in the order they appear in the file rather than the
        #   order the children happen to finish in:  a file-level comment is held
        #   in a list whose order is the order it is merged in, and the user gets
        #   to see their own order.
        ordered => 1,
        # A chunk child holds the records of its own chunk, which is exactly the
        #   quantity the partitioner packed the chunks by - so this is the site
        #   where the estimate can be asked the right question.  The chunk count
        #   was already chosen with the memory limit in mind (see
        #   '_plan_parallel_parse'), but that decision is taken before anything
        #   has been read, from the size of the input on disk;  this one is taken
        #   at each fork, from what the chunks which have finished really cost.
        memoryThrottle => 1,
        unitWeight     => sub {
            return $chunks->[$_[0]][CHUNK_LINES];
        },
        # never more than one child per chunk
        maxInFlight => $inFlight,
        # The chunk index says where in the merge order this chunk goes;  it does
        #   not name the job, because the same process can read more than one
        #   group of inputs (lcov --intersect reads the base trace and then the
        #   files to intersect it with) and chunk 0 of the second group is not the
        #   same job as segment 0 of the first.  '$segmentIdx' is the counter
        #   which is unique across the process - see its declaration - so the
        #   labels and the per-job profile keys come from there.
        jobId => sub { return $segmentIdx; },
        # allocate the next one, exactly as the segment loop below does:  the
        #   child was forked with the current value, so this must come after it
        postFork => sub { ++$segmentIdx; },
        next     => sub {
            return () unless @queue;
            my $chunkIdx = shift(@queue);
            # What this chunk turned out to be:  which inputs it reads and how
            #   many separate places in each of them, which is the only view of
            #   the partitioner's answer the user can get.
            lcovutil::info(
                 1,
                 "Chunk $chunkIdx: "
                     .
                     join(
                     ', ',
                     map({ $filelist->[$chunks->[$chunkIdx][CHUNK_INPUTS][$_]] .
                                 ' (' .
                                 scalar(@{$chunks->[$chunkIdx][CHUNK_RUNS][$_]})
                                 . ' runs)' }
                         0 .. scalar(@{$chunks->[$chunkIdx][CHUNK_INPUTS]}) - 1)
                     ) .
                     "\n");
            return ($chunkIdx, $chunkIdx);
        },
        more      => sub { return scalar(@queue); },
        childInit => sub {
            # Filtering is serial here - this fork already provides the
            #   parallelism, and letting each child fork its own filter workers
            #   would multiply the process count.
            $lcovutil::maxParallelism = 1;
            delete($ENV{LCOV_FORCE_PARALLEL});
            # Read into a container of my own rather than into the caller's
            #   accumulator:  chunks are merged as they finish, so by the time I
            #   was forked '$total_trace' may already hold other chunks - and
            #   everything I sent back would be merged into it a second time.
            #   Same reasoning for the function map.
            $chunk_trace      = TraceFile->new();
            $function_mapping = {} if $function_mapping;
            # Read with the filters off, exactly as the serial path does, then
            #   turn them back on for 'applyFilters' below:  some filters want to
            #   see what the input said (and '_checkConsistency' is skipped
            #   unless the end lines were derived here rather than read).
            $childFilters = lcovutil::disable_cov_filters();
            # Zero what we are going to count, so that what we send back is this
            #   chunk's contribution and not the parent's running total as well.
            #   'initial_state' does this for the patterns, but it cannot see
            #   them while the filters are turned off, and it does not do it for
            #   the filter counts at all.
            foreach my $f (@filters) {
                $f->[-2] = 0;
                $f->[-1] = 0;
            }
            $_->[-1] = 0 foreach (@patterns);
        },
        child => sub {
            my ($chunkIdx, $id, $forkAt, $jobId) = @_;
            # I'm the child:  read my chunk, filter it, hand it back.
            my $status     = 0;
            my $filterTime = 0;
            my @interesting;
            my $chunk = $chunks->[$chunkIdx];
            eval {
                @interesting =
                    _process_segment($chunk_trace,
                                     $readSourceFile,
                                     [
                                      map({ $filelist->[$_] }
                                          @{$chunk->[CHUNK_INPUTS]})
                                     ],
                                     $chunk->[CHUNK_RUNS]);
                # Every input has now been read, as far as the files in this
                #   chunk are concerned, so this is the point at which their
                #   per-testcase tables can be judged - and before the filters,
                #   so that the warning describes what the user gave us.
                $chunk_trace->checkTestcaseData();
                lcovutil::reenable_cov_filters($childFilters);
                my $filterStart = Time::HiRes::gettimeofday();
                $chunk_trace->applyFilters($readSourceFile);
                $filterTime = Time::HiRes::gettimeofday() - $filterStart;
            };
            if ($@) {
                print(STDERR $@);
                $status = 1;
            }
            # The filters ran here, in this chunk, over the source files this
            #   chunk holds - so what they cost is this chunk's cost, reported
            #   beside the rest of what the chunk cost.  It is a part of 'total',
            #   not something to be added to it.
            # There is no per-input filter time to be had:  a source file is
            #   filtered once, no matter how many of the inputs had something to
            #   say about it, so there is nothing to attribute to an input.
            # The same goes for the read itself and for the merge of what was
            #   read into this chunk's own trace.  '_process_segment' measured
            #   both per input file, which is what they are in a serial read;
            #   here they are not, because a chunk holds only a part of each
            #   input it names and several chunks read the same input at the same
            #   time - so what one of them spent on it says nothing about what
            #   reading that input cost.  Fold them into one number per chunk and
            #   drop the per-input ones.  'initial_state' emptied this profile
            #   before we were called, so what is here is this chunk's own.
            foreach my $key ('parse', 'append') {
                my $d = delete($lcovutil::profileData{$key});
                next unless $d;
                my $t = 0;
                $t += $_ foreach (values(%$d));
                $lcovutil::profileData{$jobId}{$key} = $t;
            }
            # All of them are keyed by the job, not by the chunk:  see 'jobId'
            #   above.
            $lcovutil::profileData{$jobId}{filter} = $filterTime;
            $lcovutil::profileData{$jobId}{total} =
                Time::HiRes::gettimeofday() - $forkAt;
            return ([$chunk_trace, \@interesting, $function_mapping,
                     [map({ [$_->[-2], $_->[-1]] } @filters)]
                    ],
                    $status);
        },
        preMerge => sub {
            my $ctx = shift;
            lcovutil::info(
                          1,
                          'Merging chunk ' .
                              $ctx->{id} . ", status $ctx->{status}"
                              .
                              (
                              $lcovutil::debug ?
                                  (' mem:' . lcovutil::current_process_size()) :
                                  '') .
                              "\n");
        },
        validate => sub {
            my ($payload, $ctx) = @_;
            my ($current, $changed, $func_map) = @$payload;
            my $chunkIdx = $ctx->{id};
            $lcovutil::profileData{$chunkIdx}{undump} =
                $ctx->{reapAt} - $ctx->{forkAt};
            die("chunk $chunkIdx returned empty " .
                ($function_mapping ? 'function' : 'trace') . " data\n")
                unless defined($function_mapping ? $func_map : $current);
            return 1;
        },
        merge => sub {
            my ($unit, $chunkIdx, $payload) = @_;
            my ($current, $changed, $func_map, $filterCounts) = @$payload;
            if (defined($current) &&
                0 != ($current->[TraceFile::STATE] & TraceFile::DID_FILTER)) {
                # the child, not I, did the filtering:  say so the way the serial
                #   path would have - once, no matter how many chunks there are
                lcovutil::info("Apply filtering..\n") unless $didFilter;
                $didFilter = 1;
            }
            for (my $i = 0; $i <= $#filters; ++$i) {
                $filters[$i]->[-2] += $filterCounts->[$i]->[0];
                $filters[$i]->[-1] += $filterCounts->[$i]->[1];
            }
            # The child compared each of its inputs against the ones before it,
            #   for the files in its chunk - so it, and not the merge below, is
            #   what says whether an input was effective.  The merge below always
            #   changes something:  chunks share no source file, so nothing a
            #   chunk brings is already in '$total_trace'.
            $effective{$_} = 1 foreach (@$changed);
            if ($function_mapping) {
                while (my ($key, $data) = each(%$func_map)) {
                    $function_mapping->{$key} = [$data->[0], []]
                        unless exists($function_mapping->{$key});
                    die("mismatched function name '" . $data->[0] . "' at $key")
                        unless ($data->[0] eq $function_mapping->{$key}->[0]);
                    push(@{$function_mapping->{$key}->[1]}, @{$data->[1]});
                }
            } else {
                $total_trace->merge_tracefile($current, TraceInfo::UNION);
            }
        },
        postReap => sub {
            my $ctx = shift;
            $lcovutil::profileData{$ctx->{id}}{merge} =
                Time::HiRes::gettimeofday() - $ctx->{forkAt};
        },
        requeue          => sub { unshift(@queue, $_[0]); },
        forkFailWhen     => sub { return 'read tracefile chunk'; },
        retryWhen        => sub { return 'read chunk ' . $_[0]->{id}; },
        mergeFailMessage => sub {
            my $ctx = shift;
            return 'unable to merge chunk ' .
                $ctx->{id} . " $ctx->{dumpfile}:$ctx->{error}";
        },
        childFailMessage =>
            sub { return 'while reading chunk ' . $_[0]->{id}; },)->run();
    lcovutil::info("Finished filter file processing\n") if $didFilter;
    # Everything the read cost belongs to the chunk which did it, and each child
    #   reported it that way - see 'child' above.  There is nothing per input
    #   file to report here:  a chunk holds only a part of each input it names,
    #   and the chunks which hold the rest of it read at the same time.
    # Nor is there a separable 'append' phase for the run as a whole:  chunks are
    #   merged into '$total_trace' as they arrive, so what that cost is reported
    #   as the parent's 'merge', per chunk, beside the rest of the fork/join
    #   breakdown - and filtering happened inside the children, so what it cost
    #   is part of what a chunk cost rather than something beside it.
    # So drop the per-input tables 'merge' pre-seeded for the serial path:  an
    #   empty one reads as 'this cost nothing' rather than 'this does not apply'.
    foreach my $key ('parse', 'append') {
        delete($lcovutil::profileData{$key})
            if (exists($lcovutil::profileData{$key}) &&
                !%{$lcovutil::profileData{$key}});
    }
    # '_read_info' makes this check for itself when it reads a whole file, but a
    #   child which read only a chunk cannot: a chunk of an otherwise good input
    #   can legitimately be empty once its files are excluded.  So ask once,
    #   here, of everything.  Note that the pre-scan found file records in every
    #   input or we would not be here at all, so this reports data which was
    #   excluded or filtered away rather than data which was never there.
    #   Nothing at all came through means nothing came through from any one
    #   input, so every input is named - as the serial read names them.
    if (!$function_mapping &&
        0 == scalar($total_trace->files())) {
        # Report it the way the serial path does:  there, the error comes out of
        #   'TraceFile::load' and '_process_segment' catches it and blames the
        #   file - so the user turns it off with the same option either way.
        foreach my $tracefile (@$filelist) {
            eval {
                lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                              "no valid records found in tracefile $tracefile");
            };
            lcovutil::ignorable_error($lcovutil::ERROR_CORRUPT,
                                   "unable to read trace file '$tracefile': $@")
                if ($@);
        }
    }
    # The children filtered their own data - see the comment above - so tell the
    #   caller's 'applyFilters' that there is nothing left for it to do.  The
    #   merge does not propagate this, since in general the two sides of a merge
    #   have not had the same operations applied to them.
    $total_trace->[TraceFile::STATE] |=
        TraceFile::DID_FILTER | TraceFile::DID_DERIVE;
    # ..in input order, as the serial read reports them
    return grep({ exists($effective{$_}) } @$filelist);
}

# Read each of the input files in '$segment' and merge it into '$total_trace'.
#   '$chunk', when it is given, is a list parallel to '$segment':  the runs of
#   sections to read from that input rather than all of it - see
#   '_partition_sections'.
# Returns the inputs which contributed coverage the ones before them in
#   '$segment' did not.
sub _process_segment($$$;$)
{
    my ($total_trace, $readSourceFile, $segment, $chunk) = @_;

    my @interesting;
    my $total = scalar(@$segment);
    my $idx   = 0;
    foreach my $tracefile (@$segment) {
        my $now  = Time::HiRes::gettimeofday();
        my $runs = defined($chunk) ? $chunk->[$idx++] : undef;
        --$total;
        # Not while reading chunks:  each of them would count the inputs down
        #   again, from its own share of them.  What the user is told about a
        #   split read is the chunk count - see '_parallel_parse'.
        lcovutil::info("Merging $tracefile..$total remaining"
                           .
                           ($lcovutil::debug ?
                                (' mem:' . lcovutil::current_process_size()) :
                                '') .
                           "\n")
            if (1 != scalar(@$segment) && !defined($chunk))
            ;    # ...in segment $segId
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
                                       $lcovutil::verify_checksum, 1, $runs);
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
    my $total_trace = TraceFile->new();
    if (!(defined($lcovutil::maxParallelism) && defined($lcovutil::maxMemory)
    )) {
        lcovutil::init_parallel_params();
    }
    # use a particular file sort order - to somewhat minimize order effects
    my $filelist = \@_;
    my @sorted_filelist;
    if ($lcovutil::sort_inputs) {
        @sorted_filelist = sort({ $a cmp $b } @_);
        $filelist        = \@sorted_filelist;
    }
    # The inputs can be split at section boundaries and read by several children
    #   at once, whether there is one of them or many - see '_parallel_parse'.
    #   Decide that here because the memory estimate below does not apply to it:
    #   its unit of work is a chunk rather than a whole input file, and
    #   estimating from the largest input would throttle it to '--parallel 1'
    #   exactly where it pays most.
    my $chunks = _plan_parallel_parse($filelist);

    # source-based filters are somewhat expensive - so we turn them
    #   off for file read and only re-enable when we write the data back out
    my $save_filters = lcovutil::disable_cov_filters();

    if (!defined($chunks) &&
        0 != $lcovutil::maxMemory &&
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
            "Sizes: self:$currentSize file:$fileSize total:$size num:$num parallel:$lcovutil::maxParallelism\n"
        );
        if ($num < $lcovutil::maxParallelism) {
            $num = $num > 1 ? $num : 1;
            lcovutil::info(
                  "Throttling to '--parallel $num' due to memory constraint\n");
            $lcovutil::maxParallelism = $num;
        }
    }
    if (defined($chunks)) {
        @effective = _parallel_parse($total_trace, $readSourceFile, $filelist,
                                     $chunks, $save_filters);
    } elsif (1 != $lcovutil::maxParallelism &&
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

        my $tempDir = lcovutil::create_temp_dir();
        my $segment_trace;
        lcovutil::ForkManager->new(
         operation => 'aggregate',
         phase     => 'aggregate',
         tempDir   => $tempDir,
         prefix    => 'lcov',
         # no memory throttle:  there are at most '--parallel' segments by
         #   construction, and the estimate above has already decided how many
         #   of them will fit
         next => sub {
             my $segment = pop(@segments);
             return () unless defined($segment);
             return ($segment, $segmentIdx++);
         },
         more => sub { return scalar(@segments); },
         # Merge into a trace of this child's own rather than into the
         #   parent's running total.  What the parent has already merged is
         #   in the parent, and 'merge_tracefile' unions counts, so a child
         #   which handed that total back would have it counted twice.  A
         #   segment forked before the first merge sees an empty trace
         #   anyway;  a retried segment - forked after some other segment was
         #   merged - does not, which is where the double count showed up.
         #   See the 'site 3' single-failure cases in
         #   tests/lcov/parallel_fail.  Same reasoning for the function
         #   mapping, whose per-key lists the parent appends to.
         childInit => sub {
             $segment_trace     = TraceFile->new();
             %$function_mapping = () if $function_mapping;
         },
         child => sub {
             my ($segment, $idx, $forkAt) = @_;
             my $status = 0;
             my @interesting;
             eval {
                 @interesting =
                     _process_segment($segment_trace, $readSourceFile,
                                      $segment);
             };
             if ($@) {
                 print(STDERR $@);
                 $status = 1;
             }
             $lcovutil::profileData{$idx}{total} =
                 Time::HiRes::gettimeofday() - $forkAt;
             # still send what we have:  the parent decides what an
             #   unsuccessful segment means
             return ([$segment_trace, \@interesting, $function_mapping],
                     $status);
         },
         preMerge => sub {
             my $ctx = shift;
             lcovutil::info(
                          1,
                          'Merging segment ' .
                              $ctx->{id} . ", status $ctx->{status}"
                              .
                              (
                              $lcovutil::debug ?
                                  (' mem:' . lcovutil::current_process_size()) :
                                  '') .
                              "\n");
         },
         validate => sub {
             my ($payload, $ctx) = @_;
             my ($current, $changed, $func_map) = @$payload;
             my $idx = $ctx->{id};
             $lcovutil::profileData{$idx}{undump} =
                 Time::HiRes::gettimeofday() - $ctx->{reapAt};
             return 1
                 if ($function_mapping ?
                     defined($func_map) :
                     defined($current));
             lcovutil::report_parallel_error(
                       'aggregate',
                       $ERROR_PARALLEL,
                       $ctx->{child},
                       0,
                       "segment $idx returned empty " .
                           ($function_mapping ? 'function' : 'trace') . ' data',
                       @{$ctx->{siblings}});
             return 0;
         },
         merge => sub {
             my ($segment, $idx, $payload)      = @_;
             my ($current, $changed, $func_map) = @$payload;
             if ($function_mapping) {
                 while (my ($key, $data) = each(%$func_map)) {
                     $function_mapping->{$key} = [$data->[0], []]
                         unless exists($function_mapping->{$key});
                     die("mismatched function name '" .
                         $data->[0] . "' at $key")
                         unless ($data->[0] eq $function_mapping->{$key}->[0]);
                     push(@{$function_mapping->{$key}->[1]}, @{$data->[1]});
                 }
             } elsif ($total_trace->merge_tracefile($current, TraceInfo::UNION))
             {
                 # something in this segment improved coverage...so save
                 #   the effective input files from this one
                 push(@effective, @$changed);
             }
         },
         postReap => sub {
             my $ctx = shift;
             $lcovutil::profileData{$ctx->{id}}{merge} =
                 Time::HiRes::gettimeofday() - $ctx->{forkAt};
         },
         requeue          => sub { push(@segments, $_[0]); },
         forkFailWhen     => sub { return 'process segment'; },
         retryWhen        => sub { return "aggregate segment $_[0]->{id}"; },
         mergeFailMessage => sub {
             my $ctx = shift;
             return 'unable to deserialize segment ' .
                 $ctx->{id} . " $ctx->{dumpfile}:$ctx->{error}";
         },
         childFailMessage => sub {
             return "while processing segment $_[0]->{id}";
         },)->run();
    } else {
        # sequential
        @effective = _process_segment($total_trace, $readSourceFile, $filelist);
    }
    # Every input has now been read and merged, so this is the first point at
    #   which the per-testcase tables can be judged:  a coverage type missing a
    #   testcase in one input is unremarkable if a later input supplies it.
    #   Ask before filtering, so that the warning describes what the user gave
    #   us rather than what the filters left behind.
    #   The split path did this in its children, where each chunk already held
    #   all of its files' data and had not been filtered yet - so asking again
    #   here would both repeat the question and ask it of filtered data.
    $total_trace->checkTestcaseData()
        unless defined($chunks);
    #...and turn any enabled filters back on...
    lcovutil::reenable_cov_filters($save_filters);
    # filters had been disabled - need to explicitly exclude function bodies
    my $filterStart = Time::HiRes::gettimeofday();
    $total_trace->applyFilters($readSourceFile);
    my $filterTime = Time::HiRes::gettimeofday() - $filterStart;
    # A separate step, after everything was read and merged, so it gets a time of
    #   its own:  the whole job, not one number per input, because the filters run
    #   over the merged data and no longer know which input a source file came
    #   from.  This is the same 'filter' geninfo reports for its own filter step.
    #   (The forked filter workers, if there were any, are reported per-worker
    #   under the 'filt_' keys - see 'TraceFile::_processFilterWorklist' - which is
    #   where the parent/child breakdown of this number is.)
    #   Not in the split read:  there, each child filtered its own chunk as it read
    #   it and the call above found nothing left to do, so what filtering cost is
    #   reported per chunk, as that chunk's 'filter' - see
    #   'AggregateTraces::_parallel_parse'.
    # '+=', because 'lcov --intersect' reads two groups of inputs and so filters
    #   twice in the one run;  what the user wants to know is what filtering cost
    #   them altogether.
    $lcovutil::profileData{filter} =
        ($lcovutil::profileData{filter} // 0) + $filterTime
        unless defined($chunks);

    return ($total_trace, \@effective);
}

# call the common initialization functions

lcovutil::define_errors();
lcovutil::init_filters();

# Optionally load C++ XS acceleration for MapData and CountData.
# Controlled by LCOV_PURE_PERL=1 env var (forces pure Perl).
# The XS module is searched relative to this file's directory.
{

    package lcovutil;
    our $XS_LOADED = 0;
    # Why the extension did not load, or '' if it did (or if LCOV_PURE_PERL
    # asked us not to try).  The fallback below is silent by design, so this is
    # the only way to tell "pure Perl was requested" from "the XS library is
    # there but unusable" - which is what a toolchain mismatch looks like, and
    # which otherwise shows up only as a much slower run.  coverage.sh reads it
    # to confirm that each of its legs really ran the backend it intended to.
    our $XS_LOAD_ERROR = '';
    unless ($ENV{LCOV_PURE_PERL}) {
        my $xs_lib = $lcovutil::tool_dir;
        # tool_dir may not be set yet at module load time; fall back to FindBin
        if (!defined $xs_lib || !-d $xs_lib) {
            $xs_lib = $FindBin::Bin;
        }
        # Try lib/LcovUtil relative to the lcovutil.pm file itself
        my $self_dir = File::Basename::dirname(__FILE__);
        my $xs_blib  = File::Spec->catdir($self_dir, 'LcovUtil', 'blib', 'lib');
        my $xs_arch = File::Spec->catdir($self_dir, 'LcovUtil', 'blib', 'arch');
        # Add blib paths to @INC so XSLoader can find the .so
        if (-d $xs_blib && -d $xs_arch) {
            unshift @INC, $xs_blib, $xs_arch;
        }
        eval {
            no warnings 'once';
            require LcovUtil;
            $lcovutil::XS_LOADED     = $LcovUtil::XS_LOADED;
            $lcovutil::XS_LOAD_ERROR = $LcovUtil::XS_LOAD_ERROR;
        };
        # Silently fall back to pure Perl on any load error.  $@ is set only
        # when 'require LcovUtil' itself failed (the extension was never built);
        # if the .pm loaded but its XSLoader::load did not, LcovUtil.pm has
        # already recorded the reason and $@ is empty.
        $lcovutil::XS_LOAD_ERROR ||= $@;
    }
}

# Install pure-Perl Storable hooks only when XS is not loaded.
# When XS is loaded, the LcovUtil bootstrap already installed its own
# STORABLE_freeze/STORABLE_thaw for MapData and CountData (which operate on
# the C++ objects).  These pure-Perl versions apply only to the hashref/arrayref
# representations used in LCOV_PURE_PERL mode.
unless ($lcovutil::XS_LOADED) {
    {

        package MapData;

        sub STORABLE_freeze
        {
            my ($self, $cloning) = @_;
            return ("", {%$self});
        }

        sub STORABLE_thaw
        {
            my ($self, $cloning, $tag, $state_ref) = @_;
            my $state = ref($state_ref) eq 'REF' ? $$state_ref : $state_ref;
            %$self = %$state;
        }
    }
    {

        package CountData;

        sub STORABLE_freeze
        {
            my ($self, $cloning) = @_;
            my $state = [$self->[FILENAME], $self->[SORTABLE],
                         $self->[FOUND], $self->[HIT],
                         {%{$self->[HASH]}},
            ];
            return ("", $state);
        }

        sub STORABLE_thaw
        {
            my ($self, $cloning, $tag, $state_ref) = @_;
            my $state = ref($state_ref) eq 'REF' ? $$state_ref : $state_ref;
            $self->[FILENAME] = $state->[0];
            $self->[SORTABLE] = $state->[1];
            $self->[FOUND]    = $state->[2];
            $self->[HIT]      = $state->[3];
            $self->[HASH]     = {%{$state->[4]}};
        }
    }
}

1;
