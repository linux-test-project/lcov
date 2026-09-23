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

     @opt_rc apply_rc_params $split_char $split_pattern parseOptions
     strip_directories
     @file_subst_patterns subst_file_name
     @comments

     $br_coverage $func_coverage $mcdc_coverage $callgraph_coverage
     $callgraph_partial_data
     @coverTypeFound @coverTypeInputTotal @coverType
     @cpp_demangle do_mangle_check $demangle_cpp_cmd
     get_overall_line rate

     $FILTER_BRANCH_NO_COND $FILTER_FUNCTION_ALIAS
     $FILTER_EXCLUDE_REGION $FILTER_EXCLUDE_BRANCH $FILTER_LINE
     $FILTER_LINE_CLOSE_BRACE $FILTER_BLANK_LINE $FILTER_LINE_RANGE
     $FILTER_TRIVIAL_FUNCTION $FILTER_DIRECTIVE
     $FILTER_MISSING_FILE $FILTER_INITIALIZER_LIST
     $FILTER_EXCEPTION_BRANCH $FILTER_ORPHAN_BRANCH $FILTER_EXCLUDE_CALLGRAPH
     @cov_filter
     $EXCL_START $EXCL_STOP $EXCL_BR_START $EXCL_BR_STOP
     $EXCL_EXCEPTION_BR_START $EXCL_EXCEPTION_BR_STOP
     $EXCL_CALLGRAPH_START $EXCL_CALLGRAPH_STOP
     $EXCL_LINE $EXCL_BR_LINE $EXCL_EXCEPTION_LINE $EXCL_CALLGRAPH_LINE
     $UNREACHABLE_START $UNREACHABLE_STOP $UNREACHABLE_LINE
     @exclude_file_patterns @include_file_patterns %excluded_files
     @omit_line_patterns @exclude_function_patterns $case_insensitive
     $cross_platform_read $path_style check_path_separator
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

     system_no_output $devnull $dirseparator $dirseparator_re
     posix_path posix_paths @drive_mounts $translate_windows_names

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
# Windows path names, handed to a perl whose path syntax is Unix's:  a
#   git-bash, MSYS or Cygwin perl reports $^O as 'msys' or 'cygwin' and
#   doesn't handle drive letters - so thinks 'Z:\dir\file' is not a path name.
#   File::Spec does not see it as absolute, and everything built on that -
#   abs_path(), FindBin, rel2abs() - puts the current directory in front of it
#   and names something which does not exist, while basename() and dirname()
#   split on '/' only and hand back the whole string.
#   The name does arrive via $0 from a windows caller, or from an option or
#   env var set to a windows-style path
# The drives are mounted in those installations, so there is a name for the
#   same file which this perl does understand:  Z: is /z under MSYS and
#   git-bash and /cygdrive/z under Cygwin, each of them configurable in the
#   installation's own fstab - so look for the mount point and rewrite the name.
# The environment variable is a test hook:  it names one more directory to look
#   for the drives in, and turns the translation on, so that every line below
#   can be exercised from any platform.  It is not used in production.
our @drive_mounts = ('', '/cygdrive');
unshift(@drive_mounts, $ENV{LCOV_DRIVE_MOUNT})
    if exists($ENV{LCOV_DRIVE_MOUNT});
our $translate_windows_names =
    exists($ENV{LCOV_DRIVE_MOUNT}) ? 1 : $^O =~ /^(?:msys|cygwin)$/;

sub posix_path
{
    # The name this perl can use for the file the argument names:  the argument
    #   itself, unless it is a Windows path name and we are a perl which cannot
    #   read one.
    my $path = shift;
    return $path unless defined($path) && $translate_windows_names;
    # the separator first, and everywhere:  a backslash is the Windows
    #   separator, whether the path is absolute, relative or a UNC name, and
    #   whether or not it is written consistently - 'Z:\dir/other\file' is a
    #   path a Windows tool might pass us.  The result of this
    #   alone is usable for a relative name, and for a UNC name, which is
    #   '//host/share/...' here
    $path =~ s{\\}{/}g;
    return $path unless $path =~ m{^([A-Za-z]):/(.*)$};
    my ($drive, $rest) = (lc($1), $2);
    foreach my $mount (@drive_mounts) {
        return "$mount/$drive/$rest" if -d "$mount/$drive";
    }
    # a drive this installation has not mounted:  there is no name for it to be
    #   translated to, so leave it as is and let whatever needs the file
    #   report the drive the user named
    return $path;
}

sub posix_paths
{
    # 'posix_path' applied in place to whatever each of @_ refers to:  a
    #   reference to a scalar holding one path, or to an array holding several.
    #   This is how a tool translates everything it was handed in one place,
    #   before any of it is looked at.
    foreach my $ref (@_) {
        if ('ARRAY' eq ref($ref)) {
            @$ref = map({ posix_path($_) } @$ref);
        } else {
            $$ref = posix_path($$ref);
        }
    }
}

sub warn_mangled_path
{
    # A PATH entry which is a single letter is a drive letter which lost its
    #   colon:  something put 'S:/tools/lcov/bin' into a PATH whose separator
    #   is ':' here, and the shell split it into 'S' and '/tools/lcov/bin'.
    #   Neither of those is a directory, so the directory that was meant is not
    #   searched at all - while 'echo $PATH' still shows its name.  This looks
    #   like a broken install rather than a bad variable.
    #   Typical tools which aren't found are usually 'java', 'gcov' or
    #   'coverage'
    # This function attempts to report the actual issue on platforms
    # whose 'perl' thinks the drive letter is meaningful.
    # On Unix, a single letter directory is fine - or is somebody else's problem
    return unless $translate_windows_names && defined($ENV{PATH});
    my @entries = split(/:/, $ENV{PATH}, -1);
    for (my $i = 0; $i < scalar(@entries); ++$i) {
        next unless $entries[$i] =~ /^[A-Za-z]$/;
        # the rest of the split name is the next entry, if there is one:
        my $whole = $entries[$i] . ':' .
            ($i + 1 < scalar(@entries) ? $entries[$i + 1] : '');
        my $posix = posix_path($whole);
        # there is nothing to suggest when the drive is not mounted, or when the
        #   letter was the last thing on the PATH and has no remainder to rejoin
        my $instead =
            $posix eq $whole ? 'the name this perl understands' : "'$posix'";
        # write directly to STDERR rather than 'warn': this runs while the
        #  module is being loaded, so the message infrastructure (the
        #  'warn_handler') isn't initialized yet
        my $msg = "Warning: PATH entry '$entries[$i]' is a single letter: ";
        $msg .= "'$whole' was split on the ':' of its drive letter, which is ";
        $msg .= "the PATH separator here, so that directory is not being ";
        $msg .= "searched.  Use $instead in PATH instead.\n";
        print(STDERR $msg);
    }
}

# The script we were loaded by:  the directory it is installed in - which is
#   where it finds the other tools of the same installation - and the name it
#   is to call itself in its messages.
#   FindBin doesn't work because it doesn't handle $0 on windows - see above.
sub _tool_paths
{
    my $path = posix_path($0);
    return (getcwd(), $path) unless -f $path;
    my $abs = abs_path($path);
    # abs_path() answers undef if the script was moved out from under us:  the
    #   name we have is then the best one left
    $abs = $path unless defined($abs);
    return (dirname($abs), basename($abs));
}
our ($tool_dir, $tool_name) = _tool_paths();

# get_version.sh lives beside the tools in bin/, so $tool_dir finds it whenever
# we are loaded by one of them.  When we are loaded some other way - a
# diagnostic one-liner, or lib/LcovUtil/Makefile.PL deriving the error ids -
# $tool_dir is that caller's directory instead, and running the script
# from there would print a bare 'No such file or directory' to stderr and leave
# $VERSION empty.  Look beside this file as well before giving up, so the
# version is right and nothing is logged in either case.
# __FILE__ is translated for the same reason $0 is:  when the @INC entry which
# found this file named the lib directory the Windows way, rel2abs() would
# otherwise put the current directory in front of the drive letter and the
# fallback would name nothing.  See 'posix_path' above.
#
# Keep the '$VERSION =' assignment on one line:  'make install' runs bin/fix.pl,
# which replaces the remainder of that line with a literal version string.
sub _find_version
{
    foreach my $dir ($tool_dir,
                     File::Spec->catdir(
                                   File::Basename::dirname(
                                       File::Spec->rel2abs(posix_path(__FILE__))
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
our $devnull      = File::Spec->devnull();         # portable way to do it
our $dirseparator = ($^O =~ /Win/) ? '\\' : '/';
# need a regexp of the dir separator.
# The windows separator is the regex escape character - so the pattern cannot
# simply interpolate it: "s/^$dirseparator//" is 's/^\//' - not a legal pattern.
#   Use '$dirseparator_re' in match expressions, substitutions and 'split' -
#     it is also correct inside a character class.
#   Use  '$dirseparator' itself to build a path, and on the
#     replacement side of a substitution.
# 'set_path_style' keeps the two in sync.
our $dirseparator_re = quotemeta($dirseparator);
# Whether this platform accepts the other platform's separator as well as its
#   own.  Windows treats '/' and '\' alike;  so do Cygwin and MSYS, whose
#   canonical separator is the POSIX one but whose path layer takes a Windows
#   name as it stands - Perl's own 'File::Spec::Cygwin' turns every backslash
#   into '/' in 'canonpath' and calls 'C:\dir\file.c' absolute.  There are three
#   cases here rather than two, and this is the one which is not decided by
#   '$dirseparator':  where this is false a backslash is an ordinary character
#   in a file name, and a Windows name reaches nothing.
# '$path_platform' is what to call this platform in the message which says that
#   a foreign name was accepted.  'set_path_style' sets all four of these.
our ($accepts_both_separators, $path_platform) =
    ($^O =~ /Win/) ? (1, 'Windows') :
    ($^O eq 'cygwin') ? (1, 'Cygwin') :
    ($^O eq 'msys') ? (1, 'MSYS') :
    (0, 'POSIX');
our $interp = ($^O =~ /Win/) ? $^X : undef;

our $debug   = 0;    # if set, emit debug messages
our $verbose = 0;    # default level - higher to enable additional logging

our $split_char = ',';    # by default: split on comma
# The same delimiter as a pattern, for 'split'.  The two are not
#   interchangeable:  'split_char' is documented as "the character (or
#   regexp)", and the character a user reaches for when the list elements
#   contain a comma - '|' above all - is a regexp metacharacter.  As a pattern
#   '|' matches the empty string, so 'split' would return one element per
#   character of the list.  So a single character is taken literally and
#   anything longer is taken as a regexp;  'set_split_char' keeps this in sync
#   with '$split_char'.
# Use this one with 'split', and '$split_char' itself with 'join'.
our $split_pattern = qr/,/;

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

# The widest execution count we store, and thus the widest one we write to a
# '.info' file.  Matches lcov::MAX_COUNT in lib/LcovUtil/CountArith.hpp, which
# is the same limit the XS implementation is bounded by (a signed 64-bit
# integer):  see normalize_count.
# Spelled in decimal:  Perl warns 'Hexadecimal number > 0xffffffff non-portable'
# for a hex literal wider than 32 bits
our $MAX_COUNT = 9223372036854775807;    # 0x7fffffffffffffff

our $br_coverage   = 0;    # If set, generate branch coverage statistics
our $mcdc_coverage = 0;    # MC/DC
our $func_coverage = 1;    # If set, generate function coverage statistics
# Callgraph coverage is a sub-metric of function coverage:  the data hangs off
#   FunctionEntry and FunctionAlias, so it cannot be enabled unless function
#   coverage is - see the check in parseOptions.
our $callgraph_coverage = 0;    # call sites within each function

# The coverpoint types a '.info' file may contain, as indexes into the two
#   tables below.
use constant {
              COVER_TYPE_FUNCTION  => 0,
              COVER_TYPE_BRANCH    => 1,
              COVER_TYPE_MCDC      => 2,
              COVER_TYPE_CALLGRAPH => 3,
              COVER_TYPE_COUNT     => 4,
};

# Everything the per-type checks use, indexed by COVER_TYPE_ :  one row
#   per type - one place to add new types.
#     'name' is what the type is called in messages - and the label its summary
#        row carries;  see 'summaryLabel' and '%coverTypeCoverpoint' below.
#     'option' is the command line arg.
#     'flag' is a ref rather than a value because the flag value isn't set
#        until after the command line in parsed.
#     'total' is this type's slot in the list 'TraceFile::count_totals' returns
#     'have' is "does this report contain coverpoints of this type"
#     'empty' overrides the generic "enabled but nothing found" message where
#        there is something to say a about data coverage (see callgraph entry)
#     'disable' says whether ignoring that error should turn the metric off.
#     'count' is the '.info' tag corresponding to the total number of
#        coverpoitns of the corresponding type, summed across all the files.
#        This is before filtering or other modification - and enables us
#        to distinguish the case that there were no coverpoints in the data
#        from the case that the data was not collected (say, --branch coverage
#        was disabled) from the case that there were no such coverpoints
#        in the report, or that we removed/filtered all the points that
#        used to exist.
#        See 'checkEnabledMetric', '@lcovutil::coverTypeInputTotal' and
#        '%recordDeclaresCoverType'.
# See 'TraceFile::checkEmpty' and 'TraceFile::checkEnabledMetric'.
our @coverType = (
    {
     name   => 'function',
     option => '--function-coverage',
     flag   => \$func_coverage,
     total  => 3,
     have   => sub { $_[1]->[3]->[0] != 0 },
     # deliberately no 'count':  'FNF:0' says this file defines no functions.
     #   This isn't too surprising -  e.g.  a header of macros, or a
     #   '#include'd fragment - may not contain any functions.
     #   A report with no functions at all what the check looks for.
    },
    {
     name   => 'branch',
     option => '--branch-coverage',
     flag   => \$br_coverage,
     total  => 2,
     have   => sub { $_[1]->[2]->[0] != 0 },
     count  => 'BRF',
    },
    {
     name   => 'MC/DC',
     option => '--mcdc-coverage',
     flag   => \$mcdc_coverage,
     total  => 4,
     have   => sub { $_[1]->[4]->[0] != 0 },
     count  => 'MCF',
    },
    {
        name   => 'callgraph',
        option => '--callgraph-coverage',
        flag   => \$callgraph_coverage,
        # the caller-side count:  the call sites my files contain, not the sites
        #   which target the functions they define - see
        #   'TraceInfo::callgraph_found'
        total => 5,
        # not count_totals' call-site slot:  a report all of whose calls cross
        #   the boundary has no site and still has callgraph data - see
        #   'TraceFile::hasCallgraphData'
        have => sub { $_[0]->hasCallgraphData() },
        # 'write_info' already wrote this one for a file whose calls were
        #   counted and came to zero - to enable error checking
        count => 'FNCF',
        empty =>
            "--callgraph-coverage is enabled but no call-site data was found in any input file.  Capture with 'geninfo --callgraph-coverage' on code compiled with -fcallgraph-info.",
        # else every summary carries a 0/0 callee column for data which was
        #   never measured
        disable => 1,
    });

# The cover types whose coverpoint is not named after the type, keyed by the
#   'name' above:  a report has lines, functions and branches, but it has one
#   callgraph, whose coverpoints are callees, and one MC/DC metric, whose
#   coverpoints are conditions.  Every other type is its own coverpoint, so it
#   needs no row here - see 'coverpointName'.
# 'summaryLabel' reads exactly that distinction, so this is the one table the
#   tools which name a cover type to the user take their words from - 'lcov'
#   ('TraceFile::print_summary'), 'genhtml' ('SummaryInfo::print_overall_rate'
#   and the source view's coverpoint captions).  They printed two different
#   labels for one metric while each kept a list of its own.
our %coverTypeCoverpoint = ('MC/DC' => 'condition', 'callgraph' => 'callee');

# Summary rows line their labels up under the widest one.
our $summaryLabelWidth = length('source files');

# Whether any '.info' file we read held a record of the corresponding type
#   above - regardless of whether that type is enabled.  A record of a disabled
#   type is dropped without being parsed but we want to keep track of
#   whether we saw something or not
#   See '%recordDispatch' and 'TraceFile::_read_info'.
# Write-once (0 -> 1) and never cleared.
#   Used to emit warning that user may have forgotten to add a flag
our @coverTypeFound = (0) x COVER_TYPE_COUNT;

# The sum of the corresponding type's count records - its 'count' tag in
#   '@coverType' above - over every '.info' file read:  undef where no input
#   contained the type (which is different from seeing zeros everywhere).
# A zero total is a measurement.  It says the producer counted this type's
#   coverpoints in those files and there weren't any: straight-line code has
#   no branches, for example.
#   A total which is not zero and has no surviving coverpoints means that the
#   coverpoints were there and this run's filters removed them - which
#   is likely not what the user expected, and what we want to complain about.
# Only accumulated for the types which are enabled:  the count of a type nobody
#   asked about is not consulted - see '%recordDeclaresCoverType'.
# Kept apart from '@coverTypeFound' because they answer different questions:
#   the report contains no such coverpoints (this check) vs
#   'checkEmpty' which asks if there was data that the command line has
#    discarded.
our @coverTypeInputTotal = (undef) x COVER_TYPE_COUNT;

sub inputCountedNone($)
{
    # Did the inputs count this type's coverpoints and find none?  The one
    #   reading of '@coverTypeInputTotal' anybody wants:  an explicit zero, as
    #   against a count nobody gave us (undef) and a count which was not zero.
    my $covType = $_[0];
    return defined($coverTypeInputTotal[$covType]) &&
        0 == $coverTypeInputTotal[$covType];
}

# What geninfo does with a caller whose two halves of the join do not line up:
#   0 (the default) drops that caller's callgraph data, 1 keeps the sites
#   which did pair and records a call the compiler saw but gcov gave no arc
#   for with an
#   unknown count ('-').  Deliberately independent of '--ignore-errors
#   inconsistent':  this is a policy on what data to keep, not on whether to
#   report the problem, and both combinations are wanted
our $callgraph_partial_data = 0;
# How hard the source view tries to underline a call.  Either way it reads the
#   identifier which starts at the column the compiler recorded and the one
#   which ends just left of it - GCC's C++ front end points at the call's opening
#   parenthesis - and takes whichever of the two spells one of the callees
#   recorded at that site.  When neither does:  0 (the default) underlines the
#   likelier of the two anyway, because in a C++ report most sites are calls
#   whose source text is not the callee's name;  1 leaves the source text alone
#   and names the site in the line's trailing comment instead.  See genhtml's
#   _calleeSpliceSpan
our $strict_callee_match = 0;

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
# see '_continuationLineMerge', '_statementBranchMerge' and '_lambdaSuppressed'
our $merge_continuation_lines  = 0;
our $ignore_lambda_consistency = 0;
# what '_continuationLineMerge' did:  the number of continuation line
#   coverpoints it removed from the summary data, and the number of statement
#   lines they were merged into - see 'summarize_cov_filters'
our $continuation_lines_merged  = 0;
our $continuation_merge_targets = 0;

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
# region between LCOV EXCL_CALLGRAPH_START/STOP
our $FILTER_EXCLUDE_CALLGRAPH;
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
# remove the call sites whose count this capture does not know
our $FILTER_UNKNOWN_CALLEE_COUNT;
our $FILTER_OMIT_PATTERNS;    # special/somewhat faked filter

our %COVERAGE_FILTERS = (
                        "branch"               => \$FILTER_BRANCH_NO_COND,
                        'brace'                => \$FILTER_LINE_CLOSE_BRACE,
                        'blank'                => \$FILTER_BLANK_LINE,
                        'directive'            => \$FILTER_DIRECTIVE,
                        'range'                => \$FILTER_LINE_RANGE,
                        'line'                 => \$FILTER_LINE,
                        'initializer'          => \$FILTER_INITIALIZER_LIST,
                        'function'             => \$FILTER_FUNCTION_ALIAS,
                        'missing'              => \$FILTER_MISSING_FILE,
                        'region'               => \$FILTER_EXCLUDE_REGION,
                        'branch_region'        => \$FILTER_EXCLUDE_BRANCH,
                        'callgraph_region'     => \$FILTER_EXCLUDE_CALLGRAPH,
                        'exception'            => \$FILTER_EXCEPTION_BRANCH,
                        'orphan'               => \$FILTER_ORPHAN_BRANCH,
                        'mcdc'                 => \$FILTER_MCDC_SINGLE,
                        "trivial"              => \$FILTER_TRIVIAL_FUNCTION,
                        'unknown_callee_count' => \$FILTER_UNKNOWN_CALLEE_COUNT,
);
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
# marker to exclude call sites but keep line, branch and function coverage
our $EXCL_CALLGRAPH_START = 'LCOV_EXCL_CALLGRAPH_START';
our $EXCL_CALLGRAPH_STOP  = 'LCOV_EXCL_CALLGRAPH_STOP';
# exclude on this line
our $EXCL_LINE           = 'LCOV_EXCL_LINE';
our $EXCL_BR_LINE        = 'LCOV_EXCL_BR_LINE';
our $EXCL_EXCEPTION_LINE = 'LCOV_EXCL_EXCEPTION_BR_LINE';
our $EXCL_CALLGRAPH_LINE = 'LCOV_EXCL_CALLGRAPH_LINE';

# should we ignore exclusion tags in the input .info file or not
# by default: do not ignore
# we don't expect user to want to change - so only changed via the RC file
our $ignore_unreachable_flag = 0;

our @exclude_file_patterns;
our @include_file_patterns;
our %excluded_files;
our $case_insensitive         = 0;
our $exclude_exception_branch = 0;
# merge the aliases of one function which call and are called identically - see
#   TraceFile::_collapseCallgraphAliases.  On by default:  the merged names and
#   their counts are retained, so the merge does not lose function coverage
our $collapse_callgraph_alias           = 1;
our $derive_function_end_line           = 1;
our $derive_function_end_line_all_files = 0;    # by default, C only
our $trivial_function_threshold         = 5;

# Translate a source file name which uses a different platform's directory
#   separator to format on this platform - e.g. a windows path read on a linux
#   box or a linux path read on a windows box - so that a '.info' or udiff file
#   captured on one can be read on the other.
# Translation enabled by default: untranslated, the name will not match
#   anything on this machine (whereas the translated path should).
# Disable via '--rc cross_platform_read=0' or your lcovrc file if your
#   project actually does contain paths which use the other platform's
#   separator - for example, '\' (backslash) in a POSIX file name.
#   If disabled: names are not modified and you will see a 'usage' error
#   (which you will need to ignore) if a path contains both characters.
# The setting has no effect on a platform such as windows, cygwin, or msys
#   which supports both separators.  There, the names are always normalized -
#   see 'check_path_separator'.
our $cross_platform_read = 1;
# Which platform's path convention this run works in:  'auto' - whatever we are
#   running on - or 'posix', 'windows' or 'cygwin'.  Only 'auto' makes sense in
#   production:  the separator has to be the one the file system here really
#   uses.  The other three are how a test drives every direction of the
#   translation above from whichever platform it happens to run on;  see
#   'set_path_style'.
our $path_style = 'auto';

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

our %languageExtensions = ('c'    => 'c|h|i|C|H|I|icc|cpp|cc|cxx|hh|hpp|hxx|xs',
                           'rtl'  => 'v|vh|sv|vhdl?',
                           'perl' => 'pl|pm',
                           'python' => 'py',
                           'java'   => 'java');
# The languages of a file are held as the OR of these flags - see
#   'TraceFile::language' - so a check for any of several languages is one '&'
#   with the OR of their flags:  'TraceFile::is_language(IS_C | IS_JAVA, $f)'
use constant {
              IS_C      => 0x1,
              IS_RTL    => 0x2,
              IS_PERL   => 0x4,
              IS_PYTHON => 0x8,
              IS_JAVA   => 0x10,
};
# the languages whose statements 'ReadCurrentSource::statementSpan' finds
use constant STATEMENT_LANGUAGES => IS_C | IS_JAVA | IS_PERL | IS_PYTHON;
# language name (as in '%languageExtensions') -> flag
our %languageFlag = ('c'      => IS_C,
                     'rtl'    => IS_RTL,
                     'perl'   => IS_PERL,
                     'python' => IS_PYTHON,
                     'java'   => IS_JAVA);

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
                     'COLOR_20' => 'EC7063',
                     'COLOR_21' => 'F2EEEE',);
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
                       'COLOR_21' => 'F2EEEE',    # paler grey than COLOR_17
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
               '+' => ['GNC', 'UNC'],
               # no tag at all:  there is no baseline to compare against, so the
               #   line is simply hit or not hit - which is what 'GNC'/'UNC' mean
               #   in a report with no differential data (see the legacy labels in
               #   genhtml).  A count with no tag in front of it is what a '.gcov'
               #   file gives 'genpng' directly, and also what genhtml's
               #   'unexpected TLA' path produces once that error is ignored
               '' => ['GNC', 'UNC'],);

our @opt_rc;    # list of command line RC overrides

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
# shell_quote($string)
#
# Return $string wrapped so that a POSIX shell passes it through as one word,
#   whatever it contains.  Use this on every path or user-supplied string
#   which is interpolated into a command handed to a shell - i.e. into
#   'system' or 'open' with one argument rather than a list.
# Single quotes protect everything except a single quote, which has to be
#   closed, escaped, and reopened.
#
sub shell_quote($)
{
    my $str = shift;
    $str = '' unless defined($str);
    $str =~ s/'/'\\''/g;
    return "'$str'";
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

    my $details;
    $details = $ENV{LCOV_SHOW_LOCATION}
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
    # this is both '$SIG{__DIE__}' and called directly - e.g., by
    #   'ignorable_error'.  Perl before 5.42 did not call the hook for a die
    #   from within the hook sub however that sub was entered; from 5.42 only
    #   an actual hook call is protected, so a direct call would come back
    #   here from its own 'die' and prefix (and log) the message twice
    local $SIG{__DIE__};
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
            # apparent Devel::Cover attribution bug:  this statement is reported
            #   uncovered despite that 'read_proc_vmsize' in the same
            #   block is hit
            lcovutil::info(    # LCOV_TESTED_LINE
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
    $lcovutil::profileData{config}{bin} = $bin;
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
        # Platform-independent configuration
        # POSIX::uname returns (sysname, nodename, release, version, machine) -
        #   the same fields, in the same order, that 'uname -a' prints, and its
        #   nodename is what 'hostname' says.
        my @uname = POSIX::uname();
        # not strftime's '%a %b':  perl sets the locale from the environment,
        #   so those would be the day and month names of LC_TIME and a reader
        #   of the profile would have to know the locale of the writer
        my @now = localtime();
        $lcovutil::profileData{config}{date} =
            sprintf(
                 '%s %s %02d %02d:%02d:%02d %04d',
                 (qw(Sun Mon Tue Wed Thu Fri Sat))[$now[6]],
                 (qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec))[$now[4]],
                 @now[3, 2, 1, 0],
                 $now[5] + 1900);
        $lcovutil::profileData{config}{uname}    = join(' ', @uname);
        $lcovutil::profileData{config}{hostname} = $uname[1];
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

sub set_split_char
{
    # turn whatever the user asked for into the pattern the 'split' calls use.
    #   Called from 'apply_rc_params' before anything which splits a list, so
    #   an invalid value is deferred rather than fatal (the suppression list
    #   has not been looked at yet) and the default stays in place meanwhile
    my $c = defined($split_char) ? $split_char : '';
    my $err;
    if ('' eq $c) {
        $err = 'is empty';
    } elsif (1 == length($c)) {
        # the documented case:  the character itself, whether or not it happens
        #   to mean something to the regexp engine
        $split_pattern = qr/\Q$c\E/;
    } else {
        # 'local $SIG{__DIE__}':  we want the regexp compiler's complaint, not
        #   the decorated one our own handler would put in '$@'
        my $pat = eval { local $SIG{__DIE__}; qr/$c/ };
        if (!defined($pat)) {
            my $msg = $@;
            $msg =~ s/ at \S+ line \d+\.?\s*$//;
            $msg =~ s/\s+$//;
            $err = "is not a valid regexp: $msg";
        } elsif ('' =~ /$pat/) {
            # 'split' returns one element per character of the list for such a
            #   pattern - silently, so every list option turns into nonsense
            $err = 'matches the empty string';
        } else {
            $split_pattern = $pat;
        }
    }
    return unless defined($err);
    $split_char    = ',';
    $split_pattern = qr/,/;
    push(@deferred_rc_errors,
         [1, $lcovutil::ERROR_USAGE,
          "'split_char' value '$c' $err - using the default ',' instead"
         ]);
}

sub set_extensions
{
    my ($type, $str) = @_;
    die("unknown language '$type'") unless exists($languageExtensions{$type});
    # the extension list is used as a regexp alternation:  the
    #   default RTL list is 'v|vh|sv|vhdl?' - so check that what the user gave
    #   us can be compiled here, rather than dying inside 'TraceFile::language'
    #   at the first file whose name we look at
    my $alternation = join('|', split($split_pattern, $str));
    unless (defined(eval { local $SIG{__DIE__}; qr/^\.($alternation)$/ })) {
        my $msg = $@;
        $msg =~ s/ at \S+ line \d+\.?\s*$//;
        $msg =~ s/\s+$//;
        die("invalid ${type}_file_extensions '$str': $msg\n");
    }
    $languageExtensions{$type} = $alternation;
    %TraceFile::languageCache = ();
}

sub do_mangle_check
{
    return unless @lcovutil::cpp_demangle;
    if (1 == scalar(@lcovutil::cpp_demangle) &&
        '' eq $lcovutil::cpp_demangle[0]) {
        # no demangler specified - use c++filt by default
        $lcovutil::cpp_demangle[0] = 'c++filt';

        # Extra flag necessary on OS X so that symbols listed by gcov
        # get demangled properly.
        # Only append the flag if the user didn't use custom flags.
        # If they did:  then user is responsible.
        push(@lcovutil::cpp_demangle, '--no-strip-underscore')
            if ($^O eq "darwin");
    }

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
        split($lcovutil::split_pattern, join($lcovutil::split_char, @_)) :
        @_;
    # The first element names the script or module;  the rest are its callback arguments
    $args[0] = posix_path($args[0]);
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
            my $err = $@ ? ': ' . lcovutil::unreported_error($@) : '';
            lcovutil::ignorable_error($lcovutil::ERROR_PACKAGE,
                         "unable to create callback from module '$script'$err");
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
    'trivial_function_threshold'   => \$lcovutil::trivial_function_threshold,
    "lcov_tmp_dir"                 => \$lcovutil::tmp_dir,
    "lcov_json_module"             => \$JsonSupport::rc_json_module,
    "branch_coverage"              => \$lcovutil::br_coverage,
    'mcdc_coverage'                => \$lcovutil::mcdc_coverage,
    'callgraph_coverage'           => \$lcovutil::callgraph_coverage,
    'callgraph_partial_data'       => \$lcovutil::callgraph_partial_data,
    'strict_callee_match'          => \$lcovutil::strict_callee_match,
    "function_coverage"            => \$lcovutil::func_coverage,
    "lcov_excl_line"               => \$lcovutil::EXCL_LINE,
    "lcov_excl_br_line"            => \$lcovutil::EXCL_BR_LINE,
    "lcov_excl_exception_br_line"  => \$lcovutil::EXCL_EXCEPTION_LINE,
    "lcov_excl_start"              => \$lcovutil::EXCL_START,
    "lcov_excl_stop"               => \$lcovutil::EXCL_STOP,
    "lcov_excl_br_start"           => \$lcovutil::EXCL_BR_START,
    "lcov_excl_br_stop"            => \$lcovutil::EXCL_BR_STOP,
    "lcov_excl_exception_br_start" => \$lcovutil::EXCL_EXCEPTION_BR_START,
    "lcov_excl_exception_br_stop"  => \$lcovutil::EXCL_EXCEPTION_BR_STOP,
    "lcov_excl_callgraph_line"     => \$lcovutil::EXCL_CALLGRAPH_LINE,
    "lcov_excl_callgraph_start"    => \$lcovutil::EXCL_CALLGRAPH_START,
    "lcov_excl_callgraph_stop"     => \$lcovutil::EXCL_CALLGRAPH_STOP,
    'lcov_unreachable_start'       => \$lcovutil::UNREACHABLE_START,
    'lcov_unreachable_stop'        => \$lcovutil::UNREACHABLE_STOP,
    'lcov_unreachable_line'        => \$lcovutil::UNREACHABLE_LINE,
    'retain_unreachable_coverpoints_if_executed' =>
        \$lcovutil::retainUnreachableCoverpointIfHit,
    "ignore_unreachable_flag"    => \$lcovutil::ignore_unreachable_flag,
    "ignore_errors"              => \@rc_ignore,
    "max_message_count"          => \$lcovutil::suppressAfter,
    "message_log"                => \$lcovutil::message_log,
    'expected_message_count'     => \@rc_expected_msg_counts,
    'stop_on_error'              => \$lcovutil::stop_on_error,
    'treat_warning_as_error'     => \$lcovutil::treat_warning_as_error,
    'warn_once_per_file'         => \$lcovutil::warn_once_per_file,
    'check_data_consistency'     => \$lcovutil::check_data_consistency,
    'ignore_lambda_consistency'  => \$lcovutil::ignore_lambda_consistency,
    'merge_continuation_lines'   => \$lcovutil::merge_continuation_lines,
    "rtl_file_extensions"        => \$rtlExtensions,
    "c_file_extensions"          => \$cExtensions,
    "perl_file_extensions"       => \$perlExtensions,
    "python_file_extensions"     => \$pythonExtensions,
    "java_file_extensions"       => \$javaExtensions,
    'info_file_pattern'          => \$info_file_pattern,
    "filter_lookahead"           => \$lcovutil::source_filter_lookahead,
    "filter_bitwise_conditional" =>
        \$lcovutil::source_filter_bitwise_are_conditional,
    'filter_blank_aggressive'        => \$filter_blank_aggressive,
    "profile"                        => \$lcovutil::profile,
    "parallel"                       => \$lcovutil::maxParallelism,
    "memory"                         => \$lcovutil::maxMemory,
    "memory_percentage"              => \$lcovutil::memoryPercentage,
    "max_fork_fails"                 => \$lcovutil::max_fork_fails,
    "max_tasks_per_core"             => \$lcovutil::max_tasks_per_core,
    "dedicate_segment_threshold"     => \$lcovutil::dedicate_segment_threshold,
    "dedicate_segment_line_estimate" =>
        \$lcovutil::dedicate_segment_line_estimate,
    'parallel_parse_min_lines'         => \$lcovutil::parallel_parse_min_lines,
    'parallel_parse_chunks_per_worker' =>
        \$lcovutil::parallel_parse_chunks_per_worker,
    "fork_fail_timeout" => \$lcovutil::fork_fail_timeout,
    'source_directory'  => \@rc_source_directories,
    'build_directory'   => \@rc_build_dir,

    "no_exception_branch"      => \$lcovutil::exclude_exception_branch,
    'collapse_callgraph_alias' => \$lcovutil::collapse_callgraph_alias,
    'filter'                   => \@rc_filter,
    'exclude'                  => \@rc_exclude_patterns,
    'include'                  => \@rc_include_patterns,
    'substitute'               => \@rc_subst_patterns,
    'omit_lines'               => \@rc_omit_patterns,
    'erase_functions'          => \@rc_erase_patterns,
    'context_script'           => \@rc_contextCallback,
    "version_script"           => \@rc_version_script,
    'resolve_script'           => \@rc_resolveCallback,
    'criteria_callback_data'   => \@CoverageCriteria::criteriaCallbackTypes,
    'criteria_callback_levels' => \@CoverageCriteria::criteriaCallbackLevels,
    'criteria_script'          => \@rc_criteria_script,
    'unreachable_script'       => \@rc_excludeCoverpointCallback,

    "checksum"              => \$lcovutil::verify_checksum,
    'compute_file_version'  => \$lcovutil::compute_file_version,
    "case_insensitive"      => \$lcovutil::case_insensitive,
    "forget_testcase_names" => \$TraceFile::ignore_testcase_name,
    "split_char"            => \$lcovutil::split_char,
    'cross_platform_read'   => \$lcovutil::cross_platform_read,
    'path_style'            => \$lcovutil::path_style,

    'check_existence_before_callback' => \$check_file_existence_before_callback,

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

our %argCommon = (
            "tempdir=s"         => \$lcovutil::tmp_dir,
            "version-script=s"  => \@lcovutil::extractVersionScript,
            "criteria-script=s" => \@CoverageCriteria::coverageCriteriaScript,

            "checksum"    => \$lcovutil::verify_checksum,
            "no-checksum" => \$rc_no_checksum,
            "quiet|q+"    => \$quiet,
            "verbose|v+"  => \$lcovutil::verbose,
            "debug+"      => \$lcovutil::debug,
            "help|h|?"    => \$help,
            "version"     => \$version,
            'comment=s'   => \@comments,
            'toolname=s'  => \$lcovutil::tool_name,

            "function-coverage" => \$lcovutil::func_coverage,
            "branch-coverage"   => \$lcovutil::br_coverage,
            'mcdc-coverage'     => \$lcovutil::mcdc_coverage,
            # 'callgraph' is spelled out as an alias rather than left to
            #   Getopt's abbreviation, which stopped being unambiguous
            #   when the second 'callgraph-*' option was added:  an exact
            #   match wins over a prefix match, and '--callgraph' is the
            #   spelling the documentation and the tests use
            'callgraph-coverage|callgraph' => \$lcovutil::callgraph_coverage,
            'callgraph-partial-data' => \$lcovutil::callgraph_partial_data,
            "no-function-coverage"   => \$rc_no_func_coverage,
            "no-branch-coverage"     => \$rc_no_branch_coverage,

            "fail-under-lines=s"    => \$fail_under_lines,
            "fail-under-branches=s" => \$fail_under_branches,
            'source-directory=s'    => \@ReadCurrentSource::source_directories,
            'build-directory=s'     => \@lcovutil::build_directory,

            'resolve-script=s'       => \@lcovutil::resolveCallback,
            'context-script=s'       => \@lcovutil::contextCallback,
            'unreachable-script=s'   => \@lcovutil::excludeCoverpointCallback,
            "filter=s"               => \@opt_filter,
            "demangle-cpp:s"         => \@lcovutil::cpp_demangle,
            "ignore-errors=s"        => \@opt_ignore_errors,
            "expect-message-count=s" => \@opt_expected_message_counts,
            'msg-log:s'              => \$message_log,
            "keep-going"             => \$keepGoing,
            "config-file=s"          => \@unsupported_config,
            "rc=s%"                  => \%unsupported_rc,
            "profile:s"              => \$lcovutil::profile,
            'history-script=s'       => \@lcovutil::profileHistoryCallback,
            "exclude=s"              => \@lcovutil::exclude_file_patterns,
            "include=s"              => \@lcovutil::include_file_patterns,
            "erase-functions=s"      => \@lcovutil::exclude_function_patterns,
            "omit-lines=s"           => \@lcovutil::omit_line_patterns,
            "substitute=s"           => \@lcovutil::file_subst_patterns,
            "parallel|j:i"           => \$lcovutil::maxParallelism,
            "memory=i"               => \$lcovutil::maxMemory,
            "forget-test-names"      => \$TraceFile::ignore_testcase_name,
            "preserve"               => \$lcovutil::preserve_intermediates,
            'sort-input'             => \$lcovutil::sort_inputs,);

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
                                      '" -> "' .
                                      $filename . '"');
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

    # the config file may have windows style pathname
    posix_paths(\@opt_config_files);
    if (0 != scalar(@opt_config_files)) {
        foreach my $f (@opt_config_files) {
            $set_value |= read_config($f, \%rcHash);
        }
    } else {
        foreach my $v (['HOME', '.lcovrc'], ['LCOV_HOME', 'etc', 'lcovrc']) {
            next unless exists($ENV{$v->[0]});
            my $f =
                File::Spec->catfile(posix_path($ENV{$v->[0]}), splice(@$v, 1));
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
    # before the extension lists below, and before anything else splits a list
    set_split_char();
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
    posix_paths(\$message_log);
    posix_paths($output_arg) if defined($output_arg);
    if (defined($message_log)) {
        if (!$message_log) {
            # base log file name on output arg (if specified) or tool name otherwise
            $message_log = (
                        defined($$output_arg) ?
                            substr($$output_arg, 0, rindex($$output_arg, '.')) :
                            $tool_name) . ".msg";
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
                    [\@lcovutil::exclude_function_patterns,
                     \@rc_erase_patterns
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

    # canonicalize windows paths
    posix_paths(\@ReadCurrentSource::source_directories,
                \@lcovutil::build_directory, \$lcovutil::tmp_dir,
                \$lcovutil::profile);

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

    # Callgraph coverage hangs off the function data, so it cannot be collected,
    #   written or reported with function coverage turned off:  the combination
    #   is a contradiction rather than a degraded mode.  Function coverage is
    #   not silently turned back on - '--no-function-coverage' is an explicit
    #   instruction - and if the user ignores the error, then the one coherent
    #   state left is callgraph coverage off.  This has to come after
    #   'parse_ignore_errors' above, or '--ignore usage' would not be in effect
    #   yet.
    if ($lcovutil::callgraph_coverage &&
        !$lcovutil::func_coverage) {
        lcovutil::ignorable_error($lcovutil::ERROR_USAGE,
            "--callgraph-coverage requires function coverage, which is disabled (--no-function-coverage or 'function_coverage=0')."
        );
        $lcovutil::callgraph_coverage = 0;
    }
    # ..and '--callgraph-partial-data' is a policy on data which is only
    #   collected when callgraph coverage is on, so asking for it alone asks
    #   for nothing.  A
    #   warning rather than an error:  unlike the contradiction above there is
    #   no state to be incoherent, and 'lcov --capture' passes the flag through
    #   to geninfo, where the metric may be turned off again by a gcov which is
    #   too old or an object with no callgraph info beside it
    if ($lcovutil::callgraph_partial_data &&
        !$lcovutil::callgraph_coverage) {
        lcovutil::ignorable_warning($lcovutil::ERROR_USAGE,
            "--callgraph-partial-data has no effect without --callgraph-coverage - ignoring it."
        );
        $lcovutil::callgraph_partial_data = 0;
    }

    # ...and which platform's paths we are working in - after the line above,
    #   because an invalid value is an ignorable error.
    set_path_style();

    # Now that we know what to ignore:  a source directory which is not a
    #   directory is an ignorable 'path' error, so this cannot be built until
    #   'parse_ignore_errors' above has decided the error is fatal.
    $ReadCurrentSource::searchPath =
        SearchPath->new('source directory',
                        @ReadCurrentSource::source_directories);

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

sub reject_metric($$$)
{
    # A metric this tool cannot ever produce, because its input does not carry
    #   the data:  a Devel::Cover DB, a Cobertura or JaCoCo XML and an
    #   'llvm-cov export' all record counters, so anything which needs edges or
    #   condition vectors would have to come from a different tool entirely.
    #   '$option' is the flag as the user spells it, '$ref' the variable it sets,
    #   and '$why' one sentence naming both what is missing and where the metric
    #   does come from.
    #
    # ERROR_UNSUPPORTED, which is the class every other "this cover type cannot
    #   be produced here" answer uses - geninfo's, for gcov being too old or an
    #   object built without '-fcallgraph-info'.  The user did not misuse the
    #   option:  they asked a tool for a cover type it does not have, which is
    #   the definition of that class, and the answer is the same whether the
    #   reason is fixed for the life of the tool or a property of one input.
    #   (The contradiction between '--callgraph-coverage' and
    #   '--no-function-coverage' in parseOptions *is* a usage error, and stays
    #   one:  there the two options disagree with each other.)
    #
    # Each tool calls this itself, right after parseOptions returns, rather than
    #   parseOptions doing it:  the option table is shared, so the shared code
    #   cannot know which tool it is parsing for.  And the option is deliberately
    #   still IN that table for these tools - leaving it out would produce a bare
    #   Getopt complaint, with no error class to ignore and no explanation of
    #   why.
    # As everywhere else, ignoring the error turns the metric off:  the run then
    #   continues in the one coherent state, and writes no records for it.
    my ($option, $ref, $why) = @_;

    return unless $$ref;
    lcovutil::ignorable_error($lcovutil::ERROR_UNSUPPORTED,
           "--$option is not supported by " . $lcovutil::tool_name . ": $why.");
    $$ref = 0;
}

sub reject_callgraph_coverage($)
{
    # see reject_metric.  '$why' says what this tool's input holds instead of
    #   call sites
    my $why = shift;
    reject_metric('callgraph-coverage',
                  \$lcovutil::callgraph_coverage,
                  "$why.  Callgraph coverage requires geninfo with " .
                      '-fcallgraph-info');
}

sub reject_mcdc_coverage($)
{
    # see reject_metric.  '$why' says what this tool's input holds instead of
    #   condition vectors
    my $why = shift;
    reject_metric('mcdc-coverage', \$lcovutil::mcdc_coverage,
        "$why.  MC/DC coverage requires geninfo with gcc 14.2 or later, or clang 18.1 or later"
    );
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
                    ['lcov_excl_callgraph_line',
                     $lcovutil::EXCL_CALLGRAPH_LINE
                    ],
                    ['lcov_excl_callgraph_start',
                     $lcovutil::EXCL_CALLGRAPH_START
                    ],
                    ['lcov_excl_callgraph_stop',
                     $lcovutil::EXCL_CALLGRAPH_STOP
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
# subst_file_name($path[, $noCount])
#
# apply @file_subst_patterns to $path and return
#
# '$noCount' is for a caller which is asking what a name would become rather
#   than using the answer as the name of something - see
#   'AggregateTraces::_partition_sections'.
#  The pattern application counts are what the 'unused pattern' report is
#   computed from, so a speculative application should not be counted.
sub subst_file_name($;$)
{
    my ($name, $noCount) = @_;
    foreach my $p (@file_subst_patterns) {
        my $old = $name;
        # sadly, no support for pre-compiled patterns
        eval '$name =~ ' . $p->[0] . ';';  # apply pattern that user provided...
            # $@ should never match:  we already checked pattern validity during
            #   initialization - above.  Still: belt and braces.
        die("invalid 'subst' regexp '" . $p->[0] . "': $@")
            if ($@);
        $p->[-1] += 1
            if (!$noCount && $old ne $name);
    }
    return $name;
}

#
# set_path_style()
#
# Configure which platform path convention this run uses:
#   'auto'   : (default) the platform we are running on - which '$dirseparator'
#              and '$accepts_both_separators' are set to.
#   'posix'  : force the setting so we can regression test in both directions
#              regardless of the platform the tests are actually running on
#   'windows': same
#   'cygwin' : same, for the third case:  the POSIX separator, with the Windows
#              one accepted as well.  Neither of the other two reaches it -
#              'posix' accepts only '/' and 'windows' writes '\'
# Nothing else about the run changes when we set the style - only the names
# we read and write - not to access the filesystem.

sub set_path_style()
{
    # style => [separator, accepts the other separator too, name for messages]
    my %styles = ('posix'   => ['/', 0, 'POSIX'],
                  'windows' => ['\\', 1, 'Windows'],
                  'cygwin'  => ['/', 1, 'Cygwin']);
    my $style = lc($path_style);
    return if 'auto' eq $style;
    if (!exists($styles{$style})) {
        my @expected = map({ "'$_'" } ('auto', sort(keys(%styles))));
        ignorable_error($lcovutil::ERROR_USAGE,
                        "invalid 'path_style' value '$path_style' - expected " .
                            join(', ', @expected) . '.');
        return;
    }
    ($dirseparator, $accepts_both_separators, $path_platform) =
        @{$styles{$style}};
    $dirseparator_re = quotemeta($dirseparator);
}

# Report error once per input file name.
# A child which reads a chunk of an input reports for its own chunk (it has
#   inherited an empty hash when it was forked). 'update_state' adds its
#   message counts back into the master
our %reported_foreign_separator;

# returns the type of the pathname we are looking at
#   - a '.info' file record is a source file name.
#   - a diff file entry may be a source file or the git root
sub _separator_subject($)
{
    my $fileTypeName = shift;
    return defined($fileTypeName) ? "'$fileTypeName' file entry" :
        'source file name';
}

# At most one message per input file which contains paths that got munged.
# This isn't a problem, but does explain why the output looks different
# than the suer might expect.
sub _note_separator_normalized($$$$$$)
{
    my ($name, $tracefile, $line, $fileTypeName, $key, $why) = @_;
    return if exists($reported_foreign_separator{"$tracefile:$key"});
    $reported_foreign_separator{"$tracefile:$key"} = 1;
    my $foreign = $dirseparator eq '/' ? '\\' : '/';
    info(1,
         "\"$tracefile\":$line: " .
             _separator_subject($fileTypeName) .
             " '$name' uses the " .
             ($foreign eq '/' ? 'POSIX' : 'Windows') .
             " directory separator '$foreign', which $why:  normalizing " .
             "these names to '$dirseparator'.\n");
}

#
# check_path_separator($name, $tracefile, $line[, $fileTypeName])
#
# '$name' is a source file name read from '$tracefile' at line '$line'.
#   Return the path name to use for it on this platform.
#  '$fileTypeName' is the type of '$tracefile' (undef for a '.info' file,
#   'diff' for a udiff) and selects the message wording.
#   The error message is different depending on the path type
#
# windows -> linux is not the same as linux -> windows because windows
#   can handle either '\' or '/' as a directory separator.  A POSIX name is not
#   an error there - it opens - so there is nothing to report;  it is normalized
#   to '\' anyway, for the reason below.
# On linux: '\' is an ordinary character in a posix filename, so a name which
#   uses it names nothing which can be found here.  It is munged - which is what
#   'cross_platform_read' asks for, and what it asks for by default - unless the
#   user has turned that off to say that the character really is part of the
#   name, in which case the name is left alone and reported as an error.
# Cygwin and MSYS are the third case, and the reason the question this asks is
#   '$accepts_both_separators' rather than 'is the separator here '\''.  They
#   write POSIX names, so a name of ours is not munged on the way out - but they
#   accept a Windows name on the way in, drive letter and all, so a name which
#   uses '\' is not an error there:  the file it names opens.  Reporting one
#   would be reporting a name which works.
# Where both separators are accepted the name is normalized to this platform's
#   separator no matter what 'cross_platform_read' says.  Only the filesystem
#   takes both;  we do not.  Every path operation of ours splits on
#   '$dirseparator_re', which is one character - and the modules we build paths
#   with disagree with each other about the other one:  'File::Spec' on Cygwin
#   and MSYS turns '\' into '/' in 'canonpath', and on Windows turns '/' into
#   '\', while 'File::Basename' takes '\' for a separator only where '$^O' is
#   one of its DOS flavours - which 'cygwin' and 'msys' are not.  A name left in
#   the foreign spelling is therefore decomposed one way by one of them and
#   another way by the other:  on Cygwin/MSYS the directory of a page and its
#   file name would come from the two different splits, and on Windows a '/'
#   name defeats the '$prefix$dirseparator' strip behind '--prefix' and
#   '--list'.  Normalizing on the way in is what keeps the two views the same;
#   it is lossless, since either spelling names the same file on these
#   platforms.
# A name which uses both separators is ambiguous.
#   - If linux, there is no way to tell which of the separators divides
#     directories - so error.
#   - Where both are accepted: they are both treated as separators (no error),
#     and normalizing gives a name which uses only this platform's.

# The name 'check_path_separator' will return for '$name', with none of its
#   messages and none of its state:  the separator normalization on its own.
# Used by callers which need to know what a source file name will be
#   before the reader gets to it - see 'AggregateTraces::_partition_sections' -
sub translate_path_separator($)
{
    my $name    = shift;
    my $foreign = $dirseparator eq '/' ? '\\' : '/';
    return $name if index($name, $foreign) < 0;

    my $translated = $name;
    $translated =~ s/\Q$foreign\E/$dirseparator/g;
    return $translated if $accepts_both_separators;
    # a name which uses both separators is ambiguous, and is left alone
    return $translated
        if ($cross_platform_read && index($name, $dirseparator) < 0);
    return $name;
}

# The name to decompose when deciding where '$name' divides into directories -
#   which is not always the name itself.
#
# 'C:\proj\src\foo.c' is absolute on Windows, so the name to decompose for it
#   here is '/C:/proj/src/foo.c' and not 'C:/proj/src/foo.c':  the latter is a
#   relative name, which would leave the report layout at the mercy of the
#   directory genhtml was started in.  The drive letter becomes an ordinary
#   leading path element - it is not a volume we have.  Nothing is prepended
#   where the platform's own path module already calls a drive-lettered name
#   absolute, which Windows, Cygwin and MSYS all do.
# The other direction needs no special case:  '/a/b/c' translates to '\a\b\c' -
#   an absolute path on the current volume in Windows.
# A name which uses both separators is ambiguous - there is no way to tell which
#   of them divides its directories - so its separators are left alone;
#   'check_path_separator' has already warned.
sub native_path($)
{
    my $name    = shift;
    my $foreign = $dirseparator eq '/' ? '\\' : '/';
    $name =~ s/\Q$foreign\E/$dirseparator/g
        if (index($name, $foreign) >= 0 && index($name, $dirseparator) < 0);
    $name = $dirseparator . $name
        if ($name =~ /^[A-Za-z]:$dirseparator_re/ &&
            !File::Spec->file_name_is_absolute($name));
    return $name;
}

sub check_path_separator($$$;$)
{
    my ($name, $tracefile, $line, $fileTypeName) = @_;
    my $foreign = $dirseparator eq '/' ? '\\' : '/';
    # Nothing to do for a name which is already in this platform's terms.  A
    #   Windows name whose drive letter is followed by '/' - 'C:/proj/foo.c' -
    #   is one of those:  that is what the translation below produces, so a file
    #   we translated can be read back.
    return $name if index($name, $foreign) < 0;

    my $translated = $name;
    $translated =~ s/\Q$foreign\E/$dirseparator/g;
    # Where the foreign separator is a separator too, the name names a file
    #   which opens, mixed or not:  no error - but we normalize it to the
    #   separator this platform writes, so that our own path handling and the
    #   path modules we use agree about where its directories divide.
    if ($accepts_both_separators) {
        _note_separator_normalized($name, $tracefile, $line, $fileTypeName,
                                   'accepted', "$path_platform accepts");
        return $translated;
    }

    my $mixed = index($name, $dirseparator) >= 0;
    # ..and where it is not a separator here
    #  the name is munged or not - depending on 'cross_platform_read'
    #   tell the user that the unexpected character really is part of the name
    if ($cross_platform_read && !$mixed) {
        _note_separator_normalized($name, $tracefile, $line, $fileTypeName,
                                   'translated', 'is not a separator here');
        return $translated;
    }

    # one message per input file for each of the two problems
    my $key = $tracefile . ($mixed ? ':mixed' : ':foreign');
    if (!exists($reported_foreign_separator{$key})) {
        $reported_foreign_separator{$key} = 1;
        if ($mixed) {
            _report_mixed_separator($name, $tracefile, $line, $fileTypeName);
        } else {
            _report_foreign_separator($name, $translated, $tracefile, $line,
                                      $fileTypeName);
        }
    }
    return $name;
}

# the name uses both separators and we are on a POSIX machine:  we cannot tell
#   which of them divides its directories - print message and use the name
#    unchanged if the error is ignored.
sub _report_mixed_separator($$$;$)
{
    my ($name, $tracefile, $line, $fileTypeName) = @_;
    # one line of the explanation per element - see the 'join' below
    my @detail = (
         'Translating the separators cannot help:  that turns one of them into',
         '  the other, which needs the name to use only one of them.  A',
         '  backslash is a legal character in a POSIX file name, so we will',
         '  not guess that these ones are separators.',
         'If you know what the name should be, then rewrite it yourself with',
         "  '--substitute' - e.g. 's#\\\\#/#g' to treat every backslash as a",
         '  separator.  Substitutions are applied after this check, so add',
         "  '--ignore-errors usage' as well;  that is also the option to use",
         '  if the name is right exactly as it is.');
    my $explain =
        explain_once('mixed_path_separator', "\n\t" . join("\n\t", @detail));
    ignorable_error($lcovutil::ERROR_USAGE,
                    "\"$tracefile\":$line: " .
                        _separator_subject($fileTypeName) .
                        " '$name' uses " .
                        "both the POSIX directory separator '/' and the " .
                        "Windows one '\\', so there is no way to tell which " .
                        'of them divides its directories.' .
                        $explain);
}

# Explain the damage caused by an untranslated windows name in an '.info' file.
# One line of the explanation per element - see the 'join' in
# '_report_foreign_separator'
sub _foreign_info_detail($$)
{
    my ($name, $translated) = @_;
    return (
       'Nothing here can be found under that name:  the source file cannot be',
       '  read (so no source-based filter, no checksum, no annotation), and',
       "  '--exclude'/'--include' patterns written for this platform do not",
       '  match it.',
       'The report genhtml writes is not affected:  the name is decomposed as',
       '  though it had been written',
       "    '" . native_path($name) . "'",
       '  so the directory hierarchy, the names of the pages and the links',
       '  between them are the ones the same name spelled our way would have',
       '  produced - and it is that spelling the pages display.  The name as',
       '  read is the one the coverage data keeps.',
       "'cross_platform_read' is disabled, which is what asks for a name to be",
       '  used exactly as it was read.  Enable it - drop that setting from the',
       "  configuration file, or pass '--rc cross_platform_read=1' - to",
       "  translate the names read from the '.info' file to this platform's",
       '  separator:',
       "    '$name' -> '$translated'",
       "  Add '--source-directory' (or '--resolve-script') to say where the",
       '  sources are here.  A leading Windows drive letter is kept as an',
       "  ordinary path element:  use '--substitute' to remove it - e.g.",
       "  's#^[A-Za-z]:/##' - no local directory can be guessed for it.");
}

# ..the damage in a udiff file:  a diff entry is matched against the names
# in the coverage data rather than to find files on the filesystem - so an
# unmatchable name is simply dropped if the message is ignored.
# Tool will think that file is unmodified.
sub _foreign_diff_detail($$$)
{
    my ($name, $translated, $fileTypeName) = @_;
    return (
       'No name from this file will match a source file name in the coverage',
       '  data, so its differences are dropped and every file is categorized',
       '  as though the code had not changed at all.',
       '  Nothing else warns about it:  the path-mismatch check compares the',
       '  last element of each name, and a backslash is not a separator here,',
       '  so the whole name looks like one element and matches nothing.',
       "  '--exclude'/'--include' patterns written for this platform do not",
       '  match it either.',
       "'cross_platform_read' is disabled, which is what asks for a name to be",
       '  used exactly as it was read.  Enable it - drop that setting from the',
       "  configuration file, or pass '--rc cross_platform_read=1' - to",
       "  translate the names read from the '$fileTypeName' file to this",
       "  platform's separator:",
       "    '$name' -> '$translated'",
       '  A leading Windows drive letter is kept as an ordinary path element:',
       "  use '--substitute' to remove it - e.g. 's#^[A-Za-z]:/##'.  Those",
       '  patterns are applied to the coverage data names as well, so both',
       '  sides of the comparison are rewritten the same way.');
}

# the name is a Windows name and we are on a POSIX machine, where a backslash
#   is not a separator:  nothing here can be found under it
sub _report_foreign_separator($$$$;$)
{
    my ($name, $translated, $tracefile, $line, $fileTypeName) = @_;
    # 'diff' is the only kind of input other than a '.info' file whose names we
    #   read.  Each kind is explained once:  what breaks is not the same, so the
    #   '.info' explanation is not an answer for a udiff, or the other way round
    my $isDiff = defined($fileTypeName);
    my @detail =
        $isDiff ? _foreign_diff_detail($name, $translated, $fileTypeName) :
        _foreign_info_detail($name, $translated);
    my $explain =
        explain_once('cross_platform_read' . ($isDiff ? "_$fileTypeName" : ''),
                     "\n\t" . join("\n\t", @detail));
    ignorable_error($lcovutil::ERROR_USAGE,
                    "\"$tracefile\":$line: " .
                        _separator_subject($fileTypeName) .
                        " '$name' uses " .
                        "the Windows directory separator '\\', but this run " .
                        "works in POSIX paths, whose separator is '/'." .
                        $explain);
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
    my $d = $lcovutil::dirseparator_re;
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
            $header . '  ' .
            $total{$type} .
            " $type message" .
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
    my @ignore_errors = split($split_pattern, join($split_char, @_));

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
    my @constraints = split($split_pattern, join($split_char, @_));
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
                lcovutil::ignorable_error(
                                        $lcovutil::ERROR_USAGE,
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

    # Deferred (warn-once) messages are parked in '%warnOnlyOnce' and handed
    #   back to the parent by 'merge_deferred_warnings', so only a child may
    #   defer:  a message the PARENT parks has no-one to unpark it, and would be
    #   dropped - including the ERROR_RANGE reports, which would then neither be
    #   printed nor counted, so the run would pass.  Set here rather than in
    #   'ForkManager::fork_one' for exactly that reason:  this sub runs only in a
    #   child, whereas the parent is the process which executes 'fork_one'.
    $lcovutil::deferWarnings = 1;

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
    # count only the continuation lines I merge - see 'compute_update'
    $lcovutil::continuation_lines_merged  = 0;
    $lcovutil::continuation_merge_targets = 0;
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
               \%lcovutil::explainOnce,
               # The whole array, not just what I added to it:  the flags are
               #   booleans which only ever go 0 -> 1, so the parent can simply
               #   OR them in - see '@coverTypeFound'.
               \@lcovutil::coverTypeFound,
               # ...and the counts of the files I read, which the parent adds to
               #   its own:  each input is read by exactly one of us, so the sum
               #   over the children is the sum over the inputs - see
               #   '@coverTypeInputTotal'
               \@lcovutil::coverTypeInputTotal,
               # ..and what I merged, which the parent adds to its own
               [$lcovutil::continuation_lines_merged,
                $lcovutil::continuation_merge_targets
               ]);

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
    my $coverTypeFound = shift;
    for (my $i = 0; $i < COVER_TYPE_COUNT; ++$i) {
        $lcovutil::coverTypeFound[$i] = 1 if $coverTypeFound->[$i];
    }
    # undef is "no input of mine collected data for this type".
    # in contrast, 0 (zero) means that we collected data but there were
    # zero coverpoints of the type.
    my $coverTypeInputTotal = shift;
    for (my $i = 0; $i < COVER_TYPE_COUNT; ++$i) {
        next unless defined($coverTypeInputTotal->[$i]);
        $lcovutil::coverTypeInputTotal[$i] =
            ($lcovutil::coverTypeInputTotal[$i] || 0) +
            $coverTypeInputTotal->[$i];
    }
    # undef when the child's dump holds no update:  the parent rejects that
    #   chunk, but its state is updated first
    my $merged = shift;
    if (defined($merged)) {
        $lcovutil::continuation_lines_merged  += $merged->[0];
        $lcovutil::continuation_merge_targets += $merged->[1];
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

# the text of the most recent message which 'ignorable_error' both reported and
#   turned into a die - see 'unreported_error' below
our $reported_error;

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
        # remember what was reported, so that a caller which catches the die
        #   this is about to become can tell that it has been reported already
        $reported_error = "($errName) $msg\n$ignoreOpt";
        die_handler($reported_error);
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

sub unreported_error($)
{
    # What is left to report:  a caller which wrapped something in an 'eval'
    #   calls this on '$@' before it builds a message from it.
    # If the die is one which 'ignorable_error' above already reported - it
    #   reports the error and then dies, when the error is not one which is
    #   being ignored - then there is nothing left to report, and it is let out
    #   again rather than wrapped inside a second copy of a message the user has
    #   already been shown.
    # Otherwise the message comes back with the prefix which 'die_handler' put
    #   on it removed.  '$SIG{__DIE__}' is 'die_handler', so every die is
    #   prefixed with the tool name, including one caught by an 'eval' - and the
    #   message the caller is about to build will be prefixed in its turn.
    my $msg = shift;
    die($reported_error)
        if defined($reported_error) && -1 != index($msg, $reported_error);
    $msg =~ s/^\Q$tool_name\E: (?:ERROR|WARNING): //;
    return $msg;
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
    # When the machine runs out of memory, the kernel kills whichever process
    #   it scores highest - usually the biggest, and a child of ours is a copy
    #   of us, so it can just as easily be the parent.  A dead child is a unit
    #   of work which is retried;  a dead parent is the whole run, gone.  So
    #   each child volunteers to be the one which is killed.  Best effort:
    #   Linux only, and raising one's own score needs no privilege.
    if (defined($pid) &&
        0 == $pid &&
        open(OOM_ADJ, '>', '/proc/self/oom_score_adj')) {
        print(OOM_ADJ "1000\n");
        close(OOM_ADJ);
    }
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
                                  $errcode .
                                  $retry .
                                  $explain);
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
    my $signal = $exitstatus & 0x7F;
    my $explain =
        "$prefix " .
        ($exitstatus ? "returned non-zero exit status $status" : 'failed') .
        MessageContext::context();
    if ($signal) {
        $explain =
            "$prefix died due to signal $signal (SIG" .
            (split(' ', $Config{sig_name}))[$signal] . ')' .
            MessageContext::context() .
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
    my $signal      = $rawStatus & 0x7F;
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

sub normalize_count($)
{
    # Canonicalize one execution count as it is read from a '.info' file, and
    # record what (if anything) is wrong with it.  Returns
    # ($count, $errno):  $count is what to store, $errno is the
    # $lcovutil::ERROR_* id to report or undef when the value was acceptable.
    # The caller reports the error itself, because the location string and the
    # count type ('hit', 'taken', a function name) differ at every call site,
    # and because some sites suppress the message.
    #
    # Normalization exists so that a particular '.info' file produces identical
    # numbers whether or not XSLoader::load succeeded.
    # The XS implementation stores counts in a signed 64-bit integer - so it
    # must truncate fractions (...which make no sense, in any case) and
    # saturate numbers that get too large.
    # Pure perl doesn't have either of these restrictions natively - so
    # is coerced to follow XS (rather than trying to have XS follow pure perl).
    #
    #   - truncate toward zero, so '1.5' is stored as 1
    #   - saturate to $MAX_COUNT, so '1.0e+19' is stored as 9223372036854775807
    #     ((1 << 63) - 1)
    #   - '-0' is not negative;  it normalizes to 0 without a diagnostic
    #
    # 'nan' and 'inf' generate ERROR_FORMAT, on both sides.
    my $count = shift;
    return (0, $lcovutil::ERROR_FORMAT)
        unless defined($count) && Scalar::Util::looks_like_number($count);
    my $value = 0 + $count;
    return (0, $lcovutil::ERROR_FORMAT)
        if ($value != $value || POSIX::isinf($value));
    return (0, $lcovutil::ERROR_NEGATIVE) if $value < 0;
    # the threshold is compared against the value as it was read, before the
    # clamp, so that raising it above $MAX_COUNT still has the intended effect
    my $excessive = defined($lcovutil::excessive_count_threshold) &&
        $value > $lcovutil::excessive_count_threshold;
    return (($value >= $MAX_COUNT ? $MAX_COUNT : int($value)),
            $excessive ? $lcovutil::ERROR_EXCESSIVE_COUNT : undef);
}

sub add_count($$)
{
    # Saturating add for two counts which normalize_count has already accepted.
    # Mirrors lcov::add_sat in lib/LcovUtil/CountArith.hpp.
    my ($a, $b) = @_;
    my $sum = $a + $b;
    return $sum >= $MAX_COUNT ? $MAX_COUNT : $sum;
}

sub site_count_hit($)
{
    # Is one call-site count (FunctionEntry::SITE_COUNT) a hit?  Not a bare
    #   boolean test, because the unknown count '-' is a non-empty string and so
    #   is *true* in Perl:  every '$count ? hit : missed' spelled directly would
    #   report an unmeasured call as taken.
    my $count = shift;
    return (defined($count) && $count ne '-' && 0 != $count) ? 1 : 0;
}

sub site_count_unknown($)
{
    # Is one call-site count (FunctionEntry::SITE_COUNT) the unknown count?
    #   Spelled out here so that the marker is compared in one place - see
    #   site_count_hit for why it must never be tested as a bare boolean
    my $count = shift;
    return (!defined($count) || $count eq '-') ? 1 : 0;
}

sub site_count_value($)
{
    # One call-site count as a number:  '-', the unknown count, reads as 0.
    # Mirrors 'BranchElement::count', which does exactly this for a branch which
    #   was never evaluated, and for the same reason:  a differential
    #   categorizer or a running total has to have a number, and the number an
    #   unknown may contribute is the one which does not claim a hit.  Display
    #   code must not use this - telling "not measured" apart from "measured
    #   zero" is the whole point of the marker.
    my $count = shift;
    return (!defined($count) || $count eq '-') ? 0 : $count;
}

sub add_site_count($$)
{
    # Fold one call-site count into a running total - of a location with several
    #   destinations, or of several ordinals shown as one row - under the same
    #   lattice the merge uses:  unknown contributes nothing to a known total,
    #   and a total is only unknown while every count folded into it was.
    #   'undef' is the empty total, so that a caller can start from it.
    my ($total, $count) = @_;
    return $total if defined($count) && $count eq '-';
    return $count unless defined($total);
    return $count if $total eq '-';
    return $total if !defined($count);
    return add_count($total, $count);
}

sub external_call($$$$$$)
{
    # One call made from a site which is leaving the report, as the lists
    #   TraceInfo::noteExternalCalls and TraceFile::noteExternalCalls hold it:
    #   [the file the caller is defined in, callee, the site's count, {testcase
    #   => that testcase's count of the site}].  '$testfnc' is the per-testcase
    #   function data of the caller's file, and '$funcKey' and '$siteKey' find
    #   the site in each of its maps.  An unknown count is '-', as it is on
    #   the site
    my ($file, $callee, $count, $testfnc, $funcKey, $siteKey) = @_;
    my %perTest;
    if (defined($testfnc)) {
        foreach my $tn ($testfnc->keylist()) {
            my $map = $testfnc->value($tn);
            my $f   = defined($map) ? $map->findKey($funcKey) : undef;
            next unless defined($f);
            my (undef, undef, undef, $c) = $f->callSiteData($siteKey);
            $perTest{$tn} = $c if defined($c);
        }
    }
    return [$file, $callee, defined($count) ? $count : '-', \%perTest];
}

# The calls excludeCallSite has taken out, as the external_call records
#   TraceInfo::noteExternalCalls takes.  A module global rather than something
#   the callback hands back, so that the callback interface stays "remove this
#   site":  _filterFile drains this into the file it just asked about, which is
#   the only file a call can have been excluded from while that call was in
#   progress
our @excludedCallSites;

sub excludeCallSite($$$$)
{
    # Remove one call site from a file's data:  the interface the 'callgraph'
    #   pass of the '--unreachable-script' callback removes a site through, and
    #   the only supported way for a callback to do it.
    # Takes the two maps that pass is handed - the per-testcase collection and
    #   the summary - because a site lives in every map which has the function,
    #   and a site removed from one of them and left in another is a report
    #   whose totals disagree with its tables.  '$funcKey' is the key
    #   'FunctionMap::keylist' hands out and '$siteKey' the key
    #   'FunctionEntry::callSiteKeys' does;  both name the same thing in every
    #   map, which is what makes this a loop rather than a search.
    # Returns true if a site was removed, and false if there was none left to
    #   remove - so a callback may use the answer to count what it excluded
    #   without having to remember what it has already seen.
    # The callee found and hit totals need no correction, unlike a branch total,
    #   which is cached and which a callback has to fix with 'adjust_counts':
    #   they are counted from the surviving sites when they are asked for (see
    #   FunctionMap::get_callgraph_found_and_hit), so an excluded site leaves
    #   both of them at the same time - which is the whole of what the report
    #   may conclude from it.  An excluded coverpoint is outside the boundary of the
    #   report by definition, so whether that call was ever made is no longer a
    #   question this report answers, and it must be counted neither as a call
    #   which happened nor as one which did not.
    # What the callee is told is the one thing which is not an inference:  a
    #   function which is still in this report is called from a site which no
    #   longer is, so that callee is recorded as having a caller outside the
    #   boundary - the same FunctionAlias::has_external_callers a call whose
    #   caller was erased (_noteErasedCalls) or whose file was removed ends up
    #   asserting, with the count the site had.  Whether the call was ever
    #   taken does not decide whether the flag is set:  the flag says that the
    #   edge is there, which is what an excluded site leaves behind
    my ($testdata, $summary, $funcKey, $siteKey) = @_;
    # ..which has to be read before the site is taken out, and out of the
    #   summary, since that is the map which has every site of the file
    my $caller = $summary->findKey($funcKey);
    my (undef, undef, undef, $count, $callee) =
        defined($caller) ? $caller->callSiteData($siteKey) : ();
    my $call =
        defined($callee) ?
        external_call($caller->filename(),
                      $callee, $count, $testdata, $funcKey, $siteKey) :
        undef;
    my $removed = 0;
    my @maps = ($summary, map({ $testdata->value($_) } $testdata->keylist()));
    foreach my $map (@maps) {
        next unless defined($map);
        my $entry = $map->findKey($funcKey);
        next unless defined($entry);
        $removed = 1 if $entry->_removeSite($siteKey);
    }
    # The caller's own file and not the site's, when the two differ:  what
    #   decides which definition of the callee the call reached is the
    #   translation unit the caller was compiled in
    push(@excludedCallSites, $call)
        if $removed && defined($call);
    return $removed;
}

# How a callee's set of callers relates to the calls it actually received - see
#   classify_callers().  Numbered so that CALLERS_BOTH is exactly
#   CALLERS_INTERNAL|CALLERS_EXTERNAL
use constant {
              CALLERS_NONE     => 0,    # nothing is known about its callers
              CALLERS_INTERNAL => 1,    # called, and every call is a known site
              CALLERS_EXTERNAL => 2,    # has a caller which is no site of this
                                        #   report
              CALLERS_BOTH     => 3,    # both of the above
              CALLERS_INDETERMINATE => 4,    # cannot be told apart - see there
};

sub classify_callers($;$)
{
    # Relate one FunctionAlias' call sites to the number of times it was
    #   actually entered, and return (class, elsewhere, external, deduced):
    #     - elsewhere:  the calls no call site of this report accounts for;
    #     - external:  those the 'x' flag's dropped sites made
    #       (FunctionAlias::external_calls) - 0 without a flag;
    #     - deduced:  the rest, which came from somewhere nothing recorded.
    #   Each is undef where it cannot be decided.
    #
    # '$measured' is whether this report measured anything at all about the
    #   compilation unit the symbol is defined in - FunctionMap::hasCallgraphData
    #   - and defaults to true.  Where it is false none of what follows applies;
    #   see the first return.
    #
    # Every call site in the report which named this symbol is on its caller
    #   list by now, with the file it is in and the number of times it was
    #   taken:  the callee's linkage does not enter into it, because the record
    #   is written by the *caller's* translation unit (linkage only decides
    #   which definition a site resolves to - see FunctionAlias::is_external).
    #   So the callers we know, we know exactly.
    # What cannot be known is who made the rest of the calls:  the symbol's own
    #   execution count is the number of times it was entered from anywhere, and
    #   the difference is calls which came from outside anything this report
    #   describes - an uninstrumented or uncaptured translation unit, a call
    #   through a function pointer or a virtual dispatch (neither of which the
    #   callgraph info can name a target for), a call from the runtime itself
    #   ('main', a static constructor, a signal handler), or a site whose
    #   resolution failed.  The count of those calls is known and their origin
    #   is not, which is exactly the distinction the four classes draw.
    # The fifth class is case when the site count is unknown ('-'):
    #   the '-' site may account for the whole difference or for none of
    #   it, so "called from elsewhere" cannot be decided either way.
    # In addition,  a call site for which no record could be written is
    #   tagged with a flag on the callee (FunctionAlias::has_external_callers),
    #   which carries the calls that site made.  That is a known external
    #   caller - as opposed to one which is deduced to exist because the known
    #   and the external sites together account for fewer calls than the
    #   symbol received.  Where the flag's count is not known, whether there is
    #   a deduced caller as well cannot be decided.
    my ($alias, $measured) = @_;
    # Nothing in this report was measured about the calls of the translation unit
    #   this symbol is defined in (FunctionMap::hasCallgraphData), so there is
    #   nothing to relate its execution count to.  A caller on its list, and
    #   either of the flags which assert one, would each have been that
    #   measurement, so it has none of them - and what the arithmetic below would
    #   make of that is that every call it received came from outside the report,
    #   which is the one answer which is certainly wrong:  the likeliest caller
    #   is its own neighbour, and no record of the call was ever written
    return (CALLERS_NONE, 0, 0, 0) if defined($measured) && !$measured;
    my $mine     = $alias->count();
    my $flagged  = $alias->has_external_callers();
    my $external = $alias->external_calls();
    my ($known, $indeterminate) = (0, 0);
    foreach my $caller ($alias->callers()) {
        # [callerEntry, line, column, ordinal, count, file] - see add_caller
        my $count = $caller->[4];
        if (!defined($count) || $count eq '-') {
            $indeterminate = 1;
            next;
        }
        $known = add_count($known, $count);
    }
    # Not entered at all:  nothing called it, so any '-' site among its callers
    #   was taken zero times and there is nothing indeterminate about it, and
    #   the flag's sites made no call either.
    # The flag still answers the question the class asks - it says that a call
    #   site outside the boundary names this function, which is where a caller is
    #   and not whether it called.  Without the flag there is no caller of any
    #   kind to report
    return ($flagged ?
                ($known ? CALLERS_BOTH : CALLERS_EXTERNAL) :
                CALLERS_NONE,
            0, 0, 0)
        unless $mine;
    # More calls recorded than entries is not diagnosed:  the two numbers come
    #   from different gcov records, and a merge of runs which disagree about
    #   function data, or a caller counted in a unit whose callgraph data was
    #   captured separately, can produce it without anything being wrong here.
    #   Everything is accounted for either way.
    # A '-' site might account for any part of the difference, so neither the
    #   difference nor what is left of it once the flag's calls are taken off
    #   can be told - unless there is no difference to account for
    my $elsewhere =
        $known >= $mine ? 0 :
        $indeterminate ? undef :
        $mine - $known;
    my $deduced;
    if (defined($elsewhere) && (0 == $elsewhere || defined($external))) {
        $deduced =
            (0 == $elsewhere || $elsewhere <= $external) ? 0 :
            $elsewhere - $external;
    }
    return ($known ? CALLERS_BOTH : CALLERS_EXTERNAL,
            $elsewhere, $external, $deduced)
        if $flagged || ($deduced && $deduced > 0);
    return (CALLERS_INDETERMINATE, undef, 0, undef) unless defined($deduced);
    return (CALLERS_INTERNAL, 0, 0, 0);
}

sub deduced_external_calls($;$)
{
    # The number of calls to this FunctionAlias which the arithmetic of
    #   classify_callers says came from outside the callgraph boundary and
    #   which no dropped call site accounts for - its count minus those of the
    #   call sites which name it and those of the sites its 'x' flag stands for
    #   - where that number is known and is not zero, and 0 otherwise.
    # This is the *deduced* external caller, as opposed to the one which the
    #   'x' flag records (FunctionAlias::has_external_callers):  a site which was
    #   seen, and dropped because it is outside the boundary.  Either, both or
    #   neither can hold.  A '-' site among the callers, or an 'x' flag whose
    #   count is not known, leaves the difference undecided, so nothing is
    #   deduced there
    my ($alias, $measured) = @_;
    my (undef, undef, undef, $deduced) = classify_callers($alias, $measured);
    return (defined($deduced) && $deduced > 0) ? $deduced : 0;
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
    #     requeue -> ($unit, $id, $why);  put a unit back on the queue.  '$why'
    #                is 'fork' when fork() failed - the unit never ran, and '$id'
    #                was the last one 'next' handed out - or 'retry' when its
    #                child died.
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
    #
    # Two of these callbacks are not covered in regression tests because
    #   reaching them from a tool means arranging a state which the
    #   tool's own timing decides:
    #     - 'remaining' has exactly one caller:  the line 'throttle' prints when
    #       it decides to wait for memory ('$tooBig' there).  That wants MORE
    #       THAN ONE child of that client already running, and the estimate for
    #       the next unit over 'max_memory', at the instant the unit is
    #       dispatched.  A tiny 'max_memory' does force the wait (see
    #       tests/lcov/fork_throttle) - but it drives this manager directly
    #       and registers no 'remaining' of its own;  going through a tool
    #       instead means holding a second child of the SAME phase alive across
    #       the dispatch, and how long a child lives is not something a test
    #       controls.
    #     - 'childFailMessage' needs a child which returned non-zero AND left a
    #       dump the parent could read - one whose work threw where the child
    #       could still hand back what it had (see genhtml's '_process_child').
    #       A child which was killed, died, or left no dump is retried instead
    #       ('report_retry' above), and that is the path every injected failure
    #       in tests/lcov/parallel_fail takes:  even the case whose data the
    #       parent cannot read is a child which exited 0.
    #   Both callbacks only interpolate this client's name for a unit of work
    #   into a string, so what is untested is the wording of a message rather
    #   than a decision.

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
                    children    => {},  # pid -> [$unit, $id, $forkAt]
                    retryCounts => {},  # id -> times this unit has been retried
                    failedAttempts => 0,    # consecutive fork() failures
                    ready => {},    # 'ordered': id -> payload awaiting its turn
                    nextToMerge => 0,
                    delay       => 0,    # seconds spent inside wait()
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
            $self->{requeue}->($unit, $id, 'fork');
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
        my $data;
        $data = Storable::retrieve($dumpfile)
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
                # the OS killing a child - or a child saying that it could not
                #   allocate memory - is a sign that we are running too many of
                #   them:  retrying at the same parallelism would just repeat it
                $self->_reduce_parallelism(scalar(keys(%$children)) + 1)
                    if (POSIX::SIGKILL == $signal);
                $self->{requeue}->($unit, $id, 'retry');
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

    sub _reduce_parallelism
    {
        # Halve the number of children this manager may run at once, starting
        #   from the number which were running when one was killed - and never
        #   below one.  The limit stays lowered for the rest of this phase:
        #   the children which are left are the same kind of work, and a limit
        #   which grew back would find the same ceiling again.
        my ($self, $wereRunning) = @_;
        my $current = defined($self->{maxInFlight}) ? $self->{maxInFlight} :
            $lcovutil::maxParallelism;
        my $reduced =
            int(($wereRunning < $current ? $wereRunning : $current) / 2) || 1;
        return if $reduced >= $current;
        lcovutil::info(
                   "$self->{operation}: a child was killed for want of memory" .
                       ":  running at most $reduced at once (was $current)\n");
        $self->{maxInFlight} = $reduced;
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
                # Over the ceiling, we wait for a child to finish - but with
                #   nothing running, there is nothing to wait for, so the unit is
                #   forked anyway:  one child at a time is the least parallel
                #   this can be.  (It used to allow a second child regardless,
                #   which is the copy of a large parent the machine may not have.)
                $tooBig = ($running > 0 && $total > $lcovutil::maxMemory);
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
    my @filters = split($split_pattern, join($split_char, @_));

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
    lcovutil::ignorable_warning($ERROR_USAGE,
        "'unknown_callee_count' filter enabled but callgraph coverage is not enabled."
        )
        if (defined($cov_filter[$FILTER_UNKNOWN_CALLEE_COUNT]) &&
            !$callgraph_coverage);
    lcovutil::ignorable_warning($ERROR_USAGE,
        "'callgraph_region' filter enabled but callgraph coverage is not enabled."
        )
        if (defined($cov_filter[$FILTER_EXCLUDE_CALLGRAPH]) &&
            !$callgraph_coverage);
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
                '    ' .
                $histogram->[-1] .
                ' coverpoint' .
                ($histogram->[-1] > 1 ? 's' : '') . "\n";
        }
        info(-1,
             "$leader  $key:\n    " .
                 $histogram->[-2] .
                 " instance" .
                 ($histogram->[-2] > 1 ? "s" : "") . "\n" .
                 $points);
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
    my $merged = $lcovutil::continuation_lines_merged;
    if ($merged) {
        my $targets = $lcovutil::continuation_merge_targets;
        info(-1,
             "Merged %d continuation line%s into %d statement line%s\n",
             $merged,
             $merged == 1 ? '' : 's',
             $targets,
             $targets == 1 ? '' : 's');
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

#
# coverpointName(type)
#
# The user-visible noun for one coverpoint of the named cover type:
#   '%coverTypeCoverpoint' where the two words differ, and the name of the type
#   itself otherwise - a line's coverpoint is a line.
#

sub coverpointName($)
{
    my $type = shift;
    return $coverTypeCoverpoint{$type} || $type;
}

#
# summaryLabel(type)
#
# The label the named cover type carries in a summary listing, padded with '.'
#   out to the width of the widest label:  the name of the type - which is also
#   the name of the option which asks for it - pluralized only where that name
#   is the name of a coverpoint too.  A report has lines and functions, but it
#   has one callgraph and one MC/DC metric, so neither of those two is plural.
#

sub summaryLabel($)
{
    my $type  = shift;
    my $label = $type;
    $label .= ('ch' eq substr($type, -2, 2) ? 'es' : 's')
        if coverpointName($type) eq $type;
    return $label . '.' x ($summaryLabelWidth - length($label));
}

#
# summaryRow(type, found, hit)
#
# One row of a summary listing, without its newline:  the label of the cover
#   type and the rate over its coverpoints.  Both 'lcov' and 'genhtml' print
#   these rows and the two have to agree, so both of them call this.
#

sub summaryRow($$$)
{
    my ($type, $found, $hit) = @_;
    return '  ' .
        summaryLabel($type) . ': ' .
        get_overall_line($found, $hit, coverpointName($type));
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
        my $err     = lcovutil::unreported_error($@);
        my $context = MessageContext::context();
        lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                             "extract_version($filename) failed$context: $err");
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
            my $err     = lcovutil::unreported_error($@);
            my $context = MessageContext::context();
            lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                  "compare_version($you, $me, $filename) failed$context: $err");
            $status = 1;
        }
        lcovutil::info(1, "compare_version: $status\n");
        return 1 unless $status;    # match if return code was zero
    }
    unless ($silent) {
        lcovutil::ignorable_error(
                          $ERROR_VERSION,
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

    # look at every tag on every line:  an anchor is the 'id' field of the tag
    # callgraph links are on rows and in cells.  There may be both anchors
    # and any number of links on a particular line.
    open(HTML, '<', $name) or die("unable to open $name: $!");
    while (<HTML>) {
        while (/<(\w+)\b([^>]*)>/g) {
            my ($tag, $attrs) = (lc($1), $2);
            my @anchors;
            push(@anchors, $1) if $attrs =~ /(?<![-\w])id="([^"]*)"/;
            push(@anchors, $1)
                if 'a' eq $tag && $attrs =~ /(?<![-\w])name="([^"]*)"/;
            my %seen;
            foreach my $anchor (map({ _decode($_) } @anchors)) {
                next if $seen{$anchor}++;   # an '<a>' with the same id and name
                lcovutil::ignorable_error(
                       $lcovutil::ERROR_USAGE,
                       "\"$name\":$.: duplicate anchor '$anchor' original at " .
                           $self->[ANCHORS]->{$anchor} . '.'
                ) if exists($self->[ANCHORS]->{$anchor});
                $self->[ANCHORS]->{$anchor} = $.;
            }
            if ('a' eq $tag &&
                $attrs =~ /(?<![-\w])href="([^"#]*)(?:#([^"]*))?"/) {
                my ($file, $anchor) = ($1, $2);
                next if $file =~ /^[a-z]+:/i;    # http:, mailto: ..
                push(@{$self->[HREFS]},          # lineNo, filename, anchor
                     [$.,
                      '' eq $file ? $filename : _decode($file),
                      defined($anchor) ? _decode($anchor) : undef
                     ]);
            } elsif ('frame' eq $tag && $attrs =~ /(?<![-\w])src="([^"]+)"/) {
                push(@{$self->[HREFS]}, [$., _decode($1), undef]);
            }
        }
    }
    close(HTML) or die("unable to close $name: $!");

    return bless $self, $class;
}

sub _decode
{
    # an attribute value as the browser sees it:  character references, and in
    #   a link the '%' escapes, replaced by what they actually represent
    my $value = shift;
    $value =~ s/%([0-9A-Fa-f]{2})/chr(hex($1))/ge;
    $value =~ s/&#x([0-9A-Fa-f]+);/chr(hex($1))/ge;
    $value =~ s/&#([0-9]+);/chr($1)/ge;
    my %entity = (amp => '&', lt => '<', gt => '>', quot => '"', apos => "'");
    $value =~ s/&(amp|lt|gt|quot|apos);/$entity{$1}/g;
    return $value;
}

sub verifyAnchor
{
    # an empty fragment or an otherwise un-anchord 'top' goes to the top
    # of the current page
    my ($self, $anchor) = @_;

    return exists($self->[ANCHORS]->{$anchor}) ||
        '' eq $anchor ||
        'top' eq lc($anchor);
}

sub hrefs
{
    my $self = shift;
    return $self->[HREFS];
}

package ValidateHTML;

sub _resolve
{
    # The path with '.', '..' and any symbolic link resolved away, so that two
    #   spellings of the same file are the same key.  Every page below the top of
    #   the report links to '../index.html', and 'catfile' does not normalize -
    #   so without this a link through '..' cannot be looked up.
    # 'realpath' returns undef for a path which does not exist - which is
    #   precisely what this package is looking for - so hand back the
    #   unresolvable path itself:  it will not be in the file table either, and
    #   the caller reports it.
    my $path = shift;
    my $real = Cwd::realpath($path);
    return defined($real) ? $real : $path;
}

sub new
{
    my ($class, $topDir, $htmlExt) = @_;
    my $self = {};

    $htmlExt = '.html' unless defined($htmlExt);

    my @dirstack = ($topDir);
    my %visited;
    # the file table is keyed on the resolved path - see '_resolve'.  The name
    #   the walk used is kept beside it for the diagnostics:  that is the one the
    #   user asked for and can find on disk
    my %spelled;
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
                my $key = _resolve($p);
                die("duplicate file $p??") if exists($self->{$key});
                lcovutil::info(1, "schedule $p\n");
                $spelled{$key} = $p;
                $self->{$key} = HTML_fileData->new($top, $e);
            }
        }
        closedir($dh);
    }
    my %fileReferred;
    while (my ($filename, $data) = each(%$self)) {
        my $name = $spelled{$filename};
        my $dir  = File::Basename::dirname($name);
        lcovutil::info(1, "verify $name:\n");
        foreach my $href (@{$data->hrefs()}) {
            my ($lineNo, $link, $anchor) = @$href;
            my $path = _resolve(File::Spec->catfile($dir, $link));
            lcovutil::info(1,
                       "  $lineNo: $link" . ($anchor ? "#$anchor" : '') . "\n");
            unless (exists($self->{$path})) {
                lcovutil::ignorable_error($lcovutil::ERROR_PATH,
                               "\"$name\":$lineNo: non-existent file '$link'.");
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
                        "\"$name\":$lineNo: \"$link#$anchor\" doesn't point to valid anchor."
                    );
                }
            }
        }
    }

    # the top level index is the entry point, so nothing refers to it:  both
    #   sides of that comparison have to be resolved, or the exemption depends on
    #   how the output directory was spelled
    my $topReal = _resolve($topDir);
    while (my ($filename, $data) = each(%$self)) {
        lcovutil::ignorable_error($lcovutil::ERROR_UNUSED,
                         "HTML file \"$spelled{$filename}\" is not referenced.")
            unless (exists($fileReferred{$filename}) ||
                    ($topReal eq File::Basename::dirname($filename) &&
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
        # apparent Devel::Cover attribution bug:  statement is reported not hit
        #   despite that the next statement in the block is hit
        $msgs = [$@];    # LCOV_TESTED_LINE
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
    die('unbalanced context "' .
        $self->[0] .
        '" not head of ("' .
        join('" "', @message_context) . '")')
        unless scalar(@message_context) && $self->[0] eq $message_context[-1];
    pop(@message_context);
}

package PipeHelper;

# How many arguments each callback is passed, not counting the command itself.
#   Used only by the backward-compatibility check in 'new' below, which has to
#   guess whether the command was handed over as one string:  it was, if the
#   number of arguments is exactly one more than the callback's own count.
#   Anything not named here is passed one argument (usually a file name).
our %callbackArgCount = ('context'         => 0,
                         'criteria'        => 3,
                         'select'          => 4,
                         'compare_version' => 4);

sub new
{
    my $class  = shift;
    my $reason = shift;

    # backward compatibility:  see if the arguments were passed in a
    #  one long string
    my $args = \@_;
    my $arglen =
        1 +
        (exists($callbackArgCount{$reason}) ? $callbackArgCount{$reason} : 1);
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

sub cmd
{
    # the command line, for messages
    return $_[0]->[1];
}

sub close
{
    # close pipe and return exit status
    my ($self, $checkError) = @_;
    close($self->[2]);
    my $status = $?;    # 'ignorable_error' below may change it
    if (0 != $status && $checkError) {
        # $reason callback failed: '$cmd' returned non-zero exit status...
        # Note that '$!' says nothing about a process which ran and exited -
        #   it holds whatever the last failing syscall left there - so the
        #   status (or the signal) is what has to be reported.
        lcovutil::report_exit_status($lcovutil::ERROR_CALLBACK,
                                     $self->[0] . ' callback failed',
                                     $status,
                                     "'" . $self->[1] . "'",
                                     '');
    }
    pop(@$self);
    return $status;
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
    # Run the callback and return its exit status - for the one callback whose
    #   answer *is* the exit status:  'compare_version', which is documented as
    #   returning non-zero when the two version IDs do not match.  Every other
    #   callback answers on stdout;  see 'pipe' and 'PipeHelper' above.
    # The arguments go through 'PipeHelper' as a list, so no shell is involved.
    #   This used to build one string with join(' ') and hand it to backticks,
    #   which meant that the shell re-parsed the result:  a file name or a
    #   version ID containing a space became several arguments, and one
    #   containing a metacharacter was interpreted (a '>' created a file).
    # An exit status is an answer only if the callback actually ran and exited.
    #   A callback which could not be executed, or which died from a signal, is
    #   reported here - otherwise 'non-zero' is indistinguishable from a
    #   legitimate 'no', and the user is told that the file versions do not
    #   match when in truth we do not know.
    # The callback is not expected to write anything, and what it writes is not
    #   the answer - but if it wrote something and then failed, that text is
    #   the most useful thing we have to show.  It used to be captured and
    #   discarded.
    my ($self, $reason, @args) = @_;
    lcovutil::info(1, "$reason: \"" . join(' ', @$self, @args) . "\"\n");
    my $iter = $self->pipe($reason, @args);
    return -1 unless defined($iter);    # 'new' reported the failure
    my $text = '';
    while (defined(my $line = $iter->next())) {
        $text .= $line;
    }
    my $status = $iter->close();
    if ($status & 0x7F) {
        $text =~ s/\s+$//;
        my $message = "$reason callback failed";
        $message .= " (it wrote: $text)" if '' ne $text;
        lcovutil::report_exit_status($lcovutil::ERROR_CALLBACK, $message,
                                     $status, "'" . $iter->cmd() . "'", '');
    }
    return $status;
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
    my $pipe = $self->pipe('extract_version', $filename);
    return undef unless defined($pipe);
    my $version = $pipe->next();
    # read to EOF, so that a callback which says more than it was asked to does
    #   not die from SIGPIPE and get reported as broken for that reason
    1 while defined($pipe->next());
    # '1':  check the exit status.
    return undef if 0 != $pipe->close(1);
    # an empty version string, or the literal '0', still needs chomp
    return undef unless defined($version);
    chomp($version);
    $version =~ s/\r//;
    lcovutil::info(1, "  version: $version\n");
    return $version;
}

sub resolve
{
    my ($self, $filename) = @_;
    my $pipe = $self->pipe('resolve_filename', $filename);
    return undef unless defined($pipe);
    my $path = $pipe->next();
    # read to EOF - see 'extract_version' above
    1 while defined($pipe->next());
    return undef if 0 != $pipe->close(1);    # check the exit status
    return undef unless defined($path);
    chomp($path);
    $path =~ s/\r//;
    lcovutil::info(1, "  resolve: $path\n");
    return $path;
}

sub compare_version
{
    my ($self, $yours, $mine, $file) = @_;
    # the arguments are passed as a list, so they must not be quoted here.
    #   Either version ID can be undef - see 'lcovutil::checkVersionMatch' -
    #   and an argument list has no place to put that, so it becomes the empty
    #   string, which is what the shell used to make of it
    return
        $self->call('compare_version', '--compare',
                    defined($yours) ? $yours : '',
                    defined($mine) ? $mine : '', $file);
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

# The select callback is asked whether one coverpoint should appear in the
#   report.  The module form returns a Perl true/false;  the script form writes
#   '1' (selected) or '0' (not selected) to stdout - as lcovrc(5) documents it,
#   and as every other script callback answers - and exits zero.

sub select
{
    my ($self, $lineData, $annotateData, $filename, $lineNo) = @_;
    my $iter = $self->pipe('select',
                           defined($lineData) ?
                               JsonSupport::encode($lineData->to_list()) : '',
                           defined($annotateData) ?
                               JsonSupport::encode($annotateData->to_list()) :
                               '',
                           $filename,
                           $lineNo);
    return 1 unless defined($iter);    # 'new' reported the failure
    my $answer = $iter->next();
    # read to EOF, so that a callback which says more than it was asked to does
    #   not die from SIGPIPE and get reported as broken for that reason
    1 while defined($iter->next());
    my $selected;
    $selected = $1
        if defined($answer) && $answer =~ /^\s*([01])\s*$/;
    my $status = $iter->close(1);    # check the exit status
    return 1 if 0 != $status;        # 'close' reported it
    unless (defined($selected)) {
        my $said = defined($answer) ? $answer : '';
        $said =~ s/\s+$//;
        lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                  "select callback '" .
                                      $iter->cmd() .
                                      "' answered " .
                                      ('' eq $said ? 'nothing' : "'$said'") .
                                      " - expected '0' or '1'");
        return 1;
    }
    return $selected;
}

sub simplify
{
    my ($self, $func) = @_;
    my $name;
    my $pipe = $self->pipe('simplify', $func);
    if (defined($pipe)) {
        $name = $pipe->next();
        # read to EOF - see 'extract_version' above
        1 while defined($pipe->next());
        $pipe->close(1);    # check the exit status
    }
    # 'broken' used to be all the user was told, whether the callback could not
    #   be executed, died from a signal, exited non-zero, or simply said
    #   nothing:  the pipe was never closed, so '$?' was never examined.
    unless (defined($name)) {
        my $detail =
            defined($pipe) ? " '" . $pipe->cmd() . "':  it said nothing" : '';
        die("broken 'simplify' callback$detail");
    }
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
    if (defined($pipe)) {
        $time = $pipe->next();
        # read to EOF - see 'extract_version' above
        1 while defined($pipe->next());
        $pipe->close(1);    # check the exit status
    }
    unless (defined($time)) {
        my $detail =
            defined($pipe) ? " '" . $pipe->cmd() . "':  it said nothing" : '';
        die("broken 'history' callback$detail");
    }
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
            $cmd .= "gzip -c $m" . lcovutil::shell_quote($f);
            open(HANDLE, "|-", $cmd) or
                die("cannot start gzip to compress to file $f: $!\n");
        } else {
            if ($demangle) {
                $cmd .= "$m " . lcovutil::shell_quote($f);
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
            my $cmd = "gzip -cd " . lcovutil::shell_quote($f);
            $cmd .= " | " . $lcovutil::demangle_cpp_cmd
                if ($demangle);
            open(HANDLE, "-|", $cmd) or
                die("cannot start gunzip to decompress file $f: $!\n");

        } elsif ($demangle &&
                 defined($lcovutil::demangle_cpp_cmd)) {
            # no 'cat':  the demangler reads the file itself
            open(HANDLE, "-|",
                 "$lcovutil::demangle_cpp_cmd < " . lcovutil::shell_quote($f))
                or
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

    my ($normalized, $errno) = lcovutil::normalize_count($count);
    if (defined($errno) && !$suppressErrMsg) {
        my $where = 'line "' . $self->filename() . ":$key\"";
        lcovutil::report_format_error($errno, 'hit', $count, $where);
    }
    $count = $normalized;
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
        $data->{$key} = lcovutil::add_count($count, $current);
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
    my ($normalized, $errno) = lcovutil::normalize_count($c);
    lcovutil::report_format_error($errno, 'taken', $c, 'branch ' . $self->id())
        if defined($errno);
    # leave the '-' marker (branch present but not evaluated)
    $self->[TAKEN] = $normalized if $self->[TAKEN] ne '-';
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
                 . ', ' .
                 $that->id() . ": '" .
                 $self->exprString() .
                 "' -> '" .
                 $that->exprString() . "'.")
            if ($self->exprString() ne $that->exprString());
    }
    # LCOV_EXCL_STOP

    # LCOV_EXCL_START
    if ($self->type() != $that->type()) {
        my $loc = defined($filename) ? "\"$filename\":$line: " : '';
        lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                                  "${loc}mismatched exception tag for id " .
                                      $self->id() . ", " .
                                      $that->id() . ": '" .
                                      $self->is_exception() .
                                      "' -> '" .
                                      $that->is_exception() . "'");
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
        lcovutil::ignorable_error(
                           $lcovutil::ERROR_MISMATCH,
                           "${loc}mismatched 'unreachable' tag for branch id " .
                               $self->id() . ", " .
                               $that->id() . ": '" .
                               $self->is_excluded() .
                               "' -> '" .
                               $that->is_excluded() . "'");
        # set 'self' to 'excluded'
        $changed = $self->[EXCLUDED] != 1;
        $self->[EXCLUDED] = 1;
    }
    my $t = $that->[TAKEN];
    return $changed if $t eq '-';    # no new news

    my $count = $self->[TAKEN];
    if ($count ne '-') {
        $changed = 1 if $count == 0 && $t != 0;
        $count   = lcovutil::add_count($count, $t);
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
              LOCATION  => 3,    # see locationOffset
};

# max length of a multi-line statement:
#  how far the line a block is written at may be from its leader (the line
#  it is associated with/the line which has the 'linecov' coverpoint)
use constant MAX_LOCATION_OFFSET => 127;

sub new
{
    my $class = shift;

    my $self = [undef, '', [], 0];
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

sub locationOffset
{
    # The line the block is written at, as an offset from the line of the
    #   BranchLocation which holds it:  0 if it is that line.  The branches of
    #   a statement which spans several lines are counted with the statement's
    #   line, and so are kept there - but the html report displays them where
    #   gcov (or whatever coverage data extraction tool) said they were.
    #   A block written on one line is not the same block as one written on
    #   a different line.  Held as an offset rather than a line number so
    #   that it means the same thing regardless of actual location (e.g.,
    #   in both the baseline and current version of a file which contains
    #   edits)
    return $_[0]->[LOCATION];
}

sub setLocationOffset
{
    # the caller has checked that the offset is within MAX_LOCATION_OFFSET
    my ($self, $offset) = @_;
    $self->[LOCATION] = $offset;
}

sub code
{
    # what tells the block apart from the others of its location:
    #   Combine the signature and the block location (if the location is
    #   not the leader)
    my $self = shift;
    return $self->[LOCATION] ?
        $self->[SIGNATURE] . '^' . $self->[LOCATION] :
        $self->[SIGNATURE];
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
    # 'line' is the line which holds the block:  messages should use the
    #   actual line that the block was written at
    my ($self, $you, $filename, $line) = @_;

    my $m = $self->elements();
    my $y = $you->elements();
    die("expected identical block")
        unless ($#$m == $#$y &&
                $self->signature() eq $you->signature());
    my $changed = 0;
    my $at      = $line + $self->locationOffset();

    for (my $idx = 0; $idx <= $#$m; ++$idx) {
        my $e = $m->[$idx];
        my $f = $y->[$idx];
        $changed = 1
            if $e->merge($f, $filename, $at);
    }
    return $changed;
}

package BranchLocation;
# hash of blockID -> array of BranchElement refs for each sequential branch ID
#   The blocks are indexed by code (see BranchBlock::code) as well

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
    my $code  = $block->code();
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
                     my $codeA = $a->code();
                     my $codeB = $b->code();
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

    my $code  = $branchBlock->code();
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
#   we hold the groups in a hash, keyed by group key (see groupKey).
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

sub groupKey
{
    # The key of a group:  its size (number of MCDC_expressions) and its
    #   location - the offset of the line the group is written at from the line
    #   which holds the block (see BranchBlock::locationOffset).  Two groups of
    #   the same size at different locations are different groups.  The key
    #   is "<size>" if the offset is zero, and "<size>^<offset>" otherwise.
    #   A static function:  it is shared by both implementations.
    my ($size, $offset) = @_;
    return ($offset // 0) ? "$size^$offset" : $size;
}

sub parseGroupKey
{
    # returns (size, location offset) of a group key - see groupKey
    my $key = shift;
    my $i   = index($key, '^');
    return $i < 0 ? ($key, 0) : (substr($key, 0, $i), substr($key, $i + 1));
}

sub groupLine
{
    # the line the group with key 'key' of the block on line 'line' is written
    #   at - the line a message about the group names
    my ($line, $key) = @_;
    return $line + (parseGroupKey($key))[1];
}

sub locationOffsets
{
    # the location offsets of my groups - see groupKey
    my $self = shift;
    return map({ (parseGroupKey($_))[1] } keys(%{$self->groups()}));
}

sub insertExpr
{
    my ($self, $filename, $groupKey, $sense, $count, $idx, $expr, $excluded) =
        @_;
    my $groups = $self->[GROUPS];
    my $group;
    if (exists($groups->{$groupKey})) {
        $group = $groups->{$groupKey};
    } else {
        $group = [];
        $groups->{$groupKey} = $group;
    }
    my $cond;
    if ($idx < scalar(@$group)) {
        $cond = $group->[$idx];
        if ($cond->expression() ne $expr) {
            lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                                      "\"$filename\":" .
                                          groupLine($self->line(), $groupKey) .
                                          ": MC/DC group " .
                                          (parseGroupKey($groupKey))[0] .
                                          " expression $idx changed from '" .
                                          $cond->expression() .
                                          "' to '$expr'");
        }
    } else {
        if ($idx != scalar(@$group)) {
            lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                  "\"$filename\":" .
                      groupLine($self->line(), $groupKey) .
                      ": MC/DC group " .
                      (parseGroupKey($groupKey))[0] .
                      ": non-contiguous expression '$idx' found - should be '" .
                      scalar(@$group) . "'.");
        }
        $cond =
            MCDC_Expression->new($self, (parseGroupKey($groupKey))[0],
                                 $idx, $expr);
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
    # groups() materializes a fresh hash on each call, so hold it in a lexical:
    #   each() over a new hash restarts from the beginning every iteration.
    my $groups = $self->groups();
    while (my ($size, $group) = each(%$groups)) {
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
    my ($self, $groupKey) = @_;
    return
        exists($self->[GROUPS]->{$groupKey}) ? $self->[GROUPS]->{$groupKey} :
        undef;
}

sub expr
{
    my ($self, $groupSize, $idx) = @_;
    # $groupSize is a group key - see groupKey
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

sub incompatible_group
{
    # return the key of a group we share whose expressions differ from yours,
    #   or undef.  Of several, the one at the lowest location (then the
    #   smallest) - so the message which uses some name does not depend on
    #   hash order
    my ($self, $you) = @_;

    my $yours  = $you->groups();
    my $groups = $self->groups();
    my ($conflict, @at);
    foreach my $size (keys %$groups) {
        next unless exists($yours->{$size});
        my $m = $groups->{$size};
        my $y = $yours->{$size};
        # merge() walks the two lists index-wise, so a shared group of unequal
        #   length leaves my trailing expressions with nothing to merge
        #   against:  that is an incompatible record not an error.
        my $differ = scalar(@$m) != scalar(@$y);
        my $idx    = 0;
        foreach my $e (@$m) {
            last if $differ;
            $differ = $e->expression() ne $y->[$idx++]->expression();
        }
        next unless $differ;
        my ($s, $offset) = parseGroupKey($size);
        next
            if (defined($conflict) &&
                ($at[0] < $offset || ($at[0] == $offset && $at[1] < $s)));
        $conflict = $size;
        @at       = ($offset, $s);
    }
    return $conflict;
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
                        "$filename:" .
                            groupLine($self->line(), $size) .
                            ":mismatched 'unreachable' tag for MC/DC element $idx of group "
                            . (parseGroupKey($size))[0]
                            . ' sense ' .
                            ($sense ? 'true' : 'false') .
                            ": '$e_excl' -> '$y_excl'.")
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
    #   above was being set.  Check defined() explicitly:  falling through
    #   to the numeric comparison below behaves the same but warns about an
    #   uninitialized value (the XS implementation is silent here).
    return $changed if !defined($count);

    if ('ARRAY' eq ref($count)) {
        # recording a differential result
        $self->[$sense ? TRUE : FALSE] = $count;
        return 1;    # assumed changed
    }
    # saturate the count the way the XS implementation does -
    #   XS count is a 64-bit signed integers - so that a malformed MCDC
    #   count field cannot make the two backends disagree.
    #  Silent as there is no location to report a diagnostic here, and the
    #   '.info' reader is where a bad field is caught.
    ($count) = lcovutil::normalize_count($count);
    return $changed if 0 == $count;

    $changed = 1 if $self->count($sense) == 0;
    $self->[$sense ? TRUE : FALSE] =
        lcovutil::add_count($self->[$sense ? TRUE : FALSE], $count);
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

sub set_tla
{
    my ($self, $sense, $tla) = @_;
    # The counterpart of BranchElement::set_tla, for the same caller:  the TLA
    #   remap loop in genhtml.  Note that it cannot write the TLA through
    #   count() - which happens to hand back the stored array here, but builds
    #   a fresh one in the XS backend, where the assignment would be lost.
    # Same precondition as BranchElement::set_tla:  a non-differential
    #   expression has no TLA to set, and making it differential here would
    #   make the two backends disagree about which expressions have one.
    my $idx = $sense ? TRUE : FALSE;
    die("unexpected set_tla() call with non-differential data")
        unless 'ARRAY' eq ref($self->[$idx]);
    $self->[$idx]->[0] = $tla;
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

package FunctionAlias;
# one alias of one function:  its name and its hit count.
#   A function has at least one alias - its own name - and C++ templates,
#   clones and Java lambdas add the rest.  The alias is the granularity at
#   which a symbol was actually called, so it is a type rather than a hash
#   slot:  see FunctionEntry::aliasNames() for why FunctionEntry cannot hand
#   out its alias container.

use constant {
              NAME     => 0,
              COUNT    => 1,   # count, or [count, tla] in a differential report
              CALLERS  => 2,   # undef until TraceFile::resolveCallSites runs
              EXTERNAL => 3,   # this symbol has external linkage - see
                               #   is_external.  Undef in all but the few
                               #   symbols a callgraph capture asserts it for
              EXTERNAL_CALLERS => 4,   # I was called from somewhere this report
                                       #   cannot name:  undef where not, else
                                       #   the calls those sites made, '-' if
                                       #   not known - see has_external_callers
              MERGED => 5,    # the other names merged into me:  undef where
                              #   none, else { name => count } - see merged
};

# The letters of the optional flag field of an 'FNA:' record.  An 'x' may be
#   followed by the number of calls it stands for - see external_calls.
#   FLAG_DEDUCED_CALLERS is not a property of the alias and is not one of
#   'flags' below:  it is the conclusion of lcovutil::deduced_external_calls,
#   which the writer appends where the report it writes can draw it, and which
#   the reader recomputes rather than believes - see TraceFile::write_info
use constant {
              FLAG_EXTERNAL         => 'e',
              FLAG_EXTERNAL_CALLERS => 'x',
              FLAG_DEDUCED_CALLERS  => 'd',
};

sub new
{
    my ($class, $name, $count) = @_;
    my $self = [$name, $count];
    bless $self, $class;
    return $self;
}

sub clone
{
    # a copy holding the same count - or, in a differential report, sharing
    #   the same [count, tla] pair, as the flat hash this replaced did
    my $self = shift;
    my $copy = FunctionAlias->new($self->[NAME], $self->[COUNT]);
    # ..and the same linkage, which is a property of the symbol rather than of
    #   the report the copy is being made for
    $copy->set_external() if $self->is_external();
    # ..and the same unnameable callers, which are a fact about the edges the
    #   data recorded and not about the report the copy is for
    $copy->[EXTERNAL_CALLERS] = $self->[EXTERNAL_CALLERS];
    # ..and the names merged into me, which are a fact about the data too
    $copy->[MERGED] = {%{$self->[MERGED]}} if defined($self->[MERGED]);
    return $copy;
}

sub merged
{
    # The names which TraceFile::_collapseCallgraphAliases merged into me, each
    #   with its own share of my count:  { name => count }, undef if none.  The
    #   rest of my count is my own name's.  A map rather than a number of names,
    #   so that two reports which each merged some of the same names combine
    #   without counting a name twice, and so that the merge does not lose
    #   function coverage.
    # Recorded as the 'FNM:' records which follow my 'FNA:' record.
    my $self = shift;
    return $self->[MERGED];
}

sub add_merged
{
    # add_merged(name, count, ...):  these names were merged into me as well,
    #   with these counts - summed with what a name already has.  My own name
    #   is never one of them:  a report which merged 'b' into 'a' combined with
    #   one which merged 'a' into 'b' (because it did not have the name which
    #   made 'a' the one kept) says no more than that the two are one
    #   function, and my count already holds both
    my $self = shift;
    my $name = $self->[NAME];
    while (@_) {
        my ($merged, $count) = splice(@_, 0, 2);
        next if $merged eq $name;
        $self->[MERGED]->{$merged} += $count;
    }
}

sub name
{
    my $self = shift;
    return $self->[NAME];
}

sub is_external
{
    # Whether this symbol has external linkage:  what an 'e' flag on its 'FNA:'
    #   record asserts, and what geninfo reads off the callgraph info's node
    #   list, where a symbol which does NOT have external linkage is
    #   file-qualified.
    # False means "not asserted", not "internal":  it is what every '.info'
    #   written without call data says, what a producer other than geninfo says,
    #   and what a comdat says (an inline function or a template instantiation
    #   is file-qualified in the callgraph info too, so a bit which claimed to
    #   mean "internal" would misclassify it).  Hence the rule built on this in
    #   TraceFile::resolveCallSites only ever resolves a site which did not
    #   resolve before - see there
    my $self = shift;
    return defined($self->[EXTERNAL]) ? $self->[EXTERNAL] : 0;
}

sub set_external
{
    # Set-only, and idempotent:  linkage is a property of the symbol, so two
    #   captures of one symbol cannot disagree about it - one of them may simply
    #   not have recorded it.  So a merge takes the assertion from whichever
    #   side made it and there is nothing to reconcile
    my $self = shift;
    $self->[EXTERNAL] = 1;
}

sub has_external_callers
{
    # Whether at least one call to this symbol comes from a site which this
    #   report cannot name:  what an 'x' flag on its 'FNA:' record asserts.
    #
    # A call site which the report *can* name is on my caller list, with its
    #   file, line, column and count, so it needs no flag - two versions of it
    #   can be compared site by site.  A call site which the report cannot name
    #   any more leaves behind its existence and the count it had, and this is
    #   that:  the flag says that such an edge exists, whether or not it was
    #   taken, and external_calls says how many calls the dropped sites made.
    #   Set where the fact would otherwise be lost outright:
    #     - geninfo, for a call it cannot write a record for (see the drop in
    #       join_call_sites);
    #     - the removal of the file a known site was in, whether by '--remove',
    #       '--extract', an exclude pattern or '--no-external';
    #     - the erasing or exclusion of the function the site is in.
    #   Not set from the residual 'count - sum(known sites) - external_calls',
    #   which is recomputable while the data it is derived from is still there
    #   and would freeze a stale conclusion if a later merge corrected the
    #   count.  That residual is how a call from outside is deduced when nothing
    #   records it - see classify_callers - so an unflagged symbol is not a
    #   symbol nothing outside called.
    # False means "not asserted", exactly as is_external() does:  every '.info'
    #   written without call data says it, and so does one whose external callers
    #   were all still nameable when it was written
    my $self = shift;
    return defined($self->[EXTERNAL_CALLERS]) ? 1 : 0;
}

sub external_calls
{
    # How many calls the call sites behind my 'x' flag made:  the number an
    #   'x<count>' flag carries.  0 where there is no flag, and undef where there
    #   is one and the count is not known - a bare 'x', or a dropped site whose
    #   own count was '-'
    my $self  = shift;
    my $calls = $self->[EXTERNAL_CALLERS];
    return 0 unless defined($calls);
    return $calls eq '-' ? undef : $calls;
}

sub add_external_calls
{
    # One more call site outside the boundary names me, and it made '$count'
    #   calls - '-' if not known.  The flag is never cleared, like set_external:
    #   an edge which is there cannot be made not to exist by a later operation,
    #   and the sides of a merge which did not see it simply have nothing to
    #   say.  The count folds as the dropped sites' own counts would have
    #   merged (lcovutil::add_site_count):  unknown contributes nothing to a
    #   known total, and only known counts add.  Monotone within the
    #   construction of one report, which is what makes 'lcov -a' of many tests
    #   of one build answer for all of them;  a *later* version of the program
    #   gets its own capture and so can say "no external callers any more"
    my ($self, $count) = @_;
    my $calls = $self->[EXTERNAL_CALLERS];
    $self->[EXTERNAL_CALLERS] =
        defined($calls) ? lcovutil::add_site_count($calls, $count) : $count;
}

sub flags
{
    # the optional flag field of my 'FNA:' record - see FLAG_EXTERNAL.  Empty
    #   for almost every alias, which is why the writer asks for it in the same
    #   call it asks for the count
    my $self  = shift;
    my $calls = $self->[EXTERNAL_CALLERS];
    my $flags = $self->is_external() ? FLAG_EXTERNAL : '';
    $flags .= FLAG_EXTERNAL_CALLERS . ($calls eq '-' ? '' : $calls)
        if defined($calls);
    return $flags;
}

sub is_differential
{
    # a differential report replaces the count with a [count, tla] pair -
    #   see FunctionEntry::addAliasDifferential
    my $self = shift;
    return 'ARRAY' eq ref($self->[COUNT]);
}

sub count
{
    my $self = shift;
    return $self->is_differential() ? $self->[COUNT]->[0] : $self->[COUNT];
}

sub set_count
{
    # counts are mutated while merging and filtering, which all happens before
    #   a report can become differential - so there is no pair here to preserve
    my ($self, $count) = @_;
    $self->[COUNT] = $count;
}

sub add_count
{
    my ($self, $count) = @_;
    $self->[COUNT] = lcovutil::add_count($self->[COUNT], $count);
}

sub tla
{
    # undef unless this is a differential report
    my $self = shift;
    return $self->is_differential() ? $self->[COUNT]->[1] : undef;
}

sub set_tla
{
    my ($self, $tla) = @_;
    die("unexpected set_tla() call with non-differential data")
        unless $self->is_differential();
    $self->[COUNT]->[1] = $tla;
}

sub set_differential
{
    my ($self, $data) = @_;
    die("expected array")
        unless 'ARRAY' eq ref($data) && 2 == scalar(@$data);
    $self->[COUNT] = $data;
}

sub write_data
{
    # everything the .info writer needs for one FNA: record, in one call -
    #   the BranchElement::write_data/MCDC_Expression::write_data idiom
    my $self = shift;
    return ($self->[NAME], $self->count(), $self->flags());
}

sub is_resolved
{
    # whether TraceFile::resolveCallSites has run since I was last changed.
    #   'undef' CALLERS means "not resolved" and an empty list means
    #   "resolved, and nothing in this report calls me" - two different
    #   answers, and callers() refuses only the first
    my $self = shift;
    return defined($self->[CALLERS]);
}

sub clear_callers
{
    # forget my callers and declare myself resolved:  this is what makes
    #   resolveCallSites idempotent
    my $self = shift;
    $self->[CALLERS] = [];
}

sub add_caller
{
    # one call site which called me:  the FunctionEntry which contains the
    #   site, where in it the site is, and how many times it was taken.
    #   TraceFile::resolveCallSites is the only caller - see it for why this
    #   direction is derived rather than stored.
    # '$file' is the file the call is WRITTEN in, and is undef when that is the
    #   file the caller is defined in - which is how the site itself holds it
    #   (see FunctionEntry::_siteKey).  It is carried rather than recomputed from
    #   the caller because those two files are not always the same one
    my ($self, $callerEntry, $line, $column, $ordinal, $count, $file) = @_;
    $self->is_resolved() or
        die("cannot add a caller of '" . $self->[NAME] . "' before resolving");
    push(@{$self->[CALLERS]},
         [$callerEntry, $line, $column, $ordinal, $count, $file]);
}

sub callers
{
    # the call sites which called me, as a list of
    #   [callerEntry, line, column, ordinal, count, file].
    # This dies rather than answering an empty list on an unresolved report:
    #   a missing metric which dies is debuggable, one which reads 0/0 is not
    my $self = shift;
    $self->is_resolved() or
        die("the call sites of '" .
            $self->[NAME] .
            "' have not been resolved:  TraceFile::resolveCallSites() must run after the last filter and before any summary"
        );
    return @{$self->[CALLERS]};
}

sub numCallers
{
    my $self    = shift;
    my @callers = $self->callers();
    return scalar(@callers);
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
              CALLS   => 6,    # the call sites in my body - see addCallSite.
                               #   undef until the first one is added, which is
                               #   never for most reports
              EXTERNAL_CALLEES => 7,   # I called something which is outside the
                                       #   boundary of this report - see
                                       #   has_external_callees
              SITES_AT => 8,    # my call sites by location - see _siteIndex.
                                #   there only while a merge which asked for
                                #   it is running
};

# The letters of the optional flag field of an 'FNL:' record - the per-function
#   booleans, as FunctionAlias::FLAG_EXTERNAL and its neighbours are the
#   per-alias ones.
use constant FLAG_EXTERNAL_CALLEES => 'c';

# the fields of one call site.  The site's (line, column, ordinal) is its key,
#   so only these are stored per site
# SITE_COUNT is a count, or the string '-' meaning "this call is here and its
#   count is not known":  the call did not pair - see the 'pairing' entry of the
#   documentation glossary - so reporting 0 would say "your tests never made this
#   call", which is a different and wrong statement.  This is the same third state the
#   'taken' field of a 'BRDA:' record has, deliberately - see BranchElement,
#   whose reader, writer, hit test and merge lattice this follows exactly:  a
#   '-' site is in *found* and never in *hit*, and unknown merged with known is
#   known.  geninfo only writes one under '--callgraph-partial-data'; every
#   reader accepts one always, because a '.info' file may come from anywhere
use constant {
              SITE_COUNT  => 0,
              SITE_CALLEE => 1,
              # the differential category of this site, set by genhtml's
              #   'FileCoverageInfo::_categorizeCallgraphCov' and undef in every
              #   other tool and in every non-differential report.  It is
              #   appended rather than replacing SITE_COUNT (which is what the
              #   function TLAs do) so that every reader of a site - the '.info'
              #   writer, 'numCallSitesHit', 'unionCallSites' - keeps seeing one
              #   shape.  It is here rather than in genhtml's own per-file
              #   structures because the caller of a function need not be in the
              #   same file as the function:  the 'called from' table of a
              #   function detail page reaches its caller's sites through
              #   'FunctionAlias::callers', and has no way back to the
              #   'FileCoverageInfo' of the file that caller lives in
              SITE_TLA => 2,
              # which of my aliases make this call - see aliasSet.  The callee
              #   of a call in a template need not be the same function in every
              #   instantiation:  'f<int>' may call 'g<int>' where 'f<char>'
              #   calls 'g<char>' from the same location, and the two are two
              #   sites at that location.  Without this, a report could not say
              #   which of them each alias makes - and it is what
              #   'collapse_callgraph_alias' compares (see
              #   TraceFile::_collapseCallgraphAliases).  Undef means "every
              #   alias", which is what a site added by a producer that does not
              #   know is taken to mean
              SITE_ALIASES => 3,
              # the line of the statement the call is part of - the leader -
              #   where that is not the line the call is written on:  the
              #   line its coverpoint is allocated to - see
              #   TraceFile::_statementCallSiteMerge.
              #   The key still tells us where the call is written - which
              #   is where hyperlinks will go if not the leader - or undef
              #   if this is the leader (..the common case) of if the
              #   site is in a different file.
              SITE_STATEMENT => 4,
};

# The separator of the names in an alias set.  A name is a field of one line of
#   a '.info' file, so it cannot contain one
use constant ALIAS_SET_SEPARATOR => "\n";

# The largest ordinal a call site can have.  This is a property of the data and
#   not of the backend which happens to be loaded, so it is enforced here as
#   well as in the XS implementation - where the ordinal is the one field of a
#   call site record narrow enough to have a limit at all (see 'struct CallSite'
#   in lib/LcovUtil/FunctionData.hpp).  It is the count of calls at one exact
#   (line, column) of one function, which is 1 for essentially every site in
#   real code, so this is four orders of magnitude of headroom
use constant MAX_CALLSITE_ORDINAL => 0xffff;

# Maximum size of a multiline statement.
#   How far the statement line of a call site (SITE_STATEMENT) may be from the
#   line the call is written on, either way.  A property of the data for the
#   same reason MAX_CALLSITE_ORDINAL is:  the XS implementation holds the
#   distance in a byte.  A statement which is longer than this is not one
#   'ReadCurrentSource::statementSpan' will find.
use constant MAX_STATEMENT_OFFSET => 127;

sub new
{
    my ($class, $name, $map, $startLine, $endLine) = @_;
    die("unexpected type " . ref($map)) unless 'FunctionMap' eq ref($map);
    my %aliases = ($name => FunctionAlias->new($name, 0));    # not hit, yet
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
        my $count   = 0;
        my $aliases = $self->[ALIASES];
        while (my ($alias, $data) = each(%$aliases)) {
            # the clone gets its own FunctionAlias, holding the same count
            $fn->[ALIASES]->{$alias} = $data->clone();
            $count += $data->count();
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
    return ((TraceFile::is_language(lcovutil::IS_C, $self->filename()) &&
                 $self->name() =~ /{lambda\(/) ||
                (TraceFile::is_language(lcovutil::IS_JAVA, $self->filename()) &&
                 $self->name() =~ /\.lambda\$/));
}

sub set_hit
{
    # the hit count across all the aliases of the function
    my ($self, $count) = @_;
    $self->[COUNT] = $count;
}

sub is_differential
{
    # a differential report replaces my count with a [count, tla] pair - see
    #   setCountDifferential
    my $self = shift;
    return 'ARRAY' eq ref($self->[COUNT]);
}

sub tla
{
    # my differential category, or undef if this is not a differential report.
    #   Reached through an accessor rather than through 'hit()->[1]' because
    #   'hit()' materializes the pair in the XS backend:  writing to the copy
    #   would change nothing there
    my $self = shift;
    return $self->is_differential() ? $self->[COUNT]->[1] : undef;
}

sub set_tla
{
    # recategorize:  genhtml rewrites my category when '--show-details' remaps
    #   the categories
    my ($self, $tla) = @_;
    die("unexpected set_tla() call with non-differential data")
        unless $self->is_differential();
    $self->[COUNT]->[1] = $tla;
}

sub aliasNames
{
    # The names of my aliases, in hash order - callers which need a
    #   deterministic order sort them.
    # Note that there is deliberately no accessor which returns the alias
    #   container itself:  an opaque XS object cannot return a live Perl hash,
    #   and one which returns a materialized copy either rebuilds it on every
    #   call or retains it for the life of the object.  MCDC_Block::groups()
    #   did the latter and it cost 589 MB of peak RSS on a 132 MB report.
    my $self = shift;
    return keys(%{$self->[ALIASES]});
}

sub alias
{
    # the FunctionAlias of this name, or undef
    my ($self, $name) = @_;
    return $self->[ALIASES]->{$name};
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

sub _setEndLine
{
    # the unchecked mutator:  'set_end_line' below does the end-before-start
    #   check and the diagnostic, then calls this.  The XS implementation
    #   provides the same primitive, so the policy above it exists once
    my ($self, $line) = @_;
    $self->[LAST] = $line;
}

sub set_end_line
{
    my ($self, $line) = @_;
    if ($line < $self->line()) {
        my $suffix =
            lcovutil::explain_once('derive_end_line',
                      "  See lcovrc man entry for 'derive_function_end_line'.");
        lcovutil::ignorable_error(
                                $lcovutil::ERROR_INCONSISTENT_DATA,
                                '"' .
                                    $self->file() . '":' .
                                    $self->line() .
                                    ': function ' .
                                    $self->name() .
                                    " end line $line less than start line " .
                                    $self->line() .
                                    ".  Cannot derive function end line.$suffix"
        );
        return;
    }
    $self->_setEndLine($line);
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

    my ($normalized, $errno) = lcovutil::normalize_count($count);
    if (defined($errno)) {
        $self->_format_error($errno, $name, $count)
            unless ($errno == $lcovutil::ERROR_EXCESSIVE_COUNT &&
                    grep({ $name =~ $_ || $self->name() =~ $_ }
                         @lcovutil::suppress_function_patterns));
    }
    # perhaps should remove lambda aliases, if they exist -
    #   - Issue is that jacoco will show normal function and lambda on the
    #     same line - which lcov takes to mean that they are aliases
    # could just delete the lambda in that case..pretend it doesn't exist.
    return $self->_addAliasCount($name, $normalized);
}

sub _addAliasCount
{
    # add 'count' to the alias of this name, creating it if it is new, and
    #   maintain both my aggregate count and my choice of representative name.
    #   The count has already been normalized:  'addAlias' above is the policy
    #   which does that and reports a bad one, and the XS implementation
    #   provides this primitive, so that policy exists once
    my ($self, $name, $count) = @_;
    my $changed;
    my $aliases = $self->[ALIASES];
    if (exists($aliases->{$name})) {
        my $data = $aliases->{$name};
        $changed = 0 == $data->count() && 0 != $count;
        $data->add_count($count);
    } else {
        $aliases->{$name} = FunctionAlias->new($name, $count);
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
    $self->[COUNT] = lcovutil::add_count($self->[COUNT], $count);
    return $changed;
}

sub preferredName
{
    # return the 'best' function alias selected from the input candidates.
    # Used to represent the function or an alias group of the function.
    # Criteria:  the shortest, ties broken lexically, with a lambda ranked
    #   as if it were 1000 characters longer - so is chosen only when every
    #   candidate name is a lambda.
    # The same rule as _addAliasCount's, so that which name a function
    #   ends up with does not depend on how it got there
    my $rank = sub {
        my $name = shift;
        return
            length($name) + ($name =~ /(?:\{lambda\(|\.lambda\$)/ ? 1000 : 0);
    };
    my $best;
    foreach my $name (@_) {
        $best = $name
            if !defined($best) ||
            $rank->($name) < $rank->($best) ||
            ($rank->($name) == $rank->($best) && $name lt $best);
    }
    return $best;
}

sub removeAliases
{
    my $self    = shift;
    my $aliases = $self->[ALIASES];
    my $rename  = 0;
    foreach my $name (@_) {
        exists($aliases->{$name}) or die("removing non-existent alias $name");

        my $count = $aliases->{$name}->count();
        delete($aliases->{$name});
        $self->[COUNT] -= $count;
        if ($self->[NAME] eq $name) {
            $rename = 1;
        }
    }
    if ($rename &&
        %$aliases) {
        $self->[NAME] = preferredName(keys(%$aliases));
    }
    # ..and the calls those aliases made:  a site which names them in its alias
    #   set no longer does, and a site which only they made is gone with them -
    #   the code which made the call is not in the report any more
    if (defined($self->[CALLS]) && @_) {
        my %gone = map({ $_ => 1 } @_);
        foreach my $key (keys(%{$self->[CALLS]})) {
            my $set = $self->[CALLS]->{$key}->[SITE_ALIASES];
            next unless defined($set);
            my @names = aliasSetNames($set);
            my @left  = grep({ !exists($gone{$_}) } @names);
            next if scalar(@left) == scalar(@names);
            if (@left) {
                $self->[CALLS]->{$key}->[SITE_ALIASES] = aliasSet(@left);
            } else {
                $self->_removeSite($key);
            }
        }
    }
    return %$aliases;    # true if this function still exists
}

sub addAliasDifferential
{
    my ($self, $name, $data) = @_;
    my $alias = $self->alias($name);
    die("alias $name exists")
        if defined($alias) && $name ne $self->name();
    if (defined($alias)) {
        $alias->set_differential($data);
    } else {
        $alias = FunctionAlias->new($name, undef);
        $alias->set_differential($data);
        $self->[ALIASES]->{$name} = $alias;
    }
}

sub setCountDifferential
{
    my ($self, $data) = @_;
    die("expected array")
        unless ref($data) eq "ARRAY" && 2 == scalar(@$data);
    $self->[COUNT] = $data;
}

sub _siteKey
{
    # the identity of a call site within the function which contains it.
    #   (line, column) is almost enough - the column is what distinguishes two
    #   calls on one line - but the compiler folds the location of a call nested
    #   in an argument list onto the enclosing call, so 'sum2(i ? y() : 0, w())'
    #   puts the edge to 'w' and the edge to 'sum2' at one column.  The ordinal
    #   is the position of the site among all the sites at that exact
    #   (line, column) in this function, and is 0 for essentially every site
    #   in real code.
    # It counts sites at a location and not sites per callee at a location,
    #   because those two callees would otherwise share a key.  What it does not
    #   number is two edges to one callee from one location:  the capture folds
    #   those into one site and so does a merge - see join_call_sites in geninfo
    #   and '_resolveCallSite' below - because a location and a callee is what a
    #   report can name a call by, and one call as written is what is measured
    # A location is a line and a column, so that folding leaves two calls to one
    #   callee at two columns of one line as the two sites they are:  what merges
    #   is only what a report could not have shown apart
    #
    # '$file' is the file the call is WRITTEN in, and is undef - and then not
    #   part of the key at all - for the overwhelming majority of sites, which
    #   are written in the same file as the function which contains them.  A
    #   function's body can span files: a call written in an '#include'd
    #   fragment is compiled into whichever translation unit included it, so
    #   the site belongs to a caller defined in one file and is located in
    #   another.  (line, column) is then not unique within the function, which
    #   is why this is part of the identity and not payload beside it.
    # It goes last, and '_splitSiteKey' reads it back with a limited split,
    #   because a path may contain a colon ('C:/...')
    my ($line, $column, $ordinal, $file) = @_;
    return defined($file) ? "$line:$column:$ordinal:$file" :
        "$line:$column:$ordinal";
}

sub _splitSiteKey($)
{
    # a site key back into (line, column, ordinal, file) - the file being undef
    #   when the site is in the same file as its function.  See _siteKey
    return split(':', $_[0], 4);
}

sub aliasSet
{
    # The alias set of a call site - see SITE_ALIASES - made of these names:
    #   the names, sorted and without duplicates, joined into one string.  A
    #   string rather than a container because most sets contain a single
    #   element, and because a string is what both pure perl and XS
    #   can hold and compare cheaply:  the XS one interns it,
    #   as it does a callee name.  Undef if there are no names, which is
    #   "every alias"
    my %seen;
    my @names = grep({ !$seen{$_}++ } @_);
    return undef unless @names;
    return $names[0] if 1 == scalar(@names);
    return join(ALIAS_SET_SEPARATOR, sort(@names));
}

sub aliasSetNames($)
{
    # the names in an alias set, in sorted order;  the empty list for undef,
    #   which is "every alias" - the caller decides what that means
    my $set = shift;
    return () unless defined($set);
    return split(ALIAS_SET_SEPARATOR, $set);
}

our %_aliasUnionMemo;

sub _unionAliasSets($$)
{
    # two inputs say which aliases make one call, and the answer is all of them.
    #   Undef is "every alias", so it absorbs the other side
    #   An aggregation meets the same pair once per input which instantiates
    #   the template, and a set is as long as the template has instantiations -
    #   so the answer is remembered rather than rebuilt each time
    my ($mine, $yours) = @_;
    return undef unless defined($mine) && defined($yours);
    return $mine if $mine eq $yours;
    my $key = ($mine lt $yours) ? "$mine\0$yours" : "$yours\0$mine";
    return $_aliasUnionMemo{$key} //=
        aliasSet(aliasSetNames($mine), aliasSetNames($yours));
}

sub siteHasAlias($$)
{
    # whether an alias set includes this name - undef includes every name
    my ($set, $name) = @_;
    return 1 unless defined($set);
    return 1 if $set eq $name;
    return scalar(grep({ $_ eq $name } aliasSetNames($set)));
}

sub addCallSite
{
    # One call from my body:  where the call is, how many times it was taken,
    #   and the symbol it calls.  The callee is payload rather than key, and it
    #   is a string rather than a reference:  it may name a function in a file
    #   which has not been read yet, so it is resolved to a FunctionEntry in a
    #   separate pass - see TraceFile::resolveCallSites.
    # Note that the caller side is the authoritative storage, and that it is
    #   local to one file:  that is what lets call data merge, filter and
    #   serialize like every other coverpoint, and what makes every removal a
    #   local edit rather than a scan of every other file.
    # Returns true if this changed my data, in the sense addAlias means it:
    #   a new site, or a site which was not taken and now is
    # '$file' is where the call is written, and may be omitted - or given as my
    #   own file - by a producer which has no cross-file sites:  see _siteKey.
    #   It is normalized to undef here rather than at each producer, so that one
    #   site cannot be recorded under two keys depending on which of them added
    #   it.
    # '$merging' says that the site comes from a different input than the ones
    #   already here - another '.info', another '.gcda', another testcase - in
    #   which case a disagreement about the ordinal is resolved rather than
    #   reported:  see _resolveCallSite.  It is false for the sites of one input,
    #   where two callees at one key really is malformed data
    # '$aliases' is the set of my aliases which make the call - see aliasSet -
    #   and is undef, "every alias", from a producer which does not say.  A
    #   site which is already here takes the union:  two aliases whose calls
    #   fold into one site both make it
    # '$statement' is the line of the statement the call is part of (the
    #   leader)- see SITE_STATEMENT - and is undef from a producer which does
    #   not say, or for a call which is on that line.
    #   The caller has checked that it is within MAX_STATEMENT_OFFSET of
    #   '$line'.  A site which is already here and has none takes this one
    my ($self, $line, $column, $ordinal, $count,
        $callee, $file, $merging, $aliases, $statement) = @_;

    $file      = undef if defined($file)    && $file eq $self->file();
    $aliases   = undef if defined($aliases) && $aliases eq '';
    $statement = undef
        if defined($statement) && ($statement == $line || defined($file));
    my $key = _siteKey($line, $column, $ordinal, $file);
    # Normalized here rather than in the reader so that every producer of a
    #   site - the '.info' reader, geninfo, a future front end - is held to the
    #   same arithmetic as every other count.
    # '-' is not a count and is passed through, exactly as BranchElement::new
    #   leaves the marker alone:  it is the one value normalize_count must not
    #   see, because 'looks_like_number' would call it ERROR_FORMAT
    my $normalized = $count;
    if (!defined($count) || $count ne '-') {
        my $errno;
        ($normalized, $errno) = lcovutil::normalize_count($count);
        if (defined($errno)) {
            lcovutil::report_format_error($errno, 'call', $count,
                                          "call site $key in '" .
                                              $self->name() . "' of " .
                                              $self->file() .
                                              " calling '$callee'");
        }
    }
    my $changed =
        $self->_addCallSite($line, $column, $ordinal, $normalized, $callee,
                            $file, $aliases, $statement);
    if (-1 == $changed && $merging) {
        ($ordinal, $changed) =
            $self->_resolveCallSite($line, $column, $file, $normalized,
                                    $callee, $aliases, $statement);
        $key = _siteKey($line, $column, $ordinal, $file);
    }
    # the messages below name the file the call is written in
    my $where = defined($file) ? $file : $self->file();
    if (-2 == $changed) {
        # Not representable rather than not consistent:  a call site record
        #   holds MAX_CALLSITE_ORDINAL ordinals, and there is no partial answer
        #   to give - dropping the site would silently lose a call, and keeping
        #   it under a different ordinal would collide with a real one
        die('"' .
            $where . '":' .
            $line .
            ": call site $key in '" .
            $self->name() .
            "' calling '$callee' has ordinal $ordinal:  no more than " .
            MAX_CALLSITE_ORDINAL .
            " calls at one location are supported" .
            MessageContext::context());
    }
    if (0 > $changed) {
        # Same file, same line, same column, same ordinal, different target,
        #   within one input:  the data is malformed - one compiled unit cannot
        #   have two calls with one identity.  Keep the first and name both.
        #   Across inputs this is not an error - see _resolveCallSite
        my $existing = ($self->callSiteData($key))[4];
        lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                                  '"' .
                                      $where . '":' .
                                      $line .
                                      ": call site $key in '" .
                                      $self->name() .
                                      "' calls '$existing" .
                                      "' but also '$callee'" .
                                      MessageContext::context());
        return 0;
    }
    return $changed;
}

sub _addCallSite
{
    # add one site, or merge into the site already at this location.  Returns 1
    #   if my data changed, 0 if it did not, -1 if a site is already here
    #   calling something else, and -2 if the ordinal is past what a call site
    #   holds - which 'addCallSite' above reports, so that the messages live
    #   with every other one.  The XS implementation provides the same primitive
    my ($self, $line, $column, $ordinal, $count,
        $callee, $file, $aliases, $statement) = @_;
    return -2 if $ordinal < 0 || $ordinal > MAX_CALLSITE_ORDINAL;
    my $key = _siteKey($line, $column, $ordinal, $file);
    $self->[CALLS] = {} unless defined($self->[CALLS]);
    my $site = $self->[CALLS]->{$key};
    if (!defined($site)) {
        # ..with no statement slot unless there is one:  the common case
        $self->[CALLS]->{$key} = [$count, $callee, undef, $aliases,
                                  defined($statement) ? ($statement) : ()
        ];
        _indexSite($self->[SITES_AT], $line, $column, $ordinal, $callee, $file)
            if defined($self->[SITES_AT]);
        return 1;
    }
    return -1 if $site->[SITE_CALLEE] ne $callee;
    # ..whatever the count says:  which aliases make the call is not coverage
    #   data, so it does not make the site 'changed'
    $site->[SITE_ALIASES] =
        _unionAliasSets($site->[SITE_ALIASES], $aliases);
    # ..and nor is the leader - the line its coverpoint is allocated to
    $site->[SITE_STATEMENT] = $statement
        if defined($statement) && !defined($site->[SITE_STATEMENT]);
    # The '-' lattice of BranchElement::merge:  unknown + anything is that
    #   thing, and only a known count can be added to.  A mixed capture where
    #   one unit knows the count and another does not therefore resolves to the
    #   count, and never the other way round
    return 0 if $count eq '-';    # no new news
    my $mine = $site->[SITE_COUNT];
    if ($mine eq '-') {
        $site->[SITE_COUNT] = $count;
        return 0 != $count;
    }
    my $changed = 0 == $mine && 0 != $count;
    $site->[SITE_COUNT] = lcovutil::add_count($mine, $count);
    return $changed;
}

sub _siteIndex
{
    # my sites grouped by location, built the first time a merge asks, kept up
    #   to date by _addCallSite and _removeSite while that merge runs, and
    #   dropped by _dropSiteIndex when it is done.  Without it
    #   every ordinal a merge resolves is a walk of every key:  a template
    #   instantiated a thousand ways calls a thousand callees from one location,
    #   so merging two of its functions costs millions of splits - which is what
    #   stalled the parent of a large parallel capture.  The XS implementation
    #   keeps its sites in location order and has no need of this.
    # One entry per location - see _siteLocation - holding
    #   [{ordinal => callee}, {callee => lowest ordinal}, low water mark]:  every
    #   ordinal below the mark is in use there, which is what lets the lowest
    #   free ordinal be found without starting from zero each time
    my $self = shift;
    return $self->[SITES_AT] if defined($self->[SITES_AT]);
    my %index;
    foreach my $key ($self->callSiteKeys()) {
        my ($line, $column, $ordinal, $file) = _splitSiteKey($key);
        _indexSite(\%index, $line, $column, $ordinal,
                   $self->[CALLS]->{$key}->[SITE_CALLEE], $file);
    }
    $self->[SITES_AT] = \%index;
    return \%index;
}

sub _dropSiteIndex
{
    # a merge is done with my _siteIndex.  It is not kept for the next one:  it
    #   is a second copy of every site's location and callee, which a capture
    #   parent would otherwise hold for every function it ever merged a
    #   conflict into, and rebuilding it costs one walk of the keys - where
    #   what it saves is one walk per ordinal resolved.  There is none to drop
    #   in the XS implementation, whose entries are not arrays
    my $self = shift;
    return if $lcovutil::XS_LOADED;
    delete($self->[SITES_AT]);
}

sub _siteLocation
{
    # the _siteIndex key of an exact (file, line, column).  The ordinal numbers
    #   the sites at one location of one file, so a site in a different file is
    #   at a different location however the line and the column read - see
    #   _siteKey
    my ($line, $column, $file) = @_;
    return defined($file) ? "$line:$column:$file" : "$line:$column";
}

sub _indexSite
{
    my ($index, $line, $column, $ordinal, $callee, $file) = @_;
    my $here = $index->{_siteLocation($line, $column, $file)} //= [{}, {}, 0];
    $here->[0]->{$ordinal} = $callee;
    my $lowest = $here->[1]->{$callee};
    $here->[1]->{$callee} = $ordinal
        if !defined($lowest) || $ordinal < $lowest;
}

sub _sitesAt
{
    # my sites at this exact (file, line, column), as [ordinal, callee] pairs in
    #   ordinal order.  The XS implementation provides the same primitive
    my ($self, $line, $column, $file) = @_;
    my $here = $self->_siteIndex()->{_siteLocation($line, $column, $file)};
    return () unless defined($here);
    my $byOrdinal = $here->[0];
    return
        map({ [$_, $byOrdinal->{$_}] }
            sort({ $a <=> $b } keys(%$byOrdinal)));
}

sub _findSiteAt
{
    # the key of my $nth site at (file, line, column) which calls $callee,
    #   counting from the lowest ordinal, or undef if I have no such site.  This
    #   is how one input's site is looked up in another's when the two do not
    #   agree on the ordinal
    my ($self, $line, $column, $file, $callee, $nth) = @_;
    $nth = 0 unless defined($nth);
    foreach my $site ($self->_sitesAt($line, $column, $file)) {
        next unless $site->[1] eq $callee;
        return _siteKey($line, $column, $site->[0], $file) if 0 == $nth--;
    }
    return undef;
}

sub _resolveCallSite
{
    # A site from another input wants an ordinal which is already taken here by
    #   a call to something else.  That is not malformed data:  the ordinal
    #   numbers the sites at one location within one compiled unit, so two units
    #   which contain the same function - two instantiations of a template, two
    #   objects sharing an inline or a comdat - each number theirs from zero, and
    #   agree on the ordinal only by luck.  Two instantiations are also aliases
    #   of one entry and so share one call site list, which is where they meet.
    # Resolve it the way the report reads it:  the ordinal is not a name, it is
    #   which of the calls at this location this is, so give this site the
    #   ordinal my call to the same callee already has - the two inputs merely
    #   numbered them differently - and failing that the lowest ordinal not in
    #   use here, which makes it a call this function also contains.  Either way
    #   no call is lost, the callees are right, and the answer does not depend on
    #   the order the inputs were read in.  Where the two disagree about how many
    #   calls to one callee are at one location, two of yours can fold into one
    #   of mine:  the counts still add up, and two units which share a function
    #   share its one 'FNL:' index, so nothing in the record could keep them
    #   apart anyway.
    # Returns the (ordinal, changed) of the site it merged into or added
    my ($self, $line, $column, $file, $count, $callee, $aliases, $statement) =
        @_;
    my $ordinal = $self->_resolveOrdinal($line, $column, $file, $callee);
    lcovutil::info(2,
                   '"' .
                       (defined($file) ? $file : $self->file()) . '":' .
                       $line .
                       ": call site $line:$column in '" .
                       $self->name() .
                       "' calling '$callee' merged as ordinal $ordinal\n");
    return ($ordinal,
            $self->_addCallSite($line, $column, $ordinal, $count,
                                $callee, $file, $aliases, $statement));
}

sub _resolveOrdinal
{
    # the ordinal a site from another input calling $callee at this exact
    #   (file, line, column) takes here:  that of my call to the same callee at
    #   this location if I have one, and otherwise the lowest ordinal I do not
    #   use there - see _resolveCallSite.  A template instantiated a thousand
    #   ways calls a thousand callees from one location, and a merge resolves
    #   each of them, so neither is a walk of the sites there - see _siteIndex.
    #   The XS implementation provides the same primitive
    my ($self, $line, $column, $file, $callee) = @_;
    my $here = $self->_siteIndex()->{_siteLocation($line, $column, $file)};
    return 0 unless defined($here);
    my $ordinal = $here->[1]->{$callee};
    return $ordinal if defined($ordinal);
    $ordinal = $here->[2];
    ++$ordinal while exists($here->[0]->{$ordinal});
    $here->[2] = $ordinal;
    return $ordinal;
}

sub _removeSite
{
    # drop the site with this key.  Returns true if there was one
    my ($self, $key) = @_;
    return 0 unless defined($self->[CALLS]) && exists($self->[CALLS]->{$key});
    my $site = delete($self->[CALLS]->{$key});
    if (defined($self->[SITES_AT])) {
        my ($line, $column, $ordinal, $file) = _splitSiteKey($key);
        my $where  = _siteLocation($line, $column, $file);
        my $here   = $self->[SITES_AT]->{$where};
        my $callee = $site->[SITE_CALLEE];
        delete($here->[0]->{$ordinal});
        if (!%{$here->[0]}) {
            delete($self->[SITES_AT]->{$where});
        } else {
            $here->[2] = $ordinal if $ordinal < $here->[2];
            if ($here->[1]->{$callee} == $ordinal) {
                # my lowest call to this callee here went:  the next one, if
                #   there is one, is now the lowest
                my @left = grep({ $here->[0]->{$_} eq $callee }
                                keys(%{$here->[0]}));
                if (@left) {
                    $here->[1]->{$callee} = (sort({ $a <=> $b } @left))[0];
                } else {
                    delete($here->[1]->{$callee});
                }
            }
        }
    }
    return 1;
}

sub callSiteKeys
{
    # the keys of my call sites, in hash order - see aliasNames() for why
    #   there is no accessor which returns the container itself.
    # CALLS is undef until the first site is added, which is never for most
    #   functions - but that must not make the answer a different *kind* of
    #   answer, so borrow an empty hash rather than returning the empty list:
    #   'keys' of an empty hash is 0 in scalar context where '()' is undef,
    #   and the XS implementation returns the count
    my $self = shift;
    return keys(%{$self->[CALLS] // {}});
}

sub sortedCallSiteKeys
{
    # my call site keys in source order:  by line, then column, then ordinal,
    #   and then by the file a cross-file site is in - last, so that the order
    #   of the sites of a function which has none is exactly what it was.  The
    #   keys are strings, so this is not the order they sort in
    my $self = shift;
    return
        sort({
                 my @x = _splitSiteKey($a);
                 my @y = _splitSiteKey($b);
                 $x[0]     <=> $y[0] or
                     $x[1] <=> $y[1] or
                     $x[2] <=> $y[2] or
                     (defined($x[3]) ? $x[3] : '') cmp
                     (defined($y[3]) ? $y[3] : '')
        } $self->callSiteKeys());
}

sub has_external_callees
{
    # Whether at least one call written in my body goes to a function outside the
    #   boundary of this report:  what a 'c' flag on my 'FNL:' record asserts,
    #   and the mirror of FunctionAlias::has_external_callers.
    #
    # The callee of such a call is not in the report - it is in a system header,
    #   in a third party library, in a file which '--remove' or an exclude
    #   pattern took out, or it is a function '--erase-functions' erased - so
    #   there is nothing for the site to point at and the site itself is dropped
    #   (TraceFile::_pruneExternalCallees).  All that is left to record is that
    #   the edge is there, and this is that:  the caller is inside the boundary,
    #   which is why the fact is kept on the caller even though the callee it
    #   names is deliberately not part of the report.
    # The flag says that such an edge exists.  It does not say that the edge was
    #   taken, and it does not say how many such edges there are:  the site which
    #   carried the count is gone, and no count is what leaving the boundary costs
    #   an edge.  Whether the call was made can still be read off the line and
    #   branch counts of the line it is written on - see _pruneExternalCallees
    # False means "not asserted", exactly as the two alias flags do:  every
    #   '.info' written without call data says it, so does one whose calls all
    #   stay inside the boundary, and so does a capture - where no boundary has
    #   been drawn yet and no site has been dropped
    my $self = shift;
    return defined($self->[EXTERNAL_CALLEES]) ? $self->[EXTERNAL_CALLEES] : 0;
}

sub set_external_callees
{
    # Set-only and idempotent, like the flag of FunctionAlias::external_calls:
    #   an edge which is there cannot be made not to exist by a later operation, and the
    #   sides of a merge which did not see it simply have nothing to say
    my $self = shift;
    $self->[EXTERNAL_CALLEES] = 1;
}

sub numCallSites
{
    # the number of 'FNC:' records in my body - which is what a user reading
    #   "N of M callees" means by M, and the reason it is not the number of
    #   distinct (location, callee) pairs the display tables have rows for:  two
    #   calls at one location to one callee are two calls, and collapsing them
    #   would make the denominator disagree with the record count in the '.info'.
    #   A site whose count is '-' is one of them - see SITE_COUNT
    my $self = shift;
    return defined($self->[CALLS]) ? scalar(keys(%{$self->[CALLS]})) : 0;
}

sub numCallSitesHit
{
    # how many of my call sites were taken at least once.  Counted rather than
    #   maintained, as numHit() is:  a site's count can change under merge,
    #   filtering or subtraction
    my $self = shift;
    return 0 unless defined($self->[CALLS]);
    my $n = 0;
    foreach my $site (values(%{$self->[CALLS]})) {
        # '-' is a site whose count is not known, which is never a site known to
        #   have been taken:  it is in numCallSites and not here, so a degraded
        #   capture understates the rate rather than overstating it
        ++$n if lcovutil::site_count_hit($site->[SITE_COUNT]);
    }
    return $n;
}

sub callSiteData
{
    # everything there is to know about one of my call sites, in one call -
    #   the FunctionAlias::write_data idiom.  Returns the empty list if I have
    #   no site with this key.
    # The file goes last, after the payload rather than with the rest of the
    #   key, so that a reader which does not care where the call is written -
    #   which is almost all of them - is unchanged:  it is undef for a site in
    #   my own file, which is almost every site.  The alias set - see
    #   SITE_ALIASES - comes after it, for the same reason, and the statement
    #   line - see SITE_STATEMENT - after that
    my ($self, $key) = @_;
    my $site = defined($self->[CALLS]) ? $self->[CALLS]->{$key} : undef;
    return () unless defined($site);
    my ($line, $column, $ordinal, $file) = _splitSiteKey($key);
    return ($line, $column, $ordinal, $site->[SITE_COUNT],
            $site->[SITE_CALLEE], $file, $site->[SITE_ALIASES],
            $site->[SITE_STATEMENT]);
}

sub _setSiteStatement
{
    # set the statement line of the site with this key - see SITE_STATEMENT.
    #   Returns true if there is such a site.  The caller has checked that the
    #   line is within MAX_STATEMENT_OFFSET of the site's own.  XS implements
    #   the same primitive
    my ($self, $key, $statement) = @_;
    my $site = defined($self->[CALLS]) ? $self->[CALLS]->{$key} : undef;
    return 0 unless defined($site);
    $site->[SITE_STATEMENT] = $statement;
    return 1;
}

sub _setSiteAliases
{
    # replace the alias set of the site with this key - see SITE_ALIASES.
    #   Returns true if there is such a site.  The policy - what the set
    #   becomes when an alias is removed or renamed - is the caller's.  XS
    #   implements the same primitive
    my ($self, $key, $aliases) = @_;
    my $site = defined($self->[CALLS]) ? $self->[CALLS]->{$key} : undef;
    return 0 unless defined($site);
    $site->[SITE_ALIASES] = $aliases;
    return 1;
}

sub callSiteTla
{
    # the differential category of one of my call sites, or undef if this is not
    #   a differential report (or if I have no such site).  Located the way
    #   FunctionAlias::callers reports a caller - by (line, column, ordinal,
    #   file) rather than by the key string - so that the 'called from' table can
    #   ask directly with what it already has
    my ($self, $line, $column, $ordinal, $file) = @_;
    my $site =
        defined($self->[CALLS]) ?
        $self->[CALLS]->{_siteKey($line, $column, $ordinal, $file)} :
        undef;
    return defined($site) ? $site->[SITE_TLA] : undef;
}

sub setCallSiteTla
{
    my ($self, $line, $column, $ordinal, $file, $tla) = @_;
    my $key  = _siteKey($line, $column, $ordinal, $file);
    my $site = defined($self->[CALLS]) ? $self->[CALLS]->{$key} : undef;
    die("no call site $key in '" . $self->name() . "' of " . $self->file())
        unless defined($site);
    $site->[SITE_TLA] = $tla;
}

sub unionCallSites
{
    # add your call sites to mine:  a site we both have sums its counts, and a
    #   site only you have is new to me.  You are another input, so a site whose
    #   ordinal I have given to another callee is resolved and not reported -
    #   see _resolveCallSite, which is also why this walks your sites in source
    #   order rather than hash order:  the ordinals it hands out then depend only
    #   on the data
    my ($self, $that) = @_;
    my $changed = 0;
    foreach my $key ($that->sortedCallSiteKeys()) {
        my ($line, $column, $ordinal, $count, $callee, $file, $aliases,
            $statement)
            = $that->callSiteData($key);
        $changed = 1
            if $self->addCallSite($line, $column, $ordinal,
                                  $count, $callee, $file,
                                  1, $aliases, $statement);
    }
    $self->_dropSiteIndex();
    return $changed;
}

sub intersectCallSites
{
    # keep only the sites we both have, summing their counts - the same
    #   treatment intersect gives an alias.  A function left with no sites is
    #   not a function with no hits:  the entry stays.
    # "Both have" is by location and callee and not by key:  you are another
    #   input, so we need not agree on the ordinal - the same reason
    #   unionCallSites resolves one - and a site of mine you also contain must
    #   survive however you numbered it
    my ($self, $that) = @_;
    my $changed = 0;
    my %nth;    # how many of my sites at this location call this callee already
    foreach my $key ($self->sortedCallSiteKeys()) {
        my ($line, $column, $ordinal, undef, $callee, $file) =
            $self->callSiteData($key);
        # two calls to one callee at one location are two calls, so my second
        #   one wants your second one:  a location where you call it once and I
        #   call it twice is a location we have one call in common at
        my $where = defined($file) ? $file : '';
        my $yours = $that->_findSiteAt($line, $column, $file, $callee,
                                       $nth{"$line:$column:$callee:$where"}++);
        if (defined($yours)) {
            # ..and the aliases either side says make the call:  the ones
            #   which do not survive the intersection are removed with the
            #   aliases themselves - see removeAliases
            my (undef, undef, undef, $count, undef, undef, $aliases, $statement)
                = $that->callSiteData($yours);
            $changed = 1
                if $self->addCallSite($line, $column, $ordinal,
                                      $count, $callee, $file,
                                      undef, $aliases, $statement);
        } else {
            $self->_removeSite($key);
            $changed = 1;
        }
    }
    $that->_dropSiteIndex();
    $self->_dropSiteIndex();
    return $changed;
}

sub subtractCallSites
{
    # remove the sites we both have, keeping the ones only I have
    my ($self, $that) = @_;
    my $changed = 0;
    foreach my $key ($that->callSiteKeys()) {
        $changed = 1 if $self->_removeSite($key);
    }
    return $changed;
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

sub _insert
{
    # create an entry and store it under its start line.  The caller has already
    #   established that no entry is there - 'define_function' below does the
    #   diagnostics.  The XS implementation provides the same primitive
    my ($self, $name, $start_line, $end_line) = @_;
    my $data = FunctionEntry->new($name, $self, $start_line, $end_line);
    $self->[0]->{$start_line} = $data;
    return $data;
}

sub _registerName
{
    # make this name find this entry
    my ($self, $name, $entry) = @_;
    $self->[1]->{$name} = $entry;
}

sub _unregisterName
{
    # forget this name.  Returns true if I knew it
    my ($self, $name) = @_;
    return 0 unless exists($self->[1]->{$name});
    delete($self->[1]->{$name});
    return 1;
}

sub _removeKey
{
    # forget the entry at this start line.  Returns true if there was one
    my ($self, $key) = @_;
    return 0 unless exists($self->[0]->{$key});
    delete($self->[0]->{$key});
    return 1;
}

sub _relocate
{
    # move an entry to a new start line, keeping it alive across the move.
    #   Returns false if it is not in my location map under its current line -
    #   which another entry, from some other map, may share
    my ($self, $entry, $line) = @_;
    my $key = $entry->line();
    return 0
        unless exists($self->[0]->{$key}) && $self->[0]->{$key} == $entry;
    delete($self->[0]->{$key});
    $entry->set_line($line);
    $self->[0]->{$line} = $entry;
    return 1;
}

sub define_function
{
    my ($self, $fnName, $start_line, $end_line, $location) = @_;
    #lcovutil::info("define: $fnName " . $self->$filename() . ":$start_line->$end_line\n");
    # could check that function ranges within file are non-overlapping

    my $data = $self->findName($fnName);
    if (defined($data) &&
        #TraceFile::is_language(lcovutil::IS_C, $self->filename()) &&
        $data->line() != $start_line
    ) {
        $location = '"' . $self->filename() . '":' . $start_line
            unless defined($location);
        lcovutil::ignorable_error(
                   $lcovutil::ERROR_INCONSISTENT_DATA,
                   "$location: duplicate function '$fnName' starts on line \"" .
                       $data->filename() .
                       "\":$start_line but previous definition started on " .
                       $data->line() .
                       MessageContext::context() . '.')
            unless
            grep({ $fnName =~ $_ } @lcovutil::suppress_function_patterns);
        # if ignored, just return the function we already have -
        # record the function location as the smallest line number we saw
        $self->_relocate($data, $start_line) if ($start_line < $data->line());
        return $data;
    }

    $data = $self->findKey($start_line);
    if (defined($data)) {
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
        $data = $self->_insert($fnName, $start_line, $end_line);
    }
    if (!defined($self->findName($fnName))) {
        $self->_registerName($fnName, $data);
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
            foreach my $alias ($data->aliasNames()) {
                ++$n if $data->alias($alias)->count() > 0;
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

sub get_callgraph_found_and_hit
{
    # the number of call sites in my functions, and how many of them were
    #   taken:  the caller-side view, which is what this file's own data can
    #   answer - see TraceInfo::callgraph_found.
    # '--filter function' does not enter into it:  a site belongs to the
    #   FunctionEntry, not to one of its names, so merging aliases neither adds
    #   nor removes one
    my $self  = shift;
    my $found = 0;
    my $hit   = 0;
    foreach my $key ($self->keylist()) {
        my $data = $self->findKey($key);
        $found += $data->numCallSites();
        $hit   += $data->numCallSitesHit();
    }
    return ($found, $hit);
}

sub hasCallgraphData
{
    # Does anything in this report say anything about the calls of the
    #   compilation unit these functions belong to?  Four things can:  a call
    #   site of its own, a function of it whose calls all left the boundary of
    #   the report (FunctionEntry::has_external_callees), a symbol of it which
    #   something outside that boundary called (has_external_callers), and a
    #   call site elsewhere in the report which names a symbol it defines -
    #   which is what '$calledSymbols' holds (see TraceFile::calledSymbols).
    #
    # Asked per file, unlike TraceFile::hasCallgraphData, and that is the point.
    #   '-fcallgraph-info' is a property of the object, so one build can hold
    #   objects compiled with it beside objects compiled without it, and a report
    #   can merge a C++ capture with a language whose tools have no callgraph
    #   data at all.  A file on the wrong side of that line carries no call
    #   records for the same reason a leaf translation unit carries none, and
    #   nothing in the data tells the two apart.  So the question is not "does
    #   this file make calls" - which cannot be answered - but "was anything
    #   measured about this file at all", which can.
    #
    # Where the answer is no, nothing is claimed for the file:  no 'FNCF:'/
    #   'FNCH:' totals, and no caller deduced from an execution count
    #   (lcovutil::classify_callers).  Both of those read as measurements, and a
    #   "0 of 0 callees" invites the reader to conclude that the code makes no
    #   calls rather than that nothing was measured.  The cost of not claiming
    #   them is that a leaf unit which nothing in this report calls loses a zero
    #   it was entitled to, which is the cheaper of the two mistakes.
    my ($self, $calledSymbols) = @_;
    foreach my $key ($self->keylist()) {
        my $data = $self->findKey($key);
        return 1
            if 0 != $data->numCallSites() || $data->has_external_callees();
        foreach my $name ($data->aliasNames()) {
            return 1
                if $data->alias($name)->has_external_callers() ||
                (defined($calledSymbols) && exists($calledSymbols->{$name}));
        }
    }
    return 0;
}

sub _mergeExternalCalls($$)
{
    # fold the external calls one side of a merge recorded for an alias into
    #   the other side's copy of it - see FunctionAlias::add_external_calls
    my ($mine, $yours) = @_;
    return unless $yours->has_external_callers();
    my $calls = $yours->external_calls();
    $mine->add_external_calls(defined($calls) ? $calls : '-');
}

sub add_count
{
    my ($self, $fnName, $count) = @_;
    my $data = $self->findName($fnName);
    if (defined($data)) {
        $data->addAlias($fnName, $count);
    } else {
        lcovutil::ignorable_error($lcovutil::ERROR_MISMATCH,
                                  "unknown function '$fnName'");
    }
}

sub union
{
    my ($self, $that) = @_;

    my $changed = 0;
    foreach my $key ($that->keylist()) {
        my $thatData = $that->findKey($key);
        my $thisData = $self->findKey($key);
        if (!defined($thisData)) {
            $thisData =
                $self->define_function($thatData->name(),
                                       $thatData->line(),
                                       $thatData->end_line());
            $changed = 1;    # something new...
        } else {
            if (!($thisData->line() == $thatData->line()
                  && ($thisData->file() eq $thatData->file() ||
                      ($lcovutil::case_insensitive &&
                        lc($thisData->file()) eq lc($thatData->file())))
            )) {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                                          "function data mismatch at " .
                                              $thatData->file() . ":" .
                                              $thatData->line());
                next;
            }
        }
        # merge in all the new aliases
        foreach my $alias ($thatData->aliasNames()) {
            my $yours = $thatData->alias($alias);
            if ($thisData->addAlias($alias, $yours->count())) {
                $changed = 1;
            }
            # ..which my name index has to find as well:  define_function
            #   registered only the name it was asked for, and an alias known
            #   only to the entry is invisible to anything which looks a
            #   symbol up - the 'd' flag, the callee side of a call site
            $self->_registerName($alias, $thisData)
                unless defined($self->findName($alias));
            # ..and the two per-alias assertions, if that side made them:  they
            #   travel with the definition rather than with the run which
            #   captured it, which is what makes them correct under 'lcov -a' of
            #   captures taken separately.  Not 'changed':  neither is coverage
            #   data
            my $mine = $thisData->alias($alias);
            $mine->set_external() if $yours->is_external();
            _mergeExternalCalls($mine, $yours);
            # ..and the names merged into it, which either side may have done
            $mine->add_merged(%{$yours->merged() // {}});
        }
        # ..and the call sites, which are keyed by location within the file and
        #   so need no cross-file step of their own
        $changed = 1 if $thisData->unionCallSites($thatData);
        # ..and the per-function assertion, which travels with the definition for
        #   the same reason the per-alias ones do - see
        #   FunctionEntry::has_external_callees
        $thisData->set_external_callees() if $thatData->has_external_callees();
    }
    return $changed;
}

sub intersect
{
    my ($self, $that) = @_;

    my $changed = 0;
    foreach my $key ($self->keylist()) {
        my $me     = $self->findKey($key);
        my $yourFn = $that->findKey($key);
        if (defined($yourFn)) {
            # intersect operation:  keep only the common aliases
            my @remove;
            foreach my $alias ($me->aliasNames()) {
                my $yours = $yourFn->alias($alias);
                if (defined($yours)) {
                    if ($me->addAlias($alias, $yours->count())) {
                        $changed = 1;
                    }
                    # an alias which survives the intersection keeps what either
                    #   side knew about it - see FunctionMap::union
                    my $mine = $me->alias($alias);
                    $mine->set_external() if $yours->is_external();
                    _mergeExternalCalls($mine, $yours);
                    $mine->add_merged(%{$yours->merged() // {}});
                } else {
                    # remove this alias from me..
                    push(@remove, $alias);
                    $self->_unregisterName($alias);
                    $changed = 1;
                }
            }
            $changed = 1 if $me->intersectCallSites($yourFn);
            # a function which survives the intersection keeps what either side
            #   knew about it, as its aliases do just above
            $me->set_external_callees() if $yourFn->has_external_callees();
            if (!$me->removeAliases(@remove)) {
                # no aliases left (no common aliases) - so remove this function
                $self->_removeKey($key);
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

    my $changed = 0;
    foreach my $key ($self->keylist()) {
        my $you = $that->findKey($key);
        if (defined($you)) {
            # just remove the common aliases...
            my $me = $self->findKey($key);
            my @remove;
            foreach my $alias ($you->aliasNames()) {
                if (defined($me->alias($alias))) {
                    push(@remove, $alias);
                    $changed = 1;
                }
            }
            $changed = 1 if $me->subtractCallSites($you);
            if (!$me->removeAliases(@remove)) {
                # no aliases left (no disjoint aliases) - so remove this function
                $self->_removeKey($key);
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
    foreach my $alias ($entry->aliasNames()) {
        $self->_unregisterName($alias);
    }
    $self->_removeKey($entry->line());
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
    die("invalid counts: found:" .
        $self->[BranchMap::FOUND] .
        "->$found, hit:" .
        $self->[BranchMap::HIT] .
        "->$hit")
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
        my $myLocation;
        $myLocation = $mydata->{$line}
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
    die("invalid MC/DC counts: found:" .
        $self->[BranchMap::FOUND] .
        "->$found, hit:" .
        $self->[BranchMap::HIT] .
        "->$hit")
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
        my $conflict = $myBranch->incompatible_group($yourBranch);
        if (!defined($conflict)) {
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
            lcovutil::ignorable_error(
                        $lcovutil::ERROR_INCONSISTENT_DATA,
                        "$filename:" .
                            MCDC_Block::groupLine($line, $conflict) .
                            ": cannot merge inconsistent MC/DC record: group " .
                            (MCDC_Block::parseGroupKey($conflict))[0]);
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

            my $conflict = $myBranch->incompatible_group($yourBranch);
            if (!defined($conflict)) {
                # bracket the merge - see union() above
                my ($oldFound, $oldHit) = $myBranch->totals();
                my $changedHere = $myBranch->merge($yourBranch, $filename);
                my ($newFound, $newHit) = $myBranch->totals();
                $self->adjust_counts($newFound - $oldFound, $newHit - $oldHit);
                $changed = 1 if $changedHere;
            } else {
                lcovutil::ignorable_error(
                        $lcovutil::ERROR_INCONSISTENT_DATA,
                        "$filename:" .
                            MCDC_Block::groupLine($line, $conflict) .
                            ": cannot merge inconsistent MC/DC record: group " .
                            (MCDC_Block::parseGroupKey($conflict))[0]);
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
        # a message names the line the block is written at
        my $at = $line + $block->locationOffset();
        for (my $idx = 0; $idx <= $#$elements; ++$idx) {
            my $br = $elements->[$idx];
            next if $br->is_excluded();
            ++$nElems;
            if (defined($filter) && $br->is_exception()) {
                next
                    unless $br->set_excluded();
                $modified = 1;
                lcovutil::info(2, "$filename:$at: remove exception branch\n");
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
                           "$filename:$at: remove $count exception branch" .
                               (1 == $count ? '' : 'es') . "\n"
            ) if $isMasterData;
            $filter->[-1] += $count * $weight;
        }
        my $remaining = $nElems - $count;
        # If there is only one branch left - then this is not a conditional
        my $removed = 0;
        if (0 == $remaining) {
            lcovutil::info(2,
                           "$filename:$at: remove exception block $blkIdx\n");
            $brdata->removeBlock($block, $branches);
            $removed = 1;
        } elsif (1 == $remaining &&
                 defined($self->[ORPHAN_f])) {    # filter orphan
            lcovutil::info(2,
                      "$filename:$at: remove orphan exception block $blkIdx\n");
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
              VERSION        => 0,
              LOCATION       => 1,
              FILENAME       => 2,
              CHECKSUM       => 3,
              LINE_DATA      => 4,    # per-testcase data
              BRANCH_DATA    => 5,
              FUNCTION_DATA  => 6,
              MCDC_DATA      => 7,
              EXTERNAL_CALLS => 8,    # calls made from a function which was
                                      #   erased from this file - see
                                      #   noteExternalCalls below
              SPAN => 9,    # line coverpoint -> last line of its statement

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
    # line number -> the last line of the statement which the line coverpoint
    #   there counts, if that is not the line itself - see 'span'
    $self->[SPAN] = MapData->new();
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

sub callgraph_found
{
    # my own call sites - the caller-side view.  Deliberately not the number of
    #   my functions which have callers:  that one needs
    #   TraceFile::resolveCallSites to have run, so it is not a question a child
    #   process or a single file can answer
    my $self = shift;
    my ($found, $hit) = $self->func()->get_callgraph_found_and_hit();
    return $found;
}

sub callgraph_hit
{
    my $self = shift;
    my ($found, $hit) = $self->func()->get_callgraph_found_and_hit();
    return $hit;
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

# The statement spans:  MapData of line -> end line.  A line coverpoint counts
#   the statement which starts on its line and ends on its end line - see
#   'TraceFile::_continuationLineMerge'.  Only a statement which extends past
#   its first line has an entry.  The span is a property of the source, not
#   of a testcase, so there is one map for all testcases.
#   An entry whose line has no line coverpoint means nothing:  it is never
#   written, and 'spanOwners' ignores it.
sub span
{
    my $self = shift;
    return $self->[SPAN];
}

# The continuation lines of the statement spans:  hash of line -> the line of
#   the coverpoint whose statement it is part of
sub spanOwners
{
    my $self     = shift;
    my $span     = $self->[SPAN];
    my $lineData = $self->sum();
    my %owner;
    foreach my $line ($span->keylist()) {
        next unless defined($lineData->value($line));
        my $end = $span->value($line);
        $owner{$_} = $line foreach ($line + 1 .. $end);
    }
    return \%owner;
}

sub noteExternalCalls
{
    # Remember, as lcovutil::external_call records, the calls which were made from a
    #   function this file no longer has:  '--erase-functions' or a function
    #   filter took the caller out of the boundary of the report, and its call
    #   sites went with it, so the fact that those calls happened is recorded on
    #   their callees instead - see FunctionAlias::has_external_callers.
    # Held here rather than on the TraceFile because the erasing is done by
    #   'TraceFile::_filterFile', which runs in a forked child and hands back
    #   nothing but this object:  the list is drained into the TraceFile by
    #   '_updateModifiedFile', which is where the child's data arrives (and the
    #   only place this object is installed), so it is empty the rest of the time
    my ($self, $calls) = @_;
    push(@{$self->[EXTERNAL_CALLS]}, @$calls) if @$calls;
}

sub takeExternalCalls
{
    # the calls noted above, removed:  they belong to the report as a whole and
    #   the one place which can hold them for the whole report is the TraceFile
    my $self  = shift;
    my $calls = $self->[EXTERNAL_CALLS];
    $self->[EXTERNAL_CALLS] = undef;
    return defined($calls) ? $calls : [];
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
                                          $mine->value($line) . ' -> ' .
                                          $yours->value($line));
        }
        $mine->replace($line, $yours->value($line));
    }
}

# The statement spans of both:  the source is the same, so they agree - if they
#   do not, the source versions differ, and the span is dropped
sub _merge_spans
{
    my ($self, $info, $filename) = @_;

    my $mine  = $self->span();
    my $yours = $info->span();
    foreach my $line ($yours->keylist()) {
        my $end = $yours->value($line);
        if ($mine->mapped($line)) {
            next if $mine->value($line) == $end;
            lcovutil::ignorable_error(
                                $lcovutil::ERROR_INCONSISTENT_DATA,
                                "statement span mismatch at $filename:$line: " .
                                    "$line-" .
                                    $mine->value($line) .
                                    " -> $line-$end");
            $mine->remove($line);
            next;
        }
        $mine->replace($line, $end);
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

    # Which of the per-testcase maps to operate, and what to operate them
    #   against is different for 'union' vs 'intersect' or 'difference'
    #
    # For 'union': you drive:  a test only I hold needs no work, and a
    #   test only you hold has to be created and unioned here.
    #
    # For 'intersect' and 'difference':  I drive and operate against your
    #   summary rather than against a map of the same name.
    if ($op == UNION) {
        foreach my $name ($info->test()->keylist()) {
            if (&$countOp($self->test($name), $info->test($name))) {
                $changed = 1;
            }
        }
    } else {
        foreach my $name ($self->test()->keylist()) {
            if (&$countOp($self->test($name), $info->sum())) {
                $changed = 1;
            }
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
    $self->_merge_spans($info, $filename) if $op == UNION;

    if ($op == UNION) {
        foreach my $name ($info->testfnc()->keylist()) {
            if (&$funcOp($self->testfnc($name), $info->testfnc($name))) {
                $changed = 1;
            }
        }
    } else {
        foreach my $name ($self->testfnc()->keylist()) {
            if (&$funcOp($self->testfnc($name), $info->func())) {
                $changed = 1;
            }
        }
    }

    if ($op == UNION) {
        foreach my $name ($info->testbr()->keylist()) {
            if (&$brOp($self->testbr($name), $info->testbr($name), $filename)) {
                $changed = 1;
            }
        }
    } else {
        foreach my $name ($self->testbr()->keylist()) {
            if (&$brOp($self->testbr($name), $info->sumbr(), $filename)) {
                $changed = 1;
            }
        }
    }
    if (&$brOp($self->sumbr(), $info->sumbr(), $filename)) {
        $changed = 1;
    }

    if ($op == UNION) {
        foreach my $name ($info->testcase_mcdc()->keylist()) {
            my $mcdc = $self->testcase_mcdc($name);
            if (&$mcdcOp($mcdc, $info->testcase_mcdc($name), $filename)) {
                $changed = 1;
            }
        }
    } else {
        foreach my $name ($self->testcase_mcdc()->keylist()) {
            my $mcdc = $self->testcase_mcdc($name);
            if (&$mcdcOp($mcdc, $info->mcdc(), $filename)) {
                $changed = 1;
            }
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
              SPANS          => 5,    # see _pythonStatementSpan
              LANG           => 6,    # see _statementLanguage
              TEXT           => 7,    # see _spanLine
              STMT           => 8,    # see statementSpan

              # reasons: (bitfield)
              EXCLUDE_REGION           => 0x10,
              EXCLUDE_BRANCH_REGION    => 0x20,
              EXCLUDE_DIRECTIVE        => 0x40,
              OMIT_LINE                => 0x80,
              EXCLUDE_CALLGRAPH_REGION => 0x100,

              # recorded exclusion markers - outside the 0xFF0 of the reasons
              e_LINE        => 0x1,
              e_BRANCH      => 0x2,
              e_EXCEPTION   => 0x4,
              e_UNREACHABLE => 0x8,
              e_CALLGRAPH   => 0x1000,
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
    my $exclude_callgraph_region;
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
    my $excl_cg_start     = qr(\b$lcovutil::EXCL_CALLGRAPH_START\b);
    my $excl_cg_stop      = qr(\b$lcovutil::EXCL_CALLGRAPH_STOP\b);
    my $excl_cg_line      = qr(\b$lcovutil::EXCL_CALLGRAPH_LINE\b);
    # @todo:  if we had annotated data here, then we could whine at the
    #   author of the unmatched start, extra end, etc.

    my $exclude_directives;
    $exclude_directives =
        qr/^\s*#\s*((else|endif)|((ifdef|ifndef|if|elif|include|define|undef)\s+))/
        if (TraceFile::is_language(lcovutil::IS_C, $filename) &&
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
    if (defined($lcovutil::cov_filter[$lcovutil::FILTER_EXCLUDE_CALLGRAPH])) {
        # the call sites only:  the lines they are on, and every other
        #   coverpoint of those lines, stay
        push(@excludes,
             [$excl_cg_start,
              $excl_cg_stop,
              \$exclude_callgraph_region,
              e_CALLGRAPH | EXCLUDE_CALLGRAPH_REGION,
              $lcovutil::EXCL_CALLGRAPH_START,
              $lcovutil::EXCL_CALLGRAPH_STOP,
             ]);
    } else {
        $excl_cg_line = undef;
    }
    LINES: foreach (@$sourceLines) {
        $line += 1;
        my $exclude_branch_line           = 0;
        my $exclude_exception_branch_line = 0
            ; # per-line exception exclusion not implemented at present.  Probably unnecessary.
        chomp($_);
        s/\r//; # remove carriage return
                # independent of the line markers below:  a line may exclude its
                #   branches and its call sites both
        my $exclude_callgraph_line =
            (defined($excl_cg_line) && $_ =~ $excl_cg_line) ?
            e_CALLGRAPH | EXCLUDE_CALLGRAPH_REGION :
            0;

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
                lcovutil::ignorable_error(
                           $lcovutil::ERROR_MISMATCH,
                           "$filename: overlapping exclude directives. Found " .
                               $d->[4] .
                               " at line $line - but no matching " .
                               $d->[5] . ' for ' .
                               $d->[4] .
                               ' at line ' .
                               $$ref->[0]) if $$ref;
                $$ref = [$line, $reason, $d->[4], $d->[5]];
                last;
            } elsif ($_ =~ $stop) {
                lcovutil::ignorable_error(
                              $lcovutil::ERROR_MISMATCH,
                              "$filename: found " .
                                  $d->[5] .
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
                 ) | (
                  $exclude_callgraph_region ? $exclude_callgraph_region->[1] : 0
                 ) | $exclude_branch_line | $exclude_exception_branch_line |
                 $exclude_callgraph_line);
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
                   ],
                   [$exclude_callgraph_region,
                    $lcovutil::EXCL_CALLGRAPH_START,
                    $lcovutil::EXCL_CALLGRAPH_STOP
                   ]
    ) {
        my ($key, $start, $stop) = @$t;
        lcovutil::ignorable_error(
                                 $lcovutil::ERROR_MISMATCH,
                                 "$filename: unmatched $start at line " .
                                     $key->[0] .
                                     " - saw EOF while looking for matching $stop"
        ) if ($key);
    }
    my $data = $self->[0];
    $data->[FILENAME] = $filename;
    $data->[SOURCE]   = $sourceLines;
    $data->[EXCLUDE]  = \@excluded;
    $data->[SPANS]    = undef;
    $data->[LANG]     = undef;
    $data->[TEXT]     = [];
    $data->[STMT]     = [];
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
        # the end column is exclusive, as it is on a single line
        $expr .= substr($line, 0, $endCol - 1);
    }
    $expr =~ s/^\s+//;
    $expr =~ s/\s+$//;
    return $expr;
}

sub isOutOfRange
{
    my ($self, $lineNo, $context) = @_;
    # (optional) '$context' is the noun the messages below are built around:
    #   'getLine' does not pass one.
    $context = 'line' unless defined($context);
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
                $self->filename() .
                ": there are only " .
                scalar(@{$data->[EXCLUDE]}) .
                " lines in the file.";
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
                                       "unknown line '$lineNo' in " .
                                           $self->filename()
                                           .
                                           (
                                           defined($data->[EXCLUDE]) ?
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

# The text of a C/C++ or Java line, for '_spanText':  comments, strings and
#   character literals removed - so that a parenthesis or semicolon inside one
#   does not count - or undef if the line cannot be read that way:  a compiler
#   directive, a comment which spans lines, or a string which does (a raw
#   string literal, say)
sub _continuationText
{
    my ($self, $lineNo) = @_;
    my $code = $self->getLine($lineNo);
    return undef
        if !defined($code) || $code =~ /^\s*#/;
    $code =~ s/'(\\.|[^'\\])'//g;
    $code = lcovutil::filterStringsAndComments($code);
    return undef if $code =~ m#(/\*|\*/|")#;
    return $code;
}

# The statement which line 'lineNo' is part of, as '(first, last)' line
#   numbers - or the empty list if we are not sure.
#   This is what '_statementBranchMerge' attributes a branch or MC/DC
#   coverpoint on a line without a line coverpoint to, so it errs toward 'not
#   known':  a coverpoint left where it is costs a report line, while one moved
#   to the wrong statement is wrong data.
# A statement may extend at most 'filter_lookahead' lines on either side of
#   'lineNo'.
# The answer for each line is kept until the next file is read:  it depends
#   only on the source and on 'filter_lookahead'.
sub statementSpan
{
    my ($self, $lineNo) = @_;
    my $data = $self->[0];
    return ()
        unless (defined($data->[FILENAME]) &&
                $lineNo >= 1 &&
                $lineNo <= $self->numLines());
    my $span = $data->[STMT]->[$lineNo];
    unless (defined($span)) {
        my $lang = $self->_statementLanguage();
        $span = [$lang == lcovutil::IS_PYTHON ?
                     $self->_pythonStatementSpan($lineNo) :
                     $lang ? $self->_braceStatementSpan($lineNo, $lang) :
                     ()
        ];
        $data->[STMT]->[$lineNo] = $span;
    }
    return @$span;
}

# The language whose statements 'statementSpan' finds in the file:  the
#   'lcovutil::IS_*' flag of Python, C/C++, Java or Perl - the first the file is
#   in, in that order - or 0 if none of them
sub _statementLanguage
{
    my $self = shift;
    my $data = $self->[0];
    unless (defined($data->[LANG])) {
        my $flags = TraceFile::language($data->[FILENAME]);
        my ($lang) =
            grep({ $flags & $_ } (lcovutil::IS_PYTHON, lcovutil::IS_C,
                                  lcovutil::IS_JAVA, lcovutil::IS_PERL));
        $data->[LANG] = defined($lang) ? $lang : 0;
    }
    return $data->[LANG];
}

# Line 'lineNo' for '_braceStatementSpan', as [text, positions]:  the text
#   from '_spanText', and the positions in it of the characters which delimit
#   statements and groups - '(', ')', '[', ']', '{', '}' and ';' - in order.
#   Undef if '_spanText' cannot read the line.  Each line is read once per
#   file.
sub _spanLine
{
    my ($self, $lineNo, $lang) = @_;
    my $cache = $self->[0]->[TEXT];
    my $entry = $cache->[$lineNo];
    unless (defined($entry)) {
        my $code = $self->_spanText($lineNo, $lang);
        if (defined($code)) {
            my @positions;
            push(@positions, $-[0]) while ($code =~ /[()\[\]{};]/g);
            $entry = [$code, \@positions];
        } else {
            $entry = 0;
        }
        $cache->[$lineNo] = $entry;
    }
    return $entry ? $entry : undef;
}

# The text of a line for '_braceStatementSpan':  comments, strings and
#   character literals removed, or undef if the line cannot be read that way.
#   C/C++ and Java share '_continuationText'.  Perl is harder to read without
#   parsing it, so any line which may hold a construct this does not
#   understand - a quote-like operator, a regular expression, a heredoc, POD -
#   is not read at all.  In an XS file, the line of a section keyword
#   ('CODE:', 'OUTPUT:', etc.) ends the statement before it and is not part of
#   one itself.  A '/' is division (or '//', defined-or) only when it
#   follows an operand:  a variable, a number, ')', ']' or '}'.  A block which
#   is the first argument of 'sort', 'map' or 'grep' is part of the expression
#   if it ends on the same line.
sub _spanText
{
    my ($self, $lineNo, $lang) = @_;
    if ($lang != lcovutil::IS_PERL) {
        my $keyword =
            'CODE|PPCODE|INIT|PREINIT|INPUT|OUTPUT|CLEANUP|POSTCALL|ALIAS|' .
            'PROTOTYPES?|OVERLOAD|INTERFACE|INTERFACE_MACRO|C_ARGS|SCOPE|' .
            'FALLBACK|VERSIONCHECK|REQUIRE|BOOT|CASE';
        return '}'
            if ($self->filename() =~ /\.xs$/ &&
                $self->getLine($lineNo) =~ /^\s*($keyword)\s*:/);
        return $self->_continuationText($lineNo);
    }

    my $code = $self->getLine($lineNo);
    return undef if !defined($code);
    $code =~ s!((?:[\$\@\%]\w+|\b\d+|[)\]}])\s*)//?=?!$1 !g;
    return undef
        if ($code =~ /^(=\w|__END__|__DATA__)/ ||
          $code =~ m@(<<|=~|!~|/|\b(m|s|y|tr|q|qq|qw|qr|qx)\s*[^\s\w=,;)}>-])@);
    $code                 =~ s/'(\\.|[^'\\])*'//g;
    $code                 =~ s/"(\\.|[^"\\])*"//g;
    return undef if $code =~ /['"`]/;
    $code                 =~ s/\$#/\$/g;
    $code                 =~ s/#.*$//;
    # a subscript or a dereference is not a block
    1 while $code =~ s/([\w\}\]\$\@\%]|->)\s*\{[^{};]*\}/$1/;
    1 while $code =~ s/\b(sort|map|grep)(\s*\(?\s*)\{[^{};]*\}/$1$2/;
    return $code;
}

# The statement of a brace-delimited language (C/C++, Java, Perl) which line
#   'lineNo' is part of - see 'statementSpan'.  The statement starts after the
#   nearest ';', '{' or '}' before the line which is not inside a group of
#   parentheses or brackets, and ends at the next ';' or '{' outside one.  The
#   condition of an 'if', 'while', 'for', 'switch' or 'catch' is a statement of
#   its own in C/C++ and Java, where the body it controls need not be a block.
# Anything else is unknown:
#   - a line which '_spanText' cannot read
#   - a statement which shares a line with another one, other than the '}'
#     which closes the block before it ('} else if (...)')
#   - a brace or a ';' inside a group of parentheses (a lambda, a statement
#     expression), other than the ';'s of a 'for'
#   - a '}' before the end, as of an initializer list
#   - a 'case', a 'default' or a label
#   - a statement which runs out of the lookahead window
sub _braceStatementSpan
{
    my ($self, $lineNo, $lang) = @_;
    my $limit = $lcovutil::source_filter_lookahead;
    my $last  = $self->numLines();
    my $text  = sub {
        my $l = shift;
        return $l > $last ? undef : $self->_spanLine($l, $lang);
    };
    return () unless defined($text->($lineNo));

    # backward:  find the end of the previous statement
    my ($line, $col);    # where this statement starts
    my $close = 0;       # ')' or ']' not yet matched, scanning backward
    for (my $l = $lineNo - 1; $l >= 1; --$l) {
        # the end of the previous statement may be just outside the window
        return () if $lineNo - $l > $limit + 1;
        my $entry = $text->($l);
        return () unless defined($entry);
        my ($code, $positions) = @$entry;
        # the last ';', '{' or '}' on the line - unless it is inside a group
        #   opened to its left, such as a 'for' header
        my $end;
        foreach my $c (reverse(@$positions)) {
            my $char = substr($code, $c, 1);
            if ($char eq ')' || $char eq ']') {
                ++$close;
            } elsif ($char eq '(' || $char eq '[') {
                if ($close) {
                    --$close;
                } else {
                    $end = undef;
                }
            } elsif (!$close) {
                # ';', '{' or '}'
                $end = $c unless defined($end);
            }
        }
        next unless defined($end);
        if (substr($code, $end + 1) =~ /\S/) {
            # the statement starts on this line:  only after the closing
            #   brace of the block before it
            return ()
                unless (substr($code, $end, 1) eq '}' &&
                        substr($code, 0, $end) !~ /\S/);
            ($line, $col) = ($l, $end + 1);
        } else {
            ($line, $col) = ($l + 1, 0);
        }
        last;
    }
    ($line, $col) = (1, 0) unless defined($line);

    # forward:  find the end of this statement
    my $peel = $lang != lcovutil::IS_PERL;
    STATEMENT: while (1) {
        # the first word of the statement
        my ($code, $positions);
        while (1) {
            return () if $line - $lineNo > $limit;
            my $entry = $text->($line);
            return () unless defined($entry);
            ($code, $positions) = @$entry;
            last if substr($code, $col) =~ /\S/;
            ($line, $col) = ($line + 1, 0);
        }
        my $first = $line;
        return () if ($first > $lineNo || $lineNo - $first > $limit);
        my $rest = substr($code, $col);
        return ()
            if ($rest =~ /^\s*(case|default)\b/ ||
                $rest =~ /^\s*\w+\s*:(?!:)/);
        if ($peel && $rest =~ /^(\s*(else|do)\b)/) {
            # the statement it introduces starts after it
            $col += length($1);
            next STATEMENT;
        }
        my $header;
        $header = $2
            if ($peel && $rest =~ /^\s*((if|while|for|switch|catch)\s*\()/);
        my $depth = 0;
        while (1) {
            foreach my $c (@$positions) {
                next if $c < $col;
                my $char = substr($code, $c, 1);
                if ($char eq '(' || $char eq '[') {
                    ++$depth;
                } elsif ($char eq ')' || $char eq ']') {
                    # closes a group opened before the statement
                    return () unless $depth;
                    next if --$depth || !defined($header);
                    # the end of a condition
                    my $after = substr($code, $c + 1);
                    if ($lineNo <= $line) {
                        # ..and the line is part of it:  the line it ends on
                        #   may also open the block it controls
                        return () unless $after =~ /^\s*\{?\s*$/;
                        return ($first, $line);
                    }
                    # ..and the line is part of the statement it controls,
                    #   which may not share a line with it
                    return () if $after =~ /\S/;
                    ($line, $col) = ($line + 1, 0);
                    next STATEMENT;
                } elsif ($char eq ';') {
                    if ($depth) {
                        # only the 'for' header separates statements there
                        return ()
                            unless (defined($header) &&
                                    $header eq 'for' &&
                                    1 == $depth);
                        next;
                    }
                    return ()
                        if ($line < $lineNo ||
                            substr($code, $c + 1) =~ /\S/);
                    return ($first, $line);
                } elsif ($char eq '{') {
                    return ()
                        if ($depth ||
                            $line < $lineNo ||
                            substr($code, $c + 1) =~ /\S/);
                    return ($first, $line);
                } elsif ($char eq '}') {
                    return ();
                }
            }
            ($line, $col) = ($line + 1, 0);
            return () if $line - $lineNo > $limit;
            my $entry = $text->($line);
            return () unless defined($entry);
            ($code, $positions) = @$entry;
        }
    }
}

# The logical line of a Python source file which line 'lineNo' is part of -
#   see 'statementSpan'.  A logical line continues onto the next physical line
#   after a '\', or while a '(', '[' or '{' is open:  this is Python's own
#   rule, so this reads the file from the top rather than looking around
#   the line.  A logical line which holds a string spanning physical lines is
#   not known.
sub _pythonStatementSpan
{
    my ($self, $lineNo) = @_;
    my $data   = $self->[0];
    my $source = $data->[SOURCE];
    unless (defined($data->[SPANS])) {
        my @spans;
        my $depth = 0;
        my $quote;    # the delimiter of an open triple-quoted string
        my $start;
        my $tainted = 0;
        for (my $l = 1; $l <= scalar(@$source); ++$l) {
            my $code = $source->[$l - 1];
            $code =~ s/\r?\n$//;
            $start = $l unless defined($start);
            my $continued = 0;
            for (my $c = 0; $c < length($code); ++$c) {
                if (defined($quote)) {
                    $tainted = 1;
                    my $end = index($code, $quote, $c);
                    last if $end < 0;
                    $c     = $end + 2;
                    $quote = undef;
                    next;
                }
                my $char = substr($code, $c, 1);
                if ($char eq '#') {
                    last;
                } elsif ($char eq '\\' && $c == length($code) - 1) {
                    $continued = 1;
                } elsif ($char eq '"' || $char eq "'") {
                    if (substr($code, $c, 3) eq $char x 3) {
                        $quote = $char x 3;
                        $c += 2;
                        next;
                    }
                    # a string on one line
                    my $end = $c + 1;
                    while ($end < length($code)) {
                        my $e = substr($code, $end, 1);
                        last if $e eq $char;
                        ++$end if $e eq '\\';
                        ++$end;
                    }
                    $c = $end;
                } elsif ($char =~ /[(\[{]/) {
                    ++$depth;
                } elsif ($char =~ /[)\]}]/) {
                    --$depth if $depth;
                }
            }
            next if ($continued || $depth || defined($quote));
            my $span = $tainted ? undef : [$start, $l];
            $spans[$_] = $span foreach ($start .. $l);
            ($start, $tainted) = (undef, 0);
        }
        $data->[SPANS] = \@spans;
    }
    my $span = $data->[SPANS]->[$lineNo];
    return ()
        unless (defined($span) &&
                $lineNo - $span->[0] <= $lcovutil::source_filter_lookahead &&
                $span->[1] - $lineNo <= $lcovutil::source_filter_lookahead);
    return @$span;
}

# Does line 'lineNo' hold a lambda?  For '_lambdaOnLine', which has already
#   looked at the function data.  C/C++:  '[captures](params) {' or
#   '[captures](params) -> type {' - or '[captures] {', which has no parameter
#   list.  Java:  'param ->' or '(params) ->'
sub containsLambda
{
    my ($self, $lineNo) = @_;
    my $filename = $self->filename();
    return 0
        unless (defined($filename) &&
                $lineNo >= 1 &&
                $lineNo <= $self->numLines());
    my $code = lcovutil::filterStringsAndComments($self->getLine($lineNo));
    # C++:  '[captures](params) specifiers -> type {';  Java:  'params ->'
    my $lambda =
        TraceFile::is_language(lcovutil::IS_C, $filename) ?
        qr/(?<![\w\]\)])\[[^\[\]]*\]\s*(\([^()]*\))?\s*(\b(mutable|constexpr|noexcept)\b\s*)*(->[^{;]*)?\{/
        :
        TraceFile::is_language(lcovutil::IS_JAVA, $filename) ?
        qr/(\([^()]*\)|\b\w+)\s*->/ :
        undef;
    return defined($lambda) && $code =~ $lambda;
}

package TraceFile;

our $ignore_testcase_name;     # use default name, if set
our $callSitesResolved = 0;    # see resolveCallSites
# the most lines a statement span may extend past its first line - see
#   TraceInfo::span
use constant MAX_SPAN_OFFSET => 127;
use constant {
              FILES          => 0,
              COMMENTS       => 1,
              STATE          => 2,   # operations performed: don't do them again
              EXTERNAL_CALLS => 3,   # calls made from a file this report is not
                                     #   keeping - see noteExternalCalls

              DID_FILTER      => 1,
              DID_DERIVE      => 2,
              DID_CONSISTENCY => 4,    # see '_checkConsistency'
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
              REC_FNC     => 11,    # a call site: FunctionEntry::addCallSite
              REC_SUMMARY => 12,    # 'LF:', 'LH:', 'FNF:', ... - ignored
              REC_FNM     => 13,    # a merged name:  FunctionAlias::merged
              REC_SKIP    => 14,    # a cover type which is turned off
};

# The count records that a section must contain if it contains any data
#   records of the corresponding type - say, the BRH/BRF records associated
#   with a BRDA.
# Keep track and look for them - to verify that the .info file format is
#   what we expect.  Used for error checking.
my @sectionCountRecords = ([[REC_DA], 'line', 'LF', 'LH'],
                           [
                            [REC_FN, REC_FNDA, REC_FNL, REC_FNA, REC_FNM,
                             REC_SKIP + lcovutil::COVER_TYPE_FUNCTION
                            ],
                            'function',
                            'FNF', 'FNH'
                           ],
                           [[REC_BRDA, REC_SKIP + lcovutil::COVER_TYPE_BRANCH],
                            'branch',
                            'BRF',
                            'BRH'
                           ],
                           [[REC_MCDC, REC_SKIP + lcovutil::COVER_TYPE_MCDC],
                            'MC/DC', 'MCF', 'MCH'
                           ],
                           [
                            [REC_FNC, REC_SKIP + lcovutil::COVER_TYPE_CALLGRAPH
                            ],
                            'call site',
                            'FNCF', 'FNCH'
                           ],);

# REC_SKIP is not one case but four:  REC_SKIP plus the type's index in
#   '@lcovutil::coverTypeFound', so that '_read_info' can note that the data was
#   in the input without having to look the tag up a second time.  They are the
#   HIGHEST cases, which is what lets that test stay the one '>=' comparison a
#   skip has always cost.

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
       'FNM'  => REC_FNM,
       'BRDA' => REC_BRDA,
       'MCDC' => REC_MCDC,
       'FNC'  => REC_FNC,
       map({ ($_ => REC_SUMMARY) } qw(LF LH FNF FNH BRF BRH MCF MCH FNCF FNCH)),
);

# Which tags belong to which cover type - as the type's COVER_TYPE_ index,
#   which is both its slot in '@lcovutil::coverTypeFound' and the offset the
#   REC_SKIP redirection below uses.  The enable flag comes from that type's row
#   in '@lcovutil::coverType', so this table does not have to know which
#   variable holds it.
my %recordCoverType = ('FN'   => lcovutil::COVER_TYPE_FUNCTION,
                       'FNDA' => lcovutil::COVER_TYPE_FUNCTION,
                       'FNL'  => lcovutil::COVER_TYPE_FUNCTION,
                       'FNA'  => lcovutil::COVER_TYPE_FUNCTION,
                       'FNM'  => lcovutil::COVER_TYPE_FUNCTION,
                       'BRDA' => lcovutil::COVER_TYPE_BRANCH,
                       'MCDC' => lcovutil::COVER_TYPE_MCDC,
                       'FNC'  => lcovutil::COVER_TYPE_CALLGRAPH);

# The count records which say how many coverpoints of their cover type the
#   producer counted, as that type's index:  the inverse of the 'count' field of
#   '@lcovutil::coverType', so the types are named in one place.  These are
#   REC_SUMMARY records like every other count - what the report says about this
#   type is recomputed from the coverpoints and the number here does not survive
#   - and what is read out of them is the total over the inputs, which is a
#   statement about the inputs rather than about the report;  see
#   '@lcovutil::coverTypeInputTotal' and the REC_SUMMARY arm of '_read_info'.
my %recordDeclaresCoverType;
for (my $covType = 0; $covType < lcovutil::COVER_TYPE_COUNT; ++$covType) {
    my $tag = $lcovutil::coverType[$covType]->{count};
    $recordDeclaresCoverType{$tag} = $covType if defined($tag);
}

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

# Which cover type each ENABLED case belongs to, as an index into
#   '@lcovutil::coverTypeFound';  undef for a case which is not a coverpoint.
#    Indexed by case rather than keyed by tag so that noting the type costs
#   '_read_info' one array fetch instead of a second hash lookup.  A disabled
#   type does not appear:  its case is REC_SKIP plus the same index, which
#   the skip arm reads directly.  Built alongside '%recordDispatch'.
my @caseCoverType;

sub _init_record_dispatch()
{
    %recordDispatch = %recordCase;
    @caseCoverType  = ();
    while (my ($tag, $idx) = each(%recordCoverType)) {
        if (${$lcovutil::coverType[$idx]->{flag}}) {
            $caseCoverType[$recordCase{$tag}] = $idx;
        } else {
            $recordDispatch{$tag} = REC_SKIP + $idx;
        }
    }
}

sub load
{
    # '$chunk' is the part of the file to read rather than all of it - see
    #   '_read_info' and 'AggregateTraces::_partition_sections'
    # '$checkLater':  the data is to be merged with other data, which is
    #   checked for consistency then - see '_checkConsistency'
    my ($class, $tracefile, $readSource, $verify_checksum,
        $ignore_function_exclusions, $chunk, $checkLater)
        = @_;
    my $self    = $class->new();
    my $context = MessageContext->new("loading $tracefile");

    $self->_read_info($tracefile, $readSource, $verify_checksum, $chunk);

    $self->[STATE] |= DID_CONSISTENCY if $checkLater;
    $self->applyFilters($readSource);
    $self->[STATE] &= ~DID_CONSISTENCY if $checkLater;
    return $self;
}

sub new
{
    my $class = shift;
    my $self  = [{}, [], 0, []];
    bless $self, $class;

    return $self;
}

sub serialize
{
    my ($self, $filename) = @_;

    # A resolved report holds references from one file's function data into
    #   another's, so it must not be handed across a fork:  Storable would
    #   follow them and the worker would send back a copy of half the report.
    #   The caller-side data is the wire format precisely so that this is never
    #   needed - see resolveCallSites, which must run in the parent, after the
    #   last worker has been reaped
    die("internal error: call sites were resolved before serialization")
        if $callSitesResolved;
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

    return !keys(%{$self->[FILES]});
}

sub checkEnabledMetric
{
    # This cover type is enabled and this report has no corresponding
    #   coverpoints:  the ERROR_EMPTY counterpart of 'lcovutil::reject_metric',
    #   which says the same thing about a type the tool can never produce.
    # Everything which differs between the types - the predicate, the
    #   message and whether ignoring the message turns the metric off - is
    #   held by the corresponding row in '@lcovutil::coverType'.
    # Emit the message at most once per run:  a run can reach here more than
    #   once, and for a type whose row says 'disable' the flag it clears makes
    #   the second call a no-op anyway.
    # '$totals' is 'count_totals's list, when the caller has one already:  see
    #   checkEmpty, which shares one across the types.
    my ($self, $covType, $totals) = @_;
    my $row = $lcovutil::coverType[$covType];

    return unless ${$row->{flag}};
    defined($totals) or $totals = [$self->count_totals()];
    return if $row->{have}->($self, $totals);
    # Nothing of this type here - but if the inputs counted this type's
    #   coverpoints and their counts sum to zero, that absence is what was
    #   measured:  a file containing only straight-line code and no branches
    #   Then the summary saying 'no data found' is the whole of the
    #   answer and there is no error to raise.
    # A total which is not zero is the opposite:  the coverpoints were in the
    #   input and are not in the report, so this run's filters or patterns
    #   removed every one of them - likely not what the user expected.
    return if $row->{count} && lcovutil::inputCountedNone($covType);
    lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
        $row->{empty} ||
            "$row->{name} coverage enabled but no corresponding coverpoints found."
    ) if lcovutil::warn_once($lcovutil::ERROR_EMPTY, "type:$row->{name}");
    ${$row->{flag}} = 0 if $row->{disable};
}

sub checkEmpty
{
    # Complain about:
    #   - no coverpoints of some covtype which was enabled on the command line
    #     (user thought something was here - but nothing is)
    #   - input files contain covtype data but type was not enabled
    #     (user might not have set an enable flag that was intended)
    # Checks have to be done after all the .info files have been read
    # and filtered.
    # Emit message at most once per run - a run can reach here more than once
    my $self = shift;

    lcovutil::ignorable_error($lcovutil::ERROR_EMPTY, "coverage DB is empty")
        if ($self->empty() &&
            lcovutil::warn_once($lcovutil::ERROR_EMPTY, 'emptyDB'));

    # count_totals() builds its whole list whether or not the corresponding
    #   metric is enabled, so a slot does not move when another metric is off -
    #   which is what lets the 'have' callbacks index it.  Built once here, for
    #   all of the types.
    my $totals = [$self->count_totals()];
    my @notes;
    for (my $covType = 0; $covType < lcovutil::COVER_TYPE_COUNT; ++$covType) {
        my $row = $lcovutil::coverType[$covType];
        if (${$row->{flag}}) {
            $self->checkEnabledMetric($covType, $totals);
        } elsif ($lcovutil::coverTypeFound[$covType] &&
                 lcovutil::warn_once('coverTypeNote', $covType)) {
            # we have records of a type which is not enabled - possible that
            #   the user forgot to add the flag
            push(@notes,
                "Note: $row->{name} records were found in the input data, but"
                    . " $row->{name} coverage is not enabled\n"
                    . "\t- '$row->{option}' may be missing from the command line.\n"
            );
        }
    }
    # now print the type notes, if there were any
    lcovutil::info(join('', @notes));
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
    # This answers a layout question - genhtml asks it to find out whether a
    #   '--prefix' names a directory which holds sources rather than one which
    #   holds directories - so the directory is the one the report will build,
    #   which is not the leading part of a name spelled for the other platform.
    #   See 'lcovutil::native_path';  the file names in the lists are the names
    #   as read, which is what the data is keyed by
    my %dirs;
    foreach my $f ($self->files()) {
        my $d = File::Basename::dirname(lcovutil::native_path($f));
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
    # return list of (number files, [#lines, #hit], [#branches, #hit],
    #   [#functions,#hit], [#conditions, #hit], [#call sites, #hit])
    my @data = (0, [0, 0], [0, 0], [0, 0], [0, 0], [0, 0]);
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
        if ($lcovutil::callgraph_coverage) {
            $data[5]->[0] += $entry->callgraph_found();    # call sites
            $data[5]->[1] += $entry->callgraph_hit();
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
    my @metrics = ('line', 'branch', 'condition', 'function');
    # ..and the callee counts only when the metric is on:  unlike the four above,
    #   a report which was not asked for call data has none, so an unconditional
    #   0/0 entry would tell the callback about a metric which does not exist
    if ($lcovutil::callgraph_coverage) {
        $total{'callgraph'} = {
                               'found' => 0,
                               'hit'   => 0
        };
        push(@metrics, 'callgraph');
    }
    my %data;
    foreach my $filename ($self->files()) {
        my $entry = $self->data($filename);
        my @data = ($entry->found(), $entry->hit(),
                    $entry->branch_found(), $entry->branch_hit(),
                    $entry->mcdc_found(), $entry->mcdc_hit(),
                    $entry->function_found(), $entry->function_hit());
        push(@data, $entry->callgraph_found(), $entry->callgraph_hit())
            if $lcovutil::callgraph_coverage;
        my $idx = 0;
        foreach my $t (@metrics) {
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
# print_summary(fn_do, br_do, mcdc_do, callgraph_do)
#
# Print overall coverage rates for the specified coverage types.
#   $countDat is the array returned by 'TraceFile->count_totals()'

sub print_summary
{
    my ($self, $fn_do, $br_do, $mcdc_do, $callgraph_do) = @_;

    $br_do        = $lcovutil::br_coverage        unless defined($br_do);
    $mcdc_do      = $lcovutil::mcdc_coverage      unless defined($mcdc_do);
    $fn_do        = $lcovutil::func_coverage      unless defined($fn_do);
    $callgraph_do = $lcovutil::callgraph_coverage unless defined($callgraph_do);
    my @counts = $self->count_totals();
    # which of the optional metrics the caller asked for, in '@coverType' order
    my @enabled;
    $enabled[lcovutil::COVER_TYPE_FUNCTION]  = $fn_do;
    $enabled[lcovutil::COVER_TYPE_BRANCH]    = $br_do;
    $enabled[lcovutil::COVER_TYPE_MCDC]      = $mcdc_do;
    $enabled[lcovutil::COVER_TYPE_CALLGRAPH] = $callgraph_do;

    lcovutil::info("Summary coverage rate:\n");
    lcovutil::info("  source files: %d\n", $counts[0]);
    # line coverage is the one metric which cannot be turned off, so it is not in
    #   '@coverType' and is printed here rather than in the loop
    lcovutil::info("%s\n",
                   lcovutil::summaryRow('line', $counts[1]->[0],
                                        $counts[1]->[1]));
    foreach my $covType (0 .. lcovutil::COVER_TYPE_COUNT - 1) {
        next unless $enabled[$covType];
        my $row   = $lcovutil::coverType[$covType];
        my $total = $counts[$row->{total}];
        lcovutil::info("%s\n",
                       lcovutil::summaryRow(
                                          $row->{name}, $total->[0], $total->[1]
                       ));
    }
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

sub _noteCallsFrom
{
    # Note every call made from a site in '$filename', for noteExternalCalls:
    #   the file is about to go away, and its call sites are the only record that
    #   those edges are there.  Taken or not:  the flag the note ends up setting
    #   says that the edge exists, and carries the site's count
    my ($self, $filename) = @_;

    my @calls;
    my $functionMap = $self->data($filename)->func();
    my $testfnc     = $self->data($filename)->testfnc();
    foreach my $key ($functionMap->keylist()) {
        my $entry = $functionMap->findKey($key);
        foreach my $site ($entry->callSiteKeys()) {
            my (undef, undef, undef, $count, $callee) =
                $entry->callSiteData($site);
            # A call to a name this same file defines went to that definition -
            #   the rule _resolveCallee decides every site by - and that
            #   definition is going away with the site:  there is no surviving
            #   callee for the call to be a fact about.  Left unnoted rather
            #   than resolved later, when the file is gone and an unrelated
            #   definition of the name elsewhere would answer for it
            push(@calls,
                 lcovutil::external_call(
                               $filename, $callee, $count, $testfnc, $key, $site
                 )) unless defined($functionMap->findName($callee));
        }
    }
    $self->noteExternalCalls(\@calls);
}

sub remove
{
    my ($self, $filename) = @_;
    $filename = lc($filename) if $lcovutil::case_insensitive;
    $self->file_exists($filename) or
        die("remove nonexistent file $filename");
    # This file's calls outlive it, on their callees - see noteExternalCalls.
    #   Before the delete, which is the last moment its call sites exist
    $self->_noteCallsFrom($filename) if $lcovutil::callgraph_coverage;
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
    # the result has been checked if both sides have been - or if I am empty
    #   and you have been - and no file is in both:  its merged data is new
    my $checked = (!%$mine || 0 != ($self->[STATE] & DID_CONSISTENCY)) &&
        0 != ($trace->[STATE] & DID_CONSISTENCY);
    foreach my $filename (keys %$mine) {
        if (exists($yours->{$filename})) {
            $checked = 0;
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
    if ($checked) {
        $self->[STATE] |= DID_CONSISTENCY;
    } else {
        $self->[STATE] &= ~DID_CONSISTENCY;
    }
    $self->add_comments($trace->comments());
    # ..and the calls whose sites that side no longer has:  a callee of one of
    #   them may be a file only I have - see noteExternalCalls.  Kept for both
    #   operations:  the call was made, whether or not this operation is keeping
    #   the file it was made from
    $self->noteExternalCalls($trace->[EXTERNAL_CALLS]);
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

sub _noteErasedCalls
{
    # The calls made by a function which is about to be erased, as the
    #   lcovutil::external_call records TraceInfo::noteExternalCalls takes:  its call sites
    #   go with it, and they are the only record that those edges are there.
    # Every site, taken or not, which is the rule TraceFile::_noteCallsFrom
    #   applies to the same question for the same reason:  the flag this ends up
    #   setting says that the edge exists, and carries the site's count
    # '$testfnc' is the per-testcase function data, which still has the
    #   function:  the master pass runs first (see _eraseFunctions)
    my ($calls, $fcn, $source_file, $testfnc, $key) = @_;
    foreach my $site ($fcn->callSiteKeys()) {
        my (undef, undef, undef, $count, $callee) = $fcn->callSiteData($site);
        push(@$calls,
             lcovutil::external_call($source_file, $callee, $count,
                                     $testfnc, $key, $site));
    }
}

sub _isDestructor($)
{
    # does this callee name look like a destructor - demangled ('Foo::~Foo()'),
    #   Itanium-mangled ('_ZN3FooD1Ev' and the D0/D2 variants) or MSVC ('??1Foo@@')
    my $name = shift;
    return $name =~ /(^|::)~/ ||
        $name =~ /^_Z.*D[0-5]Ev$/ ||
        $name =~ /^\?\?1/;
}

sub _filterBraceCallSites
{
    # The 'brace' filter on a closing brace which has call sites on it - which
    #   the per-testcase line loop of _filterFile leaves alone, because a line
    #   with a coverpoint of another kind is not one it may suppress.  The calls
    #   made on a line which is nothing but a closing brace are mostly the
    #   destructors of the objects which go out of scope there (and their
    #   unwind copies), and only those count here.  Whatever else a compiler
    #   keys to the brace - '_Unwind_Resume', '__cxa_end_catch' at the end of a
    #   'catch', '__stack_chk_fail', '__cyg_profile_func_exit', sanitizer
    #   calls - neither triggers nor blocks a rule:  many of those are normally
    #   never made, so their zero says nothing about the scope.  A closing
    #   brace with a zero count, whose preceding executable line was hit, and
    #   which has at least one destructor call:
    #   - if any of its destructor calls was taken, the line was executed:  its
    #     count becomes the smallest non-zero count among those calls
    #   - if none was taken, the line is removed - with every call site on it -
    #     provided that every other line of the function was executed:  every
    #     constructor was then called too, so the destructors should have been,
    #     and were probably missed because an object was constructed in place.
    #     The other lines which this rule is judging are not held against it,
    #     so that two nested scopes do not block each other.  A function whose
    #     end line is not known is not judged, and neither is a line where a
    #     destructor call's count is not known ('-')
    #   A closing brace whose only calls are to non-destructors is judged by the
    #     rules for a brace with no call site at all - suppressCloseBrace - and
    #     loses its call sites along with the line.
    # Decided on the summary rather than per testcase, as the line loop does:  a
    #   line is either in the report or not, whatever any one testcase says, and
    #   the summary is what says whether a destructor ran at all.  A count which
    #   is adjusted is adjusted in each testcase from that testcase's own call
    #   counts, and the summary is their sum.  Removed call sites are recorded
    #   on their callees, as every other removal of a site is
    # Returns true if anything changed
    my ($srcReader, $source_file, $traceInfo, $aliased, $brace) = @_;
    my ($testdata, $sumcount, $funcdata, $checkdata,
        $testfncdata, $testbrdata, $sumbrcount, $mcdc) = $traceInfo->get_info();
    return 0 unless defined($funcdata) && defined($sumcount);

    # the sites of each line of this file:  [function key, site key, count,
    #   callee, function entry] - from the summary, which holds the merged count
    my %sites;
    foreach my $key ($funcdata->keylist()) {
        my $entry = $funcdata->findKey($key);
        foreach my $site ($entry->callSiteKeys()) {
            my ($line, undef, undef, $count, $callee, $file) =
                $entry->callSiteData($site);
            next if defined($file);
            push(@{$sites{$line}}, [$key, $site, $count, $callee, $entry]);
        }
    }
    my %action;    # line => 'adjust', 'missed' or 'plain'
    my %destructors;
    foreach my $line (keys(%sites)) {
        my $count = $sumcount->value($line);
        next
            unless defined($count) &&
            $srcReader->isCharacter($line, '}') &&
            0 == $srcReader->isExcluded($line);
        next
            if (defined($sumbrcount) && defined($sumbrcount->value($line))) ||
            (defined($mcdc) && defined($mcdc->value($line)));
        my @dtor = grep({ _isDestructor($_->[3]) } @{$sites{$line}});
        if (!@dtor) {
            $action{$line} = 'plain'
                if $srcReader->suppressCloseBrace($line, $count, $sumcount);
            next;
        }
        next unless $count == 0;
        my $prev;
        for (my $l = $line - 1; $l > 0 && !defined($prev); --$l) {
            $prev = $sumcount->value($l);
        }
        next unless defined($prev) && $prev > 0;
        $destructors{$line} = \@dtor;
        if (grep({ lcovutil::site_count_hit($_->[2]) } @dtor)) {
            $action{$line} = 'adjust';
        } elsif (!grep({ $_->[2] eq '-' } @dtor)) {
            $action{$line} = 'missed';
        }
    }
    # ..a destructor call which was missed is only forgiven in a function all
    #   of whose other lines ran
    foreach my $line (grep({ $action{$_} eq 'missed' } keys(%action))) {
        foreach my $s (@{$destructors{$line}}) {
            my $entry = $s->[4];
            my ($first, $last) = ($entry->line(), $entry->end_line());
            my @missed;
            @missed = grep(
                       { $_ >= $first &&
                               $_ <= $last &&
                               !exists($action{$_}) &&
                               0 == $sumcount->value($_) } $sumcount->keylist())
                if defined($last);
            if (!defined($last) || @missed) {
                delete($action{$line});
                last;
            }
        }
    }
    return 0 unless %action;

    my @removedCalls;
    foreach my $line (sort({ $a <=> $b } keys(%action))) {
        lcovutil::info(2,
                       "filter DA (" .
                           $brace->[0] . ") '" .
                           $srcReader->getLine($line) .
                           "' $source_file:$line ($action{$line})\n");
        ++$brace->[-2];    # one location where this applied
        ++$brace->[-1];    # one coverpoint:  the line
        if ('adjust' eq $action{$line}) {
            my $total = 0;
            foreach my $tn ($testdata->keylist()) {
                my $d = $testdata->value($tn);
                next unless defined($d->value($line));
                my $map = $testfncdata->value($tn);
                my $min;
                foreach my $s (@{$destructors{$line}}) {
                    my $f = defined($map) ? $map->findKey($s->[0]) : undef;
                    next unless defined($f);
                    my (undef, undef, undef, $c) = $f->callSiteData($s->[1]);
                    next unless defined($c) && lcovutil::site_count_hit($c);
                    $min = $c if !defined($min) || $c < $min;
                }
                next unless defined($min);
                $d->remove($line);
                $d->append($line, $min, 1);
                $total = lcovutil::add_count($total, $min);
            }
            unless ($aliased->{TraceInfo::LINE_DATA}) {
                $sumcount->remove($line);
                $sumcount->append($line, $total, 1);
            }
            next;
        }
        # the line goes, and every call on it:  recorded on the callees first,
        #   while the sites are still there to be read
        foreach my $s (@{$sites{$line}}) {
            my ($key, $site, $count, $callee) = @$s;
            push(@removedCalls,
                 lcovutil::external_call($source_file, $callee, $count,
                                         $testfncdata, $key, $site));
            ++$brace->[-1];    # ..and one per call site
            foreach my $tn ($testfncdata->keylist()) {
                my $f = $testfncdata->value($tn)->findKey($key);
                $f->_removeSite($site) if $f;
            }
            unless ($aliased->{TraceInfo::FUNCTION_DATA}) {
                my $f = $funcdata->findKey($key);
                $f->_removeSite($site) if $f;
            }
        }
        foreach my $tn ($testdata->keylist()) {
            $testdata->value($tn)->remove($line, 1);    # remove if present
        }
        $sumcount->remove($line) unless $aliased->{TraceInfo::LINE_DATA};
        $checkdata->remove($line) if $checkdata->mapped($line);
    }
    $traceInfo->noteExternalCalls(\@removedCalls) if @removedCalls;
    return 1;
}

sub _eraseFunctions
{
    my ($source_file, $srcReader, $functionMap, $lineData,
        $branchData, $mcdcData, $checksum, $state,
        $isMasterList, $externalCalls, $testfnc) = @_;

    my $modified      = 0;
    my $removeTrivial = $cov_filter[$FILTER_TRIVIAL_FUNCTION];
    # A function erased here leaves the boundary of the report, and the callees
    #   it called - which have not left it - are told that they have a caller
    #   outside it:  the '--erase-functions' case of
    #   FunctionAlias::has_external_callers, and the same answer removing the
    #   whole file would have given (TraceFile::remove).  Master pass only:  the
    #   per-testcase maps hold the same sites and would record every call again.
    # '%wasLocal' is the set of names this file defined BEFORE anything was
    #   erased, which is what tells a call to a function which survives from a
    #   call to a local definition which is being erased as well:  there the
    #   callee is gone too, so there is nothing for the call to be a fact about,
    #   and an unrelated definition of the same name in another file must not
    #   answer for it
    my $noteCalls = $lcovutil::callgraph_coverage &&
        $isMasterList &&
        defined($externalCalls);
    my @erasedCalls;
    my %wasLocal;
    %wasLocal = map({ ($_ => 1) } $functionMap->list_functions()) if $noteCalls;
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
               is_language(lcovutil::IS_C, $source_file) &&
               (defined($srcReader) &&
                $srcReader->containsTrivialFunction($fcn->line(), $end_line))
        ) {
            # remove single-line functions which has no body
            # Only count what we removed from the top level/master list -
            #   - otherwise, we double count for every testcase.
            ++$removeTrivial->[-2] if $isMasterList;
            # before the erasing, which is the last moment the sites exist - and
            #   once for the whole entry, which is what each alias of it removes
            _noteErasedCalls(\@erasedCalls, $fcn, $source_file, $testfnc, $key)
                if $noteCalls;
            foreach my $alias ($fcn->aliasNames()) {
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
            foreach my $alias ($fcn->aliasNames()) {
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
                                      ":$end_line] due to '" .
                                      $p->[-2] . "'\n");
                    }
                    _noteErasedCalls(\@erasedCalls, $fcn, $source_file,
                                     $testfnc, $key)
                        if $noteCalls;
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
         # ..and now that the erasing is done, the calls whose callee outlived
         #   the caller - see '%wasLocal' above
    push(@$externalCalls,
         grep(
             { !$wasLocal{$_->[1]} || defined($functionMap->findName($_->[1])) }
             @erasedCalls)) if @erasedCalls;
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
                        '"' .
                            $traceInfo->filename() .
                            "\":$first:  function " .
                            $func->name() .
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
                            '"' .
                                $traceInfo->filename() .
                                "\":$first:  function " .
                                $func->name() .
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
                    '"' .
                        $traceInfo->filename() .
                        "\":$first:  function " .
                        $func->name() .
                        " found on line but no corresponding 'line' coverage data point.  Cannot derive function end line."
                        . $suffix);

                # last FUNC; # quit looking here - all the other functions after this one will have same issue
                next FUNC;    # warn about them all
            }
            lcovutil::info(1,
                           '"' .
                               $traceInfo->filename() .
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
            lcovutil::ignorable_error(
                                  $lcovutil::ERROR_INCONSISTENT_DATA,
                                  '"' .
                                      $func->filename() . '":' .
                                      $func->line() .
                                      ': failed to set end line for function ' .
                                      $func->name() . '.' .
                                      $suffix);
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
                                             '"' .
                                                 $func->file() . '":' .
                                                 $first .
                                                 ': function \'' .
                                                 $func->name() .
                                                 ' last line is ' .
                                                 $func->end_line() .
                                                 ' but is ' .
                                                 $f->end_line() .
                                                 " in testcase '$tn'");
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
        $f->set_hit($count);

        # and mark that each alias was hit...
        foreach my $alias ($f->aliasNames()) {
            my $data = $f->alias($alias);
            $data->set_count($data->count() + $count);
        }
    }
}

# The source of the file a consistency check, if it can be had:
#   'srcReader' itself if that is the file it holds already, else 'srcReader'
#   opened on the file - or undef if the file is not there to be read
sub _consistencySource
{
    my ($traceInfo, $srcReader) = @_;
    return undef unless defined($srcReader);
    my $filename = $traceInfo->filename();
    return $srcReader
        if ($srcReader->notEmpty() &&
            $srcReader->filename() eq $filename);
    return undef
        unless ($srcReader->isRecoveredBaselineFile($filename) ||
                -e ReadCurrentSource::resolve_path($filename));
    return $srcReader->open($filename) ? $srcReader : undef;
}

# Is the branch/line consistency check of line 'line' suppressed, because
#   'ignore_lambda_consistency' is enabled and the line holds a lambda?  A
#   lambda's body may be on the line which defines it, so the line's count and
#   the counts of the branches on it need not be about the same code.
#   C/C++ and Java only:  the lambda is found by the name of a function which
#   starts on the line, or else in the source of the line
sub _lambdaSuppressed
{
    my ($traceInfo, $srcReader, $line) = @_;
    return 0 unless $lcovutil::ignore_lambda_consistency;
    my $filename = $traceInfo->filename();
    my $lang     = language($filename);
    return 0 unless ($lang & (lcovutil::IS_C | lcovutil::IS_JAVA));

    my $found = 0;
    my $func  = $traceInfo->func()->findKey($line);
    if (defined($func)) {
        $found = $func->isLambda()
            ||
            grep({ ($lang & lcovutil::IS_C) ?
                         ($_ =~ /\{lambda\(/ || $_ =~ /^_Z.*Ul\w*?E\d*_/) :
                         $_ =~ /\.lambda\$/ } $func->aliasNames());
    }
    unless ($found) {
        my $reader = _consistencySource($traceInfo, $srcReader);
        $found = defined($reader) && $reader->containsLambda($line);
    }
    return 0 unless $found;
    lcovutil::info(1,
        "\"$filename\":$line: lambda detected, consistency check suppressed\n");
    return 1;
}

# move the branch data of line 'from' of BranchData 'map' to line 'to', after
#   any branch blocks already there
sub _moveBranches
{
    # each block remembers the line it is written at - see
    #   BranchBlock::locationOffset
    my ($map, $from, $to) = @_;
    my $location = $map->value($from);
    return unless defined($location);
    # copies:  the blocks belong to the location they are removed with
    my @blocks = map({ Storable::dclone($_) } $location->blocks());
    my ($found, $hit) = $location->totals();
    $map->remove($from);
    foreach my $block (@blocks) {
        $block->setLocationOffset($from + $block->locationOffset() - $to);
        $map->insertBlock($block, $to);
    }
    $map->adjust_counts($found, $hit);
}

# Can the branch and MC/DC data of line 'from' of the BranchData and MCDC_Data
#   in 'maps' be moved to line 'to', so that each block still knows the line it
#   is written at?  See BranchBlock::MAX_LOCATION_OFFSET
sub _locationsFit
{
    my ($from, $to, @maps) = @_;
    foreach my $map (@maps) {
        next unless defined($map);
        my $data = $map->value($from);
        next unless defined($data);
        my @offsets =
            'BranchLocation' eq ref($data) ?
            map({ $_->locationOffset() } $data->blocks()) :
            $data->locationOffsets();
        foreach my $offset (@offsets) {
            return 0
                if abs($from + $offset - $to) >
                BranchBlock::MAX_LOCATION_OFFSET;
        }
    }
    return 1;
}

# move the MC/DC data of line 'from' of MCDC_Data 'map' to line 'to'.  Each
#   group keeps the line it is written at - see MCDC_Block::groupKey - so it
#   is merged only into a group of line 'to' of the same size and location
sub _moveMCDC
{
    my ($traceInfo, $map, $from, $to) = @_;
    my $block = $map->value($from);
    return unless defined($block);
    # read everything before the block is removed with its line
    my @expr;
    my $groups = $block->groups();
    foreach my $key (sort keys(%$groups)) {
        my ($size, $offset) = MCDC_Block::parseGroupKey($key);
        my $moved = MCDC_Block::groupKey($size, $from + $offset - $to);
        foreach my $e (@{$groups->{$key}}) {
            push(@expr,
                 [$moved, $_,
                  $e->count($_), $e->index(),
                  $e->expression(), $e->is_excluded($_)
                 ]) foreach (0, 1);
        }
    }
    $map->remove($from);
    my $target = $map->new_mcdc($traceInfo, $to);
    my ($oldFound, $oldHit) = $target->totals();
    my $filename = $traceInfo->filename();
    foreach my $e (@expr) {
        my ($size, $sense, $count, $idx, $text, $excluded) = @$e;
        $target->insertExpr($filename, $size, $sense, $count,
                            $idx, $text, $excluded);
    }
    my ($found, $hit) = $target->totals();
    $map->adjust_counts($found - $oldFound, $hit - $oldHit);
}

# The lines of the statement 'first'..'last' cannot be distinguished if one of
#   them is excluded ('flags':  see 'ReadCurrentSource::isExcluded'), or may
#   start or end an exclusion:  the filters which apply exclusions may not have
#   read the source yet
sub _statementExcluded
{
    my ($reader, $first, $last, $flags) = @_;
    my $markers = join('|',
                       map({ quotemeta($_) } $lcovutil::EXCL_START,
                           $lcovutil::EXCL_STOP,
                           $lcovutil::EXCL_LINE,
                           $lcovutil::EXCL_BR_START,
                           $lcovutil::EXCL_BR_STOP,
                           $lcovutil::EXCL_BR_LINE,
                           $lcovutil::EXCL_EXCEPTION_BR_START,
                           $lcovutil::EXCL_EXCEPTION_BR_STOP,
                           $lcovutil::EXCL_EXCEPTION_LINE,
                           $lcovutil::UNREACHABLE_START,
                           $lcovutil::UNREACHABLE_STOP,
                           $lcovutil::UNREACHABLE_LINE));
    for (my $l = $first; $l <= $last; ++$l) {
        return 1
            if ($reader->isExcluded($l, $flags) ||
                $reader->getLine($l) =~ /\b($markers)\b/);
    }
    return 0;
}

# Can a continuation line with count $count be merged into an anchor with
#   count $anchor (which may be undef)?  Yes if the line is not hit, or if both
#   are hit and the line no more often than the anchor
sub _continuationMergeable
{
    my ($count, $anchor) = @_;
    return !$count || ($anchor && $count <= $anchor);
}

# move the line coverpoint at line 'from' of 'traceInfo' to line 'to' - in the
#   summary and in each testcase, which may be the same map - with its checksum
sub _moveLine
{
    my ($traceInfo, $reader, $from, $to) = @_;
    my $sum      = $traceInfo->sum();
    my $sumAddr  = Scalar::Util::refaddr($sum);
    my $testcase = $traceInfo->test();
    foreach my $map ((grep({ Scalar::Util::refaddr($_) != $sumAddr }
                           map({ $testcase->value($_) } $testcase->keylist())),
                      $sum
    )) {
        my $count = $map->value($from);
        next unless defined($count);
        $map->remove($from);
        $map->append($to, $count, 1);
    }
    my $checksum = $traceInfo->check();
    if ($checksum->mapped($from)) {
        $checksum->remove($from);
        my $content = $reader->getLine($to);
        $checksum->replace($to, Digest::MD5::md5_base64($content))
            if defined($content);
    }
}

# Fold the coverpoints of each line 'from' of 'traceInfo' into line 'to', for
#   each 'from => [to, branches, mcdc]' of 'fold':  the line coverpoint takes
#   the greater of the two counts - in the summary and in each testcase, which
#   may be the same map - and the branch and MC/DC data of the line are moved
#   if 'branches' and 'mcdc' say so and every block still fits.  The checksum
#   of 'from' is dropped:  there is no source to compute the checksum of 'to'
#   from, and 'to' keeps its own.
# This is a baseline seen through the statements of current data which
#   'merge_continuation_lines' produced - see genhtml's
#   '_foldBaselineStatements' - so the greater count, not the sum:  a
#   continuation line counts the same executions of the statement as its first
#   line does, which is why '_continuationLineMerge' keeps the statement
#   line's count
sub foldContinuationLines
{
    my ($traceInfo, $fold) = @_;
    my $sum      = $traceInfo->sum();
    my $sumAddr  = Scalar::Util::refaddr($sum);
    my $testcase = $traceInfo->test();
    my $checksum = $traceInfo->check();
    my $brData   = $lcovutil::br_coverage ? $traceInfo->sumbr() : undef;
    my $mcdc     = $lcovutil::mcdc_coverage ? $traceInfo->mcdc() : undef;
    foreach my $from (sort({ $a <=> $b } keys(%$fold))) {
        my ($to, $branches, $conditions) = @{$fold->{$from}};
        foreach my $map ((
                        grep({ Scalar::Util::refaddr($_) != $sumAddr }
                            map({ $testcase->value($_) } $testcase->keylist())),
                        $sum
        )) {
            my $count = $map->value($from);
            next unless defined($count);
            $map->remove($from);
            my $target = $map->value($to);
            next if defined($target) && $target >= $count;
            $map->remove($to) if defined($target);
            $map->append($to, $count, 1);
        }
        $checksum->remove($from) if $checksum->mapped($from);
        $branches   = 0 unless defined($brData);
        $conditions = 0 unless defined($mcdc);
        next
            unless (($branches || $conditions)
                    &&
                    _locationsFit($from,
                                  $to,
                                  $branches ? $brData : undef,
                                  $conditions ? $mcdc : undef));
        if ($branches) {
            my $addr = Scalar::Util::refaddr($brData);
            my $tbr  = $traceInfo->testbr();
            foreach my $tn ($tbr->keylist()) {
                my $m = $tbr->value($tn);
                _moveBranches($m, $from, $to)
                    unless Scalar::Util::refaddr($m) == $addr;
            }
            _moveBranches($brData, $from, $to);
        }
        if ($conditions) {
            my $addr = Scalar::Util::refaddr($mcdc);
            my $tm   = $traceInfo->testcase_mcdc();
            foreach my $tn ($tm->keylist()) {
                my $m = $tm->value($tn);
                _moveMCDC($traceInfo, $m, $from, $to)
                    unless Scalar::Util::refaddr($m) == $addr;
            }
            _moveMCDC($traceInfo, $mcdc, $from, $to);
        }
    }
}

# Does line 'line' of 'reader' hold nothing but a '{' or a '}', once comments
#   are removed?
sub _bareBrace
{
    my ($reader, $line, $perl) = @_;
    my $code = $reader->getLine($line);
    return 0 unless defined($code);
    $code = ReadCurrentSource::removeComments($code);
    $code =~ s/#.*$// if $perl;
    return $code =~ /^\s*[{}]\s*$/;
}

# The last line of the statement 'first'..'last', less the lines at its end
#   which hold nothing but a brace and have no line coverpoint in 'lineData' -
#   none from the coverage tool, or one which a filter removed:  the '{' which
#   opens the block after a function's declaration or a control statement's
#   header, or the '}' which closes a block.  The brace says nothing about the
#   statement, so the statement does not include it.  A line which holds more
#   than the brace - '{}', '};', '} else {' - is part of the statement.
#   A statement does not start with a '{':  that ends the statement before it.
sub _trimBraces
{
    my ($lineData, $reader, $perl, $first, $last) = @_;
    --$last
        while ($last > $first &&
               !defined($lineData->value($last)) &&
               _bareBrace($reader, $last, $perl));
    return $last;
}

# The spans of 'traceInfo', less the brace lines at their end which have no
#   line coverpoint now - see '_trimBraces':  a filter may have removed the
#   coverpoint of a '}' after the spans were found.  A span which is left
#   with one line is removed.
# Returns non-zero if a span was changed.
sub _trimSpans
{
    my ($traceInfo, $srcReader) = @_;
    my $span = $traceInfo->span();
    return 0 unless 0 != $span->entries();
    my $reader = _consistencySource($traceInfo, $srcReader);
    return 0 unless defined($reader);
    my $lineData = $traceInfo->sum();
    my $perl     = is_language(lcovutil::IS_PERL, $traceInfo->filename());
    my $changed  = 0;

    foreach my $line ($span->keylist()) {
        my $end  = $span->value($line);
        my $last = _trimBraces($lineData, $reader, $perl, $line, $end);
        next if $last == $end;
        if ($last > $line) {
            $span->replace($line, $last);
        } else {
            $span->remove($line);
        }
        $changed = 1;
    }
    return $changed;
}

# 'merge_continuation_lines', the line coverpoints:  each line coverpoint
#   counts a statement, which may be split across lines (see
#   'ReadCurrentSource::statementSpan').  The coverpoint is put on the first
#   line of the statement, and its span - the lines of the statement - is
#   recorded:  see 'TraceInfo::span'.
#   The coverage tool may write more than one line coverpoint for a statement.
#   A coverpoint on a later line is an artifact of the tool if its count is 0,
#   or if both it and the coverpoint it would be merged into are hit and its
#   count is not greater - in the summary and in each testcase (see
#   '_continuationMergeable').  It is removed - from the summary and from each
#   testcase - so that the statement is reported once.  The remaining
#   coverpoint's count does not change.
#   One which cannot be merged - e.g., the condition of a loop whose header is
#   split across lines, whose branches would be taken more often than the
#   line they are moved to is executed - starts a new segment of the
#   statement:  the statement is partitioned, and each segment is a statement
#   of its own from here on.  So does a line which is the start line of a
#   function.
#   The span of a segment ends at the line before the next one, or at the
#   last line of the statement.  A brace line at the end of the statement
#   which has no line coverpoint is not part of it - see '_trimBraces'.
# A statement which has an excluded line, or a line which may start or end an
#   exclusion, is left alone:  its lines are not one statement.
# The branch and MC/DC data and the call sites of a line whose coverpoint is
#   removed or moved go to its segment's coverpoint afterward, by
#   '_statementBranchMerge' and '_statementCallSiteMerge'.
# A file which has spans already - read from a '.info' file which was
#   written with 'merge_continuation_lines' - was merged when the spans were
#   found, and is left alone.
# Returns non-zero if the data was changed.
sub _continuationLineMerge
{
    my ($traceInfo, $srcReader) = @_;
    my $filename = $traceInfo->filename();
    return 0
        unless ($lcovutil::merge_continuation_lines &&
                is_language(lcovutil::STATEMENT_LANGUAGES, $filename));
    my $span = $traceInfo->span();
    return 0 if 0 != $span->entries();

    my $lineData = $traceInfo->sum();
    my @lines    = sort { $a <=> $b } $lineData->keylist();
    return 0 unless @lines;
    my $reader = _consistencySource($traceInfo, $srcReader);
    return 0 unless defined($reader);

    my $func     = $traceInfo->func();
    my $testcase = $traceInfo->test();
    # branch and MC/DC data
    my @other;
    push(@other, $traceInfo->sumbr()) if $lcovutil::br_coverage;
    push(@other, $traceInfo->mcdc()) if $lcovutil::mcdc_coverage;
    my $flags = ReadCurrentSource::e_LINE;
    $flags |= ReadCurrentSource::e_CALLGRAPH if $lcovutil::callgraph_coverage;
    my $perl = is_language(lcovutil::IS_PERL, $filename);

    my $changed = 0;
    my $done    = 0;    # the last line which is part of a statement seen
    for (my $i = 0; $i < @lines;) {
        # a statement does not take in a coverpoint seen already
        $done = $lines[$i - 1] if ($i && $lines[$i - 1] > $done);
        my $line = $lines[$i++];
        my ($first, $last) = $reader->statementSpan($line);
        # a statement which starts after the '}' which closes the block before
        #   it is found from its next line - within the same lookahead window
        unless (defined($first)) {
            ($first, $last) = $reader->statementSpan($line + 1);
            $first = undef
                if (defined($first) &&
                    ($first != $line ||
                     $last - $line > $lcovutil::source_filter_lookahead));
        }
        next
            unless (defined($first) &&
                    $first < $last &&
                    $first > $done &&
                    $last - $first <= MAX_SPAN_OFFSET);
        $last = _trimBraces($lineData, $reader, $perl, $first, $last);
        next unless $first < $last;
        $done = $last;
        # the line coverpoints of the statement
        my @da = ($line);
        push(@da, $lines[$i++]) while ($i < @lines && $lines[$i] <= $last);

        my $f = $flags;
        for (my $l = $first; $l <= $last; ++$l) {
            if (grep({ defined($_->value($l)) } @other)) {
                $f |= ReadCurrentSource::e_BRANCH;
                last;
            }
        }
        next if _statementExcluded($reader, $first, $last, $f);

        my @segment = (shift(@da));    # the coverpoint of each segment
        my %target;                    # the segments a line was merged into
        foreach my $l (@da) {
            my $to = $segment[-1];
            # a function's start line starts a segment of its own
            my $mergeable = !defined($func->findKey($l));
            $mergeable &&=
                _continuationMergeable($lineData->value($l),
                                       $lineData->value($to));
            foreach my $tn ($testcase->keylist()) {
                last unless $mergeable;
                my $data = $testcase->value($tn);
                my $c    = $data->value($l);
                $mergeable = !defined($c) ||
                    _continuationMergeable($c, $data->value($to));
            }
            unless ($mergeable) {
                push(@segment, $l);
                next;
            }
            # the summary may be one of the testcases:  'remove' only if
            #   present
            $lineData->remove($l, 1);
            $testcase->value($_)->remove($l, 1) foreach ($testcase->keylist());
            $traceInfo->check()->remove($l, 1);
            lcovutil::info(1,
                "\"$filename\":$l: merged continuation line coverpoint into statement line $to\n"
            );
            ++$lcovutil::continuation_lines_merged;
            $target{$#segment} = 1;
            $changed = 1;
        }
        $lcovutil::continuation_merge_targets += scalar(keys(%target));
        # the first segment starts where the statement does - unless its
        #   coverpoint is a function's, or has branch or MC/DC data which
        #   could not say where it is written
        my $start = $segment[0];
        if ($start > $first &&
            !defined($func->findKey($start)) &&
            _locationsFit($start, $first, @other)) {
            _moveLine($traceInfo, $reader, $start, $first);
            lcovutil::info(1,
                "\"$filename\":$start: moved line coverpoint to statement line $first\n"
            );
            $segment[0] = $first;
            $changed = 1;
        }
        my @range;
        for (my $s = 0; $s < @segment; ++$s) {
            my $begin = $segment[$s];
            my $end   = $s + 1 < @segment ? $segment[$s + 1] - 1 : $last;
            push(@range, $begin == $end ? $begin : "$begin-$end");
            next unless $end > $begin;
            $span->replace($begin, $end);
            $changed = 1;
        }
        lcovutil::info(1,
                       "\"$filename\":$first: statement $first-$last " .
                           "partitioned into " .
                           join(', ', @range) . "\n") if 1 < scalar(@segment);
    }
    return $changed;
}

# 'merge_continuation_lines', the call site coverpoints:  a call written on a
#   line which has no line coverpoint - a later line of a statement split
#   across lines, typically, or a line whose coverpoint
#   '_continuationLineMerge' removed - belongs to the statement the line is
#   part of.  Its coverpoint is allocated to the line coverpoint whose
#   statement span the line is in (see 'TraceInfo::span'):  that is its
#   statement line - see
#   FunctionEntry::SITE_STATEMENT - in the summary and in each testcase.  The
#   site still says where the call is written, which is where a reader is taken
#   to see it.  A call written in another file, and a site which has a
#   statement line already, are left alone.
# Returns the number of call sites given a statement line.
sub _statementCallSiteMerge
{
    my ($traceInfo, $srcReader) = @_;
    my $filename = $traceInfo->filename();
    return 0
        unless ($lcovutil::merge_continuation_lines &&
                $lcovutil::callgraph_coverage &&
                is_language(lcovutil::STATEMENT_LANGUAGES, $filename));

    my $lineData = $traceInfo->sum();
    my $func     = $traceInfo->func();
    my @candidate;    # [function key, site key, line]
    foreach my $key ($func->keylist()) {
        my $entry = $func->findKey($key);
        foreach my $site ($entry->sortedCallSiteKeys()) {
            my ($line, undef, undef, undef, undef, $file, undef, $statement) =
                $entry->callSiteData($site);
            push(@candidate, [$key, $site, $line])
                unless (defined($file) ||
                        defined($statement) ||
                        defined($lineData->value($line)));
        }
    }
    return 0 unless @candidate;
    my $anchor = $traceInfo->spanOwners();
    return 0 unless %$anchor;

    my $testcase = $traceInfo->testfnc();
    my $moved    = 0;
    foreach my $c (@candidate) {
        my ($key, $site, $line) = @$c;
        my $to = $anchor->{$line};
        next
            unless (defined($to) &&
                    abs($to - $line) <= FunctionEntry::MAX_STATEMENT_OFFSET);
        # the summary may be one of the testcases:  setting it twice is
        #   harmless
        foreach
            my $map ($func, map({ $testcase->value($_) } $testcase->keylist()))
        {
            my $entry = $map->findKey($key);
            $entry->_setSiteStatement($site, $to) if defined($entry);
        }
        lcovutil::info(1,
            "\"$filename\":$line: allocated call site $site coverpoint to statement line $to\n"
        );
        ++$moved;
    }
    return $moved;
}

# 'merge_continuation_lines', the branch and MC/DC coverpoints:  a branch or
#   MC/DC coverpoint on a line which has no line coverpoint - a later line of a
#   condition split across lines, typically, or a line whose coverpoint
#   '_continuationLineMerge' removed - belongs to the statement the line is
#   part of.
#   Move it to the line coverpoint whose statement span the line is in (see
#   'TraceInfo::span'), and check that the counts on that line agree
#   afterward (see '_checkMergedLines').  Lines which are in no span are left
#   where they are.
# Returns a hash of the lines which received data -> the lines it came from.
sub _statementBranchMerge
{
    my ($traceInfo, $srcReader) = @_;
    my %merged;
    my $filename = $traceInfo->filename();
    return \%merged
        unless ($lcovutil::merge_continuation_lines &&
                ($lcovutil::br_coverage || $lcovutil::mcdc_coverage) &&
                is_language(lcovutil::STATEMENT_LANGUAGES, $filename));

    my $lineData = $traceInfo->sum();
    my $brData   = $lcovutil::br_coverage ? $traceInfo->sumbr() : undef;
    my $mcdc     = $lcovutil::mcdc_coverage ? $traceInfo->mcdc() : undef;
    my %orphan;
    foreach my $map ($brData, $mcdc) {
        next unless defined($map);
        foreach my $line ($map->keylist()) {
            $orphan{$line} = 1 unless defined($lineData->value($line));
        }
    }
    return \%merged unless %orphan;
    my $anchor = $traceInfo->spanOwners();
    return \%merged unless %$anchor;

    foreach my $line (sort { $a <=> $b } keys(%orphan)) {
        my $to = $anchor->{$line};
        next unless (defined($to) && _locationsFit($line, $to, $brData, $mcdc));

        # the summary and each testcase - which may be the same map
        if (defined($brData)) {
            my $sumAddr  = Scalar::Util::refaddr($brData);
            my $testcase = $traceInfo->testbr();
            foreach my $tn ($testcase->keylist()) {
                my $m = $testcase->value($tn);
                _moveBranches($m, $line, $to)
                    unless Scalar::Util::refaddr($m) == $sumAddr;
            }
            _moveBranches($brData, $line, $to);
        }
        if (defined($mcdc)) {
            my $sumAddr  = Scalar::Util::refaddr($mcdc);
            my $testcase = $traceInfo->testcase_mcdc();
            foreach my $tn ($testcase->keylist()) {
                my $m = $testcase->value($tn);
                _moveMCDC($traceInfo, $m, $line, $to)
                    unless Scalar::Util::refaddr($m) == $sumAddr;
            }
            _moveMCDC($traceInfo, $mcdc, $line, $to);
        }
        lcovutil::info(1,
            "\"$filename\":$line: merged branch/MC/DC data onto statement line $to\n"
        );
        push(@{$merged{$to}}, $line);
    }
    _checkMergedLines($traceInfo, $srcReader, \%merged);
    return \%merged;
}

# Do the counts on each line which received data from '_statementBranchMerge'
#   agree with each other?  The branches and MC/DC conditions on the line are
#   all thought to be part of its statement now:
#   - C/C++ counts:  no branch is taken more often than the statement is
#     executed, and some branch is taken if the statement is executed
#   - Python and Java hit/not-hit data:  a branch is taken exactly if the
#     statement is executed
#   - Perl:  a branch is taken only if the statement is executed
#   - and in any language, an MC/DC condition is sensitized only if the
#     statement is executed
sub _checkMergedLines
{
    my ($traceInfo, $srcReader, $merged) = @_;
    my $filename = $traceInfo->filename();
    my $rule =
        is_language(lcovutil::IS_PERL, $filename) ? 'perl' :
        is_language(lcovutil::IS_PYTHON | lcovutil::IS_JAVA, $filename) ?
        'boolean' :
        'count';
    my $lineData = $traceInfo->sum();
    my $brData   = $lcovutil::br_coverage ? $traceInfo->sumbr() : undef;
    my $mcdc     = $lcovutil::mcdc_coverage ? $traceInfo->mcdc() : undef;

    foreach my $line (sort { $a <=> $b } keys(%$merged)) {
        my $lineHit = $lineData->value($line);
        my @reason;
        my $location = defined($brData) ? $brData->value($line) : undef;
        if (defined($location)) {
            my $brHit = $location->hasHitElement(1);
            if ($rule eq 'count') {
                my $max = 0;
                foreach my $blk ($location->blocks()) {
                    foreach my $br (@{$blk->elements()}) {
                        $max = $br->count() if $br->count() > $max;
                    }
                }
                push(@reason,
                    "largest branch hit count $max exceeds line hit count $lineHit"
                ) if $max > $lineHit;
            } elsif ($brHit && !$lineHit) {
                push(@reason,
                    'line is not hit but at least one branch on line has been evaluated'
                );
            }
            push(@reason,
                 'line is hit but no branches on line have been evaluated')
                if ($lineHit && !$brHit && $rule ne 'perl');
        }
        my $block = defined($mcdc) ? $mcdc->value($line) : undef;
        if (defined($block) && !$lineHit) {
            my (undef, $hit) = $block->totals(1);
            push(@reason, 'line is not hit but an MC/DC condition on line is')
                if $hit;
        }
        next unless @reason;
        next if _lambdaSuppressed($traceInfo, $srcReader, $line);
        lcovutil::ignorable_error(
                       $lcovutil::ERROR_INCONSISTENT_DATA,
                       "\"$filename\":$line: after merging branch/MC/DC data " .
                           'from line' .
                           (1 < scalar(@{$merged->{$line}}) ? 's ' : ' ') .
                           join(', ', @{$merged->{$line}}) .
                           ' onto this statement: ' .
                           join('; ', @reason) . '.' .
                           _consistencySuffix());
    }
}

sub _checkConsistency
{
    return unless $lcovutil::check_data_consistency;
    my ($traceInfo, $srcReader) = @_;
    my $modified = 0;

    my $start = Time::HiRes::gettimeofday();

    # before anything which counts lines:  a line coverpoint which only
    #   continues a statement is removed
    $modified = 1 if _continuationLineMerge($traceInfo, $srcReader);
    $modified = 1 if _statementCallSiteMerge($traceInfo, $srcReader);

    my @functions = sort { $a->line() <=> $b->line() }
        grep({ defined($_->end_line()) } $traceInfo->func()->valuelist());
    my $lineData = $traceInfo->sum();
    my @lines;
    @lines = sort { $a <=> $b } $lineData->keylist()
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
                    '"' .
                        $func->filename() .
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
                # a lambda on the line, with 'ignore_lambda_consistency' on:
                #   the line's count need not be the function's, so neither
                #   report nor fix it
                last if _lambdaSuppressed($traceInfo, $srcReader, $currentLine);
                my $suffix =
                    ($lcovutil::fix_inconsistency && lcovutil::is_ignored(
                                             $lcovutil::ERROR_INCONSISTENT_DATA)
                    ) ? ": function marked 'hit'" :
                    '';
                lcovutil::ignorable_error(
                           $lcovutil::ERROR_INCONSISTENT_DATA,
                           '"' .
                               $func->filename() .
                               "\":$first: function '" .
                               $func->name() .
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
            lcovutil::ignorable_error(
                         $lcovutil::ERROR_INCONSISTENT_DATA,
                         '"' .
                             $traceInfo->filename() .
                             "\":$first: function '" .
                             $func->name() .
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

    # a branch or MC/DC coverpoint on a line without a line coverpoint which
    #   belongs to a statement which has one is moved there
    my $merged = _statementBranchMerge($traceInfo, $srcReader);
    $modified = 1 if %$merged;

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
                           '"' .
                               $traceInfo->filename() .
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
        !TraceFile::is_language(lcovutil::IS_PERL, $traceInfo->filename());
    if ($lcovutil::br_coverage) {
        my $brData = $traceInfo->sumbr();

        foreach my $line ($brData->keylist()) {
            # we expect to find a line everywhere there is a branch

            # checked when the data was merged
            next if exists($merged->{$line});
            my $lineHit  = $lineData->value($line);
            my $location = $brData->value($line);
            unless (defined($lineHit)) {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                      '"' .
                          $traceInfo->filename() .
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
                    '"' .
                        $traceInfo->filename() .
                        "\":$line: line is hit but no branches on line have been evaluated."
                        . _consistencySuffix())
                    if ($checkBranchConsistency &&
                        !_lambdaSuppressed($traceInfo, $srcReader, $line));
            } elsif (!$lineHit && $brHit) {
                lcovutil::ignorable_error($lcovutil::ERROR_INCONSISTENT_DATA,
                    '"' .
                        $traceInfo->filename() .
                        "\":$line: line is not hit but at least one branch on line has been evaluated."
                        . _consistencySuffix())
                    unless _lambdaSuppressed($traceInfo, $srcReader, $line);
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

sub _invokeExcludeCallback($$$$)
{
    # Ask the '--unreachable-script' callback about one coverpoint type, and turn
    #   whatever it throws into an ignorable error naming the call which failed.
    # The callback is handed the per-testcase collection before the summary:
    #   that is the order the argument list has always had, and the order the
    #   message below has to spell, or a user debugging a failing callback is
    #   sent looking at the wrong argument
    my ($type, $srcReader, $testCount, $sumCount) = @_;
    my $callback = $lcovutil::excludeCoverpointCallback;
    my $changed  = 0;
    eval {
        $changed = $callback->exclude($type, $srcReader, $testCount, $sumCount);
    };
    if ($@) {
        my $class = ref($callback);
        my $msg   = "\"unreachable\" callback $class->exclude($type, readSrc," .
            " perTestDB, summaryDB) failed: $@";
        lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK, $msg);
        return 0;
    }
    return $changed;
}

sub _filterFile
{
    my ($traceInfo, $source_file, $actions, $srcReader, $state) = @_;

    # read first:  the consistency check uses the source too
    my $context = MessageContext->new("filtering $source_file");
    if (lcovutil::is_filter_enabled()) {
        lcovutil::info(1, "reading $source_file for lcov filtering\n");
        $srcReader->open($source_file);
    } else {
        $srcReader->close();
    }

    my $modified = 0;
    if (0 != ($actions & DID_DERIVE)) {
        $modified = _deriveFunctionEndLines($traceInfo);
    }
    if (0 != ($actions & DID_CONSISTENCY)) {
        $modified = 1 if _checkConsistency($traceInfo, $srcReader);
    }
    return ($traceInfo, $modified) if (0 == ($actions & DID_FILTER));
    my $region           = $cov_filter[$FILTER_EXCLUDE_REGION];
    my $branch_region    = $cov_filter[$FILTER_EXCLUDE_BRANCH];
    my $callgraph_region = $cov_filter[$FILTER_EXCLUDE_CALLGRAPH];
    my $range            = $cov_filter[$lcovutil::FILTER_LINE_RANGE];
    my $branch_histogram;
    $branch_histogram = $cov_filter[$FILTER_BRANCH_NO_COND]
        if (is_language(lcovutil::IS_C, $source_file));
    my $brace_histogram;
    $brace_histogram = $cov_filter[$FILTER_LINE_CLOSE_BRACE]
        if (is_language(lcovutil::IS_C, $source_file));
    my $blank_histogram          = $cov_filter[$FILTER_BLANK_LINE];
    my $function_alias_histogram = $cov_filter[$FILTER_FUNCTION_ALIAS];
    my $trivial_histogram        = $cov_filter[$FILTER_TRIVIAL_FUNCTION];
    my $filter_initializer_list;
    $filter_initializer_list = $cov_filter[$FILTER_INITIALIZER_LIST]
        if (is_language(lcovutil::IS_C, $source_file));
    my $directive = $cov_filter[$FILTER_DIRECTIVE];
    my $omit;
    $omit = $cov_filter[$FILTER_OMIT_PATTERNS]
        if defined($FILTER_OMIT_PATTERNS);
    my $mcdc_single;
    $mcdc_single = $cov_filter[$FILTER_MCDC_SINGLE]
        if defined($FILTER_MCDC_SINGLE) && $lcovutil::mcdc_coverage;

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
    my $fileVersion;
    $fileVersion = lcovutil::extractFileVersion($path)
        if $srcReader->notEmpty();
    if (defined($fileVersion) &&
        !$srcReader->isRecoveredBaselineFile($path) &&
        defined($traceInfo->version())
        &&
        !lcovutil::checkVersionMatch($source_file, $traceInfo->version(),
                                     $fileVersion, 'filter')
    ) {
        # not reached:  'checkVersionMatch' called without its 'silent'
        #   argument never says no - a mismatch is an ERROR_VERSION, which
        #   dies, unless the user ignores it, and then the mismatch is ignored
        #   and the answer is yes.
        # The block is not marked LCOV_UNREACHABLE:  Devel::Cover can
        #   attribute the counts of the merged per-test databases of the
        #   regression suite to the wrong lines, and has reported hits here.
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

        # ..and the calls made by the functions it erases, which outlive them on
        #   their callees:  collected here and drained into the TraceFile by
        #   '_updateModifiedFile', because this may be running in a forked child
        #   and this object is all that comes back from one
        my @externalCalls;
        $modified = 1
            if _eraseFunctions($source_file, $reader,
                               $traceInfo->func(), $traceInfo->sum(),
                               $traceInfo->sumbr(), $traceInfo->mcdc(),
                               $traceInfo->check(), $state,
                               1, \@externalCalls,
                               $funcData);
        $traceInfo->noteExternalCalls(\@externalCalls);
        foreach my $tn ($lineData->keylist()) {
            $modified = 1
                if _eraseFunctions($source_file,
                                   $reader,
                                   $funcData->value($tn),
                                   $lineData->value($tn),
                                   $branchData->value($tn),
                                   $mcdcData->value($tn),
                                   $checkData->value($tn),
                                   $state,
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

    # The calls made by the functions the region/range removal below takes out,
    #   which outlive them on their callees:  the same treatment
    #   '_eraseFunctions' gives the functions it erases, and for the same reason
    #   - the function's call sites are the only record that those calls were
    #   made, and the callees have not left the boundary of the report.
    # Collected here and drained once, after the loop:  the removal takes the
    #   function out of every testcase's map, so the snapshot of what this file
    #   defined has to be taken before the first of them - see '%wasLocal' in
    #   '_eraseFunctions', which is the same guard for the same case
    my @erasedCalls;
    my %wasLocal;
    my $noteErased = $lcovutil::callgraph_coverage &&
        $lcovutil::func_coverage &&
        ($region || $range);
    %wasLocal = map({ ($_ => 1) } $funcdata->list_functions()) if $noteErased;

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
                                   "filter FN " .
                                       $data->name() . ' ' .
                                       $data->file() .
                                       ":$line\n");
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
                            $f->[1]->[-2] += $data->numAliases();
                            last;
                        }
                    }
                }
                if ($remove) {
                    # before the removal, which is the last moment the sites
                    #   exist - and from the summary entry, which holds the
                    #   merged count of each of them.  Once per function:  the
                    #   removal below reaches every map, so the next testcase's
                    #   'keylist' no longer has this key
                    if ($noteErased) {
                        my $entry = $funcdata->findKey($key);
                        _noteErasedCalls(\@erasedCalls, $entry, $source_file,
                                         $testfncdata, $key)
                            if defined($entry);
                    }
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
        if ($lcovutil::callgraph_coverage &&
            $functionMap &&
            ($region || $range || $omit || $directive || $callgraph_region)) {
            # The call sites of the surviving functions, which are keyed by the
            #   line the *call* is on and not by the function's own line:  a
            #   call in an excluded region has to go even though the function
            #   containing it stays, exactly as an excluded branch does.
            # This runs before the line data below, because the rule there is
            #   that a line which still has a coverpoint of another kind is not
            #   a line to suppress - so the sites of an excluded line must
            #   already be gone by the time it is asked
            foreach my $key ($functionMap->keylist()) {
                my $entry = $functionMap->findKey($key);
                foreach my $site ($entry->callSiteKeys()) {
                    my ($line, undef, undef, undef, $callee, $siteFile) =
                        $entry->callSiteData($site);
                    # A call written in another file is not judged by this
                    #   file's source:  its line number indexes that file, so
                    #   every question below would be asked of the wrong text.
                    #   It is not judged by that file's pass either - the site
                    #   is in this file's FunctionMap, which is the only thing
                    #   that pass walks - so an exclusion in an '#include'd
                    #   fragment does not reach the calls written in it.  Said
                    #   here rather than fixed, because the fix is a whole-report
                    #   pass and every filter here is deliberately local to one
                    #   file (a child may hold only this one)
                    next if defined($siteFile);
                    my $remove;
                    my $counted;    # 'isOutOfRange' counts its own coverpoint
                    if ($srcReader->isOutOfRange($line, 'line')) {
                        $remove  = $range;
                        $counted = 1;
                    } elsif (0 != ($reason =
                                       $srcReader->isExcluded(
                                                  $line, $srcReader->e_CALLGRAPH
                                       ))
                    ) {
                        # the line itself, or just its call sites
                        #   ('LCOV_EXCL_CALLGRAPH_...')
                        my $r = $srcReader->excludeReason($line);
                        foreach my $f (
                                   [ReadCurrentSource::EXCLUDE_REGION, $region],
                                   [ReadCurrentSource::OMIT_LINE, $omit],
                                   [ReadCurrentSource::EXCLUDE_DIRECTIVE,
                                    $directive
                                   ],
                                   [ReadCurrentSource::EXCLUDE_CALLGRAPH_REGION,
                                    $callgraph_region
                                   ]
                        ) {
                            if ($r & $f->[0]) {
                                $remove = $f->[1];
                                last;
                            }
                        }
                    }
                    next unless $remove;
                    # At the verbosity the function filter reports at rather than
                    #   the one the line filter reports at:  this only ever fires
                    #   for an explicit exclusion, and losing a whole call is the
                    #   kind of thing a user asks '-v' to be told about
                    lcovutil::info(1,
                                   'filter FNC (' .
                                       $remove->[0] .
                                       ") $source_file:$line" .
                                       " call to '$callee'\n");
                    # one coverpoint suppressed - and not one more location:
                    #   the line this site is on is counted by the filter which
                    #   removes the line itself
                    ++$remove->[-1] unless $counted;
                    # ..from every testcase, and from the summary unless that is
                    #   one of them - the aliasing note at the head of this sub
                    foreach my $tn ($testfncdata->keylist()) {
                        my $f = $testfncdata->value($tn)->findKey($key);
                        $f->_removeSite($site) if $f;
                    }
                    unless ($aliased{TraceInfo::FUNCTION_DATA}) {
                        my $f = $funcdata->findKey($key);
                        $f->_removeSite($site) if $f;
                    }
                    $modified = 1;
                }
            }
        }    # if callgraph_coverage
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
                $modified = 1
                    if _invokeExcludeCallback($str, $srcReader, $testCount,
                                              $sumCount);
            }
        }

        # Every filter the loop below can apply has to be named here, or asking
        #   for it alone does nothing at all:  'blank' was missing, so
        #   '--filter blank' only ever worked in company - '--filter line' is
        #   brace and blank together, which is how the gap stayed hidden
        next
            unless $region    ||
            $range            ||
            $brace_histogram  ||
            $blank_histogram  ||
            $branch_histogram ||
            $directive        ||
            $omit             ||
            $filter_initializer_list;

        # Line related data
        my %initializerListRange;
        # The lines which have a call site.  A line which still carries a
        #   coverpoint of another kind is not a line to suppress - the same rule
        #   the branch and MC/DC check in the loop below applies - and a call on
        #   a line which looks like nothing but a closing brace is a real call:
        #   to the destructor of an object which went out of scope there, or to
        #   the end of a 'catch'.  The sites of a line which was *excluded* are
        #   already gone, in the loop above, so an explicit exclusion still wins.
        #   The 'brace' filter has rules of its own for a closing brace with
        #   call sites, applied once after this loop - see _filterBraceCallSites
        # A call written in another file is not one of this file's lines, even
        #   though this file's map is where it is kept:  its line number indexes
        #   that file, so counting it here would hold a line of this file which
        #   happens to have the same number - and which the user may well have
        #   excluded - against a call that is not on it
        my %callSiteLine;
        if ($lcovutil::callgraph_coverage && $functionMap) {
            foreach my $key ($functionMap->keylist()) {
                my $entry = $functionMap->findKey($key);
                foreach my $site ($entry->callSiteKeys()) {
                    my ($line, undef, undef, undef, undef, $siteFile) =
                        $entry->callSiteData($site);
                    $callSiteLine{$line} = 1 unless defined($siteFile);
                }
            }
        }
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

            # don't suppress if this line has associated branch, MC/DC or
            #   call site data
            next
                if (
                 (defined($sumbrcount) && defined($sumbrcount->value($line))) ||
                 (defined($mcdc_count) &&
                    defined($mcdc_count->value($line))) ||
                 exists($callSiteLine{$line}));

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

            my $outOfRange;
            $outOfRange = $srcReader->isOutOfRange($line, 'line')
                unless $is_filtered;
            $is_filtered = $lcovutil::cov_filter[$lcovutil::FILTER_LINE_RANGE]
                if !defined($is_filtered) &&
                defined($outOfRange) &&
                $outOfRange;
            my $excluded;
            $excluded = $srcReader->isExcluded($line)
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
            my $isCloseBrace;
            $isCloseBrace =
                ($brace_histogram &&
                 $srcReader->suppressCloseBrace($line, $l_hit, $testcount))
                unless $is_filtered;
            $is_filtered = $brace_histogram
                if !defined($is_filtered) &&
                defined($isCloseBrace) &&
                $isCloseBrace;
            my $isBlank;
            $isBlank =
                ($blank_histogram &&
                 ($lcovutil::filter_blank_aggressive || $l_hit == 0) &&
                 $srcReader->isBlank($line))
                unless $is_filtered;
            $is_filtered = $blank_histogram
                if !defined($is_filtered) && defined($isBlank) && $isBlank;

            next unless $is_filtered;

            $modified = 1;
            lcovutil::info(2,
                           'filter DA (' .
                               $is_filtered->[0] . ') '
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
         # ..and now that the removing is done, the calls whose callee outlived
         #   the caller:  a call to a name this file defined and no longer does
         #   has no surviving callee to be a fact about, and an unrelated
         #   definition of the name elsewhere must not answer for it
    if (@erasedCalls) {
        my @survivingCallee = grep(
                { !$wasLocal{$_->[1]} || defined($funcdata->findName($_->[1])) }
                @erasedCalls);
        $traceInfo->noteExternalCalls(\@survivingCallee);
    }
    # ..then the closing braces which have call sites on them, which the line
    #   loop above did not touch:  once, on the summary, after every exclusion
    #   has taken what it takes - see _filterBraceCallSites for the rules
    $modified = 1
        if $brace_histogram &&
        $lcovutil::callgraph_coverage &&
        _filterBraceCallSites($srcReader, $source_file, $traceInfo, \%aliased,
                              $brace_histogram);
    # Last, the call sites the user callback wants gone.  Once per file, and not
    #   inside the loop above with the branch and MC/DC types:  that loop asks
    #   the callback again for every testcase, with the same whole-file source
    #   and the same summary map each time, which a marking callback survives
    #   because marking twice is marking once - but removing a site is
    #   destructive, and the second pass would find it already gone.
    # After the loop rather than before it, so that the sites the region, range
    #   and omit filters take out are gone by the time the callback is asked:
    #   what it sees is what the report would otherwise have shown, and it is
    #   not asked to rule on a call which is already excluded
    if (defined($lcovutil::excludeCoverpointCallback) &&
        $lcovutil::callgraph_coverage &&
        $funcdata) {
        # function coverage is a prerequisite of callgraph coverage - see the
        #   '--callgraph-coverage requires function coverage' check in
        #   'parseArgs' - so there is no separate '$func_coverage' test here
        die("expected srcReader")
            unless defined($srcReader) && $srcReader->notEmpty();
        @lcovutil::excludedCallSites = ();
        $modified                    = 1
            if _invokeExcludeCallback('callgraph', $srcReader,
                                      $testfncdata, $funcdata);
        # ..and the calls it took out, on the callees which are still here:  a
        #   site outside the boundary of the report is not evidence either way
        #   about the call, but a call which was taken did reach its callee, and
        #   that callee is in the report to be told so
        if (@lcovutil::excludedCallSites) {
            $traceInfo->noteExternalCalls(\@lcovutil::excludedCallSites);
            @lcovutil::excludedCallSites = ();
        }
    }

    # a '}' whose coverpoint a filter removed is not part of a statement
    $modified = 1 if _trimSpans($traceInfo, $srcReader);

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
            lcovutil::ignorable_error(
                     $lcovutil::ERROR_UNSUPPORTED,
                     $msg .
                         ".  See lcovrc man entry for 'derive_function_end_line'."
            );
        }
    }
}

sub _updateModifiedFile
{
    my ($self, $name, $traceFile) = @_;
    $self->[FILES]->{$name} = $traceFile;
    # Every filtered file arrives here - from this process or from a child - so
    #   this is the one place the calls the filters found on their way past can
    #   be lifted onto the report as a whole:  see
    #   TraceInfo::noteExternalCalls, which explains why they travel on the file
    $self->noteExternalCalls($traceFile->takeExternalCalls());
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
    # did ANY file in this run held a function with no end line
    my $sawNoEndLine = 0;
    # keep track of patterns application counts before we fork children
    my @pats = grep { @$_ }
        (\@lcovutil::exclude_function_patterns, \@lcovutil::omit_line_patterns);
    # and also filter application counts
    my @filters = grep { defined($_) } @lcovutil::cov_filter;
    my @save    = (\@pats, \@filters);

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
                         # save current counts...
                         $state[0]->[1] = 0;
                         if (ref($d->[0]) eq 'TraceInfo') {
                             # serial processing...
                             my ($data, $modified) =
                                 _filterFile(@$d, $srcReader, \@state);
                             $sawNoEndLine = 1 if $state[0]->[1];
                             $self->_updateModifiedFile($d->[1], $data)
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
                     # the child's flag, not this update's:  a chunk which
                     #   modified nothing has no updates at all
                     $sawNoEndLine = 1 if $state->[0]->[1];
                     foreach my $u (@$updates) {
                         $self->_updateModifiedFile(@$u);
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
                 requeue => sub { push(@$workList, $_[0]); },
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
    # 'warn_once' inside makes one call the right shape even when several files
    #   were affected
    _generate_end_line_message() if $sawNoEndLine;
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

    # each file is checked once:  data which has been checked is not checked
    #   again unless it has been merged with other data since
    my $check = 0 == ($self->[STATE] & DID_CONSISTENCY);

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
            (   $lcovutil::derive_function_end_line_all_files ||
                is_language(
                         lcovutil::IS_C | lcovutil::IS_JAVA | lcovutil::IS_PERL,
                         $source_file))
        ) {
            # try to derive end lines if at least one is unknown.
            #   can't compute for lambdas because we can't distinguish
            #   the last line reliably.
            $actions = DID_DERIVE
                if grep({ !($_->isLambda() || defined($_->end_line())) }
                        $traceInfo->func()->valuelist());
        }

        my $filter =
            (is_language(lcovutil::STATEMENT_LANGUAGES, $source_file) &&
             lcovutil::is_filter_enabled());
        $filter = 1
            if (defined($lcovutil::func_coverage) &&
                (0 != scalar(@lcovutil::exclude_function_patterns) ||
                 defined($lcovutil::cov_filter[$FILTER_TRIVIAL_FUNCTION])));
        # merging continuation lines reads the source and finds the statement
        #   of every line coverpoint:  costly enough to justify parallel
        #   processing - see '_continuationLineMerge'
        my $merge =
            ($check &&
             $lcovutil::check_data_consistency                        &&
             $lcovutil::merge_continuation_lines                      &&
             is_language(lcovutil::STATEMENT_LANGUAGES, $source_file) &&
             0 == $traceInfo->span()->entries());
        if ($filter || $merge) {
            # we are forking anyway - so also compute end lines there
            $actions |= DID_FILTER if $filter;
            $actions |= DID_CONSISTENCY if $check;
            push(@filter_workList, [$traceInfo, $name, $actions]);
        } else {
            if (0 != $actions) {
                # all we are doing is deriving function end lines - which doesn't
                # take long enough to be worth forking
                TraceFile::_deriveFunctionEndLines($traceInfo);
            }
            TraceFile::_checkConsistency($traceInfo, $srcReader) if $check;
        }

    }    # foreach file
    $self->[STATE] |= DID_DERIVE | DID_CONSISTENCY;

    if (@filter_workList) {
        lcovutil::info("Apply filtering..\n")
            unless $lcovutil::in_child_process;    # ..once, not once per chunk
        $self->_processFilterWorklist($srcReader, \@filter_workList);
        # keep track - so we don't do this again
        $self->[STATE] |= DID_FILTER;
    }
}

sub _symbolIndex
{
    # Index every alias in this report by name, which is how a call site names
    #   its callee.  Returns (\%symbol, \%duplicated, \%definedIn):  a name which
    #   exactly one file defines is in the first, with the file which defines it
    #   in the third, and one which several define - a 'static' function, usually
    #   - is in the second instead, keyed by file as well, because it cannot be
    #   resolved by name alone.  That is the rare case, and it costs nothing until
    #   it happens.
    # '$reset' also declares every alias unresolved, which is what makes
    #   resolveCallSites idempotent;  a caller which is only looking a name up
    #   must not ask for it.
    # A name merged into an alias (see _collapseCallgraphAliases) finds that
    #   alias, as a fourth value says - a hash of every such name - unless some
    #   file defines the name:  a definition is what a call resolves to, and a
    #   merged name is only remembered
    my ($self, $reset) = @_;

    my (%symbol, %definedIn, %duplicated, @merged);
    foreach my $filename ($self->files()) {
        my $functionMap = $self->data($filename)->func();
        foreach my $key ($functionMap->keylist()) {
            my $entry = $functionMap->findKey($key);
            foreach my $name ($entry->aliasNames()) {
                my $alias = $entry->alias($name);
                $alias->clear_callers() if $reset;
                my $names = $alias->merged();
                push(@merged, [$filename, $alias, $names]) if defined($names);
                if (exists($duplicated{$name})) {
                    $duplicated{$name}->{$filename} = $alias;
                } elsif (exists($symbol{$name})) {
                    $duplicated{$name} = {
                                          $definedIn{$name} => $symbol{$name},
                                          $filename         => $alias
                    };
                    # ..and the name has no one defining file any more:  the
                    #   duplicate index is keyed by file precisely because the
                    #   answer depends on where the call was made
                    delete($definedIn{$name});
                } else {
                    $symbol{$name}    = $alias;
                    $definedIn{$name} = $filename;
                }
            }
        }
    }
    # ..then the merged names, by the same rules among themselves:  a name
    #   merged in two files is as ambiguous as one defined in two
    my %mergedNames;
    foreach my $m (@merged) {
        my ($filename, $alias, $names) = @$m;
        foreach my $name (keys(%$names)) {
            if (exists($mergedNames{$name})) {
                if (exists($duplicated{$name})) {
                    $duplicated{$name}->{$filename} = $alias;
                } else {
                    $duplicated{$name} = {
                                          $definedIn{$name} => $symbol{$name},
                                          $filename         => $alias
                    };
                    delete($symbol{$name});
                    delete($definedIn{$name});
                }
            } elsif (!exists($symbol{$name}) && !exists($duplicated{$name})) {
                $mergedNames{$name} = 1;
                $symbol{$name}      = $alias;
                $definedIn{$name}   = $filename;
            }
        }
    }
    return (\%symbol, \%duplicated, \%definedIn, \%mergedNames);
}

sub _resolveCallee($$$$$)
{
    # Which alias a call to '$callee' from a site in '$fromFile' went to, as
    #   (alias, the file which defines it) - or an empty list if that cannot be
    #   decided.  See _symbolIndex for the three indexes and resolveCallSites for
    #   what the answer is used for;  the file is what reaches the per-testcase
    #   copies of the same alias (see _applyExternalCalls).
    # '$fromFile' need not be a file this report has:  a call from one it does
    #   not is exactly the case the linkage rule below is for
    my ($symbol, $duplicated, $definedIn, $fromFile, $callee) = @_;

    return ($symbol->{$callee}, $definedIn->{$callee})
        unless exists($duplicated->{$callee});
    my $candidates = $duplicated->{$callee};
    # The file the call is in defines a function of that name:  a call to a name
    #   the file defines goes to that definition
    my $alias = $candidates->{$fromFile};
    return ($alias, $fromFile) if defined($alias);
    # It does not, so the call went to a definition with external linkage:  a
    #   symbol which has not got it is unreachable from outside the file which
    #   defines it, so every file-local candidate is excluded outright and one
    #   external candidate is the answer.  That is the whole point of recording
    #   the linkage (see FunctionAlias::is_external):  without it an unrelated
    #   'static' of the same name in some third file voids a perfectly good
    #   cross-file call.
    # The rule is additive by construction - a candidate is only ever *asserted*
    #   external - so it can turn an unresolved site into a resolved one and can
    #   never change where a site which resolves today goes.  With no assertion
    #   anywhere, which is what data captured by a tool that does not record the
    #   flag looks like, nothing matches and the caller's ambiguity case is what
    #   happens
    my @external =
        grep({ $candidates->{$_}->is_external() } keys(%$candidates));
    return 1 == scalar(@external) ?
        ($candidates->{$external[0]}, $external[0]) :
        ();
}

sub _deducedExternalCalls
{
    # Whether the 'FNA:' record of '$name' gets the 'd' flag:  the summary of
    #   its file has resolved callers for it, and they account for fewer calls
    #   than it received - see lcovutil::deduced_external_calls.
    #   '$measured' is a reference to the answer of hasCallgraphData for the
    #   file, which is computed the first time it is needed
    my ($summary, $name, $measured, $calledSymbols) = @_;
    return 0 unless defined($summary);
    my $entry = $summary->findName($name);
    return 0 unless defined($entry);
    my $alias = $entry->alias($name);
    return 0 unless defined($alias) && $alias->is_resolved();
    $$measured = $summary->hasCallgraphData($calledSymbols)
        unless defined($$measured);
    return lcovutil::deduced_external_calls($alias, $$measured);
}

sub _callSiteFileIndex
{
    # The index each file is written under in the 'SF:' records of one tracefile,
    #   as a hash of file name to index, or an empty one when the report needs no
    #   index at all - see the 'SF:' description in geninfo(1) and the 'FNC:'
    #   writer in write_info.
    #
    # A file gets an index for one of two reasons:
    #   - some call site is written in it and contained in a function defined
    #     somewhere else, so an 'FNC:' record has to name it;
    #   - or the name itself begins with digits and a comma, which is the one
    #     spelling a reader could not tell from the optional index field.  Giving
    #     it an index makes the record unambiguous without touching the name,
    #     since the name is then the field which takes the rest of the line.
    # Nothing else does.
    #
    # The indexes are assigned in file-name order and are a property of this one
    #   tracefile:  nothing reads them once the file has been parsed, and two
    #   '.info' files may number the same file differently
    my $self = shift;
    my %needed;
    if ($lcovutil::callgraph_coverage) {
        foreach my $filename ($self->files()) {
            my $functionMap = $self->data($filename)->func();
            next unless $functionMap;
            foreach my $key ($functionMap->keylist()) {
                my $entry = $functionMap->findKey($key);
                foreach my $site ($entry->callSiteKeys()) {
                    my $siteFile = ($entry->callSiteData($site))[5];
                    $needed{$siteFile} = 1 if defined($siteFile);
                }
            }
        }
    }
    foreach my $filename ($self->files()) {
        $needed{$filename} = 1
            if ReadCurrentSource::resolve_path(
                                             $self->data($filename)->filename(),
                                             1) =~ /^\d+,/;
    }
    my %index;
    my $next = 0;
    foreach my $filename (sort(keys(%needed))) {
        $index{$filename} = $next++;
    }
    return \%index;
}

sub _pruneUnwritableSites
{
    # A call site written in a file this report does not have cannot be written
    #   to a '.info' file:  the record names the site's file by its index, and
    #   only an 'SF:' record can define an index - so a file with no section of
    #   its own has no index for the record to use.
    # That is not a malformed report:  it is what removing the file the call is
    #   written in while keeping the file the caller is defined in does -
    #   '--remove', '--extract', an exclude pattern, '--no-external'.  Which is
    #   exactly the case noteExternalCalls covers, so it gets the same treatment:
    #   the site goes, and the fact that the edge is there survives on the callee
    #   as FunctionAlias::has_external_callers.
    # Whole-report and parent-only, like every other question of the form "is
    #   this in the report":  resolveCallSites runs it with the index it has
    #   already built, and write_info runs it for a report which was never
    #   resolved.  Idempotent - a second pass finds nothing to do.
    # Returns the number of sites removed.
    my ($self, $symbol, $duplicated, $definedIn) = @_;
    return 0 unless $lcovutil::callgraph_coverage;
    my $haveIndex = defined($symbol);
    my %known     = map({ ($_ => 1) } $self->files());
    my @calls;
    my $removed = 0;
    foreach my $filename ($self->files()) {
        my $traceInfo   = $self->data($filename);
        my $functionMap = $traceInfo->func();
        next unless $functionMap;
        my $testfncdata = $traceInfo->testfnc();
        foreach my $key ($functionMap->keylist()) {
            my $entry = $functionMap->findKey($key);
            foreach my $site ($entry->callSiteKeys()) {
                my (undef, undef, undef, $count, $callee, $siteFile) =
                    $entry->callSiteData($site);
                next unless defined($siteFile) && !exists($known{$siteFile});
                lcovutil::info(
                             1,
                             "\"$siteFile\" is not in this report:  the call" .
                                 " to '$callee' in '" .
                                 $entry->name() .
                                 "' of \"$filename\" cannot be written and is" .
                                 " recorded on the callee\n");
                # '$filename' and not '$siteFile':  what decides which
                #   definition the call reached is the translation unit it was
                #   compiled in, which is where the caller is defined - the same
                #   rule resolveCallSites applies to a site it keeps.  Taken or
                #   not:  the flag says the edge exists, and the count it
                #   carries is the site's
                push(@calls,
                     lcovutil::external_call($filename, $callee, $count,
                                             $testfncdata, $key, $site));
                # ..from every testcase, and from the summary - the aliasing note
                #   in _filterUnknownCalleeCount applies here too
                foreach my $tn ($testfncdata->keylist()) {
                    my $f = $testfncdata->value($tn)->findKey($key);
                    $f->_removeSite($site) if $f;
                }
                $entry->_removeSite($site);
                ++$removed;
            }
        }
    }
    return 0 unless $removed;
    $self->noteExternalCalls(\@calls);
    # resolveCallSites applies these itself a moment later, with the index it
    #   already has;  a caller which only wants to write the report has no such
    #   pass, so the flag is set here
    unless ($haveIndex) {
        ($symbol, $duplicated, $definedIn) = $self->_symbolIndex(0);
        $self->_applyExternalCalls($symbol, $duplicated, $definedIn);
    }
    return $removed;
}

sub noteExternalCalls
{
    # Remember the calls made from a file this report is not keeping, as
    #   lcovutil::external_call records.  The site goes away with its file and nothing later
    #   can tell that it was ever there, so the fact that the edge is there is
    #   recorded on the *callee* instead - see
    #   FunctionAlias::has_external_callers.
    # Noted here and applied in resolveCallSites rather than at once, because the
    #   callee may be in a file this process has not read yet:  a parallel read
    #   gives each worker a run of sections, so the excluded caller and its callee
    #   can be in different chunks.  This list is part of the object and so
    #   crosses the fork with it (see serialize), and the merge of two reports
    #   keeps both lists
    my ($self, $calls) = @_;
    push(@{$self->[EXTERNAL_CALLS]}, @$calls) if @$calls;
}

sub _applyExternalCalls
{
    # Record every call noted by noteExternalCalls on its callee:  the flag,
    #   and the calls the site made.  resolveCallSites is the only caller:  by
    #   then the last input has been read and every callee which is in this
    #   report is in the index.
    # A callee which cannot be resolved is passed over in silence:  there is no
    #   one alias for the flag to go on, so there is nothing to record and
    #   nothing the user could do about it either.  Any calls which were taken are
    #   still counted in the callee's own execution count, which is where the
    #   residual in lcovutil::classify_callers finds them for as long as the count
    #   is there.
    # A call which is recorded is consumed, because its count is added to the
    #   callee's:  applying it again would count it twice.  One which is not
    #   stays on the list - resolveCallSites can run again after another input
    #   is merged, and a callee which that input brought in gets it on the next
    #   pass
    my ($self, $symbol, $duplicated, $definedIn) = @_;
    my @unresolved;
    foreach my $call (@{$self->[EXTERNAL_CALLS]}) {
        my ($fromFile, $callee, $count, $perTest) = @$call;
        my ($alias, $calleeFile) =
            TraceFile::_resolveCallee($symbol, $duplicated, $definedIn,
                                      $fromFile, $callee);
        if (!defined($alias)) {
            push(@unresolved, $call);
            next;
        }
        $alias->add_external_calls($count);
        # ..by the name it has, which a call to a name merged into it has not
        $callee = $alias->name();
        # ..and on the per-testcase copy of that alias, because the '.info'
        #   writer writes a section per testcase out of the per-testcase maps:
        #   a flag set only on the summary alias is written when the report has
        #   one testcase, where the two maps are the same object, and silently
        #   dropped when it has more.  Where they are the same object, the
        #   summary's count is already that testcase's.
        # Every testcase of the callee's file, and not some subset of them:  the
        #   removal which recorded this call took the site out of the report as a
        #   whole, so the edge is a fact about each of them - with the count that
        #   testcase had for the site, which is 0 for one which did not have it
        next unless defined($calleeFile);
        my $summaryAddr =
            Scalar::Util::refaddr($self->data($calleeFile)->func());
        my $testfncdata = $self->data($calleeFile)->testfnc();
        foreach my $tn ($testfncdata->keylist()) {
            my $map = $testfncdata->value($tn);
            next if Scalar::Util::refaddr($map) == $summaryAddr;
            my $entry = $map->findName($callee);
            next unless $entry;
            my $c = $perTest->{$tn};
            $entry->alias($callee)->add_external_calls(defined($c) ? $c : 0);
        }
    }
    $self->[EXTERNAL_CALLS] = \@unresolved;
}

sub _pruneExternalCallees
{
    # A call to a name no file in this report defines:  'printf', a template
    #   instantiated in a system header, a method of a third party library.  Such
    #   a callee is outside the boundary of the report, so the site is removed.
    #
    # Why:  the metric is meant to say whether the functions the report describes
    #   were exercised, and such a call cannot contribute to that answer.  Nothing
    #   in the report defines the callee, so there is no page for its name to lead
    #   to and no test the user could add to the report to cover it, while a C++
    #   report carries enough of them - every implicit 'std::' instantiation - to
    #   dominate the denominator.  What is kept is that the edge is there, on the
    #   caller, which is the end of it the report still has.
    # Dropping the site is not the same as losing what it measured:  the line the
    #   call is written on keeps its line count and a branch on that line keeps
    #   its branch counts, so whether the code which makes the call ran is still
    #   in the report - as an upper bound rather than a count, since a line can
    #   hold several calls and a call in a short-circuit or a ternary can be
    #   skipped on a line which ran.  The other end of a boundary crossing can be
    #   deduced much the same way:  a call from outside shows as the difference
    #   between a function's execution count and the counts of the sites the
    #   report does list - see classify_callers, which draws exactly that
    #   inference where no flag says that such an edge is there.
    # This is the mirror of _pruneUnwritableSites, which drops the sites whose
    #   *caller* is in no file of the report:  there the call is recorded on the
    #   callee and here it is recorded on the caller, each time on whichever end
    #   of the call the report is keeping - see
    #   FunctionEntry::has_external_callees.
    #
    # Whole-report and parent-only, like every other question of the form "is
    #   this in the report" - which is why the removal cannot be done by 'geninfo',
    #   and why a raw capture holds these sites.  The index is unaffected (it
    #   indexes definitions, not calls) and the pass is idempotent.  Returns the
    #   number of sites removed
    my ($self, $symbol, $duplicated) = @_;
    my $removed = 0;
    foreach my $filename ($self->files()) {
        my $traceInfo   = $self->data($filename);
        my $functionMap = $traceInfo->func();
        next unless $functionMap;
        my $testfncdata = $traceInfo->testfnc();
        foreach my $key ($functionMap->keylist()) {
            my $entry = $functionMap->findKey($key);
            foreach my $site ($entry->callSiteKeys()) {
                my ($line, undef, undef, undef, $callee, $siteFile) =
                    $entry->callSiteData($site);
                # "in the report" is both indexes:  a name several files define
                #   is in it whether or not this call can be told which of them
                #   it went to
                next
                    if exists($symbol->{$callee}) ||
                    exists($duplicated->{$callee});
                # the file to look at is the one the call is written in, which is
                #   the caller's own only when the two are the same
                my $where = defined($siteFile) ? $siteFile : $filename;
                lcovutil::info(2,
                    "\"$where\":$line: call to '$callee' is not in this report - dropping it\n"
                );
                # The site goes, and the fact that this function calls out of the
                #   boundary survives on it.  Whether the call was taken does not
                #   enter into it:  the flag says the edge is there, exactly as
                #   FunctionAlias::has_external_callers does at the other end of
                #   a crossing, and the count is what the site took with it
                $entry->set_external_callees();
                # ..from every testcase, and from the summary - the aliasing note
                #   in _filterUnknownCalleeCount applies here too
                foreach my $tn ($testfncdata->keylist()) {
                    my $f = $testfncdata->value($tn)->findKey($key);
                    $f->_removeSite($site) if $f;
                }
                $entry->_removeSite($site);
                ++$removed;
            }
        }
    }
    lcovutil::info(1,
                   "dropped $removed call site(s) whose callee is not in this" .
                       " report\n") if $removed;
    return $removed;
}

sub _filterUnknownCalleeCount
{
    # The 'unknown_callee_count' filter:  remove the call sites whose count
    #   this capture does not know - the unpaired calls, see the 'pairing' entry
    #   of the documentation glossary.
    #
    # Why a filter rather than a display rule:  a site with an unknown count is
    #   in 'found' and never in 'hit' (numCallSitesHit), so it is a ceiling on
    #   the rate which no test can lift.  Whether that ceiling is worth carrying
    #   is something only the user knows - the sites are the report's own calls,
    #   measured by a compiler which could not count them - so it is a filter they
    #   ask for and not something done to them.
    #
    # It runs from resolveCallSites, after the passes above:  a site this removes
    #   must be gone from the callee-side view as well, and that view is built
    #   there.  Consequently 'geninfo' accepts the filter and does not apply it -
    #   'lcov --capture' forwards '--filter' to it - and the site is removed when
    #   the report is assembled.
    #
    # The counts in the histogram are the same two every other filter reports:
    #   how many source locations it applied at, and how many coverpoints it
    #   removed.  Those differ here more than usual, since a location can hold
    #   several calls
    my $self   = shift;
    my $filter = $lcovutil::cov_filter[$lcovutil::FILTER_UNKNOWN_CALLEE_COUNT];
    return unless defined($filter);
    foreach my $filename ($self->files()) {
        my $traceInfo   = $self->data($filename);
        my $functionMap = $traceInfo->func();
        next unless $functionMap;
        my $testfncdata = $traceInfo->testfnc();
        my %seen;    # the locations this filter has already been counted at
        foreach my $key ($functionMap->keylist()) {
            my $entry = $functionMap->findKey($key);
            foreach my $site ($entry->callSiteKeys()) {
                my ($line, undef, undef, $count, $callee, $siteFile) =
                    $entry->callSiteData($site);
                next unless lcovutil::site_count_unknown($count);
                # the site's own file, which is the caller's only when the call
                #   is written where the caller is defined - and is what the
                #   location count below has to be keyed on for the same reason
                my $where = defined($siteFile) ? $siteFile : $filename;
                lcovutil::info(1,
                               'filter FNC (' .
                                   $filter->[0] .
                                   ") $where:$line" .
                                   " call to '$callee'\n");
                ++$filter->[-2] unless $seen{"$where:$line"}++;
                ++$filter->[-1];
                # ..from every testcase, and from the summary.  Both
                #   unconditionally:  when the two are aliased the second
                #   removal finds the site already gone and says so by
                #   returning false, which is not an error the way handing
                #   'remove' an undef would be
                foreach my $tn ($testfncdata->keylist()) {
                    my $f = $testfncdata->value($tn)->findKey($key);
                    $f->_removeSite($site) if $f;
                }
                $entry->_removeSite($site);
            }
        }
    }
}

sub _renameCalleesOf
{
    # Rename the callees of the call sites of '$entry' which '$rename' maps to
    #   another name:  all of them in one pass.  A site whose new callee is
    #   called from the same place already folds into that call - the counts
    #   are added and the alias set is the union of theirs - the way a merge of
    #   two inputs resolves the same disagreement (see _resolveCallSite).  The
    #   folded call keeps the ordinal of the call which had the name already,
    #   or else the lowest of theirs.  '$targets' holds every name '$rename'
    #   maps to.  Returns the number of sites the folding removed.
    # All at once, because one place in a template body may call a different
    #   function from each of thousands of instantiations, and those calls fold
    #   into one when the functions are merged:  renaming them one by one would
    #   look at that place once per call, and build every intermediate union of
    #   the alias sets
    my ($entry, $rename, $targets) = @_;
    my %groups;
    foreach my $key ($entry->callSiteKeys()) {
        my ($line, $column, $ordinal, $count, $callee, $file, $set, $statement)
            = $entry->callSiteData($key);
        my $to = $rename->{$callee};
        next unless defined($to) || $targets->{$callee};
        push(@{
                 $groups{
                     join("\0", $line, $column, $file // '', $to // $callee)
                 }
             },
             [$key, $ordinal, $count, $set, defined($to), $statement]);
    }
    my $folded = 0;
    foreach my $id (sort(keys(%groups))) {
        my $sites = $groups{$id};
        next unless grep({ $_->[4] } @$sites);
        my ($line, $column, $file, $callee) = split("\0", $id, 4);
        $file = undef if '' eq $file;
        my ($kept) = grep({ !$_->[4] } @$sites);
        my ($ordinal) =
            defined($kept) ? ($kept->[1]) :
            sort({ $a <=> $b } map({ $_->[1] } @$sites));
        my $set =
            (grep({ !defined($_->[3]) } @$sites)) ?
            undef :
            FunctionEntry::aliasSet(
                        map({ FunctionEntry::aliasSetNames($_->[3]) } @$sites));
        $entry->_removeSite($_->[0]) foreach @$sites;
        $entry->addCallSite($line, $column, $ordinal, $_->[2], $callee,
                            $file, 0, $set, $_->[5]) foreach @$sites;
        $folded += scalar(@$sites) - 1;
    }
    $entry->_dropSiteIndex() if %groups;
    return $folded;
}

sub _renameCallees
{
    # Rename the callee of every call site, in the summary and in every
    #   testcase, for which '$to' has an answer:  called with the file of the
    #   caller and the callee, it returns the new name or undef.  '$names' is
    #   every name it may answer for, which is all most sites are looked up in.
    #   See _renameCalleesOf for what happens to the sites
    my ($self, $names, $to) = @_;
    foreach my $filename ($self->files()) {
        my $traceInfo = $self->data($filename);
        my @maps      = ($traceInfo->func());
        unless ($traceInfo->isAliased(TraceInfo::FUNCTION_DATA)) {
            my $testfnc = $traceInfo->testfnc();
            push(@maps, map({ $testfnc->value($_) } $testfnc->keylist()));
        }
        # the answers for this file, as they are needed
        my (%rename, %targets);
        foreach my $map (@maps) {
            foreach my $key ($map->keylist()) {
                my $entry = $map->findKey($key);
                my $any;
                foreach my $site ($entry->callSiteKeys()) {
                    my $callee = ($entry->callSiteData($site))[4];
                    next unless $names->{$callee};
                    unless (exists($rename{$callee})) {
                        my $name = $to->($filename, $callee);
                        $name = undef if defined($name) && $name eq $callee;
                        $rename{$callee} = $name;
                        $targets{$name}  = 1 if defined($name);
                    }
                    $any = 1 if defined($rename{$callee});
                }
                _renameCalleesOf($entry, \%rename, \%targets) if $any;
            }
        }
    }
}

sub _renameMergedCallees
{
    # Every call to a name which is not defined but was merged into an alias
    #   (see _symbolIndex) is a call to that alias's name, so that everything
    #   which follows sees one name for one callee.  This is a call written
    #   somewhere the merge did not see - typically a use of an instantiation
    #   which another file defines ('extern template'), read after that file was
    #   collapsed
    my ($self, $symbol, $duplicated, $definedIn, $mergedNames) = @_;
    $self->_renameCallees($mergedNames,
                          sub {
                              my ($filename, $callee) = @_;
                              my ($alias) =
                                  TraceFile::_resolveCallee(
                                               $symbol, $duplicated, $definedIn,
                                               $filename, $callee);
                              return defined($alias) ? $alias->name() : undef;
                          });
}

sub adoptAliasNames
{
    # Rename my aliases to the names '$other' keeps for them, where the two
    #   merged them differently - see _collapseCallgraphAliases.  The name kept
    #   is the shortest of the names merged, so two versions of one program
    #   keep different names when one has an instantiation the other has not:
    #   one keeps 'f<ab>' for 'f<ab>', 'f<int>' and 'f<char>', and the other
    #   'f<int>' for 'f<int>' and 'f<char>'.  The differential report matches
    #   functions, callers and callees by name, and would see one name gone and
    #   another new, where it should compare the two.  genhtml calls this on
    #   the baseline with the current data, which is the version every page
    #   shows.
    # An alias of mine is renamed to the alias of '$other' which stands for
    #   its name or, failing that, for one of the names merged into it - the
    #   first, in sort order, which '$other' has an answer for.  Two of mine
    #   which '$other' merged become one, since there is only one name in
    #   '$other' to compare them with;  but a name '$other' merged into two
    #   different aliases, in different files, is not an answer.  Nor is a name
    #   which another function of the same file has.  The counts and the
    #   merged names go with each alias as they do when it is collapsed, and
    #   every call to it is a call to its new name.
    # Returns the number of aliases renamed:  if there are any, the
    #   callee-side view has to be built again (see resolveCallSites)
    my ($self, $other) = @_;

    # every name an alias of '$other' stands for, and that alias's name - or
    #   undef, if there is more than one
    my %kept;
    foreach my $filename ($other->files()) {
        my $map = $other->data($filename)->func();
        foreach my $key ($map->keylist()) {
            my $entry = $map->findKey($key);
            foreach my $name ($entry->aliasNames()) {
                my $merged = $entry->alias($name)->merged();
                foreach my $n ($name, defined($merged) ? keys(%$merged) : ()) {
                    $kept{$n} =
                        (exists($kept{$n}) && ($kept{$n} // '') ne $name) ?
                        undef :
                        $name;
                }
            }
        }
    }

    my ($renamed, %callees) = (0);
    foreach my $filename ($self->files()) {
        my $traceInfo = $self->data($filename);
        my $map       = $traceInfo->func();
        foreach my $key ($map->keylist()) {
            my $entry = $map->findKey($key);
            my %renames;
            foreach my $name ($entry->aliasNames()) {
                my $to = $kept{$name};
                unless (exists($kept{$name})) {
                    my $merged = $entry->alias($name)->merged() // {};
                    my ($first) =
                        grep({ exists($kept{$_}) } sort(keys(%$merged)));
                    $to = $kept{$first} if defined($first);
                }
                next unless defined($to) && $to ne $name;
                my $owner = $map->findName($to);
                next if defined($owner) && $owner != $entry;
                $renames{$name} = $to;
                $callees{$name} =
                    (exists($callees{$name}) && ($callees{$name} // '') ne $to)
                    ?
                    undef :
                    $to;
            }
            next unless %renames;
            $renamed += scalar(keys(%renames));
            _renameAliases($map, $entry, \%renames);
            next if $traceInfo->isAliased(TraceInfo::FUNCTION_DATA);
            my $testfnc = $traceInfo->testfnc();
            foreach my $tn ($testfnc->keylist()) {
                my $copy = $testfnc->value($tn)->findKey($key);
                _renameAliases($testfnc->value($tn), $copy, \%renames)
                    if defined($copy);
            }
        }
    }
    $self->_renameCallees(\%callees, sub { return $callees{$_[1]} })
        if $renamed;
    return $renamed;
}

sub _renameAliases
{
    # Each alias of '$entry' which '$renames' maps to another becomes that
    #   one:  its calls are made by the other, its count and its 'x' calls are
    #   added to the other's, and it is gone.  The callee side - the sites which
    #   call it - is the caller's business:  see _collapseCallgraphAliases.
    #   '$map' is the FunctionMap '$entry' is in, whose name index has to forget
    #   the names too.
    # Every name at once, because the sites are what costs:  a template with
    #   thousands of instantiations has thousands of sites, and renaming one
    #   name at a time would visit each of them once per name
    my ($map, $entry, $renames) = @_;
    my @gone = grep({ defined($entry->alias($_)) } sort(keys(%$renames)));
    return unless @gone;
    foreach my $key ($entry->callSiteKeys()) {
        my $set = ($entry->callSiteData($key))[6];
        next unless defined($set);
        my @names = FunctionEntry::aliasSetNames($set);
        next unless grep({ exists($renames->{$_}) } @names);
        $entry->_setSiteAliases($key,
                                FunctionEntry::aliasSet(
                                            map({ $renames->{$_} // $_ } @names)
                                ));
    }
    foreach my $loser (@gone) {
        my $gone = $entry->alias($loser);
        my ($count, $external, $flagged, $calls, $merged) = (
                                           $gone->count(), $gone->is_external(),
                                           $gone->has_external_callers(),
                                           $gone->external_calls(),
                                           $gone->merged());
        my $winner = $renames->{$loser};
        $entry->_addAliasCount($winner, $count);
        # ..which, if it is a new name here, my name index has to find
        $map->_registerName($winner, $entry)
            unless defined($map->findName($winner));
        my $alias = $entry->alias($winner);
        $alias->set_external() if $external;
        $alias->add_external_calls(defined($calls) ? $calls : '-') if $flagged;
        # ..and the winner now stands for the loser's name, and for every name
        #   which an earlier merge folded into the loser
        #   - each with its own share of the count, which for the loser is what
        #   that earlier merge did not give to another name
        $merged //= {};
        my $own = $count;
        $own -= $_ foreach values(%$merged);
        $alias->add_merged($loser, $own, %$merged);
        $map->_unregisterName($loser);
    }
    $entry->removeAliases(@gone);
}

sub _collapseCallgraphAliases
{
    # The 'collapse_callgraph_alias' setting:  merge the aliases of one
    #   function which are indistinguishable in the callgraph.
    #   A template instantiated for several types, or a function the compiler
    #   cloned, is one FunctionEntry with several names, and whether their
    #   calls differ is what call site attribution tells us (see SITE_ALIASES).
    #   Where they do not - each alias calls the same functions from the same
    #   places and is called from the same places - the separate names are
    #   clutter in the report, and this folds them into one.
    #
    # "The same" is a property of the edges, not of the records:
    #   a call is (the file it is written in, its line, its column, the function
    #   at the other end), where "function" is the FunctionEntry - so a call to
    #   'g<int>' and a call to 'g<char>' from the same place are the same call
    #   if those are aliases of one function.  The ordinal and the count are not
    #   part of it:  the first is a numbering, and the second is what is being
    #   added up.  Two aliases merge if they have the same set of calls in each
    #   direction - none at all included - and agree about the 'e' flag (a
    #   linkage is a property of the symbol, and one of them having it would be
    #   lost or invented by the merge) and about having an 'x' flag (one
    #   asserting external callers and the other not is a difference in the
    #   callgraph which no site records).  An alias whose name more than one
    #   file defines is left alone:  which definition a call to it reached is
    #   decided per site, so renaming it is not a local edit.
    #
    # The retained name is FunctionEntry::preferredName of the group;  it gets
    #   the sum of the counts and of the 'x' calls, and remembers each merged
    #   name with its own count (see FunctionAlias::merged).  A call which both
    #   made from one place is two sites when their callees differ by name, and
    #   is one site - with the sum of their counts - once the callee is merged.
    #
    # Runs from resolveCallSites after the sites are resolved, because both
    #   directions of a call are what it compares, and the callers it changes
    #   are corrected in place - only the merged names' lists change, so the
    #   rest of the resolution stands.  Returns the number of resolved sites the
    #   merge removed.
    #
    # The two flags are a hard rule, and there is no setting which merges
    #   aliases that differ in them:
    #     - a different 'x' flag means one alias had callers the callgraph
    #       could not name and the other did not - which is a difference in the
    #       callers, the very thing that two aliases have to agree about to be
    #       merged.  Merging them would claim callers for a name which had none.
    #     - a different 'e' flag is usually not a property of the code but of
    #       the captures:  gcc 14 and later record the linkage and older
    #       versions do not, so data merged from both says 'e' for one
    #       instantiation and nothing for another.  Merging them with the flag
    #       set would usually be right, but would lose which name had the
    #       linkage, and the linkage is what resolves a call to a name several
    #       files define (see _resolveCallee).
    #   The '-v' summary below says how many groups were kept apart by the one
    #   flag alone and by the other alone.  If the 'e' count turns out to be
    #   common in real data, the better answer is to treat a missing 'e' as
    #   unknown rather than as "not external", and to merge in every case
    #   - not to add a setting.
    #
    # The cost is linear in the size of the data:  a hash of each alias's edges,
    #   built once, then one pass over the sites of an entry for all the names
    #   merged in it (see _renameAliases), and a site which every alias makes
    #   - one with no alias set - is left out of the comparison altogether,
    #   since it is the same for all of them.  So there is no XS
    #   implementation:  this runs once per report, and '--profile' is what
    #   would say whether it ever needs one
    my ($self, $symbol, $duplicated, $definedIn) = @_;
    return 0 unless $lcovutil::collapse_callgraph_alias;

    # every name merged, and the name it was merged into;  the function each
    #   name kept is an alias of;  and the functions which call any of them
    my (%rename, %winners, %callers);
    # the FunctionEntry a call to '$callee' from '$fromFile' reached - a merged
    #   name included, which its entry no longer knows:  the calls to it are
    #   renamed only at the end
    my $destination = sub {
        my ($fromFile, $callee) = @_;
        my ($alias, $file) =
            TraceFile::_resolveCallee($symbol, $duplicated, $definedIn,
                                      $fromFile, $callee);
        return "?$callee" unless defined($alias) && defined($file);
        my $entry =
            $self->data($file)->func()->findName($rename{$callee} // $callee);
        return defined($entry) ? "$file\0" . $entry->line() : "?$callee";
    };
    # the per-testcase maps of a file, unless they are its summary
    my %testMaps;
    my $testMaps = sub {
        my $filename = shift;
        return @{
            $testMaps{$filename} //= do {
                my $traceInfo = $self->data($filename);
                my $testfnc   = $traceInfo->testfnc();
                $traceInfo->isAliased(TraceInfo::FUNCTION_DATA) ? [] :
                    [map({ $testfnc->value($_) } sort($testfnc->keylist()))];
            }
        };
    };

    my ($removed, $onlyLinkage, $onlyExternal) = (0, 0, 0);
    # a file which nothing measured the calls of has the same signature - none -
    #   for every alias, which says nothing about whether they differ
    my $called = $self->calledSymbols();
    foreach my $filename (sort($self->files())) {
        my $traceInfo   = $self->data($filename);
        my $functionMap = $traceInfo->func();
        next unless $functionMap && $functionMap->hasCallgraphData($called);
        foreach my $key (sort({ $a <=> $b } $functionMap->keylist())) {
            my $entry = $functionMap->findKey($key);
            next unless defined($entry);
            my @names = $entry->aliasNames();
            next if scalar(@names) < 2;
            my %calls = map({ ($_ => {}) }
                            grep({ !exists($duplicated->{$_}) } @names));
            next if scalar(keys(%calls)) < 2;
            # what each alias calls - other than what they all call, which
            #   tells none of them apart
            foreach my $site ($entry->callSiteKeys()) {
                my ($line, $column, undef, undef, $callee, $siteFile, $set) =
                    $entry->callSiteData($site);
                next unless defined($set);
                my $edge = join("\0",
                                '>', $siteFile // '',
                                $line, $column,
                                $destination->($filename, $callee));
                foreach my $name (FunctionEntry::aliasSetNames($set)) {
                    $calls{$name}->{$edge} = 1 if exists($calls{$name});
                }
            }
            # ..and what calls it
            foreach my $name (keys(%calls)) {
                foreach my $row ($entry->alias($name)->callers()) {
                    # [callerEntry, line, column, ordinal, count, file]
                    my ($from, $line, $column, undef, undef, $file) = @$row;
                    $calls{$name}->{
                        join("\0",
                             '<', $file // $from->file(),
                             $line, $column,
                             $from->file(), $from->line())
                    } = 1;
                }
            }
            my (%bySignature, %renames);
            foreach my $name (sort(keys(%calls))) {
                push(@{
                         $bySignature{join("\1", sort(keys(%{$calls{$name}})))}
                     },
                     $name);
            }
            foreach
                my $group (sort({ $a->[0] cmp $b->[0] } values(%bySignature))) {
                next if scalar(@$group) < 2;
                my %byFlags;
                foreach my $name (@$group) {
                    my $alias = $entry->alias($name);
                    push(@{
                             $byFlags{
                                 ($alias->is_external() ? 'e' : '') .
                                     ($alias->has_external_callers() ? 'x' : '')
                             }
                         },
                         $name);
                }
                if (scalar(keys(%byFlags)) > 1) {
                    # the same calls, and kept apart by a flag:  said at
                    #   verbosity 1, since which of the two it was is what a
                    #   user wondering why would want to know
                    my @e = sort(keys(
                                      %{{
                                         map({ ((/e/ ? 1 : 0) => 1) }
                                             keys(%byFlags))
                                      }}
                    ));
                    my @x = sort(keys(
                                      %{{
                                         map({ ((/x/ ? 1 : 0) => 1) }
                                             keys(%byFlags))
                                      }}
                    ));
                    ++$onlyLinkage if 1 == scalar(@x);
                    ++$onlyExternal if 1 == scalar(@e);
                    lcovutil::info(1,
                                   "collapse FNA \"$filename\":" .
                                       $entry->line() .
                                       ' not merging ' .
                                       join(', ', map({ "'$_'" } @$group)) .
                                       ':  they differ in the '
                                       .
                                       (1 == scalar(@x) ? "'e'" :
                                            1 == scalar(@e) ? "'x'" :
                                            "'e' and 'x'") .
                                       " flag\n");
                }
                foreach my $flags (sort(keys(%byFlags))) {
                    my $winner =
                        FunctionEntry::preferredName(@{$byFlags{$flags}});
                    my @same =
                        sort(grep({ $_ ne $winner } @{$byFlags{$flags}}));
                    next unless @same;
                    $winners{$winner} = $entry;
                    foreach my $loser (@same) {
                        lcovutil::info(1,
                                       "collapse FNA \"$filename\":" .
                                           $entry->line() .
                                           " merged '$loser' into '$winner'\n");
                        # every call the loser made is the winner's:  below,
                        #   for every group of this function at once..
                        $renames{$loser} = $winner;
                        # ..and every call to it is a call to the winner:  at
                        #   the end, once for each caller
                        $rename{$loser} = $winner;
                    }
                    # ..which are the callers of any of them
                    foreach my $name ($winner, @same) {
                        foreach my $row ($entry->alias($name)->callers()) {
                            my $from = $row->[0];
                            $callers{$from->file() . "\0" . $from->line()} //=
                                $from;
                        }
                    }
                }
            }
            next unless %renames;
            _renameAliases($functionMap, $entry, \%renames);
            foreach my $map ($testMaps->($filename)) {
                my $copy = $map->findKey($key);
                _renameAliases($map, $copy, \%renames) if defined($copy);
            }
        }
    }
    if (%rename) {
        my %targets = map({ ($_ => 1) } keys(%winners));
        my %rows;
        foreach my $id (sort(keys(%callers))) {
            my $from = $callers{$id};
            $removed += _renameCalleesOf($from, \%rename, \%targets);
            # ..in every testcase as well
            if ($self->contains($from->file())) {
                foreach my $map ($testMaps->($from->file())) {
                    my $copy = $map->findKey($from->line());
                    _renameCalleesOf($copy, \%rename, \%targets)
                        if defined($copy);
                }
            }
            # ..and the callers of a winner are its own sites and the losers'
            #   - some of them folded together
            foreach my $site ($from->callSiteKeys()) {
                my ($line, $column, $ordinal, $count, $callee, $file) =
                    $from->callSiteData($site);
                push(@{$rows{$callee}},
                     ["$id\0$site", $from, $line, $column,
                      $ordinal, $count, $file
                     ]) if exists($winners{$callee});
            }
        }
        foreach my $winner (sort(keys(%winners))) {
            my $alias = $winners{$winner}->alias($winner);
            $alias->clear_callers();
            foreach
                my $row (sort({ $a->[0] cmp $b->[0] } @{$rows{$winner} // []}))
            {
                my (undef, @caller) = @$row;
                $alias->add_caller(@caller);
            }
        }
    }
    lcovutil::info(1,
        "collapse_callgraph_alias:  $onlyLinkage group(s) of aliases not merged only because their 'e' flags differ, $onlyExternal only because their 'x' flags differ\n"
    ) if $onlyLinkage || $onlyExternal;
    return $removed;
}

sub resolveCallSites
{
    # Turn the caller-side call data into the callee-side view of it:  tell
    #   every FunctionAlias which call sites called it.  Returns the number of
    #   sites which resolved and the number which did not.
    #
    # The authoritative data is the other direction - the sites a function
    #   contains, on that function's own entry - because that is local to one
    #   file and so merges, filters and serializes with no cross-file step, and
    #   because every removal is then a local edit.  This direction is derived,
    #   and never merged, serialized or incrementally maintained:  so nothing
    #   can dangle, because nothing persists.  It must run
    #     - after the last input is merged, or a file read later re-adds sites
    #       which an already-resolved alias has counted;
    #     - after every filter and every removal, so that no removal has to be
    #       propagated to another file;
    #     - before any summary, since the callgraph metric reads the result;
    #     - in the parent, never across a fork (see serialize).
    #   Every alias is reset first, so this is idempotent:  anything which
    #   invalidates the report can run it again instead of patching it.
    my $self = shift;

    # Index the callees, and reset the callee side while we are there
    my ($symbol, $duplicated, $definedIn, $mergedNames) =
        $self->_symbolIndex(1);
    # ..then the calls to a merged name, which are calls to the retained name:
    #   first, so that everything below sees one name for one callee
    $self->_renameMergedCallees($symbol, $duplicated, $definedIn, $mergedNames)
        if %$mergedNames;
    # ..then the sites which are in a file this report has not got, which have to
    #   go before anything counts them:  they cannot be written, so a summary
    #   which counted them would not match the '.info' file of the same report
    $self->_pruneUnwritableSites($symbol, $duplicated, $definedIn);
    # ..then the calls which went out of the report, which is the other half of
    #   the same question and is asked before the filter below so that the filter
    #   is not credited with removing a site which was going anyway
    $self->_pruneExternalCallees($symbol, $duplicated);
    # ..then the filter, before anything counts a site:  a site it removes must be
    #   gone from both views, and the index is unaffected (it indexes definitions,
    #   not calls), so it does not have to be built again afterwards
    $self->_filterUnknownCalleeCount();
    # ..then the calls whose own sites are gone, which the index is also what
    #   resolves.  Before the sites below, so that a callee gets its flag whether
    #   or not it has a nameable caller as well
    $self->_applyExternalCalls($symbol, $duplicated, $definedIn);

    my $resolved   = 0;
    my $unresolved = 0;
    foreach my $filename ($self->files()) {
        my $functionMap = $self->data($filename)->func();
        foreach my $key ($functionMap->keylist()) {
            my $entry = $functionMap->findKey($key);
            foreach my $site ($entry->callSiteKeys()) {
                my ($line, $column, $ordinal, $count, $callee, $siteFile) =
                    $entry->callSiteData($site);
                # '$filename' and not the site's own file, for a call written in
                #   an '#include'd fragment:  the caller is defined is one
                #   (of several) static functions with the same name -
                #   in the translation unit where the call was compiled. The
                #   site's file is where the call is written in, which the
                #   header included by two units does not tell us
                my ($alias) =
                    TraceFile::_resolveCallee($symbol, $duplicated, $definedIn,
                                              $filename, $callee);
                # ..and the file the message below names is the other one:  it
                #   is telling the user where to look at the source
                my $where = defined($siteFile) ? $siteFile : $filename;
                if (defined($alias)) {
                    $alias->add_caller($entry, $line, $column,
                                       $ordinal, $count, $siteFile);
                    ++$resolved;
                } elsif (exists($duplicated->{$callee})) {
                    # Several files define this name, this file is not one of
                    #   them, and the linkage does not single one of them out:
                    #   the site is counted where it is, on its own caller, and
                    #   is absent from every callee-side view.
                    # Said out loud, unlike the case below, because it is a
                    #   caller the callee's page should have listed and does not
                    #   - a loss of information rather than the ordinary shape
                    #   of a call out of the report.  A warning and not an error:
                    #   the caller-side totals are unaffected, so the report is
                    #   still correct as far as it goes
                    # Two different data scenarios reach here and the advice is not
                    #   the same for them:  no candidate carries the linkage
                    #   assertion, which is what a capture that could not record
                    #   it looks like and is fixable by capturing again;  or more
                    #   than one does, which no single program can produce (one
                    #   name, one external definition) and recapturing will not
                    #   change.  The candidates are named either way, since the
                    #   answer is one of them and only the user can say which
                    my $candidates = $duplicated->{$callee};
                    my @files      = sort(keys(%$candidates));
                    my @external =
                        grep({ $candidates->{$_}->is_external() } @files);
                    my $linkage;
                    if (@external) {
                        $linkage = scalar(@external) .
                            " of them are recorded as having external linkage - at most one definition of a name can have it in a program which links, so this data covers more than one program, or the linkage records disagree";
                    } else {
                        $linkage =
                            "none of them is recorded as having external linkage (capture with '--callgraph-coverage' using gcc 14 or later to record it)";
                    }
                    # ..only the first few, when there are many:  the point is
                    #   that the name is ambiguous, not the whole list
                    my @named = @files;
                    splice(@named, 3, scalar(@named) - 3, '...')
                        if scalar(@named) > 3;
                    # "this file" is the file the caller is defined in, which is
                    #   the one the linkage rule asked about - and is named
                    #   outright when the call is written somewhere else
                    my $defining =
                        defined($siteFile) ? "\"$filename\"" : 'this file';
                    my $msg =
                        "\"$where\":$line: call to '$callee' cannot be resolved:  ";
                    $msg .= scalar(@files) .
                        " file(s) define that name, $defining defines none of them, and $linkage.  ";
                    $msg .= 'The candidates are: ' . join(', ', @named) . '.  ';
                    $msg .=
                        "The call is counted on '" .
                        $entry->name() .
                        "' and is missing from the callee's list of callers.";
                    lcovutil::ignorable_warning(
                                             $lcovutil::ERROR_INCONSISTENT_DATA,
                                             $msg);
                    ++$unresolved;
                } else {
                    # The callee is not described by this report at all:  the
                    #   treatment 'printf' gets, and an ordinary thing rather
                    #   than a problem, so it is only said on request.
                    # Not normally reached:  _pruneExternalCallees has taken every
                    #   such site out a moment ago, this being the same question it
                    #   asks.  Kept as the honest answer for a site which somehow
                    #   survives it - counted as unresolved rather than passed over
                    lcovutil::info(2,
                        "\"$where\":$line: call to '$callee' is not in this report\n"
                    );
                    ++$unresolved;
                }
            }
        }
    }
    # ..and, if asked, the aliases which the resolved callgraph cannot tell
    #   apart are merged:  a merged site is one fewer resolved
    $resolved -=
        $self->_collapseCallgraphAliases($symbol, $duplicated, $definedIn);
    $callSitesResolved = 1;
    return ($resolved, $unresolved);
}

sub checkCallgraphData
{
    # '--callgraph-coverage' asked for on data which has no call sites anywhere.
    #   Unlike the contradictions parseOptions catches, this one is a property
    #   of the input rather than of the options, so it cannot be known at option
    #   time:  hence ERROR_EMPTY, the class "no valid records found in
    #   tracefile" already uses.
    #
    # The condition is that NO file has a site.  A single file with none is
    #   entirely ordinary - a header holding only inline definitions, a leaf
    #   translation unit, a file all of whose functions were filtered - so a
    #   per-file test would fire on perfectly good reports.
    #
    # Call this from the parent only, after the last input is merged and after
    #   filtering, which is why it lives beside resolveCallSites and is called
    #   from the same place:  a chunk which happens to hold no calls is not a
    #   report with no calls, which is the same trap the ERROR_EMPTY in
    #   _read_info documents.
    #
    # Ignoring it turns the metric off, as ignoring the option-time checks does.
    #   Here that has a visible consequence:  otherwise every summary would
    #   carry a callee column reading 0/0, which invites the reader to conclude
    #   the code makes no calls, rather than that the metric was never measured.
    #
    # The message, the predicate and the turning-off are this type's row in
    #   '@lcovutil::coverType' - the same check 'checkEmpty' makes for every
    #   type.  This name stays because the callers which have only this metric
    #   to ask about read better for it.
    my $self = shift;

    $self->checkEnabledMetric(lcovutil::COVER_TYPE_CALLGRAPH);
}

sub hasCallgraphData
{
    # Does this report carry any callgraph information at all?  See
    #   checkCallgraphData for why the question is asked of the whole report
    #   rather than file by file.
    #
    # Not the same question as 'callgraph_found() != 0', which counts call sites
    #   only.  Resolution turns a call whose callee is not in the report into a
    #   crossing - the 'c' flag on the calling function, and its mirror on an
    #   alias which external callers reached - and stops counting it as a site.
    #   So a report can hold nothing but crossings:  found is 0, and the report
    #   still says that these functions call out of the boundary and those are
    #   called from outside it.  Turning the metric off there would erase that,
    #   because both flags are written only while it is on.
    #
    # The per-file question is FunctionMap::hasCallgraphData, and this is it
    #   asked of every file - without the term which says that some other file
    #   calls into this one, because a call into one file is a call site in
    #   another and this loop has already found it there.
    my $self = shift;

    foreach my $filename ($self->files()) {
        return 1 if $self->data($filename)->func()->hasCallgraphData();
    }
    return 0;
}

sub calledSymbols
{
    # The name of every symbol some call site in this report names, as a set.
    #   What it answers is whether anything in the report calls into a given
    #   file, which is one of the things which makes that file's callgraph data
    #   real - see FunctionMap::hasCallgraphData.
    #
    # Names, rather than the callers resolution attaches to each callee, for two
    #   reasons.  The '.info' writer asks this question, and geninfo writes
    #   before resolution has run (see resolveCallSites), so an answer which
    #   needed it would differ between a capture and a rewrite of the same data.
    #   And a name which several files define counts for each of them, which errs
    #   towards keeping a claim rather than dropping one - the direction an
    #   ambiguity should be resolved in here, because the claim is what the
    #   measurement actually supports
    my $self = shift;
    my %called;
    foreach my $filename ($self->files()) {
        my $functionMap = $self->data($filename)->func();
        foreach my $key ($functionMap->keylist()) {
            my $data = $functionMap->findKey($key);
            foreach my $site ($data->callSiteKeys()) {
                my $callee = ($data->callSiteData($site))[4];
                $called{$callee} = 1;
            }
        }
    }
    return \%called;
}

sub dropUnmeasurableCallgraph
{
    # '--callgraph-coverage' asked for, and this run captured no call site at
    #   all:  the metric is not measurable here, so turn it off rather than
    #   leave it on with nothing in it.
    #
    # The reason was already reported where it was found - per object, as
    #   ERROR_UNSUPPORTED for a build without '-fcallgraph-info', or per
    #   function, as ERROR_INCONSISTENT for sites whose arcs an optimization
    #   removed.  Having chosen to ignore that, the user does not need a second
    #   error saying the same thing in more general terms; what they need is for
    #   the run to continue in a coherent state, which is the state
    #   'reject_metric' and 'checkCallgraphData' also leave it in:  off, and
    #   writing no records for the metric.
    #
    # Decided in the parent, after the last object is merged, for two reasons.
    #   The per-object error is raised inside a worker, and a worker's flag
    #   settings do not cross back over the fork - only its coverage data does.
    #   And one object without the data is ordinary in a build where another
    #   object has it, so the answer is not a property of any single object.
    my $self = shift;

    return if !$lcovutil::callgraph_coverage || $self->hasCallgraphData();
    lcovutil::info(
        "--callgraph-coverage: no call site was captured - turning the metric off.\n"
    );
    $lcovutil::callgraph_coverage = 0;
}

# file name -> the flags of its languages;  cleared when an extension list
#   changes - see 'lcovutil::set_extensions'
our %languageCache;

# The languages of file 'filename':  the OR of the 'lcovutil::IS_*' flags of
#   each language whose extension list holds the file's extension
sub language
{
    my $filename = shift;
    my $known    = $languageCache{$filename};
    return $known if defined($known);
    my $idx   = rindex($filename, '.');
    my $ext   = $idx == -1 ? '' : substr($filename, $idx);
    my $flags = 0;
    foreach my $l (keys(%lcovutil::languageExtensions)) {
        my $extensions = $lcovutil::languageExtensions{$l};
        $flags |= $lcovutil::languageFlag{$l}
            if ($lcovutil::case_insensitive ? $ext =~ /\.($extensions)$/i :
                $ext =~ /\.($extensions)$/);
    }
    return $languageCache{$filename} = $flags;
}

# Is file 'filename' in any of the languages 'flags' - an OR of 'lcovutil::IS_*'
sub is_language
{
    my ($flags, $filename) = @_;
    return 0 != (language($filename) & $flags);
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
              SEC_START    => 0,  # offset of the section's first byte
              SEC_END      => 1,  # offset just past its 'end_of_record' line
              SEC_LINE     => 2,  # '.info' line number of its first line
              SEC_NLINES   => 3,  # number of lines in it
              SEC_FILE     => 4,  # its 'SF:'/'KF:' name, undef if it has none
              SEC_TESTNAME => 5,  # payload of the 'TN:' in force, undef if none
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
    my $sf = $1;
    # ..remembered here rather than read as '$-[0]' below, because the
    #   substitutions which follow overwrite it when they match
    my $head = substr($section, 0, $-[0]);
    # '.' matches a CR, and '_read_info' strips trailing whitespace from the
    #   record before it looks at it (which is how a CRLF '.info' file is read at
    #   all), so strip it here too:  'SF:foo.c' and "SF:foo.c\r" are one source
    #   file to the reader and must be one name here.  Same test as there.
    $sf =~ s/\s+$//
        if (length($sf) && substr($sf, -1) lt '!');
    # 'SF:[<index>,]<name>':  drop the optional index, so that a section which
    #   carries one is grouped with the sections of the same file which do not -
    #   the name is what the partitioner compares.  Same expression as the
    #   reader's - see the 'SF:' arm of '_read_info'.
    $sf =~ s/^\d+,//;
    my ($tn) = $head =~ /^TN:(.*)$/m;
    $tn =~ s/\s+$//
        if (defined($tn) && length($tn) && substr($tn, -1) lt '!');
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

# A call site which named the file it is written in by index is held as one of
#   these until the read is over - see '%pendingSites' in '_read_info'.  Name the
#   fields rather than counting commas at each use.
use constant {
              PEND_OWNER    => 0,    # file the site's function is defined in
              PEND_TESTNAME => 1,    # testcase the section belonged to
              PEND_ALIAS    => 2,    # name the 'FNA:' record gave the function
              PEND_LINE     => 3,
              PEND_COLUMN   => 4,
              PEND_ORDINAL  => 5,
              PEND_COUNT    => 6,
              PEND_CALLEE   => 7,
              PEND_AT       => 8,    # '.info' line the 'FNC:' record is on
              PEND_ALIASES  => 9,    # the aliases which make the call
};

# Work out which file each pending call site is written in, and return the sites
#   with that file prefixed, for '_addDeferredSites' to install - see
#   '%pendingSites' in '_read_info'.
#
# '$defined' is what the read saw:  index -> [['.info' line, file name], ...], in
#   file order, with an entry for every 'SF:' record which gave that index a name.
#   A site takes the FIRST definition at or after it, and the last one before it
#   if there is none.  That is what makes the concatenation of two '.info' files
#   readable:  an index is a property of one tracefile, so each half numbers the
#   files it names for itself, and the definition which applies to a site is the
#   one its own half gave.  The usual case - one writer, which defines a file's
#   index on that file's own section - is a reference forward, since two files can
#   call into each other and no order of the sections can avoid it.
#
# An index the read never saw defined is normally a malformed tracefile, and
#   reported as one;  but a chunk of a parallel read sees only its own run of
#   sections, so the record which defines the index may be in another chunk.  That
#   is what '$rescan' is for, and the scan is cheap for the same reason
#   'scan_sections' is:  it looks only at the file records, and it only runs for a
#   chunk which really does hold a site it cannot resolve on its own.  A chunk is
#   only ever built for a seekable input (see '_read_info'), so the handle can be
#   rewound and re-read.
sub _resolvePendingSites
{
    my ($self, $hdl, $pending, $defined, $tracefile, $rescan) = @_;

    if ($rescan) {
        # The definitions this read saw are not enough to decide which one
        #   applies to a site:  the next one after it may be in a section which
        #   went to another chunk, and so may the only one there is.  Replace them
        #   with what the whole tracefile holds, for the indexes named here.
        %$defined = ();
        seek($hdl, 0, 0) or
            die("cannot rewind $tracefile: $!\n");
        $hdl->input_line_number(0);
        my %resolved;    # written name -> the file name it resolves to
        while (<$hdl>) {
            next unless /^[SK]F:(\d+),(.+)$/;
            my ($idx, $name) = ($1, $2);
            next unless exists($pending->{$idx});
            # trailing whitespace, for a CRLF file:  same test as the reader's
            $name =~ s/\s+$//
                if (length($name) && substr($name, -1) lt '!');
            $resolved{$name} =
                ReadCurrentSource::resolve_path(lcovutil::check_path_separator(
                                                           $name, $tracefile, $.
                                                ),
                                                1
                ) unless exists($resolved{$name});
            push(@{$defined->{$idx}}, [$., $resolved{$name}]);
        }
    }
    my @deferred;
    foreach my $idx (sort({ $a <=> $b } keys(%$pending))) {
        foreach my $site (@{$pending->{$idx}}) {
            my $at = $site->[PEND_AT];
            my $file;
            foreach my $def (@{$defined->{$idx}}) {
                $file = $def->[1];
                last if $def->[0] >= $at;
            }
            unless (defined($file)) {
                lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                    "\"$tracefile\":$at: no 'SF:' record defines source file index '$idx', named by the call to '"
                        . $site->[PEND_CALLEE]
                        . "'");
                next;
            }
            push(@deferred, [$file, @$site]);
        }
    }
    return \@deferred;
}

# Add the call sites which could not be added while the section they were read in
#   was being read, because the file they are written in was named by an index
#   whose meaning is only settled once the whole tracefile has been read - see
#   '_resolvePendingSites'.
#
# The section has been installed by the time we get here, so the site goes in
#   through the report rather than through the section's scratch map, which
#   '_installSection' owns:  into the function data merged over all
#   testcases, and into the map of the testcase the section belonged to.  Those
#   are one object when the file 'isAliased', and adding the site to it twice
#   would count the call twice.
# A site whose function is not in the destination map is dropped rather than
#   reported:  the map is what the section installed, so the only way for the
#   name to be missing is for the function itself to have been dropped - which is
#   the same reason '_pruneUnwritableSites' drops a site, and is not an error.
sub _addDeferredSites
{
    my ($self, $deferred) = @_;

    foreach my $site (@$deferred) {
        my $siteFile = shift(@$site);
        my $file     = $site->[PEND_OWNER];
        # the file may be gone:  an empty one is dropped at the end of the read
        next unless $self->contains($file);
        my $traceInfo = $self->data($file);
        my @maps      = ($traceInfo->func());
        unless ($traceInfo->isAliased(TraceInfo::FUNCTION_DATA)) {
            my $perTest = $traceInfo->testfnc();
            push(@maps, $perTest->value($site->[PEND_TESTNAME]))
                if $perTest->mapped($site->[PEND_TESTNAME]);
        }
        foreach my $map (@maps) {
            my $entry = $map->findName($site->[PEND_ALIAS]);
            next unless $entry;
            # count errors are checked in the addCallSite method
            $entry->addCallSite($site->[PEND_LINE], $site->[PEND_COLUMN],
                                $site->[PEND_ORDINAL], $site->[PEND_COUNT],
                                $site->[PEND_CALLEE], $siteFile,
                                undef, $site->[PEND_ALIASES]);
        }
    }
}

# The location offset of a BRDA or MCDC record:  where the block is written,
#   relative to the line which holds it - see BranchBlock::locationOffset.
#   'location' is the optional '^<location>' field of the record.
sub _recordLocationOffset
{
    my ($tracefile, $line, $location) = @_;
    return 0 unless defined($location);
    my $offset = $location - $line;
    if (abs($offset) > BranchBlock::MAX_LOCATION_OFFSET) {
        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
             "\"$tracefile\":$.: location $location of line $line is more than "
                 . BranchBlock::MAX_LOCATION_OFFSET .
                 " lines away in .info file record '$_' (location ignored)");
        return 0;
    }
    return $offset;
}

# Die on error.
#
# The end line 'end' of the statement which the line coverpoint at 'line' of
#   'traceInfo' counts, read from the DA record of 'tracefile' - see
#   'TraceInfo::span'.  A span which is not a line after the coverpoint, at
#   most MAX_SPAN_OFFSET lines away, is a format error, and is dropped.  The
#   record of each testcase has the same span.
sub _readSpan
{
    my ($traceInfo, $line, $end, $tracefile) = @_;
    my $filename = $traceInfo->filename();
    unless ($end =~ /^\d+$/ &&
            $line < $end &&
            $end - $line <= MAX_SPAN_OFFSET) {
        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
            "\"$tracefile\":$.: unexpected statement end line '$end' for line coverpoint $filename:$line"
        );
        return;
    }
    my $span = $traceInfo->span();
    if ($span->mapped($line) && $span->value($line) != $end) {
        lcovutil::ignorable_error(
                  $lcovutil::ERROR_INCONSISTENT_DATA,
                  "statement span mismatch at $filename:$line in $tracefile: " .
                      "$line-" .
                      $span->value($line) .
                      " -> $line-$end");
    }
    $span->replace($line, $end);
}

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
    # The calls made from the sections which are being skipped, as the
    #   lcovutil::external_call records TraceFile::noteExternalCalls takes,
    #   applied to the callees once the whole file has been read - see
    #   TraceFile::noteExternalCalls
    my @externalCalls;
    # ..and, while one such section is being read, the callees it named and the
    #   function names it defined:  see the '$skipCurrentFile' block below, and
    #   '$closeSection', which turns the two into the pairs above
    my @skippedCalls;
    my %skippedNames;
    my %fnIdxMap;
    # The source file indexes this tracefile defines:  index -> [['.info' line,
    #   file name], ...].  A call site written in a file other than the one its
    #   function is defined in names that file by index - see the 'SF:'
    #   description in geninfo(1) - and the index means nothing outside this
    #   tracefile, so it is resolved here and never stored.
    my %sourceIndex;
    # ..and the sites which named one:  index -> list of PEND_ records.  Held
    #   until the whole file has been read, because that is when which definition
    #   of an index applies to which site is settled - see
    #   '_resolvePendingSites'.  Also the only table here which is a list per
    #   index rather than one value:  every other record in a section is complete
    #   in itself.
    my %pendingSites;
    my $branchBlock;
    my $currentBlockLine;
    my $currentBlock;
    my $currentBlockOffset;
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
     # The cases the open section has seen, and the count records ('LF:',
     #   'BRF:', ...) among them by tag, so that '$closeSection' can check
     #   '@sectionCountRecords'.  One array store per record:  the tag is looked
     #   at again only for the handful of count records.
    my @sectionCases;
    my %sectionCounts;

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
        # remember both halves of the message here, where we still know the
        #   name which changed
        $changed_testname = "'$orig'->'$name'"
            if ($name =~ s/\W/_/g && $isRecord);
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
        foreach my $required (@sectionCountRecords) {
            my ($cases, $what, @tags) = @$required;
            next unless grep({ $sectionCases[$_] } @$cases);
            my @missing = grep({ !exists($sectionCounts{$_}) } @tags);
            lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                                      "\"$tracefile\":$.: missing "
                                          .
                                          join(' and ',
                                               map({ "'$_:'" } @missing)) .
                                          " count record" .
                                          (1 < @missing ? 's' : '') .
                                          " for the $what coverpoints in " .
                                          &$openSection()) if @missing;
        }
        @sectionCases  = ();
        %sectionCounts = ();
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
        } elsif (@skippedCalls) {
            # The calls this skipped section made, less those which went to a
            #   function it defined itself:  those went to a definition which is
            #   being skipped too, so there is no callee left for them to be a
            #   fact about
            push(@externalCalls,
                 map({ [$filename, $_->[0], $_->[1], {$testname => $_->[1]}] }
                     grep({ !exists($skippedNames{$_->[0]}) } @skippedCalls)));
        }
        @skippedCalls    = ();
        %skippedNames    = ();
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
                    lcovutil::ignorable_error(
                             $lcovutil::ERROR_FORMAT,
                             "\"$tracefile\":$.: 'end_of_record' with no open" .
                                 ' section' .
                                 &$closedSection());
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
            # 'SF:[<index>,]<name>':  the optional leading integer is the
            #   shorthand a call site written in this file names it by - see
            #   '%sourceIndex'.  The name is the rest of the record, so a name
            #   which itself begins with digits and a comma - the one spelling
            #   this cannot be told from an index - is written WITH an index by
            #   'TraceFile::_callSiteFileIndex', and so is not ambiguous.
            my $sfIndex;
            $sfIndex = $1 if $sourceName =~ s/^(\d+),//;
            if ($inSection) {
                lcovutil::ignorable_error(
                        $lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: file record '$line' found inside " .
                            &$openSection() .
                            " - missing 'end_of_record'");
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
            # A name written on the other platform is put into this platform's
            #   terms first, before '--substitute' and before we go looking for
            #   the file:  the user writes those patterns - and everything else
            #   which takes a path - for the platform they are running on.
            $sourceName =
                lcovutil::check_path_separator($sourceName, $tracefile, $.);
            $filename = ReadCurrentSource::resolve_path($sourceName, 1);
            # Remembered, not applied:  a record later in the file may define the
            #   same index again, and which definition a site takes is decided
            #   once the whole file has been read - see '_resolvePendingSites'.
            #   Before the skip check below, because an excluded file can still be
            #   the file a site is written in - the site is then dropped by
            #   '_pruneUnwritableSites', which records it on the callee.
            push(@{$sourceIndex{$sfIndex}}, [$., $filename])
                if defined($sfIndex);
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
            %fnIdxMap           = ();
            $branchBlock        = undef;
            $currentBlockLine   = -1;
            $currentBlock       = -1;
            $currentBlockOffset = 0;

            if ($verify_checksum) {
                # unconditionally 'close' the current file - in case we don't
                #   open a new one.  If that happened, then we would be looking
                #   at the source for some previous file.
                $readSourceCallback->close();
                if (is_language(lcovutil::IS_C, $filename)) {
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
                lcovutil::ignorable_error(
                         $lcovutil::ERROR_FORMAT,
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
            lcovutil::ignorable_error(
                           $lcovutil::ERROR_FORMAT,
                           "\"$tracefile\":$.: unexpected .info file record " .
                               "'$line' outside of a section:  expected 'TN:'" .
                               " or 'SF:'" .
                               &$closedSection());
            next;
        }
        # Noted for every record in a section - kept, skipped or of a type which
        #   is turned off - since the count records are a property of the file
        $sectionCases[$case] = 1;
        $sectionCounts{substr($line, 0, $colon)} = 1 if $case == REC_SUMMARY;
        if ($skipCurrentFile) {
            # This file is not being kept - '--remove', '--extract', an exclude
            #   pattern - but a call it makes is a fact about the *callee*, which
            #   may well be kept.  This is the last chance to record it:  the
            #   site itself goes away with the file, and nothing later can tell
            #   that it was ever here.  Every call, taken or not:  what is recorded
            #   is that the edge is there, and the count the site carried - see
            #   FunctionAlias::external_calls.
            # The section's own function names are collected beside its calls,
            #   for the same reason TraceFile::_noteCallsFrom looks them up:  a
            #   call to a name this section defines went to the definition which
            #   is being skipped along with it.  Both are decided when the
            #   section ends, since a record may name a function the section
            #   defines further down
            if ($lcovutil::callgraph_coverage && defined($filename)) {
                if ($case == REC_FNC &&
                    $line =~
                    /^FNC:\d+(?:@\d+)?(?:#[\d.]+)?,\d+,\d+,\d+,([^,]+),(.+)$/) {
                    push(@skippedCalls, [$2, $1]);
                } elsif ($case == REC_FNA &&
                         $line =~ /^FNA:\d+(?:[a-z]\w*)?,[^,]+,(.+)$/) {
                    $skippedNames{$1} = 1;
                } elsif ($case == REC_FN && $line =~ /^FN:\d+(?:,\d+)?,(.+)$/) {
                    $skippedNames{$1} = 1;
                }
            }
            next;
        }

        # A record belonging to a cover type which is turned off.  There is
        #   nowhere to put its data, so drop it here - before its regular
        #   expression is run, which is the point:  see '%recordDispatch' above.
        #   It is dropped after the checks above, so that a record which is in
        #   the wrong PLACE is still reported as such whether or not its cover
        #   type is enabled;  only the record's own payload goes unexamined.
        # Note the type first:  the data is in the input whether or not we are
        #   keeping it, and 'TraceFile::empty' says so, since a '.info' file
        #   full of records the command line drops may be missing
        #   '--<type>-coverage' flag rather than a deliberate choice.
        if ($case >= REC_SKIP) {
            $lcovutil::coverTypeFound[$case - REC_SKIP] = 1;
            next;
        }
        # ...and the same note for a type which IS enabled, so that the flag
        #   means "some input contains this type" either way.
        my $covType = $caseCoverType[$case];
        $lcovutil::coverTypeFound[$covType] = 1 if defined($covType);

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
                # 'DA:line,count[,checksum][,end]' - the checksum is empty
                #   if there is an end and no checksum
                /^DA:(\d+),([^,]+)(,([^,\s]*)(,(\S+))?)?/ && do {
                    # make emacs happier with a /
                    my ($line, $count, $checksum, $end) = ($1, $2, $4, $6);
                    $checksum = undef
                        if (defined($checksum) && '' eq $checksum);
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
                                        "checksum mismatch between source $filename:$line and $tracefile: $checksum -> $chk"
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
                    _readSpan($fileData, $line, $end, $tracefile)
                        if defined($end);
                    last;
                };
            } elsif ($case == REC_BRDA) {
                /^BRDA:(\d+),([ef]?)(U?)(\d+)(?:\^(\d+))?,(.+)$/ && do {
                    # Branch coverage data found
                    # line data is "lineNo,blockId[^location],(branchIdx|branchExpr),taken
                    #   - the optional location is the line the block is
                    #     written at, if it is not lineNo:  see
                    #     BranchBlock::locationOffset
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
                    my ($line, $block, $location, $d) = ($1, $4, $5, $6);
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

                    my $offset =
                        _recordLocationOffset($tracefile, $line, $location);
                    if (!defined($branchBlock) ||
                        $block != $currentBlock    ||
                        $line != $currentBlockLine ||
                        $offset != $currentBlockOffset) {
                        if (defined($branchBlock)) {
                            $branchMap->insertBlock($branchBlock,
                                                    $currentBlockLine);
                        }
                        $branchBlock = BranchBlock->new();
                        $branchBlock->setLocationOffset($offset) if $offset;
                        $currentBlockLine   = $line;
                        $currentBlock       = $block;
                        $currentBlockOffset = $offset;
                        $branchIndex        = 0;
                    }
                    $branchBlock->appendNew($branchIndex++, $taken, $expr,
                                            $type, $unreachable);
                    last;
                };
            } elsif ($case == REC_MCDC) {
                /^MCDC:(\d+),(U?)(\d+)(?:\^(\d+))?,([tf]),(\d+),(\d+),(.+)$/ &&
                    do {
                    # lineNum, unreachable groupSize[^location], sense, count,
                    #   index, expression
                    # 'sense' is t/f: was this expression sensitized
                    # 'filtered' indicates that this particular MC/DC element
                    #    was excluded by
                    # the optional location is the line the group is written
                    #   at, if it is not lineNum:  see MCDC_Block::groupKey
                    my ($line, $groupSize, $location, $sense, $count, $idx,
                        $expr)
                        = ($1, $3, $4, $5, $6, $7, $8);
                    if ($groupSize > 0xFFFFFF) {
                        # see MCDC_Block::groupKey
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$tracefile\":$.: unexpected MC/DC group size '$groupSize' in condition data record '$_' (skipped)."
                        );
                        last;
                    }
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
                    my $groupKey =
                        MCDC_Block::groupKey($groupSize,
                           _recordLocationOffset($tracefile, $line, $location));
                    $current_mcdc->insertExpr($filename, $groupKey,
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
                # The optional flag letters after the index are the per-function
                #   booleans - see FunctionEntry::FLAG_EXTERNAL_CALLEES.  They
                #   ride on the index for the same reason the 'FNA:' ones do, and
                #   are applied when the 'FNA:' records which follow create the
                #   entry:  there is no FunctionEntry yet here
                /^FNL:(\d+)([a-z]*),(\d+)(,(\d+))?$/ && do {
                    my $fnIndex  = $1;
                    my $lineNo   = $3;
                    my $end_line = $5;
                    die("unexpected duplicate index $fnIndex")
                        if exists($fnIdxMap{$fnIndex});
                    # The letters are checked here, where the record they came
                    #   from is the one a message would quote, and carried as the
                    #   boolean they mean
                    my $callsOut = 0;
                    foreach my $flag (split(//, $2)) {
                        if ($flag eq FunctionEntry::FLAG_EXTERNAL_CALLEES) {
                            # ..this function called out of the boundary of the
                            #   report it was written from - see
                            #   FunctionEntry::has_external_callees
                            $callsOut = 1;
                        } else {
                            # Kept rather than dropped, as an unknown 'FNA:' flag
                            #   is:  the flags say nothing about any count, so the
                            #   function itself is good data whatever this letter
                            #   meant
                            lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                                "\"$tracefile\":$.: unknown function flag '$flag' in .info file record '$_'"
                            );
                        }
                    }
                    $fnIdxMap{$fnIndex} =
                        [$lineNo, $end_line, undef, $callsOut];
                    last;
                };
            } elsif ($case == REC_FNA) {
                # The optional flag letters after the index are the per-alias
                #   facts a callgraph capture records - see
                #   FunctionAlias::flags.  A letter may carry a count ('x5').
                #   They ride on the index rather than on a field of their own
                #   because the alias name is the last field and keeps its
                #   commas
                /^FNA:(\d+)((?:[a-z]\d*)*),([^,]+),(.+)$/ && do {
                    my $fnIndex = $1;
                    my $flags   = $2;
                    my $hit     = $3;
                    my $alias   = $4;
                    die("unknown index $fnIndex")
                        unless exists($fnIdxMap{$fnIndex});
                    my ($lineNo, $end_line) = @{$fnIdxMap{$fnIndex}};
                    my $fn =
                        $functionMap->define_function($alias, $lineNo,
                                                $end_line, "\"$tracefile\":$.");
                    $fn->addAlias($alias, $hit);
                    # Remember the entry this index names, for the 'FNC:'
                    #   records which follow it:  every alias of an index is an
                    #   alias of one FunctionEntry, so which of them got here
                    #   first does not matter
                    $fnIdxMap{$fnIndex}->[2] = $fn;
                    # ..and the name, in record order:  that is how an 'FNC:'
                    #   record of this index says which aliases make the call
                    push(@{$fnIdxMap{$fnIndex}->[4]}, $alias);
                    # ..and now there is an entry for the flags the 'FNL:' record
                    #   carried for the function itself.  Set-only, so the second
                    #   alias of the index simply says the same thing again
                    $fn->set_external_callees() if $fnIdxMap{$fnIndex}->[3];
                    if ($flags ne '') {
                        my $aliasData = $fn->alias($alias);
                        my $isExtern  = FunctionAlias::FLAG_EXTERNAL;
                        my $isCalled  = FunctionAlias::FLAG_EXTERNAL_CALLERS;
                        my $isDeduced = FunctionAlias::FLAG_DEDUCED_CALLERS;
                        while ($flags =~ /([a-z])(\d*)/g) {
                            my ($flag, $number) = ($1, $2);
                            if ($number ne '' && $flag ne $isCalled) {
                                # only 'x' carries a count
                                $flag .= $number;
                            }
                            if ($flag eq $isExtern) {
                                # ..has external linkage, which is what lets a
                                #   call from a file that defines no function of
                                #   that name resolve to it - see
                                #   TraceFile::resolveCallSites
                                $aliasData->set_external();
                            } elsif ($flag eq $isCalled) {
                                # ..was called from a site this data cannot name
                                #   - see FunctionAlias::has_external_callers -
                                #   which made this many calls, where that is
                                #   known
                                $aliasData->add_external_calls(
                                                 $number ne '' ? $number : '-');
                            } elsif ($flag eq $isDeduced) {
                                # ..was called more often than its sites
                                #   account for.  Advisory:  recomputed from
                                #   the counts of the report this is read into
                                #   (lcovutil::deduced_external_calls), which a
                                #   merge may have changed, so nothing is kept
                            } else {
                                # Kept rather than dropped:  the flags say
                                #   nothing about the count, so the alias itself
                                #   is good data whatever this letter meant
                                lcovutil::ignorable_error(
                                    $lcovutil::ERROR_FORMAT,
                                    "\"$tracefile\":$.: unknown function flag '$flag' in .info file record '$_'"
                                );
                            }
                        }
                    }
                    last;
                };
            } elsif ($case == REC_FNM) {
                # A name merged into an alias of the function named by the
                #   index, and that name's share of the alias's count - see
                #   FunctionAlias::merged.  The alias is named by its position
                #   among the 'FNA:' records of the index, as an 'FNC:' record
                #   names one, so that the merged name can be the last field
                #   and keep its commas.  The alias has to have been read
                #   already:  the writer puts these right after its 'FNA:'.
                #   The count is '[^,]+' for the reason the 'FNA:' one is
                /^FNM:(\d+)#(\d+),([^,]+),(.+)$/ && do {
                    my ($fnIndex, $pos, $count, $name) = ($1, $2, $3, $4);
                    my $known = $fnIdxMap{$fnIndex};
                    my $alias = defined($known) ? $known->[4]->[$pos] : undef;
                    if (!defined($alias)) {
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$tracefile\":$.: merged alias record for function index '$fnIndex' alias '$pos' found before that alias is defined in .info file record '$_'"
                        );
                        last;
                    }
                    my ($normalized, $errno) =
                        lcovutil::normalize_count($count);
                    $known->[2]->_format_error($errno, $name, $count)
                        if defined($errno);
                    $known->[2]->alias($alias)->add_merged($name, $normalized);
                    last;
                };
            } elsif ($case == REC_FNC) {
                # A call site in the body of the function named by the index.
                #   The count is '[^,]+' rather than '\d+' for the same reason
                #   'FNDA:' is - Perl may have written a float - and because it
                #   may be '-', the "count not known" marker (see SITE_COUNT);
                #   addCallSite is what decides which values are acceptable.
                #   The callee symbol is the record's single free-text field, so
                #   it takes the rest of the line and may contain commas
                # '@<index>' on the function index says that the call is WRITTEN
                #   in another file - the one that source file index names - while
                #   still being part of the body of this file's function:  an
                #   inline function defined in a header, say.  It rides on the
                #   leading field for the same reason the 'FNA:' flags do.
                # '#<n>[.<n>...]' after that says which of the function's
                #   aliases make the call, as positions among the 'FNA:'
                #   records of the index in the order they were read - see
                #   FunctionEntry::SITE_ALIASES.  Absent, it is all of them
                # '^<line>' after that is the line of the statement the call is
                #   part of, where that is not the line it is written on - see
                #   FunctionEntry::SITE_STATEMENT
                /^FNC:(\d+)(?:@(\d+))?(?:#(\d+(?:\.\d+)*))?(?:\^(\d+))?,(\d+),(\d+),(\d+),([^,]+),(.+)$/
                    &&
                    do {
                    my $fnIndex   = $1;
                    my $sfIndex   = $2;
                    my $positions = $3;
                    my $statement = $4;
                    my $lineNo    = $5;
                    my $column    = $6;
                    my $ordinal   = $7;
                    my $count     = $8;
                    my $callee    = $9;

                    if (!exists($fnIdxMap{$fnIndex})) {
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$tracefile\":$.: unknown function index '$fnIndex' in .info file record '$_'"
                        );
                        last;
                    }
                    my $fn = $fnIdxMap{$fnIndex}->[2];
                    if (!defined($fn)) {
                        # 'FNL:' established the index, but no 'FNA:' gave it a
                        #   name, so there is no function to attach the site to
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$tracefile\":$.: function index '$fnIndex' has no 'FNA:' record in .info file record '$_'"
                        );
                        last;
                    }
                    if ($lineNo <= 0) {
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$tracefile\":$.: unexpected call site line '$lineNo' in .info file record '$_'"
                        );
                        last;
                    }
                    # ..a call written in another file is part of a statement
                    #   of that file, which is not the one this section has the
                    #   lines of - and a statement is no longer than
                    #   MAX_STATEMENT_OFFSET.  The site is kept, on its own line
                    if (defined($statement) &&
                        (defined($sfIndex) ||
                            abs($statement - $lineNo) >
                            FunctionEntry::MAX_STATEMENT_OFFSET)
                    ) {
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$tracefile\":$.: unexpected call site statement line '$statement' in .info file record '$_'"
                        );
                        $statement = undef;
                    }
                    # The aliases which make the call.  Explicit list even when
                    #   the record says "all of them"
                    my $names = $fnIdxMap{$fnIndex}->[4];
                    my $aliases;
                    if (defined($positions)) {
                        my @named;
                        foreach my $p (split(/\./, $positions)) {
                            if ($p >= scalar(@$names)) {
                                lcovutil::ignorable_error(
                                    $lcovutil::ERROR_FORMAT,
                                    "\"$tracefile\":$.: function index '$fnIndex' has no alias '$p' in .info file record '$_'"
                                );
                                next;
                            }
                            push(@named, $names->[$p]);
                        }
                        # every position was bad and ignored:  drop the site,
                        #   rather than give it to aliases nobody named
                        last unless @named;
                        $aliases = FunctionEntry::aliasSet(@named);
                    } else {
                        $aliases = FunctionEntry::aliasSet(@$names);
                    }
                    if (defined($sfIndex)) {
                        # The site cannot be added yet:  the file it is written in
                        #   is part of its identity, and which file the index
                        #   names is not settled until the whole tracefile has
                        #   been read - see '_resolvePendingSites'
                        push(@{$pendingSites{$sfIndex}},
                             [$filename, $testname, $fn->name(), $lineNo,
                              $column, $ordinal, $count, $callee,
                              $., $aliases
                             ]);
                        last;
                    }
                    # count errors are checked in the addCallSite method
                    $fn->addCallSite($lineNo, $column,
                                     $ordinal, $count,
                                     $callee, undef,
                                     undef, $aliases,
                                     $statement);
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

            # The count records ('LF:', 'FNCH:', ...):  every one of them is
            #   recomputed from the coverpoints, so the value in the file is
            #   ignored.  Both this and the regular expression below reach the
            #   same conclusion;  the expression is what catches a count tag
            #   which is not in '%recordCase'.
            if ($case == REC_SUMMARY) {
                # Not quite everything is ignored:  for the types which have a
                #   count record of their own ('%recordDeclaresCoverType') the
                #   counts are summed over the inputs, because the total
                #   number of coverpoints seen is used for error checking.
                # Only recorded for enabled types.
                if (/^(\w+):(\d+)/ &&
                    exists($recordDeclaresCoverType{$1})) {
                    my $covType = $recordDeclaresCoverType{$1};
                    $lcovutil::coverTypeInputTotal[$covType] =
                        ($lcovutil::coverTypeInputTotal[$covType] || 0) + $2
                        if ${$lcovutil::coverType[$covType]->{flag}};
                }
                last;
            }

            /^(FN|BR|L|MC)C?[HF]/ && do {
                last;    # ignore count records
            };

            lcovutil::ignorable_error(
                        $lcovutil::ERROR_FORMAT,
                        "\"$tracefile\":$.: unexpected .info file record '$_'" .
                            ' in ' .
                            &$openSection());
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
        lcovutil::ignorable_error(
                                 $lcovutil::ERROR_FORMAT,
                                 "\"$tracefile\":$.: unexpected end of file: " .
                                     "missing 'end_of_record' for " .
                                     &$openSection());
        &$closeSection();
    }

    # The call sites which named the file they are written in by index:  now that
    #   the whole file has been read, work out which file each index means, and
    #   add the sites to the sections they were read in - which have been
    #   installed by now
    if (%pendingSites) {
        my $deferred =
            $self->_resolvePendingSites(\*INFO, \%pendingSites, \%sourceIndex,
                                        $tracefile, defined($chunk));
        $self->_addDeferredSites($deferred);
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

    # The calls made from the sections this read skipped, recorded on the
    #   callees which were kept.  Here rather than as each is seen, because a
    #   callee's own section may come after the excluded caller's
    $self->noteExternalCalls(\@externalCalls);

    # A chunk which read nothing useful is not an empty tracefile:  the rest of
    #   the file went to other chunks.  The parent asks the same question of the
    #   merged result - see 'AggregateTraces::_parallel_parse'.
    if (scalar($self->files()) == 0 &&
        !defined($chunk)) {
        lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                              "no valid records found in tracefile $tracefile");
    }
    if (defined($changed_testname)) {
        lcovutil::ignorable_warning(
                                $lcovutil::ERROR_FORMAT,
                                "invalid characters removed from testname in " .
                                    "tracefile $tracefile: $changed_testname\n"
        );
    }
}

# write data to filename (stdout if '-')
# returns nothing
sub write_info_file($$$)
{
    my ($self, $filename, $do_checksum) = @_;

    # Not only for the tools which read '.info' files - they have already asked
    #   this, on the way in, and 'checkEmpty' says everything at most once - but
    #   for the ones which build a tracefile from something else and write it:
    #   the '*2lcov' translators and geninfo.  This is their equivalent point,
    #   the last one before the data leaves the process.
    $self->checkEmpty();
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

    my $srcReader;
    $srcReader = ReadCurrentSource->new()
        if ($verify_checksum);
    # A call site written in a file this report has not got has no record to be
    #   written as, so it is turned into the callee's flag before anything is
    #   printed - and the files which a record does have to name are given the
    #   index it names them by.  Both are no-ops for a report with no cross-file
    #   call site, which is every report the capture of a project whose functions
    #   are all written where they are defined produces
    $self->_pruneUnwritableSites();
    my $sourceIndex = $self->_callSiteFileIndex();
    # ..and the symbols this report calls, which is what says whether a file
    #   whose own functions hold no site was measured at all - see
    #   FunctionMap::hasCallgraphData.  Only where the metric is on, because
    #   nothing else reads it
    my $calledSymbols =
        $lcovutil::callgraph_coverage ? $self->calledSymbols() : undef;
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
        my $span = $entry->span();
        # munge the source file name, if requested
        $source_file = ReadCurrentSource::resolve_path($source_file, 1);
        # whether this file's calls were measured - asked once, and only if a
        #   'd' flag needs it (see _deducedExternalCalls)
        my $measured;

        # Please note:  if you add or change something here (lcov info file format) -
        #   then please make corresponding changes to the '_read_info' method, above
        #   and update the format description found in .../man/geninfo.1.
        foreach my $testname (sort($testdata->keylist())) {
            my $lineMap   = $testdata->value($testname);
            my $funcMap   = $testfncdata->value($testname);
            my $branchMap = $testbrdata->value($testname);
            my $mcdc      = $testmcdc->value($testname);

            print(INFO_HANDLE "TN:$testname\n");
            # ..with this file's index, when some record has to name it - see
            #   '_callSiteFileIndex'.  The field is optional and is written only
            #   when it is needed, so a report which needs none is byte for byte
            #   the report this always wrote
            my $sfIndex = $sourceIndex->{$filename};
            print(INFO_HANDLE 'SF:',
                  (defined($sfIndex) ? "$sfIndex," : ''),
                  $source_file, "\n");
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
                my $c_found = 0;
                my $c_hit   = 0;
                foreach my $key (@functionOrder) {
                    my $data = $functionMap->findKey($key);
                    # sort enables diff of output data files, for testing
                    my @aliases = sort($data->aliasNames());
                    my $line    = $data->line();

                    if ($line <= 0) {
                        my $alias = $aliases[0];
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
                    # print function leader, with the flags which belong to the
                    #   function rather than to one of its names - see
                    #   FunctionEntry::FLAG_EXTERNAL_CALLEES.  Only under
                    #   '--callgraph-coverage', for the reason the 'FNA:'
                    #   flags are written only there
                    my $fnFlags =
                        ($lcovutil::callgraph_coverage &&
                         $data->has_external_callees()) ?
                        FunctionEntry::FLAG_EXTERNAL_CALLEES :
                        '';
                    print(INFO_HANDLE "FNL:$fnIndex$fnFlags,$line$endLine\n");
                    ++$f_found;
                    my $counted  = 0;
                    my $aliasPos = 0;
                    foreach my $alias (@aliases) {
                        my $aliasData = $data->alias($alias);
                        my ($name, $hit, $flags) = $aliasData->write_data();
                        # ..and whether this symbol was called from outside the
                        #   boundary by deduction rather than by record.  Asked
                        #   of the file's summary, which is the map the call
                        #   sites were resolved into (TraceFile::
                        #   resolveCallSites) - a testcase's map never is - so
                        #   every section says what the report as a whole does.
                        #   Nothing is said where the sites were not resolved:
                        #   geninfo writes one translation unit, whose callers
                        #   in other units it cannot see, so the difference
                        #   would read as an external caller for every function
                        #   which another file calls
                        $flags .= FunctionAlias::FLAG_DEDUCED_CALLERS
                            if $lcovutil::callgraph_coverage &&
                            _deducedExternalCalls($funcdata, $name, \$measured,
                                                  $calledSymbols);
                        ++$f_hit if $hit > 0 && !$counted;
                        $counted ||= $hit > 0;
                        # print the alias, with the flags a callgraph capture
                        #   asserted for it - see FunctionAlias::flags.  Only
                        #   under '--callgraph-coverage', because call data is
                        #   the only thing which reads them and a report which
                        #   asked
                        #   for none should not grow fields
                        $flags = '' unless $lcovutil::callgraph_coverage;
                        print(INFO_HANDLE "FNA:$fnIndex$flags,$hit,$name\n");
                        # ..and the names merged into it with their shares of
                        #   its hit count, by its position among the 'FNA:'
                        #   records of the index - see the reader.
                        #   Whether or not there is call data:  they are what
                        #   the name represents, which a report of functions
                        #   alone shows too
                        my $merged = $aliasData->merged();
                        print(INFO_HANDLE
                              "FNM:$fnIndex#$aliasPos,$merged->{$_},$_\n")
                            foreach sort(keys(%{$merged // {}}));
                        ++$aliasPos;
                    }
                    next unless $lcovutil::callgraph_coverage;
                    # Then this function's call sites, in source order so that
                    #   the output can be diffed.  They come after the aliases
                    #   because they belong to the entry rather than to any one
                    #   of its names - and the reader needs the 'FNA:' record to
                    #   have created the entry before it can attach a site to it
                    # The position of each alias among the 'FNA:' records just
                    #   written, which is how a site names the aliases which
                    #   make it - see FunctionEntry::SITE_ALIASES.  Only for a
                    #   function with more than one alias:  the single alias
                    #   of the  rest makes every call there is
                    my %position;
                    if (scalar(@aliases) > 1) {
                        my $p = 0;
                        %position = map({ $_ => $p++ } @aliases);
                    }
                    foreach my $site ($data->sortedCallSiteKeys()) {
                        my ($siteLine, $col, $ord, $count, $callee, $siteFile,
                            $siteAliases, $statement)
                            = $data->callSiteData($site);
                        # A call written somewhere other than the file this
                        #   section is for names that file by its index, as a
                        #   suffix on the function index.  A suffix rather than a
                        #   field of its own for the reason the 'FNA:' flags are
                        #   one (see FunctionAlias::FLAG_EXTERNAL):  the callee
                        #   name is the last field and takes the rest of the
                        #   line, because a demangled name contains commas
                        my $where = '';
                        if (defined($siteFile)) {
                            my $idx = $sourceIndex->{$siteFile};
                            # '_pruneUnwritableSites' has removed every site
                            #   whose file has no section, so every one left has
                            #   an index
                            die("no source index for \"$siteFile\"")
                                unless defined($idx);
                            $where = '@' . $idx;
                        }
                        # ..and which aliases make the call, where that is not
                        #   all of them:  so a report which has no template
                        #   whose instantiations call different things is byte
                        #   for byte the report this always wrote
                        if (%position && defined($siteAliases)) {
                            my @at =
                                sort({ $a <=> $b }
                                 map({ $position{$_} // () }
                                     FunctionEntry::aliasSetNames($siteAliases))
                                );
                            $where .= '#' . join('.', @at)
                                if @at && scalar(@at) < scalar(@aliases);
                        }
                        # ..and the line its coverpoint is allocated to, where
                        #   that is not its own - see SITE_STATEMENT
                        $where .= '^' . $statement if defined($statement);
                        print(INFO_HANDLE
                                "FNC:$fnIndex$where,$siteLine,$col,$ord,$count,$callee\n"
                        );
                        ++$c_found;
                        # '-' is in found and never in hit, which is what
                        #   numCallSitesHit answers too - the two have to agree,
                        #   because 'FNCH:' is what a reader believes
                        ++$c_hit if lcovutil::site_count_hit($count);
                    }
                }
                print(INFO_HANDLE "FNF:$f_found\n");
                print(INFO_HANDLE "FNH:$f_hit\n");
                # ..and the call totals, where there is a measurement for them
                #   to be the total of.  A file nothing was recorded about gets
                #   no pair rather than a zero one:  'FNCF:0' asserts that this
                #   file's calls were counted and that there were none, which is
                #   not what is known about a unit compiled without the callgraph
                #   data - see FunctionMap::hasCallgraphData.
                # A file with no function of its own is the exception, and not
                #   really one:  there is nothing in it for a site to belong to,
                #   so its zero is arithmetic on an empty set rather than a
                #   measurement, exactly as the 'FNF:0' beside it is.  That is
                #   the shape of an '#include'd fragment, whose section carries
                #   the lines its text holds while the calls in that text belong
                #   to functions of the file which includes it.
                # Asked of the map being written, not of the file:  each section
                #   is one testcase's data and stands on its own
                # Inputs which counted their call sites and found none are the
                #   third way to have a basis for writing the pair:  it is the
                #   same assertion, handed to us rather than derived here, and
                #   passing it on is what keeps the next tool in the pipeline
                #   from mistaking the measurement for a missing capture.  The
                #   'BRF:' below is written for the same reason.
                my $callsCountedNone =
                    lcovutil::inputCountedNone(lcovutil::COVER_TYPE_CALLGRAPH);
                if ($lcovutil::callgraph_coverage &&
                    (0 == $f_found ||
                        $callsCountedNone ||
                        $functionMap->hasCallgraphData($calledSymbols))
                ) {
                    print(INFO_HANDLE "FNCF:$c_found\n");
                    print(INFO_HANDLE "FNCH:$c_hit\n");
                }
            }
            my $br_found = 0;
            my $br_hit   = 0;
            # $branchMap is undef if there are no branches in the scope
            if ($lcovutil::br_coverage &&
                defined($branchMap)) {
                # Write branch related data
                foreach my $line (sort({ $a <=> $b } $branchMap->keylist())) {
                    lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                        "\"$source_file\": unexpected line number '$line' in branch data record."
                    ) if ($line <= 0);    # keep bogus data if error ignored
                    my $brdata = $branchMap->value($line);

                    # sort the branch data on each line first by number
                    # of branches and then by type (exception vs normal)
                    my $blockId = 0;
                    foreach my $block ($brdata->blocks(1)) {
                        # the line the block is written at, if it is not
                        #   this one - see BranchBlock::locationOffset
                        my $offset   = $block->locationOffset();
                        my $location = $offset ? '^' . ($line + $offset) : '';
                        foreach my $br (@{$block->elements()}) {
                            # one call for all five fields - see
                            #   BranchElement::write_data
                            my ($taken, $branch_id, $branch_expr, $type,
                                $excluded)
                                = $br->write_data();
                            # mostly for Verilog:  if there is a branch expression: use it.
                            $type = '' if 'b' eq $type;
                            printf(INFO_HANDLE "BRDA:%u,%s%s%u%s,%s,%s\n",
                                   $line,
                                   $type,
                                   $excluded ? 'U' : '',
                                   $blockId,
                                   $location,
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
            }
            # The total.  Zero is important when the inputs counted branches
            # and found none - used for error checking - see above.
            if ($lcovutil::br_coverage &&
                ($br_found > 0 ||
                    lcovutil::inputCountedNone(lcovutil::COVER_TYPE_BRANCH))
            ) {
                print(INFO_HANDLE "BRF:$br_found\n");
                print(INFO_HANDLE "BRH:$br_hit\n");
            }
            my $mcdc_found = 0;
            my $mcdc_hit   = 0;
            if ($mcdc &&
                $lcovutil::mcdc_coverage) {
                foreach my $line (sort({ $a <=> $b } $mcdc->keylist())) {
                    if ($line <= 0) {
                        lcovutil::ignorable_error($lcovutil::ERROR_FORMAT,
                            "\"$source_file\": unexpected line number '$line' in MC/DC data record."
                        );
                    }
                    my $m      = $mcdc->value($line);
                    my $groups = $m->groups();
                    foreach my $groupKey (sort keys %$groups) {
                        my $exprs = $groups->{$groupKey};
                        # the line the group is written at, if it is not
                        #   this one - see MCDC_Block::groupKey
                        my ($groupSize, $offset) =
                            MCDC_Block::parseGroupKey($groupKey);
                        $groupSize .= '^' . ($line + $offset) if $offset;
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
            }
            # as 'BRF:' above
            if ($lcovutil::mcdc_coverage &&
                ($mcdc_found != 0 ||
                    lcovutil::inputCountedNone(lcovutil::COVER_TYPE_MCDC))
            ) {
                print(INFO_HANDLE "MCF:$mcdc_found\n");
                print(INFO_HANDLE "MCH:$mcdc_hit\n");
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
                # the end of the statement the coverpoint counts - after an
                #   empty checksum field if there is no checksum
                my $end = $span->value($line);
                $chk = ($chk ? $chk : ',') . ",$end" if defined($end);
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
    foreach my $arg (@_) {
        # may be a windows path name
        my $pattern = lcovutil::posix_path($arg);

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
                # 'shell_quote', not a bare pair of single quotes:  a directory
                #   name may itself contain a single quote (and the pattern
                #   comes from lcovrc), which would otherwise end the quoting
                #   and let the shell interpret the rest
                my $cmd =
                    'find ' .
                    lcovutil::shell_quote($f) .
                    ' -name ' .
                    lcovutil::shell_quote($lcovutil::info_file_pattern) .
                    ' -type f';
                my ($stdout, $stderr, $code) = Capture::Tiny::capture {
                    system($cmd);
                };
                # can fail due to unreadable entry - but might still
                #  have returned data to process
                lcovutil::ignorable_error($lcovutil::ERROR_UTILITY,
                                          "error in \"$cmd\": $stderr")
                    if $code;
                # split on newline, not whitespace:  'find' writes one path per
                #   line, and a path is allowed to contain a space
                my @found = grep({ '' ne $_ } split(/\n/, $stdout));
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
    # The group key has to be the source file's identity as the READER will see
    #   it, not the text of the 'SF:' record:  '_read_info' normalizes the
    #   separator and then applies '--substitute' to it, and two 'SF:' payloads
    #   which differ as text and name one source file afterwards are one atom of
    #   work.  ('--substitute' is the option for aggregating captures made in
    #   different build directories, so this is its normal use, not a corner.)
    # 'ReadCurrentSource::resolve_path' is the third thing the reader applies,
    #   and it is not applied here:  it searches the filesystem, and doing that
    #   in the parent would both cost a stat per section and consume the state
    #   the reader's own diagnostics are built from (which directory of
    #   '--source-directory' was used, what the resolve callback answered).  So
    #   decline to split when either of those could rename a file instead - a
    #   parallel read is an optimization, and this is the one case where we
    #   cannot cheaply tell whether it is sound.
    return undef
        if ($lcovutil::resolveCallback ||
            ($ReadCurrentSource::searchPath &&
             scalar(@$ReadCurrentSource::searchPath)));
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
        $name =
            lcovutil::subst_file_name(lcovutil::translate_path_separator($name),
                                      1);
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

    # Longest-processing-time-first: the same as the genhtml scheduler,
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
                int($totalSize /
                    ($nWorkers * $lcovutil::parallel_parse_chunks_per_worker));
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
                              $ctx->{id} .
                              ", status $ctx->{status}"
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
                ($function_mapping ? 'function' : 'trace') .
                " data\n")
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
    #   merge propagates only the consistency check (see 'merge_tracefile'):  in
    #   general the two sides of a merge have not had the same filtering applied
    #   to them.
    $total_trace->[TraceFile::STATE] |=
        TraceFile::DID_FILTER | TraceFile::DID_DERIVE |
        TraceFile::DID_CONSISTENCY;
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
            # checked when everything has been read and merged
            $current = TraceFile->load($tracefile, $readSourceFile,
                                       $lcovutil::verify_checksum, 1, $runs, 1);
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
    if (!(defined($lcovutil::maxParallelism) && defined($lcovutil::maxMemory)))
    {
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
                       ' segment' .
                       (scalar(@segments) > 1 ? 's' : '') .
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
                              $ctx->{id} .
                              ", status $ctx->{status}"
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
                         $data->[0] .
                         "' at $key")
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

    # Everything the caller asked for has now been read, merged and filtered, and
    #   the caller has not looked at it yet:  this is the point at which to say
    #   that it does not hold what the command line asked for, or that it holds
    #   something the command line is discarding.
    # Two exceptions:
    #   - '--map-functions' never fills '$total_trace' in.  The children hand
    #     back '$function_mapping' instead, so the trace is empty by
    #     construction and contains no coverpoints of any type.
    #   - a baseline is not a report.  genhtml reads one to work out what
    #     changed.  It may have been captured with fewer metrics than the
    #     current data - so "you asked for branches and there are
    #     none here" is about the wrong file.  What the baseline DID contain is
    #     already recorded in '@lcovutil::coverTypeFound' - and the
    #     current data's check still uses that.
    $total_trace->checkEmpty()
        unless ($function_mapping ||
                'ReadBaselineSource' eq ref($readSourceFile));

    return ($total_trace, \@effective);
}

# call the common initialization functions
lcovutil::warn_mangled_path();    # warn about unrecognizable windows paths
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
