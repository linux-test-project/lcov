# some common utilities for lcov-related scripts

use strict;
use warnings;
require Exporter;

package lcovutil;

use File::Path qw(rmtree);
use File::Basename qw(basename dirname);
use File::Spec;
use Cwd qw/abs_path getcwd/;
use Storable qw(dclone);
use Capture::Tiny;
use Module::Load::Conditional qw(check_install);
use Storable;
use Digest::MD5 qw(md5_base64);
use FindBin;
use Getopt::Long;
use DateTime;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw($tool_name $tool_dir $lcov_version $lcov_url
     @temp_dirs set_tool_name
     info warn_once set_info_callback init_verbose_flag $verbose
     debug $debug
     append_tempdir temp_cleanup folder_is_empty $tmp_dir $preserve_intermediates
     define_errors parse_ignore_errors ignorable_error ignorable_warning is_ignored
     die_handler warn_handler abort_handler

     $maxParallelism $maxMemory init_parallel_params current_process_size
     save_profile merge_child_profile save_cmd_line

     @opt_rc apply_rc_params $split_char parseOptions
     strip_directories
     @file_subst_patterns subst_file_name

     $br_coverage $func_coverage
     @cpp_demangle do_mangle_check $demangle_cpp_cmd
     $cpp_demangle_tool $cpp_demangle_params

     $FILTER_BRANCH_NO_COND $FILTER_FUNCTION_ALIAS
     $FILTER_EXCLUDE_REGION $FILTER_EXCLUDE_BRANCH $FILTER_LINE
     $FILTER_LINE_CLOSE_BRACE $FILTER_BLANK_LINE $FILTER_LINE_RANGE
     $FILTER_TRIVIAL_FUNCTION
     @cov_filter
     $EXCL_START $EXCL_STOP $EXCL_BR_START $EXCL_BR_STOP
     $EXCL_EXCEPTION_BR_START $EXCL_EXCEPTION_BR_STOP
     $EXCL_LINE $EXCL_BR_LINE $EXCL_EXCEPTION_LINE
     @exclude_file_patterns @include_file_patterns %excluded_files
     @omit_line_patterns @exclude_function_patterns $case_insensitive
     munge_file_patterns warn_file_patterns transform_pattern
     parse_cov_filters summarize_cov_filters
     disable_cov_filters reenable_cov_filters is_filter_enabled
     filterStringsAndComments simplifyCode balancedParens
     set_rtl_extensions set_c_extensions
     $source_filter_lookahead $source_filter_bitwise_are_conditional
     $exclude_exception_branch
     $derive_function_end_line $trivial_function_threshold

     %geninfoErrs $ERROR_GCOV $ERROR_SOURCE $ERROR_GRAPH $ERROR_MISMATCH
     $ERROR_BRANCH $ERROR_EMPTY $ERROR_FORMAT $ERROR_VERSION $ERROR_UNUSED
     $ERROR_PACKAGE $ERROR_CORRUPT $ERROR_NEGATIVE $ERROR_COUNT
     $ERROR_UNSUPPORTED $ERROR_DEPRECATED $ERROR_INCONSISTENT_DATA
     $ERROR_CALLBACK
     $ERROR_PARALLEL report_parallel_error
     $stop_on_error

     @extractVersionScript $verify_checksum

     is_external @internal_dirs $opt_no_external
     rate get_overall_line $default_precision check_precision

     system_no_output $devnull $dirseparator

     %tlaColor %tlaTextColor use_vanilla_color %pngChar %pngMap
     %dark_palette %normal_palette parse_w3cdtf
);

our @ignore;
our @message_count;
our $suppressAfter = 100;    # stop warning after this number of messsages
our %ERROR_ID;
our %ERROR_NAME;
our $tool_dir     = $FindBin::RealBin;
our $tool_name    = basename($0);        # import from lcovutil module
our $lcov_version = 'LCOV version ' . `"$tool_dir"/get_version.sh --full`;
our $lcov_url     = "https://github.com//linux-test-project/lcov";
our @temp_dirs;
our $tmp_dir = '/tmp';          # where to put temporary/intermediate files
our $preserve_intermediates;    # this is useful only for debugging
our $devnull      = File::Spec->devnull();    # portable way to do it
our $dirseparator = ($^O =~ /Win/) ? '\\' : '/';
our $interp       = ($^O =~ /Win/) ? $^X : undef;

our $debug   = 0;    # if set, emit debug messages
our $verbose = 0;    # default level - higher to enable additional logging

our $split_char = ',';    # by default: split on comma

# geninfo errors are shared by 'lcov' - so we put them in a common location
our $ERROR_GCOV              = 0;
our $ERROR_SOURCE            = 1;
our $ERROR_GRAPH             = 2;
our $ERROR_FORMAT            = 3;  # bad record in .info file
our $ERROR_EMPTY             = 4;  # no records found in info file
our $ERROR_VERSION           = 5;
our $ERROR_UNUSED            = 6;  # exclude/include/substitute pattern not used
our $ERROR_MISMATCH          = 7;
our $ERROR_BRANCH            = 8;  # branch numbering is not correct
our $ERROR_PACKAGE           = 9;  # missing package
our $ERROR_CORRUPT           = 10; # corrupt file
our $ERROR_NEGATIVE          = 11; # unexpected negative count in coverage data
our $ERROR_COUNT             = 12; # too many messages of type
our $ERROR_UNSUPPORTED       = 13; # some unsupported feature or usage
our $ERROR_PARALLEL          = 14; # error in fork/join
our $ERROR_DEPRECATED        = 15; # deprecated feature
our $ERROR_CALLBACK          = 16; # callback produced an error
our $ERROR_INCONSISTENT_DATA = 17; # somthing wrong with .info

our %geninfoErrs = ("gcov"         => $ERROR_GCOV,
                    "source"       => $ERROR_SOURCE,
                    "branch"       => $ERROR_BRANCH,
                    "mismatch"     => $ERROR_MISMATCH,
                    "graph"        => $ERROR_GRAPH,
                    "format"       => $ERROR_FORMAT,
                    "empty"        => $ERROR_EMPTY,
                    "version"      => $ERROR_VERSION,
                    "unused"       => $ERROR_UNUSED,
                    "parallel"     => $ERROR_PARALLEL,           # error on wait
                    "corrupt"      => $ERROR_CORRUPT,
                    "negative"     => $ERROR_NEGATIVE,
                    "count"        => $ERROR_COUNT,
                    "unsupported"  => $ERROR_UNSUPPORTED,
                    "inconsistent" => $ERROR_INCONSISTENT_DATA,
                    "deprecated"   => $ERROR_DEPRECATED,
                    "callback"     => $ERROR_CALLBACK,
                    "package"      => $ERROR_PACKAGE,);
our $stop_on_error;    # attempt to keep going

our $br_coverage   = 0;    # If set, generate branch coverage statistics
our $func_coverage = 1;    # If set, generate function coverage statistics
our $rtlExtensions;
our $cExtensions;

# for external file filtering
our @internal_dirs;
our $opt_no_external;

# filename substitutions
our @file_subst_patterns;

# C++ demangling
our @cpp_demangle;         # the options passed in
our $demangle_cpp_cmd;     # the computed command string
# deprecated: demangler for C++ function names is c++filt
our $cpp_demangle_tool;
# Deprecated:  prefer -Xlinker approach with @cpp_dmangle_tool
our $cpp_demangle_params;

our @extractVersionScript;   # script/callback to find version ID of file
our $verify_checksum;        # compute and/or check MD5 sum of source code lines

# Specify coverage rate default precision
our $default_precision = 1;

# undef indicates not set by command line or RC option - so default to
# sequential processing
our $maxParallelism;

our $maxMemory = 0;    # zero indicates no memory limit to parallelism

sub default_info_impl(@);

our $info_callback = \&default_info_impl;

# filter classes that may be requested
# don't report BRDA data for line which seems to have no conditionals
#   These may be from C++ exception handling (for example) - and are not
#   interesting to users.
our $FILTER_BRANCH_NO_COND = 0;
# don't report line coverage for closing brace of a function
#   or basic block, if the immediate predecessor line has the same count.
our $FILTER_LINE_CLOSE_BRACE = 1;
# merge functions which appear on same file/line - guess that that
#   they are all the same
our $FILTER_FUNCTION_ALIAS = 2;
# region between LCOV EXCL_START/STOP
our $FILTER_EXCLUDE_REGION = 3;
# region between LCOV EXCL_BR_START/STOP
our $FILTER_EXCLUDE_BRANCH = 4;
# empty line
our $FILTER_BLANK_LINE = 5;
# empty line, out of range line
our $FILTER_LINE_RANGE = 6;
# backward compatibility: empty line, close brace
our $FILTER_LINE = 7;
# remove functions which have only a single line
our $FILTER_TRIVIAL_FUNCTION = 8;

our %COVERAGE_FILTERS = ("branch"        => $FILTER_BRANCH_NO_COND,
                         'brace'         => $FILTER_LINE_CLOSE_BRACE,
                         'blank'         => $FILTER_BLANK_LINE,
                         'range'         => $FILTER_LINE_RANGE,
                         'line'          => $FILTER_LINE,
                         'function'      => $FILTER_FUNCTION_ALIAS,
                         'region'        => $FILTER_EXCLUDE_REGION,
                         'branch_region' => $FILTER_EXCLUDE_BRANCH,
                         "trivial"       => $FILTER_TRIVIAL_FUNCTION,);
our @cov_filter;    # 'undef' if filter is not enabled,
                    # [line_count, coverpoint_count] histogram if
                    #   filter is enabled: nubmer of applications
                    #   of this filter

our $EXCL_START = "LCOV_EXCL_START";
our $EXCL_STOP  = "LCOV_EXCL_STOP";
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
our $case_insensitive           = 0;
our $exclude_exception_branch   = 0;
our $derive_function_end_line   = 1;
our $trivial_function_threshold = 5;

# list of regexps applied to line text - if exclude if matched
our @omit_line_patterns;
our @exclude_function_patterns;

our $rtl_file_extensions  = 'v|vh|sv|vhdl?';
our $c_file_extensions    = 'c|h|i||C|H|I|icc|cpp|cc|cxx|hh|hpp|hxx';
our $java_file_extensions = 'java';
# don't look more than 10 lines ahead when filtering (default)
our $source_filter_lookahead = 10;
# by default, don't treat expressions containing bitwise operators '|', '&', '~'
#   as conditional in bogus branch filtering
our $source_filter_bitwise_are_conditional = 0;

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

sub is_folder_empty
{
    my $dirname = shift;
    opendir(my $dh, $dirname) or die "Not a directory: $!";
    return scalar(grep { $_ ne "." && $_ ne ".." } readdir($dh)) == 0;
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

sub append_tempdir($)
{
    push(@temp_dirs, @_);
}

sub warn_handler($)
{
    my ($msg) = @_;

    if (!$debug) {
        $msg =~ s/ at \S+ line \d+\.$//;
    }
    warn("$tool_name: $msg");
}

sub die_handler($)
{
    my ($msg) = @_;

    temp_cleanup();
    if (!$debug) {
        $msg =~ s/ at \S+ line \d+\.$//;
    }
    # Enforce consistent "ERROR:" message prefix
    $msg =~ s/^error:\s+//i;
    die("$tool_name: ERROR: $msg");
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
        close($handle);
    }
}

our $use_MemoryProcess;

sub read_proc_vmsize
{
    if (open(PROC, "<", '/proc/self/stat')) {
        my $str = do { local $/; <PROC> };    # slurp whole thing
        close(PROC);
        my @data = split(' ', $str);
        return $data[23 - 1];                 # man proc - vmsize is at index 22
    } else {
        lcovutil::ignorable_error($lcovutil::ERROR_PACKAGE,
                                  "unable to open: $!");
        return 0;
    }
}

sub init_parallel_params()
{
    if (!defined($lcovutil::maxParallelism)) {
        $lcovutil::maxParallelism = 1;
    } elsif (0 == $lcovutil::maxParallelism) {
        lcovutil::count_cores();
    }
    $lcovutil::maxMemory *= 1 << 20;
    if (1 != $lcovutil::maxParallelism &&    # no memory limits if not parallel
        0 != $lcovutil::maxMemory
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
            lcovutil::ignorable_error($lcovutil::ERROR_PACKAGE,
                "package Memory::Process is required to control memory consumption during parallel operatons: $@"
            );
            lcovutil::info(
                     "Attempting to retrieve memory size from /proc instead\n");
            # check if we can get this from /proc (i.e., are we on linux?)
            if (0 == read_proc_vmsize()) {
                $lcovutil::maxMemory = 0;    # turn off that feature
                lcovutil::info(
                    "Continuing execution without Memory::Process or /proc.  Note that your maximum memory constraint will be ignored\n"
                );
            }
            $use_MemoryProcess = 0;
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
        return $arr->[0]->[0];    # current total
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
                        die("unexpected duplicate key $x in $key->$f")
                            if exists($lcovutil::profileData{$key}{$f}{$x});
                        $lcovutil::profileData{$key}{$f}{$x} = $y;
                    }
                } else {
                    die("unexpected duplicate key $f in $key")
                        if exists($lcovutil::profileData{$key}{$f});
                    $lcovutil::profileData{$key}{$f} = $t;
                }
            }
        } else {
            die("unexpected duplicate key $key in profileData")
                if exists($lcovutil::profileData{$key});
            $lcovutil::profileData{$key} = $d;
        }
    }
}

sub save_cmd_line($$)
{
    my ($argv, $bin) = @_;
    my $cmd = $lcovutil::tool_name;
    $lcovutil::profileData{config}{bin} = $FindBin::RealBin;
    foreach my $arg (@$argv) {
        $cmd .= ' ';
        if ($arg =~ /\s/) {
            $cmd .= "'$arg'";
        } else {
            $cmd .= $arg;
        }
    }
    $lcovutil::profileData{config}{cmdLine} = $cmd;
}

sub save_profile($)
{
    my ($dest) = @_;

    if (defined($lcovutil::profile)) {
        $lcovutil::profileData{config}{maxParallel} = $maxParallelism;
        $lcovutil::profileData{config}{tool}        = $lcovutil::tool_name;
        $lcovutil::profileData{config}{version}     = $lcovutil::lcov_version;
        $lcovutil::profileData{config}{tool_dir}    = $lcovutil::tool_dir;
        $lcovutil::profileData{config}{url}         = $lcovutil::lcov_url;
        $lcovutil::profileData{config}{date}        = `date`;
        $lcovutil::profileData{config}{uname}       = `uname -a`;
        foreach my $k ('date', 'uname') {
            chomp($lcovutil::profileData{config}{$k});
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
            close(JSON);
        } else {
            print("Error:  unable to open profile output $dest: '$!'\n");
        }
    }
}

sub set_rtl_extensions
{
    my $str = shift;
    $rtl_file_extensions = join('|', split($split_char, $str));
}

sub set_c_extensions
{
    my $str = shift;
    $c_file_extensions = join('|', split($split_char, $str));
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
    die("ERROR: could not find $tool tool needed for --demangle-cpp")
        if (lcovutil::system_no_output(3, "echo \"\" | '$tool'"));
}

#
# read_config(filename)
#
# Read configuration file FILENAME and return a reference to a hash containing
# all valid key=value pairs found.
#

sub read_config($)
{
    my $filename = $_[0];
    my %result;
    my $key;
    my $value;
    local *HANDLE;

    info(1, "read_config: $filename\n");
    if (!open(HANDLE, "<", $filename)) {
        warn("WARNING: cannot read configuration file $filename: $!\n");
        return undef;
    }
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
        while ($value =~ /\$ENV\{([^}]+)\}/) {
            my $varname = $1;
            if (!exists($ENV{$varname})) {
                warn(
                    "Variable '$key' in RC file '$filename' uses environment variable '$varname' - which is not set (ignoring '$_').\n"
                );
                next VAR;
            }
            $value =~ s/^\$ENV{$varname}/$ENV{$varname}/g;
        }
        if (defined($key) && defined($value)) {
            info(2, "  set: $key = $value\n");
            if (exists($result{$key})) {
                if ('ARRAY' eq ref($result{$key})) {
                    push(@{$result{$key}}, $value);
                } else {
                    $result{$key} = [$result{$key}, $value];
                }
            } else {
                $result{$key} = $value;
            }
        } else {
            warn("WARNING: malformed statement in line $. " .
                 "of configuration file $filename\n");
        }
    }
    close(HANDLE);
    return \%result;
}

#
# apply_config(REF, ref)
#
# REF is a reference to a hash containing the following mapping:
#
#   key_string => var_ref
#
# where KEY_STRING is a keyword and VAR_REF is a reference to an associated
# variable. If the global configuration hashes CONFIG or OPT_RC contain a value
# for keyword KEY_STRING, VAR_REF will be assigned the value for that keyword.
#
# Return 1 if we set something

sub _set_config($$$)
{
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
        if ('ARRAY' eq ref($value)) {
            warn("setting scalar config '$key' with array value [" .
                 join(', ', @$value) . "] - using '" . $value->[-1] . "'");
            $$r = $value->[-1];
        } else {
            $$r = $value;
        }
        info(2, "  assign $$r to $key\n");
    }
}

sub apply_config($$$)
{
    my ($ref, $config, $rc_overrides) = @_;
    my $set_value = 0;
    foreach (keys(%{$ref})) {
        # if sufficiently verbose, could mention that key is ignored
        next if ((exists($rc_overrides->{$_})) ||
                 !exists($config->{$_}));
        my $v = $config->{$_};
        $set_value = 1;
        _set_config($ref, $_, $v);    # write into options
    }
    return $set_value;
}

# use these list values from the RC file unless the option is
#   passed on teh command line
my (@rc_filter, @rc_ignore, @rc_exclude_patterns,
    @rc_include_patterns, @rc_subst_patterns, @rc_omit_patterns,
    @rc_erase_patterns, @rc_version_script, @unsupported_config,
    %unsupported_rc, $keepGoing, $help,
    $rc_no_branch_coverage, $rc_no_func_coverage, $rc_no_checksum,
    $version);
my $quiet = 0;
my $tempdirname;

# these options used only by lcov - but moved here so that we can
#   share arg parsing
our ($lcov_remove,     # If set, removes parts of tracefile
     $lcov_capture,    # If set, capture data
     $lcov_extract);    # If set, extracts parts of tracefile
our @opt_config_files;
our @opt_ignore_errors;
our @opt_filter;

my %deprecated_rc = ("genhtml_demangle_cpp"        => "demangle_cpp",
                     "genhtml_demangle_cpp_tool"   => "demangle_cpp",
                     "genhtml_demangle_cpp_params" => "demangle_cpp",
                     "geninfo_checksum"            => "checksum",
                     "geninfo_no_exception_branch" => "no_exception_branch",
                     "lcov_branch_coverage"        => "branch_coverage",
                     "lcov_function_coverage"      => "function_coverage",
                     "genhtml_function_coverage"   => "function_coverage",
                     "genhtml_branch_coverage"     => "branch_coverage",);
my @deprecated_uses;

my %rc_common = (
             'derive_function_end_line' => \$lcovutil::derive_function_end_line,
             'trivial_function_threshold' => \$lcovutil::trivial_function_threshold,
             "lcov_tmp_dir"                => \$lcovutil::tmp_dir,
             "lcov_json_module"            => \$JsonSupport::rc_json_module,
             "branch_coverage"             => \$lcovutil::br_coverage,
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
             "lcov_function_coverage" => \$lcovutil::func_coverage,
             "lcov_branch_coverage"   => \$lcovutil::br_coverage,
             "ignore_errors"          => \@rc_ignore,
             "max_message_count"      => \$lcovutil::suppressAfter,
             'stop_on_error'          => \$lcovutil::stop_on_error,
             "rtl_file_extensions"    => \$rtlExtensions,
             "c_file_extensions"      => \$cExtensions,
             "filter_lookahead"       => \$lcovutil::source_filter_lookahead,
             "filter_bitwise_conditional" =>
        \$lcovutil::source_filter_bitwise_are_conditional,
             "profile"  => \$lcovutil::profile,
             "parallel" => \$lcovutil::maxParallelism,
             "memory"   => \$lcovutil::maxMemory,

             "no_exception_branch"   => \$lcovutil::exclude_exception_branch,
             'filter'                => \@rc_filter,
             'exclude'               => \@rc_exclude_patterns,
             'include'               => \@rc_include_patterns,
             'substitute'            => \@rc_subst_patterns,
             'omit_lines'            => \@rc_omit_patterns,
             'erase_functions'       => \@rc_erase_patterns,
             "version_script"        => \@rc_version_script,
             "checksum"              => \$lcovutil::verify_checksum,
             "case_insensitive"      => \$lcovutil::case_insensitive,
             "forget_testcase_names" => \$TraceFile::ignore_testcase_name,
             "split_char"            => \$lcovutil::split_char,

             "demangle_cpp" => \@lcovutil::cpp_demangle,

);

our %argCommon = ("tempdir=s"        => \$tempdirname,
                  "version-script=s" => \@lcovutil::extractVersionScript,
                  "checksum"         => \$lcovutil::verify_checksum,
                  "no-checksum"      => \$rc_no_checksum,
                  "quiet|q+"         => \$quiet,
                  "verbose|v+"       => \$lcovutil::verbose,
                  "debug+"           => \$lcovutil::debug,
                  "help|h|?"         => \$help,
                  "version"          => \$version,

                  "function-coverage"    => \$lcovutil::func_coverage,
                  "branch-coverage"      => \$lcovutil::br_coverage,
                  "no-function-coverage" => \$rc_no_func_coverage,
                  "no-branch-coverage"   => \$rc_no_branch_coverage,

                  "filter=s"          => \@opt_filter,
                  "demangle-cpp:s"    => \@lcovutil::cpp_demangle,
                  "ignore-errors=s"   => \@opt_ignore_errors,
                  "keep-going"        => \$keepGoing,
                  "config-file=s"     => \@unsupported_config,
                  "rc=s%"             => \%unsupported_rc,
                  "profile:s"         => \$lcovutil::profile,
                  "exclude=s"         => \@lcovutil::exclude_file_patterns,
                  "include=s"         => \@lcovutil::include_file_patterns,
                  "erase-functions=s" => \@lcovutil::exclude_function_patterns,
                  "omit-lines=s"      => \@lcovutil::omit_line_patterns,
                  "substitute=s"      => \@lcovutil::file_subst_patterns,
                  "parallel|j:i"      => \$lcovutil::maxParallelism,
                  "memory=i"          => \$lcovutil::maxMemory,
                  "forget-test-names" => \$TraceFile::ignore_testcase_name,
                  "preserve"          => \$lcovutil::preserve_intermediates,);

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
    my %new_opt_rc;

    foreach my $v (@opt_rc) {
        my $index = index($v, '=');
        die("malformed --rc option '$v' - should be 'key=value'")
            if $index == -1;
        my $key   = substr($v, 0, $index);
        my $value = substr($v, $index + 1);
        $key =~ s/^\s+|\s+$//g;
        next unless exists($rcHash{$key});
        info(1, "apply --rc overrides\n")
            unless $set_value;
        # can't complain about deprecated uses here because the user
        #  might have suppressed that message - but we haven't looked at
        #  the suppressions in the parameter list yet.
        push(@deprecated_uses, $key)
            if (exists($deprecated_rc{$key}));
        # strip spaces
        $value =~ s/^\s+|\s+$//g;
        _set_config(\%rcHash, $key, $value);
        $set_value = 1;
        # record override of this one - so we skip the value from the
        #  config file
        $new_opt_rc{$key} = $value;
    }
    my $config;    # did we see a config file or not?
                   # Read configuration file if available
    if (0 != scalar(@opt_config_files)) {
        foreach my $f (@opt_config_files) {
            $config = read_config($f);
            $set_value |= apply_config(\%rcHash, $config, \%new_opt_rc);
        }
        return $set_value;
    } elsif (defined($ENV{"HOME"}) && (-r $ENV{"HOME"} . "/.lcovrc")) {
        $config = read_config($ENV{"HOME"} . "/.lcovrc");
    } elsif (-r "/etc/lcovrc") {
        $config = read_config("/etc/lcovrc");
    } elsif (-r "/usr/local/etc/lcovrc") {
        $config = read_config("/usr/local/etc/lcovrc");
    }

    if ($config) {
        # Copy configuration file and --rc values to variables
        $set_value |= apply_config(\%rcHash, $config, \%new_opt_rc);
    }
    lcovutil::set_rtl_extensions($rtlExtensions)
        if $rtlExtensions;
    lcovutil::set_c_extensions($cExtensions)
        if $cExtensions;

    return $set_value;
}

sub parseOptions
{
    my ($rcOptions, $cmdLineOpts) = @_;

    apply_rc_params($rcOptions);

    my %options = (%argCommon, %$cmdLineOpts);
    if (!GetOptions(%options)) {
        return 0;
    }
    foreach my $d (['--config-file', scalar(@unsupported_config)],
                   ['--rc', scalar(%unsupported_rc)]) {
        die("Error: '" . $d->[0] . "' option name cannot be abbreviated\n")
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

    lcovutil::init_verbose_flag($quiet);
    @opt_filter                      = @rc_filter unless @opt_filter;
    @opt_ignore_errors               = @rc_ignore unless @opt_ignore_errors;
    @lcovutil::exclude_file_patterns = @rc_exclude_patterns
        unless @lcovutil::exclude_file_patterns;
    @lcovutil::include_file_patterns = @rc_include_patterns
        unless @lcovutil::include_file_patterns;
    @lcovutil::subst_file_patterns = @rc_subst_patterns
        unless @lcovutil::subst_file_patterns;
    @lcovutil::omit_line_patterns = @rc_omit_patterns
        unless @lcovutil::omit_line_patterns;
    @lcovutil::exclude_function_patterns = @rc_erase_patterns
        unless @lcovutil::exclude_function_patterns;
    @lcovutil::extractVersionScript = @rc_version_script
        unless @lcovutil::extractVersionScript;

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
    if (defined($rc_no_checksum)) {
        $lcovutil::verify_checksum = ($rc_no_checksum ? 0 : 1);
    }

    if (!$lcov_capture) {
        lcovutil::munge_file_patterns();
        lcovutil::init_parallel_params();
        # Determine which errors the user wants us to ignore
        parse_ignore_errors(@opt_ignore_errors);
        # Determine what coverpoints the user wants to filter
        parse_cov_filters(@opt_filter);

        # Ensure that the c++filt tool is available when using --demangle-cpp
        lcovutil::do_mangle_check();

        foreach my $key (@deprecated_uses) {
            lcovutil::ignorable_warning($lcovutil::ERROR_DEPRECATED,
                "RC option '$key' is deprecated.  Consider using '" .
                    $deprecated_rc{$key} .
                    ". instead.  (Backward-compatible support will be removed in the future"
            );
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
    if ($lcovutil::case_insensitive) {
        $pattern = "/$pattern/i";
    }
    return qr($pattern);
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
    # sadly, substitions aren't regexps and can't be precompiled
    foreach my $p (['substitute', \@file_subst_patterns]) {
        my ($flag, $list) = @$p;
        next unless @$list;
        PAT: foreach my $pat (@$list) {
            my $text = 'abc';
            my $str  = eval { '$test =~ ' . $pat . ';' };
            die("Invalid regexp \"$flag $pat\":\n$@")
                if $@;

            if ($lcovutil::case_insensitive) {
                for (my $i = length($pat) - 1; $i >= 0; --$i) {
                    my $char = substr($pat, $i, 1);
                    if ($char eq 'i') {
                        next PAT;
                    } elsif ($char =~ /[\/#!@%]/) {
                        last;
                    }
                }
                warn(
                    "--$flag pattern '$pat' does not seem to be case insensitive - but you asked for case insenstive matching\n"
                );
            }
        }
        # keep track of number of times this was applied
        @$list = map({ [$_, 0]; } @$list);
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
                    ]
    ) {
        eval 'qr/' . $regexp->[1] . '/';
        my $error = $@;
        chomp($error);
        $error =~ s/at \(eval.*$//;
        die("ERROR: invalid '" . $regexp->[0] . "' exclude pattern: $error")
            if $error;
    }
}

sub warn_file_patterns
{
    foreach my $p (['include', \@include_file_patterns],
                   ['exclude', \@exclude_file_patterns],
                   ['substitute', \@file_subst_patterns],
                   ['omit-lines', \@omit_line_patterns],
                   ['exclude-functions', \@exclude_function_patterns]
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
            # $@ should never match:  we already checked pattern vaidity during
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
    for ($i = 0; $i < $depth; $i++) {
        if ($lcovutil::case_insensitive) {
            $filename =~ s/^[^\/]*\/+(.*)$/$1/i;
        } else {
            $filename =~ s/^[^\/]*\/+(.*)$/$1/;
        }
    }
    return $filename;
}

sub define_errors($)
{
    my $hash = shift;
    foreach my $k (keys(%$hash)) {
        my $id = $hash->{$k};
        $ERROR_ID{$k}                 = $id;
        $ERROR_NAME{$id}              = $k;
        $ignore[$ERROR_ID{$k}]        = 0;
        $message_count[$ERROR_ID{$k}] = 0;
    }
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
        die("ERROR: unknown argument for --ignore-errors: '$item'")
            unless exists($ERROR_ID{lc($item)});
        my $item_id = $ERROR_ID{lc($item)};
        $ignore[$item_id] += 1;
    }
}

sub is_ignored($)
{
    my $code = shift;

    return ($code < scalar(@ignore) && $ignore[$code]);
}

our %warnOnlyOnce;
# if 'stop_on_error' is false, then certain errors should be emitted at most once
#  (not relevant if stop_on_error is true - as we will exit after the error.
sub warn_once
{
    my $key = shift;
    return 0
        if (exists($warnOnlyOnce{$key}));
    $warnOnlyOnce{$key} = 1;
    return 1;
}

sub warnSuppress($$)
{
    my ($code, $errName) = @_;
    if ($message_count[$code] == $suppressAfter - 1) {
        my $explain =
            $message_count[$ERROR_COUNT] == 0 ?
            "\n\tTo increase or decrease this limit us '--rc max_message_count=value'."
            :
            '';
        ignorable_warning($ERROR_COUNT,
            "$suppressAfter count reached for '$errName' messages: no more will be reported.$explain"
        );
    }
}

sub ignorable_error($$;$)
{
    my ($code, $msg, $quiet) = @_;

    my $errName = "code_$code";
    $errName = $ERROR_NAME{$code}
        if exists($ERROR_NAME{$code});

    if ($message_count[$code]++ > $suppressAfter &&
        0 < $suppressAfter) {
        # safe to just continue without checking anything else - as either
        #  this message is not fatal and we emitted it some number of times,
        #  or the message is fatal - and this is the first time we see it

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

        if (defined($stop_on_error) && 0 == $stop_on_error) {
            warn_handler("Error: $msg\n" .
                         ($message_count[$code] == 1 ? '' : "$ignoreOpt\n"));
            return;
        }
        die_handler("Error: $msg\n$ignoreOpt");
    }
    # only tell the user how to suppress this on the first occurrence
    my $ignoreOpt =
        ($message_count[$code] == 1) ? "" :
        "\t(use \"$tool_name --ignore-errors $errName,$errName ...\" to suppress this warning)\n";
    warn_handler("Warning: ('$errName') $msg\n$ignoreOpt")
        unless $ignore[$code] > 1 || (defined($quiet) && $quiet);
}

sub ignorable_warning($$;$)
{
    my ($code, $msg, $quiet) = @_;
    my $errName = "code_$code";
    $errName = $ERROR_NAME{$code}
        if exists($ERROR_NAME{$code});
    if ($message_count[$code]++ > $suppressAfter &&
        0 < $suppressAfter) {
        # warn that we are suppressing from here on - for the first skipped
        #   message of this type
        warnSuppress($code, $errName);
        return;
    }
    chomp($msg);    # we insert the newline
    if ($code >= scalar(@ignore) ||
        !$ignore[$code]) {
        # only tell the user how to suppress this on the first occurrence
        my $ignoreOpt =
            ($message_count[$code] == 1) ? "" :
            "\t(use \"$tool_name --ignore-errors $errName,$errName ...\" to suppress this warning)\n";
        warn_handler("Warning: $msg\n$ignoreOpt");
    }
}

sub report_parallel_error
{
    my ($operation, $msg) = @_;
    ignorable_error($ERROR_PARALLEL,
        "$operation: error '$msg' waiting for child (try removing the '--parallel' option"
    );
}

sub is_filter_enabled
{
    # return true of there is an opportunity for filtering
    return (defined($lcovutil::cov_filter[$lcovutil::FILTER_BRANCH_NO_COND]) ||
             defined($lcovutil::cov_filter[$lcovutil::FILTER_LINE_CLOSE_BRACE])
             || defined($lcovutil::cov_filter[$lcovutil::FILTER_BLANK_LINE])
             || defined($lcovutil::cov_filter[$lcovutil::FILTER_LINE_RANGE])
             || defined($lcovutil::cov_filter[$lcovutil::FILTER_EXCLUDE_REGION])
             || defined($lcovutil::cov_filter[$lcovutil::FILTER_EXCLUDE_BRANCH])
             || defined(
                   $lcovutil::cov_filter[$lcovutil::FILTER_TRIVIAL_FUNCTION]) ||
             0 != scalar(@lcovutil::omit_line_patterns));
}

sub parse_cov_filters(@)
{
    my @filters = split($split_char, join($split_char, @_));

    # first, mark that all known filters are disabled
    foreach my $item (keys(%COVERAGE_FILTERS)) {
        my $id = $COVERAGE_FILTERS{$item};
        $cov_filter[$id] = undef
            unless defined($cov_filter[$id]);
    }

    return if (!@filters);

    foreach my $item (@filters) {
        die("ERROR: unknown argument for --filter: '$item'\n")
            unless exists($COVERAGE_FILTERS{lc($item)});
        my $item_id = $COVERAGE_FILTERS{lc($item)};

        $cov_filter[$item_id] = [0, 0];
    }
    if ($cov_filter[$FILTER_LINE]) {
        # when line filtering is enabled, turn on brace and blank fltering as well
        #  (backward compatibility)
        $cov_filter[$FILTER_LINE_CLOSE_BRACE] = [0, 0];
        $cov_filter[$FILTER_BLANK_LINE]       = [0, 0];
    }
}

sub summarize_cov_filters
{

    # use verbosity level -1:  so print unless user says "-q -q"...really quiet

    for my $key (keys(%COVERAGE_FILTERS)) {
        my $id = $COVERAGE_FILTERS{$key};
        next unless defined($lcovutil::cov_filter[$id]);
        my $histogram = $lcovutil::cov_filter[$id];
        next if 0 == $histogram->[0];
        info(-1,
             "Filter suppressions '$key':\n    " . $histogram->[0] .
                 " instance" . ($histogram->[0] > 1 ? "s" : "") .
                 "\n    " . $histogram->[1] . " coverpoint" .
                 ($histogram->[1] > 1 ? "s" : "") . "\n");
    }
    my $patternCount = scalar(@omit_line_patterns);
    if ($patternCount) {
        my $omitCount = 0;
        foreach my $p (@omit_line_patterns) {
            $omitCount += $p->[1];
        }
        info(-1,
             "Omitted %d total line%s matching %d '--omit-lines' pattern%s\n",
             $omitCount,
             $omitCount == 1 ? '' : 's',
             $patternCount,
             $patternCount == 1 ? '' : 's');
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
    # disable but return current status - so the can be re-enabled
    for (my $i = 0; $i < scalar(@$filters); $i++) {
        $cov_filter[$i] = $filters->[$i];
    }
    @lcovutil::omit_line_patterns        = @{$data->[1]};
    @lcovutil::exclude_function_patterns = @{$data->[2]};
}

sub merge_child_pattern_counts
{
    # merge back counts of successful application of substituion and exclusion
    #  patterns (else the parent won't know that the child uses some pattern -
    #  and will complain about it later
    my ($excluded, $subst_patterns) = @_;
    foreach my $ex (@$excluded) {
        if (!exists($lcovutil::excluded_files{$ex})) {
            # call routine so pattern use count is incremented
            TraceFile::skipCurrentFile($ex);
            $lcovutil::excluded_files{$ex} = 1;
        }
    }
    for (my $i = 0; $i <= $#$subst_patterns; ++$i) {
        $lcovutil::file_subst_patterns[$i]->[1] += $subst_patterns->[$i]->[1];
    }
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
    # lambda code may have trailing parens after the function...
    #$close <= $open or die("malformed code in '$line'");

    #return $close == $open;
    return $close >= $open;
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

    return rate($hit, $found, "% ($hit of $found $name$plural)");
}

# Make sure precision is within valid range [1:4]
sub check_precision()
{
    die("ERROR: specified precision is out of range (1 to 4)\n")
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

# figure out what file version we see
sub extractFileVersion
{
    my $filename = shift;

    return undef
        unless @extractVersionScript;

    #die("$filename does not exist")
    #    unless -f $filename;
    my $version;
    my $cmd = join(' ', @extractVersionScript) . " '$filename'";
    lcovutil::debug(1, "extractFileVersion: $cmd\n");
    if (open(VERS, "-|", $cmd)) {
        $version = <VERS>;
        chomp($version);
        close(VERS);
        my $status = $? >> 8;
        0 == $status or
            die("version-script '$cmd' returned non-zero exit code: '$!'");
    } else {
        lcovutil::ignorable_error($lcovutil::ERROR_CALLBACK,
                                  "'open(-| $cmd)' failed: \"$!\"");
    }
    return $version;
}

sub checkVersionMatch
{
    my ($filename, $me, $you) = @_;

    my $match;
    if (@extractVersionScript) {
        my $cmd = join(' ', @extractVersionScript) .
            " --compare '$you' '$me' '$filename'";
        lcovutil::debug("compare_version: \"$cmd\"\n");
        my $rtn = `$cmd`;
        $match = $? ? 0 : 1;
    } else {
        $match = $me eq $you;    # simple string compare
    }
    lcovutil::ignorable_error($ERROR_VERSION,
                    "$filename: revision control version mismatch: $me <- $you")
        unless $match;
}

#
# parse_w3cdtf(date_string)
#
# Parse date string in W3CDTF format into DateTime object.
#

sub parse_w3cdtf($)
{
    my ($str) = @_;
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

package InOutFile;

our $checkedGzipAvail;

sub checkGzip
{
    # Check for availability of GZIP tool
    lcovutil::system_no_output(1, "gzip", "-h") and
        die("ERROR: gzip command not available!\n");
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
                die("Error: unable to demangle: $!\n");
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
                die("ERROR: cannot start gzip to compress to file $f: $!\n");
        } else {
            if ($demangle) {
                $cmd .= "$m '$f'";
            } else {
                $cmd .= $f;
            }
            open(HANDLE, $demangle ? '|-' : $m, $cmd) or
                die("ERROR: cannot write to $f: $!\n");
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
                die("ERROR: integrity check failed for compressed file $f!\n");

            # Open compressed file
            my $cmd = "gzip -cd '$f'";
            $cmd .= " | " . $lcovutil::demangle_cpp_cmd
                if ($demangle);
            open(HANDLE, "-|", $cmd) or
                die("ERROR: cannot start gunzip to decompress file $f: $!\n");

        } elsif ($demangle &&
                 defined($lcovutil::demangle_cpp_cmd)) {
            open(HANDLE, "-|", "cat '$f' | $lcovutil::demangle_cpp_cmd") or
                die("ERROR: cannot start demangler for file $f: $!\n");
        } else {
            # Open decompressed file
            open(HANDLE, "<", $f) or
                die("ERROR: cannot read file $f: $!\n");
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

sub _summary
{
    # dummy method - to parallelize calling sequence with CountData, BranchData
    my $self = shift;
    return $self;
}

# Class definitions
package CountData;

our $UNSORTED = 0;
our $SORTED   = 1;

sub new
{
    my $class    = shift;
    my $sortable = defined($_[0]) ? shift : $UNSORTED;
    my $self = [{},
                $sortable,
                0,    # found
                0,    # hit
    ];
    bless $self, $class;

    return $self;
}

sub append
{
    # return 1 if we hit something new, 0 if not (count was already non-zero)
    my ($self, $key, $count) = @_;
    my $interesting = 0;    # hit something new or not

    if ($count < 0) {
        lcovutil::ignorable_error($lcovutil::ERROR_NEGATIVE,
                          "Unexpected negative count '$count' for line '$key'");
    }
    my $data = $self->[0];
    if (!defined($data->{$key})) {
        $interesting = 1;         # something new - whether we hit it or not
        $data->{$key} = $count;
        ++$self->[2];                    # found
        ++$self->[3] if ($count > 0);    # hit
    } else {
        my $current = $data->{$key};
        if ($count > 0 &&
            $current == 0) {
            ++$self->[3];
            $interesting = 1;
        }
        $data->{$key} = $count + $current;
    }
    return $interesting;
}

sub value
{
    my $self = shift;
    my $key  = shift;

    my $data = $self->[0];
    if (!exists($data->{$key})) {
        return undef;
    }
    return $data->{$key};
}

sub remove
{
    my ($self, $key, $check_if_present) = @_;

    my $data = $self->[0];
    if (!defined($check_if_present) ||
        exists($data->{$key})) {

        die("$key not found")
            unless exists($data->{$key});
        --$self->[2];    # found;
        --$self->[3]     # hit
            if ($data->{$key} > 0);

        delete $data->{$key};
        return 1;
    }

    return 0;
}

sub _summary
{
    my $self = shift;

    return $self;
}

sub found
{
    my $self = shift;

    return $self->[2];
}

sub hit
{
    my $self = shift;

    return $self->[3];
}

sub keylist
{
    my $self = shift;
    return keys(%{$self->[0]});
}

sub entries
{
    my $self = shift;
    return scalar(keys(%{$self->[0]}));
}

sub merge
{
    my $self = shift;
    my $info = shift;

    my $interesting = 0;
    foreach my $key ($info->keylist()) {
        if ($self->append($key, $info->value($key))) {
            $interesting = 1;
        }
    }
    return $interesting;
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
    $self->_summary();
    return ($self->[2], $self->[3]);
}

package BranchBlock;
# branch element:  index, taken/not-taken count, optional expression
# for baseline or current data, 'taken' is just a number (or '-')
# for differential data: 'taken' is an array [$taken, tla]

sub new
{
    my ($class, $id, $taken, $expr, $is_exception) = @_;
    # if branchID is not an expression - go back to legacy behaviour
    my $self = [$id, $taken,
                (defined($expr) && $expr eq $id) ? undef : $expr,
                defined($is_exception) && $is_exception ? 1 : 0
    ];
    bless $self, $class;
    if ($self->count() < 0) {
        lcovutil::ignorable_error($lcovutil::ERROR_NEGATIVE,
                           "Unexpected negative taken '$taken' for branch $id");
    }
    return $self;
}

sub isTaken
{
    my $self = shift;
    return $self->[1] ne '-';
}

sub id
{
    my $self = shift;
    return $self->[0];
}

sub data
{
    my $self = shift;
    return $self->[1];
}

sub count
{
    my $self = shift;
    return $self->[1] eq '-' ? 0 : $self->[1];
}

sub expr
{
    my $self = shift;
    return $self->[2];
}

sub exprString
{
    my $self = shift;
    my $e    = $self->[2];
    return defined($e) ? $e : 'undef';
}

sub is_exception
{
    my $self = shift;
    return $self->[3];
}

sub merge
{
    # return 1 if something changed, 0 if nothing new covered or discovered
    my ($self, $that, $filename, $line) = @_;
    if ($self->exprString() ne $that->exprString()) {
        my $loc = defined($filename) ? "\"$filename\":$line: " : '';
        lcovutil::ignorable_error($ERROR_MISMATCH,
                                  "${loc}mismatched expressions for id " .
                                      $self->id() . ", " . $that->id() .
                                      ": '" . $self->exprString() .
                                      "' -> '" . $that->exprString() . "'");
        # else - ignore the issue and merge data even though the expressions
        #  look different
        # To enable a consistent result, keep the one which is alphabetically
        # first
        if ($that->exprString() le $self->exprString()) {
            $self->[2] = $that->[2];
        }
    }
    if ($self->is_exception() != $that->is_exception()) {
        my $loc = defined($filename) ? "\"$filename\":$line: " : '';
        lcovutil::ignorable_error($ERROR_MISMATCH,
                                  "${loc}mismatched exception tag for id " .
                                      $self->id() . ", " . $that->id() .
                                      ": '" . $self->is_exception() .
                                      "' -> '" . $that->is_exception() . "'");
        # set 'self' to 'not related to exception' - to give a consistent
        #  answer for the merge operation.  Otherwise, we pick whatever
        #  was seen first - which is unprecitable during threaded execution.
        $self->[3] = 0;
    }
    my $t = $that->[1];
    return 0 if $t eq '-';    # no new news

    my $count = $self->[1];
    my $interesting;
    if ($count ne '-') {
        $count += $t;
        $interesting = $count == 0 && $t != 0;
    } else {
        $count       = $t;
        $interesting = $t != 0;
    }
    $self->[1] = $count;
    return $interesting;
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
    my ($self, $id) = @_;
    $self->hasBlock($id) or die("unknown block $id");
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

    !exists($self->[1]->{$blockId}) or die "duplicate blockID";
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

package FunctionEntry;
# keep track of all the functions/all the function aliases
#  at a particular line in the file.  THey must all be the
#  same function - perhaps just templatized differently.

sub new
{
    my ($class, $name, $filename, $startLine, $endLine) = @_;
    my %aliases = ($name => 0);    # not hit, yet
    my $self    = [$name, \%aliases, $filename, $startLine, 0, $endLine];

    bless $self, $class;
    return $self;
}

sub name
{
    my $self = shift;
    return $self->[0];
}

sub hit
{
    my $self = shift;
    return $self->[4];
}

sub count
{
    my ($self, $alias, $merged) = @_;

    exists($self->aliases()->{$alias}) or
        die("$alias is not an alias of " . $self->name());

    return $self->[4]
        if (defined($merged) && $merged);

    return $self->aliases()->{$alias};
}

sub aliases
{
    my $self = shift;
    return $self->[1];
}

sub numAliases
{
    my $self = shift;
    return scalar(keys %{$self->[1]});
}

sub file
{
    my $self = shift;
    return $self->[2];
}

sub line
{
    my $self = shift;
    return $self->[3];
}

sub end_line
{
    my $self = shift;
    return $self->[5];
}

sub set_end_line
{
    my ($self, $line) = @_;
    die("bad end line $line for " . $self->name() . " start: " . $self->line())
        unless ($line >= $self->line());
    $self->[5] = $line;
}

sub addAlias
{
    my ($self, $name, $count) = @_;

    if ($count < 0) {
        my $alias =
            $name ne $self->name() ? " (alias of '" . $self->name() . "'" : "";
        lcovutil::ignorable_error($lcovutil::ERROR_NEGATIVE,
               "Unexpected negative count '$count' for function '$name'$alias");
    }

    my $interesting;
    if (exists($self->[1]->{$name})) {
        $interesting = 0 == $self->[1]->{$name} && 0 != $count;
        $self->[1]->{$name} += $count;
    } else {
        $self->[1]->{$name} = $count;
        $interesting = 0 != $count;
        # keep track of the shortest name as the function represntative
        my $curlen = length($self->[0]);
        my $len    = length($name);
        $self->[0] = $name
            if ($len < $curlen ||    # alias is shorter
                ($len == $curlen &&   # alias is same length but lexically first
                 $name lt $self->[0]));
    }
    $self->[4] += $count;
    return $interesting;
}

sub merge
{
    my ($self, $that) = @_;
    my $interesting = 0;
    foreach my $name (keys(%{$that->[1]})) {
        if ($self->addAlias($name, $that->[1]->{$name})) {
            $interesting = 1;
        }
    }
    return $interesting;
}

sub addAliasDifferential
{
    my ($self, $name, $data) = @_;
    die("alias $name exists")
        if exists($self->[1]->{$name}) && $name ne $self->name();
    die("expected array")
        unless ref($data) eq "ARRAY" && 2 == scalar(@$data);
    $self->[1]->{$name} = $data;
}

sub setCountDifferential
{
    my ($self, $data) = @_;
    die("expected array")
        unless ref($data) eq "ARRAY" && 2 == scalar(@$data);
    $self->[4] = $data;
}

sub findMyLines
{
    # use my start/end location to find my list of line coverpoints within
    # this function.
    # return sorted list of [ [lineNo, hitCount], ...]
    my ($self, $lineData) = @_;
    return undef unless $self->end_line();
    my @lines;
    for (my $lineNo = $self->line(); $lineNo <= $self->end_line; ++$lineNo) {
        my $hit = $lineData->value($lineNo);
        push(@lines, [$lineNo, $hit])
            if (defined($hit));
    }
    return \@lines;
}

sub findMyBranches
{
    # use my start/end location to list of branch entries within this function
    # return sorted list [ branchEntry, ..] sorted by line
    my ($self, $branchData) = @_;
    die("expected BranchData") unless ref($branchData) eq "BranchData";
    return undef               unless $self->end_line();
    my @branches;
    for (my $lineNo = $self->line(); $lineNo <= $self->end_line; ++$lineNo) {
        my $entry = $branchData->value($lineNo);
        push(@branches, $entry)
            if (defined($entry));
    }
    return \@branches;
}

package FunctionMap;

sub new
{
    my $class = shift;
    my $self  = [{}, {}];    # [locationMap, nameMap]
    bless $self, $class;
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
    my ($self, $fnName, $filename, $start_line, $end_line) = @_;
    #lcovutil::info("define: $fnName $filename:$start_line->$end_line\n");
    # could check that function ranges within file are non-overlapping

    my ($locationMap, $nameMap) = @$self;

    my $key = $filename . ":" . $start_line;
    my $data;
    if (exists($locationMap->{$key})) {
        $data = $locationMap->{$key};
        # @todo maybe refactor to make the ERROR_INCONSISTENT_DATA
        lcovutil::ignorable_error(
                    $ERROR_MISMATCH,
                    "mismatched end line for $fnName at $filename:$start_line: "
                        .
                        (
                        defined($data->end_line()) ? $data->end_line() : 'undef'
                        ) .
                        " -> " . (defined($end_line) ? $end_line : 'undef'))
            unless ((defined($end_line) &&
                     defined($data->end_line()) &&
                     $end_line == $data->end_line()) ||
                    (!defined($end_line) && !defined($data->end_line())));
    } else {
        $data = FunctionEntry->new($fnName, $filename, $start_line, $end_line);
        $locationMap->{$key} = $data;
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
    my ($self, $key) = @_;
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
        lcovutil::ignorable_error($ERROR_MISMATCH,
                                  "unknown function '$fnName'");
    }
}

sub merge
{
    my ($self, $that) = @_;

    my $interesting = 0;
    foreach my $key (keys(%{$that->[0]})) {
        my $thatData = $that->[0]->{$key};
        my $thisData;
        if (!exists($self->[0]->{$key})) {
            $thisData =
                $self->define_function($thatData->name(), $thatData->file(),
                                       $thatData->line(), $thatData->end_line()
                );
            $interesting = 1;    # something new...
        } else {
            $thisData = $self->[0]->{$key};
            if ($thisData->line() != $thatData->line() ||
                $thisData->file() ne $thatData->file()) {
                warn("ERROR: function data mismatch at " .
                     $thatData->file() . ":" . $thatData->line());
                next;
            }
        }
        my $aliases = $thatData->aliases();
        foreach my $alias (keys %$aliases) {
            my $count = $aliases->{$alias};
            $self->define_function($alias, $thisData->file(), $thisData->line(),
                                   $thisData->end_line())
                unless defined($self->findName($alias));
            if ($thisData->addAlias($alias, $count)) {
                $interesting = 1;
            }
        }
    }
    return $interesting;
}

sub cloneWithRename
{
    my ($self, $conv) = @_;

    my $newData = FunctionMap->new();
    foreach my $key ($self->keylist()) {
        my $data    = $self->findKey($key);
        my $aliases = $data->aliases();
        foreach my $alias (keys %$aliases) {
            my $cn  = $conv->{$alias};
            my $hit = $aliases->{$alias};

            # Abort if two functions on different lines map to the
            # same demangled name.
            die(  "ERROR: Demangled function name $cn maps to different lines ("
                . $newData->findName($cn)->line()
                . " vs " . $data->line() . ") in " . $newData->file())
                if (defined($newData->findName($cn)) &&
                    $newData->findName($cn)->line() != $data->line());
            $newData->define_function($cn, $data->file(), $data->line(),
                                      $data->end_line());
            $newData->add_count($cn, $hit);
        }
    }
    return $newData;
}

sub insert
{
    my ($self, $entry) = @_;
    die("expected FunctionEntry - " . ref($entry))
        unless 'FunctionEntry' eq ref($entry);
    my ($locationMap, $nameMap) = @$self;
    my $key = $entry->file() . ":" . $entry->line();
    #die("duplicate entry \@$key")
    #  if exists($locationMap->{$key});
    if (exists($locationMap->{$key})) {
        my $current = $locationMap->{$key};
        print("DUP:  " . $current->name() . " -> " . $entry->name() .
              "\n" . $current->file() . ":" . $current->line() .
              " -> " . $entry->file() . $entry->line() . "\n");
        die("duplicate entry \@$key");
    }
    $locationMap->{$key} = $entry;
    foreach my $alias (keys %{$entry->aliases()}) {
        die("duplicate alias '$alias'")
            if (exists($nameMap->{$alias}));
        $nameMap->{$alias} = $entry;
    }
}

sub remove
{
    my ($self, $entry) = @_;
    die("expected FunctionEntry - " . ref($entry))
        unless 'FunctionEntry' eq ref($entry);
    my ($locationMap, $nameMap) = @$self;
    my $key = $entry->file() . ":" . $entry->line();
    foreach my $alias (keys %{$entry->aliases()}) {
        delete($nameMap->{$alias});
    }
    delete($locationMap->{$key});
}

package BranchData;

sub new
{
    my $class = shift;
    my $self = [{},    #  hash of lineNo -> BranchEntry
                       #      hash of blockID ->
                       #         array of 'taken' entries for each sequential
                       #           branch ID
                0,     # branches found
                0,     # branches executed
                0,     # "map is modified" flag - to indicate need for update
    ];
    bless $self, $class;
    return $self;
}

sub append
{
    my ($self, $line, $block, $br, $filename) = @_;
    # HGC:  might be good idea to pass filename so we could give better
    #   error message if the data is inconsistent.
    # OTOH:  unclear what a normal user could do about it anyway.
    #   Maybe exclude that file?
    my $data = $self->[0];
    $filename = '<stdin>' if (defined($filename) && $filename eq '-');
    if (!defined($br)) {
        lcovutil::ignorable_error($ERROR_BRANCH,
                            (defined $filename ? "\"$filename\":$line: " : "")
                                . "expected 'BranchEntry' or 'integer, BranchBlock'"
        ) unless ('BranchEntry' eq ref($block));

        die("line $line already contains element")
            if exists($data->{$line});
        $data->{$line} = $block;
        return 0;
    }

    # this cannot happen unless inconsistent branch data was generated by gcov
    die((defined $filename ? "\"$filename\":$line: " : "") .
        "BranchData::append expected BranchBlock got '" .
        ref($br) .
        "'.\nThis may be due to mismatched 'gcc' and 'gcov' versions.\n")
        unless ('BranchBlock' eq ref($br));

    my $branch = $br->id();
    my $branchElem;
    my $interesting = 0;
    if (exists($data->{$line})) {
        $branchElem = $data->{$line};
        $line == $branchElem->line() or die("wrong line mapping");
    } else {
        $branchElem    = BranchEntry->new($line);
        $data->{$line} = $branchElem;
        $interesting   = 1;                         # something new
    }

    if (!$branchElem->hasBlock($block)) {
        $branch == 0
            or
            lcovutil::ignorable_error($ERROR_BRANCH,
                                      "unexpected non-zero initial branch");
        $branch = 0;
        my $l = $branchElem->addBlock($block);
        push(@$l,
             BranchBlock->new($branch, $br->data(),
                              $br->expr(), $br->is_exception()));
        $interesting = 1;    # something new..
    } else {
        $block = $branchElem->getBlock($block);

        if ($branch > scalar(@$block)) {
            lcovutil::ignorable_error($ERROR_BRANCH,
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
            $self->[3] = 1;
            $interesting = 1;
        } else {
            my $me = $block->[$branch];
            if (0 == $me->count() && 0 != $br->count()) {
                $self->[3] = 1;
                $interesting = 1;
            }
            if ($me->merge($br, $filename, $line)) {
                $interesting = 1;
            }
        }
    }
    return $interesting;
}

sub remove
{
    my ($self, $line, $check_if_present) = @_;
    my $data = $self->[0];

    return 0 if ($check_if_present && !exists($data->{$line}));

    $self->[3] = 1;    # modified counts
    delete($data->{$line});
    return 1;
}

sub removeExceptionBranches
{
    my ($self, $line) = @_;

    my $brdata = $self->value($line);
    return unless defined($brdata);
    foreach my $block_id ($brdata->blocks()) {
        my $blockData = $brdata->getBlock($block_id);
        @$blockData = grep { !$_->is_exception() } (@$blockData);
        if (0 == scalar(@$blockData)) {
            lcovutil::info(2, "$line: remove exception block $block_id\n");
            $blockData->removeBlock($block_id);
        }
    }
    # If there is only one branch left - then this is not a conditional
    if (2 > scalar($brdata->blocks())) {
        lcovutil::info(2, "$line: lone block\n")
            if 1 == scalar($brdata->blocks());
        $self->remove($line);
    } else {
        # just assume we changed something...
        $self->[3] = 1;
    }
}

sub _summary
{
    my $self = shift;

    if (!$self->[3]) {
        # 'modified flag not set
        return $self;
    }
    my $data  = $self->[0];
    my $found = 0;
    my $hit   = 0;

    while (my ($line, $branch) = each(%$data)) {
        $line == $branch->line() or die("lost track of line");
        my ($f, $h) = $branch->totals();
        $found += $f;
        $hit   += $h;
    }
    $self->[1] = $found;
    $self->[2] = $hit;
    $self->[3] = 0;        # not modified
    return $self;
}

sub found
{
    my $self = shift;

    return $self->_summary()->[1];
}

sub hit
{
    my $self = shift;

    return $self->_summary()->[2];
}

sub merge
{
    my ($self, $info, $filename) = @_;
    my $interesting = 0;

    my $idata = $info->[0];
    foreach my $line ($info->keylist()) {
        my $branch = $idata->{$line};
        foreach my $blockId ($branch->blocks()) {
            my $bdata = $branch->getBlock($blockId);
            foreach my $br (@$bdata) {
                if ($self->append($line, $blockId, $br, $filename)) {
                    $interesting = 1;
                }
            }
        }
    }
    return $interesting;
}

# return BranchEntry struct (or undef)
sub value
{
    my ($self, $lineNo) = @_;

    my $map = $self->[0];
    return exists($map->{$lineNo}) ? $map->{$lineNo} : undef;
}

# return list of lines which contain branch data
sub keylist
{
    my $self = shift;
    return keys(%{$self->[0]});
}

sub get_found_and_hit
{
    my $self = shift;
    $self->_summary();

    return ($self->[1], $self->[2]);
}

package TraceInfo;
#  coveage data for a particular source file

sub new
{
    my ($class, $filename) = @_;
    my $self = {};
    bless $self, $class;

    $self->{_version} = undef;    # version ID from revision control (if any)

    # keep track of location in .info file that this file data was found
    #  - useful in error messages
    $self->{_location} = [];    # will fill with file/line

    $self->{_filename} = $filename;
    # _checkdata   : line number  -> source line checksum
    $self->{_checkdata} = MapData->new();
    # _sumcount    : line number  -> execution count - merged over all testcases
    $self->{_sumcount} = CountData->new($CountData::SORTED);
    # _funcdata    : function name or function location  -> FunctionEntry for all tests
    $self->{_funcdata} = FunctionMap->new();
    # _sumbrcount  : line number  -> branch coverage - for all tests
    $self->{_sumbrcount} = BranchData->new();

    $self->{_found}   = 0;
    $self->{_hit}     = 0;
    $self->{_f_found} = 0;
    $self->{_f_hit}   = 0;
    $self->{_b_found} = 0;
    $self->{_b_hit}   = 0;

    # _testdata    : test name  -> CountData ( line number -> execution count )
    $self->{_testdata} = MapData->new();
    # _testfncdata : test name  -> FunctionMap ( function name -> FunctionEntry )
    $self->{_testfncdata} = MapData->new();
    # _testbrdata  : test name  -> BranchData ( line number -> branch coverage )
    $self->{_testbrdata} = MapData->new();

    return $self;
}

sub filename
{
    my $self = shift;
    return $self->{_filename};
}

sub set_filename
{
    my ($self, $name) = @_;
    $self->{_filename} = $name;
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
    my $l = $self->{_location};
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
    (!defined($version) || !defined($self->{_version})) or
        die("expected to set version ID at most once: " .
            (defined($version) ? $version : "undef") . " " .
            (defined($self->{_version}) ? $self->{_version} : "undef"));
    $self->{_version} = $version
        if defined($version);
    return $self->{_version};
}

# line coverage data
sub test
{
    my $self = shift;
    my $name = defined($_[0]) ? shift : undef;

    if (!defined($name)) {
        return $self->{_testdata};
    }

    if (!$self->{_testdata}->mapped($name)) {
        $self->{_testdata}->append_if_unset($name, CountData->new(1));
    }

    return $self->{_testdata}->value($name);
}

sub sum
{
    # return MapData of line -> hit count
    #   data merged over all testcases
    my $self = shift;
    return $self->{_sumcount};
}

sub func
{
    # return FunctionMap of function name or location -> FunctionEntry
    #   data is merged over all testcases
    my $self = shift;
    return $self->{_funcdata};
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

sub f_found
{
    my $self = shift;
    return $self->func()
        ->numFunc(
              defined($lcovutil::cov_filter[$lcovutil::FILTER_FUNCTION_ALIAS]));
}

sub f_hit
{
    my $self = shift;
    return $self->func()
        ->numHit(
              defined($lcovutil::cov_filter[$lcovutil::FILTER_FUNCTION_ALIAS]));
}

sub b_found
{
    my $self = shift;
    return $self->sumbr()->found();
}

sub b_hit
{
    my $self = shift;
    return $self->sumbr()->hit();
}

sub check
{
    my $self = shift;
    return $self->{_checkdata};
}

# function coverage
sub testfnc
{
    my ($self, $name) = @_;

    if (!defined($name)) {
        return $self->{_testfncdata};
    }

    if (!$self->{_testfncdata}->mapped($name)) {
        $self->{_testfncdata}->append_if_unset($name, FunctionMap->new());
    }

    return $self->{_testfncdata}->value($name);
}

# branch coverage
sub testbr
{
    my ($self, $name) = @_;

    if (!defined($name)) {
        return $self->{_testbrdata};
    }

    if (!$self->{_testbrdata}->mapped($name)) {
        $self->{_testbrdata}->append_if_unset($name, BranchData->new());
    }

    return $self->{_testbrdata}->value($name);
}

sub sumbr
{
    # return BranchData map of line number -> BranchEntry
    #   data is merged over all testcases
    my $self = shift;
    return $self->{_sumbrcount};
}

#
# set_info_entry(hash_ref, testdata_ref, sumcount_ref, funcdata_ref,
#                checkdata_ref, testfncdata_ref,
#                testbrdata_ref, sumbrcount_ref[,lines_found,
#                lines_hit, f_found, f_hit, $b_found, $b_hit])
#
# Update the hash referenced by HASH_REF with the provided data references.
#

sub set_info($$$$$$$$;$$$$$$)
{
    my $self = shift;

    $self->{_testdata}    = shift;
    $self->{_sumcount}    = shift;
    $self->{_funcdata}    = shift;
    $self->{_checkdata}   = shift;
    $self->{_testfncdata} = shift;
    $self->{_testbrdata}  = shift;
    $self->{_sumbrcount}  = shift;

    if (defined($_[0])) { $self->{_found}   = shift; }
    if (defined($_[0])) { $self->{_hit}     = shift; }
    if (defined($_[0])) { $self->{_f_found} = shift; }
    if (defined($_[0])) { $self->{_f_hit}   = shift; }
    if (defined($_[0])) { $self->{_b_found} = shift; }
    if (defined($_[0])) { $self->{_b_hit}   = shift; }
}

#
# get_info_entry(hash_ref)
#
# Retrieve data from an entry of the structure generated by TraceFile::_read_info().
# Return a list of references to hashes:
# (test data hash ref, sum count hash ref, funcdata hash ref, checkdata hash
#  ref, testfncdata hash ref hash ref, lines found, lines hit,
#  functions found, functions hit)
#

sub get_info($)
{
    my $self          = shift;
    my $testdata_ref  = $self->{_testdata};
    my $sumcount_ref  = $self->{_sumcount};
    my $funcdata_ref  = $self->{_funcdata};
    my $checkdata_ref = $self->{_checkdata};
    my $testfncdata   = $self->{_testfncdata};
    my $testbrdata    = $self->{_testbrdata};
    my $sumbrcount    = $self->{_sumbrcount};
    my $lines_found   = $self->found();
    my $lines_hit     = $self->hit();
    my $fn_found      = $self->f_found();
    my $fn_hit        = $self->f_hit();
    my $br_found      = $self->b_found();
    my $br_hit        = $self->b_hit();

    return ($testdata_ref, $sumcount_ref, $funcdata_ref, $checkdata_ref,
            $testfncdata, $testbrdata, $sumbrcount, $lines_found,
            $lines_hit, $fn_found, $fn_hit, $br_found,
            $br_hit);
}

#
# rename_functions(info, conv)
#
# Rename all function names in TraceInfo according to CONV: OLD_NAME -> NEW_NAME.
# In case two functions demangle to the same name, assume that they are
# different object code implementations for the same source function.
#

sub rename_functions($$)
{
    my ($self, $conv, $filename) = @_;

    my $newData = $self->func()->cloneWithRename($conv);
    $self->{_funcdata} = $newData;

    # testfncdata: test name -> testfnccount
    # testfnccount: function name -> execution count
    my $testfncdata = $self->testfnc();
    foreach my $tn ($testfncdata->keylist()) {
        my $testfnccount    = $testfncdata->value($tn);
        my $newtestfnccount = $testfnccount->cloneWithRename($conv);
        $testfncdata->replace($tn, $newtestfnccount);
    }
}

sub _merge_checksums
{
    my $self     = shift;
    my $info     = shift;
    my $filename = shift;

    foreach my $line ($self->check()->keylist()) {
        if ($info->check()->mapped($line) &&
            $self->check()->value($line) ne $info->check()->value($line)) {
            die("ERROR: checksum mismatch at $filename:$line\n");
        }
    }
    foreach my $line ($info->check()->keylist()) {
        $self->check()->replace($line, $info->check()->value($line));
    }
}

sub merge
{
    my ($self, $info, $filename) = @_;

    my $me  = defined($self->version()) ? $self->version() : "<no version>";
    my $you = defined($info->version()) ? $info->version() : "<no version>";

    lcovutil::checkVersionMatch($filename, $me, $you);
    my $interesting = 0;
    foreach my $name ($info->test()->keylist()) {
        if ($self->test($name)->merge($info->test($name))) {
            $interesting = 1;
        }
    }
    if ($self->sum()->merge($info->sum())) {
        $interesting = 1;
    }

    if ($self->func()->merge($info->func())) {
        $interesting = 1;
    }
    $self->_merge_checksums($info, $filename);

    foreach my $name ($info->testfnc()->keylist()) {
        if ($self->testfnc($name)->merge($info->testfnc($name))) {
            $interesting = 1;
        }
    }

    foreach my $name ($info->testbr()->keylist()) {
        if ($self->testbr($name)->merge($info->testbr($name), $filename)) {
            $interesting = 1;
        }
    }
    if ($self->sumbr()->merge($info->sumbr(), $filename)) {
        $interesting = 1;
    }
    return $interesting;
}

# this package merely reads sourcefiles as they are found on the current
#  filesystem - ie., the baseline version might have been modified/might
#  have diffs - but the current version does not.
package ReadCurrentSource;

our @source_directories;

sub new
{
    my ($class, $filename) = @_;

    my $self = [];
    bless $self, $class;

    $self->open($filename) if defined($filename);
    return $self;
}

sub close
{
    my $self = shift;
    while (scalar(@$self)) {
        pop(@$self);
    }
}

sub resolve_path
{
    my $filename = shift;
    my $path     = $filename;
    my $idx      = 0;
    while (!-e $path &&
           !File::Spec->file_name_is_absolute($path) &&
           $idx < scalar(@source_directories)) {
        $path = File::Spec->catfile($source_directories[$idx], $filename);
        $idx += 1;
    }
    return -e $path ? $path : $filename;
}

sub open
{
    my ($self, $filename, $version) = @_;

    $version = "" unless defined($version);
    my $path = resolve_path($filename);
    if (open(SRC, "<", $path)) {
        lcovutil::info(1, "read $version$filename\n");
        my @sourceLines = <SRC>;
        CORE::close(SRC);
        $self->[0] = $filename;
        $self->parseLines($filename, \@sourceLines);
    } else {
        lcovutil::ignorable_error($lcovutil::ERROR_SOURCE,
                                  "unable to open $filename: $!\n");
        $self->close();
        return undef;
    }
    return $self;
}

sub parseLines
{
    my ($self, $filename, $sourceLines) = @_;

    my @excluded;
    my $exclude_region           = 0;
    my $exclude_br_region        = 0;
    my $exclude_exception_region = 0;
    my $line                     = 0;
    my $excl_start               = qr($lcovutil::EXCL_START);
    my $excl_stop                = qr($lcovutil::EXCL_STOP);
    my $excl_line                = qr($lcovutil::EXCL_LINE);
    my $excl_br_start            = qr($lcovutil::EXCL_BR_START);
    my $excl_br_stop             = qr($lcovutil::EXCL_BR_STOP);
    my $excl_br_line             = qr($lcovutil::EXCL_BR_LINE);
    my $excl_ex_start            = qr($lcovutil::EXCL_EXCEPTION_BR_START);
    my $excl_ex_stop             = qr($lcovutil::EXCL_EXCEPTION_BR_STOP);
    my $excl_ex_line             = qr($lcovutil::EXCL_EXCEPTION_LINE);
    # @todo:  if we had annotated data here, then we could whine at the
    #   author fo the unmatched start, extra end, etc.
    LINES: foreach (@$sourceLines) {
        $line += 1;
        my $exclude_branch_line           = 0;
        my $exclude_exception_branch_line = 0;
        chomp($_);
        foreach my $d ([$excl_start, $excl_stop, \$exclude_region],
                       [$excl_br_start, $excl_br_stop, \$exclude_br_region],
                       [$excl_ex_start, $excl_ex_stop,
                        \$exclude_exception_region
                       ]
        ) {
            my ($start, $stop, $ref) = @$d;
            if ($_ =~ $start) {
                lcovutil::ignorable_error($ERROR_MISMATCH,
                    "$filename: overlapping exclude directives. Found $start at line $line - but no matching $stop for $start at line "
                        . $$ref)
                    if $$ref;
                $$ref = $line;
                last;
            } elsif ($_ =~ $stop) {
                lcovutil::ignorable_error($ERROR_MISMATCH,
                    "$filename: found $stop directive at line $line without matching $start directive"
                ) unless $$ref;
                $$ref = 0;
                last;
            }
        }
        if ($_ =~ $excl_line) {
            push(@excluded, 3);    #everything excluded
            next;
        } elsif ($_ =~ $excl_br_line) {
            $exclude_branch_line = 2;
        } elsif ($_ =~ $excl_ex_line) {
            $exclude_branch_line = 4;
        } elsif (0 != scalar(@lcovutil::omit_line_patterns)) {
            foreach my $p (@lcovutil::omit_line_patterns) {
                my $pat = $p->[0];
                if ($_ =~ $pat) {
                    push(@excluded, 3);    #everything excluded
                     #lcovutil::info("'" . $p->[-2] . "' matched \"$_\", line \"$filename\":"$line\n");
                    ++$p->[-1];
                    next LINES;
                }
            }
        }
        push(@excluded,
             ($exclude_region ? 1 : 0) | ($exclude_br_region ? 2 : 0) |
                 ($exclude_exception_region ? 4 : 0) | $exclude_branch_line |
                 $exclude_exception_branch_line);
    }
    lcovutil::ignorable_error($ERROR_MISMATCH,
        "$filename: unmatched $lcovutil::EXCL_START at line $exclude_region - saw EOF while looking for matching $lcovutil::EXCL_STOP"
    ) if $exclude_region;
    lcovutil::ignorable_error($ERROR_MISMATCH,
        "$filename: unmatched $lcovutil::EXCL_BR_START at line $exclude_br_region - saw EOF while looking for matching $lcovutil::EXCL_BR_STOP"
    ) if $exclude_br_region;
    lcovutil::ignorable_error($ERROR_MISMATCH,
        "$filename: unmatched $lcovutil::EXCL_EXCEPTION_BR_START at line $exclude_exception_region - saw EOF while looking for matching $lcovutil::EXCL_EXCEPTION_BR_STOP"
    ) if $exclude_exception_region;

    $self->[0] = $filename;
    $self->[1] = $sourceLines;
    $self->[2] = \@excluded;
}

sub setData
{
    my ($self, $filename, $data) = @_;
    die("expected array")
        if (defined($data) && ref($data) ne 'ARRAY');
    $self->[0] = $filename;
    if (defined($data) &&
        0 != scalar(@$data)) {
        $self->parseLines($filename, $data);
    } else {
        $self->open($filename, join(' ', @lcovutil::extractVersionScript));
    }
}

sub notEmpty
{
    my $self = shift;
    return 0 != scalar(@$self);
}

sub filename
{
    return $_[0]->[0];
}

sub getLine
{
    my ($self, $line) = @_;

    return $self->[1]->[$line - 1];
}

sub isOutOfRange
{
    my ($self, $lineNo, $context) = @_;
    if (defined($self->[2]) &&
        scalar(@{$self->[2]}) < $lineNo) {

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
                               scalar(@{$self->[2]}) . " lines in file)\n");
            ++$filt->[0];    # applied in 1 location
            ++$filt->[1];    # one coverpoint suppressed
            return 1;
        }
        my $key = $self->filename() . $lineNo;
        if (lcovutil::warn_once($key)) {
            my $c = ($context eq 'line') ? 'line' : "$context at line";
            my $msg =
                "unknown $c '$lineNo' in " .
                $self->filename() . ": there are only " .
                scalar(@{$self->[2]}) . " lines in file." .
                "\n  Use '$lcovutil::tool_name --filter range' to remove out-of-range lines.";
            if ($lcovutil::tool_name eq 'geninfo') {
                # some versions of gcov seem to make up lines that do not exist -
                # this appears to be related to macros on last line in file
                lcovutil::ignorable_error($lcovutil::ERROR_GCOV, $msg);
            } else {
                lcovutil::ignorable_error($lcovutil::ERROR_SOURCE,
                    $msg .
                        "\n  This can be caused by code changes/version mismatch; see the \"--version-script script_file\" discussion in the genhtml man page."
                );
            }
        }
        # Note:  if user ignored the error, then we return 'not out of range'.
        #   The line is out of range/something is wrong - but the user did not
        #   ask us to filter it out.
    }
    return 0;
}

sub isExcluded
{
    my ($self, $lineNo, $branch) = @_;
    if (!defined($self->[2]) ||
        scalar(@{$self->[2]}) < $lineNo) {
        # this can happen due to version mismatches:  data extracted with verion N
        # of the file, then generating HTML with version M
        # "--version-script callback" option can be used to detect this
        my $key = $self->filename() . $lineNo;
        lcovutil::ignorable_error(
            $lcovutil::ERROR_SOURCE,
            "unknown line '$lineNo' in " . $self->filename()
                .
                (defined($self->[2]) ?
                     (" there are only " .
                      scalar(@{$self->[2]}) . " lines in file") :
                     "") .
                ".\n  This can be caused by code changes/version mismatch; see the \"--version-script script_file\" discussion in the genhtml man page."
        ) if lcovutil::warn_once($key);
        return 0;    # even though out of range - this is not excluded by filter
    }
    return 1
        if ($branch &&
            0 != ($self->[2]->[$lineNo - 1] & $branch));
    return 0 != ($self->[2]->[$lineNo - 1] & 1);
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

sub containsConditional
{
    my ($self, $line) = @_;

    # special case - maybe C++ exception handler on close brace at end of function?
    return 0
        if $self->isCharacter($line, '}');
    my $src = $self->getLine($line);
    return 1
        unless defined($src);
    my $foundCond = 1;

    my $code = "";
    for (my $next = $line + 1;
         defined($src) && ($next - $line) < $lcovutil::source_filter_lookahead;
         ++$next) {

        $src = lcovutil::filterStringsAndComments($src);

        $src = lcovutil::simplifyCode($src);

        my $bitwiseOperators =
            $lcovutil::source_filter_bitwise_are_conditional ? '&|~' : '';

        last
            if ($src =~
            /([?!><$bitwiseOperators]|&&|\|\||==|!=|\b(if|switch|case|while|for)\b)/
            );

        $code = $code . $src;

        if (lcovutil::balancedParens($code) ||
            # assume we got to the end of the statement if we see semicolon
            # or brace.
            $src =~ /[{;]\s*$/
        ) {
            $foundCond = 0;
            last;
        }
        $src = $self->getLine($next);
    }
    return $foundCond;
}

sub containsTrivialFunction
{
    my ($self, $start, $end) = @_;
    return 0
        if (1 + $end - $start >= $lcovutil::trivial_function_threshold);
    my $text = '';
    for (my $line = $start; $line <= $end; ++$line) {
        my $src = $self->getLine($line);
        chomp($src);
        # remove end-of-line comments
        $src =~ s#//.*$##;
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

# Block value used for unnamed blocks
our $UNNAMED_BLOCK = vec(pack('b*', 1 x 32), 0, 32);
our $ignore_testcase_name;    # use default name, if set

sub load
{
    my ($class, $tracefile, $readSource, $verify_checksum,
        $ignore_function_exclusions)
        = @_;
    my $self = $class->new();

    $self->_read_info($tracefile, $readSource, $verify_checksum);

    $self->applyFilters();
    return $self;
}

sub new
{
    my $class = shift;
    my $self  = {};
    bless $self, $class;

    return $self;
}

sub serialize
{
    my ($self, $filename) = @_;

    Storable::store($self, $filename);
}

sub deserialize
{
    my ($class, $file) = @_;
    my $self = Storable::retrieve($file) or die("unable to deserialize $file");
    ref($self) eq $class or die("did not deserialize a $class");
    return $self;
}

sub empty
{
    my $self = shift;

    return !keys(%$self);
}

sub files
{
    my $self = shift;

    # for case-insensitive support:  need to store the file keys in
    #  lower case (so they can be found) - but return the actual
    #  names of the files (mixed case)

    return keys %$self;
}

sub file_exists
{
    my ($self, $name) = @_;
    $name = lc($name) if $lcovutil::case_insensitive;
    return exists($self->{$name});
}

sub skipCurrentFile
{
    my $filename = shift;

    # check whether this file should be excluded or not...
    if (@lcovutil::exclude_file_patterns) {
        foreach my $p (@lcovutil::exclude_file_patterns) {
            my $pattern = $p->[0];
            if ($filename =~ $pattern) {
                ++$p->[-1];
                return 1;    # all done - explicitly excluded
            }
        }
    }
    if (@lcovutil::include_file_patterns) {
        foreach my $p (@lcovutil::include_file_patterns) {
            my $pattern = $p->[0];
            if ($filename =~ $pattern) {
                ++$p->[-1];
                return 0;    # exlicitly included
            }
        }
        return 1;            # not explicitly included - so exclude
    }
    return 0;
}

sub data
{
    my $self                  = shift;
    my $file                  = shift;
    my $checkMatchingBasename = shift;

    my $key = $lcovutil::case_insensitive ? lc($file) : $file;

    if (!defined($self->{$key})) {
        if (defined $checkMatchingBasename) {
            # check if there is a file in the map that has the same basename
            #  as the lone we are looking for.
            # this can happen if the 'udiff' file refers to paths in the repo
            #  whereas the .info files refer to paths in the build area.
            my $base = File::Basename::basename($file);
            $base = lc($base) if $lcovutil::case_insensitive;
            my $count = 0;
            my $found;
            foreach my $f (keys %$self) {
                my $b = File::Basename::basename($f);
                $b = lc($b) if $lcovutil::case_insensitive;
                if ($b eq $base) {
                    $count++;
                    $found = $self->{$f};
                }
            }
            return $found
                if $count == 1;
        }
        $self->{$key} = TraceInfo->new($file);
    }

    return $self->{$key};
}

sub remove
{
    my ($self, $filename) = @_;
    $filename = lc($filename) if $lcovutil::case_insensitive;
    $self->file_exists($filename) or
        die("remove nonexistent file $filename");
    delete($self->{$filename});
}

sub insert
{
    my ($self, $filename, $data) = @_;
    $filename = lc($filename) if $lcovutil::case_insensitive;
    die("insert existing file $filename")
        if $self->file_exists($filename);
    die("expected TraceInfo got '" . ref($data) . "'")
        unless (ref($data) eq 'TraceInfo');
    $self->{$filename} = $data;
}

sub append_tracefile
{
    my ($self, $trace) = @_;
    die("expected TraceFile")
        unless (defined($trace) && 'TraceFile' eq ref($trace));

    my $interesting = 0;
    foreach my $filename ($trace->files()) {
        if (defined($self->{$filename})) {
            if ($self->data($filename)
                ->merge($trace->data($filename), $filename)) {
                $interesting = 1;
            }
        } else {
            $self->{$filename} = $trace->data($filename);
            $interesting = 1;
        }
    }
    return $interesting;
}

sub _eraseFunction
{
    my ($fcn, $name, $end_line, $source_file,
        $functionMap, $lineData, $branchData, $checksum)
        = @_;
    if (defined($end_line)) {
        for (my $line = $fcn->line(); $line <= $end_line; ++$line) {

            if (defined($checksum)) {
                $checksum->remove($line, 1);    # remove if present
            }
            if ($lineData->remove($line, 1)) {
                lcovutil::info(2,
                            "exclude DA in FN '$name' on $source_file:$line\n");
            }
            if ($branchData->remove($line, 1)) {
                lcovutil::info(2,
                          "exclude BRDA in FN '$name' on $source_file:$line\n");
            }
        }    # foreach line
    }
    # remove this function and all its aliases...
    $functionMap->remove($fcn);
}

my $didUnsupportedWarning;

sub _eraseFunctions
{
    my ($source_file, $srcReader, $functionMap, $lineData,
        $branchData, $checksum, $isMasterList) = @_;

    my $removeTrivial = $lcovutil::cov_filter[$FILTER_TRIVIAL_FUNCTION];
    FUNC: foreach my $key ($functionMap->keylist()) {
        my $fcn      = $functionMap->findKey($key);
        my $end_line = $fcn->end_line();
        my $name     = $fcn->name();
        if (!defined($end_line)) {
            if (!defined($didUnsupportedWarning)) {
                $didUnsupportedWarning = 1;
                lcovutil::ignorable_error($ERROR_UNSUPPORTED,
                    "Function begin/end line exclusions not supported with this version of GCC/gcov; require gcc/9 or newer"
                );
            }
            # we can skip out of processing if we don't know the end line
            # - there is no way for us to remove line and branch points in
            #   the function region
            # Or we can keep going and at least remove the matched function
            #   coverpoint.
            #last; # at least for now:  keep going
        } elsif (
               defined($removeTrivial) &&
               is_c_file($source_file) &&
               (defined($srcReader) &&
                $srcReader->containsTrivialFunction($fcn->line(), $end_line))
        ) {
            # remove single-line functions which has no body
            # Only count what we removed from the top leve/master list -
            #   - otherwise, we double count for every testcase.
            $removeTrivial->[0]++ if $isMasterList;
            foreach my $alias (keys %{$fcn->aliases()}) {
                lcovutil::info(1,
                      "\"$source_file\":$end_line: filter trivial FN $alias\n");
                _eraseFunction($fcn, $alias, $end_line,
                               $source_file, $functionMap, $lineData,
                               $branchData, $checksum);
                $removeTrivial->[1]++ if $isMasterList;
            }
            next FUNC;
        }
        foreach my $p (@lcovutil::exclude_function_patterns) {
            my $pat = $p->[0];
            while (my ($alias, $hit) = each(%{$fcn->aliases()})) {
                if ($alias =~ $pat) {
                    ++$p->[-1] if $isMasterList;
                    if (defined($end_line)) {
                        # if user ignored the unsupported message, then the
                        # best we can do is to remove the matched function -
                        # and leave the lines and branches in place
                        lcovutil::info(1,
                                 "exclude FN $name line range $source_file:[" .
                                     $fcn->line() .
                                     ":$end_line] due to '" . $p->[-2] . "'\n");
                    }
                    _eraseFunction($fcn, $alias, $end_line,
                                   $source_file, $functionMap, $lineData,
                                   $branchData, $checksum);
                    next FUNC;
                }    # if match
            }    # foreach alias
        }    # foreach pattern
    }    # foreach function
}

sub applyFilters
{
    my $self = shift;

    my $srcReader = ReadCurrentSource->new();
    my $region    = $lcovutil::cov_filter[$lcovutil::FILTER_EXCLUDE_REGION];
    my $range     = $lcovutil::cov_filter[$lcovutil::FILTER_LINE_RANGE];
    my $branch_histogram         = $cov_filter[$FILTER_BRANCH_NO_COND];
    my $brace_histogram          = $cov_filter[$FILTER_LINE_CLOSE_BRACE];
    my $blank_histogram          = $cov_filter[$FILTER_BLANK_LINE];
    my $function_alias_histogram = $cov_filter[$FILTER_FUNCTION_ALIAS];
    my $trivial_histogram        = $cov_filter[$FILTER_TRIVIAL_FUNCTION];

    # have to look through each file in each testcase; they may be different
    # due to differences in #ifdefs when the corresponding tests were compiled.

    foreach my $name ($self->files()) {
        my $traceInfo = $self->data($name);
        die("expected TraceInfo, got '" . ref($traceInfo) . "'")
            unless ('TraceInfo' eq ref($traceInfo));
        my $source_file = $traceInfo->filename();
        if (lcovutil::is_external($source_file)) {
            delete($self->{$source_file});
            next;
        }
        # derive function end line for C/C++ code if requested
        # (not trying to handle python nested functions, etc)
        if (defined($lcovutil::derive_function_end_line) &&
            $lcovutil::derive_function_end_line != 0 &&
            defined($lcovutil::func_coverage) &&
            is_c_file($source_file)) {
            my @lines = sort { $a <=> $b } $traceInfo->sum()->keylist();
            # sort functions by start line number
            my @functions = sort { $a->line() <=> $b->line() }
                $traceInfo->func()->valuelist();
            my $currentLine = shift(@lines);
            my $funcData    = $traceInfo->testfnc();
            while (@functions) {
                my $func  = shift(@functions);
                my $first = $func->line();
                while ($first < $currentLine) {
                    $currentLine = shift @lines;
                }
                if (!defined($func->end_line())) {
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
                            $currentLine = $lines[-1];
                        }
                    } elsif ($currentLine < $first) {
                        # we ran out of lines in the data...check for inconsistency
                        lcovutil::ignorable_error(
                            $lcovutil::ERROR_INCONSISTENT_DATA,
                            "\"$name\":$first:  function " . $func->name() .
                                " found on line but no corresponding 'line' coverage data point.  Cannot derive function end line."
                        );

                        # last; # quit looking here - all the other functions after this one will have same issue
                        next;    # warn about them all
                    }
                    lcovutil::info(1,
                                   "\"$name\":$currentLine: assign end_line " .
                                       $func->name() . "\n");
                    $func->set_end_line($currentLine);
                }
                # now look for this function in each testcase -
                #  set the same endline (if not already set)
                my $key = $func->file() . ':' . $first;
                foreach my $tn ($funcData->keylist()) {
                    my $d = $funcData->value($tn);
                    my $f = $d->findKey($key);
                    if (defined($f)) {
                        if (!defined($f->end_line())) {
                            $f->set_end_line($func->end_line());
                        } else {
                            if ($f->end_line() != $func->end_line()) {
                                lcovutil::ignorable_error(
                                       $lcovutil::ERROR_INCONSISTENT,
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
        }

        # munge the source file name, if requested
        $source_file = lcovutil::subst_file_name($source_file);
        $srcReader->close();

        if (is_c_file($source_file) &&
            lcovutil::is_filter_enabled()) {
            lcovutil::info(1, "reading $source_file for lcov filtering\n");
            $srcReader->open($source_file);
        }

        if (defined($lcovutil::func_coverage) &&
            !defined($didUnsupportedWarning)  &&
            (0 != scalar(@lcovutil::exclude_function_patterns) ||
                defined($lcovutil::cov_filter[$FILTER_TRIVIAL_FUNCTION]))
        ) {

            # filter excluded function line ranges

            my $funcData   = $traceInfo->testfnc();
            my $lineData   = $traceInfo->test();
            my $branchData = $traceInfo->testbr();
            my $checkData  = $traceInfo->check();
            my $reader     = defined($trivial_histogram) &&
                $srcReader->notEmpty() ? $srcReader : undef;

            foreach my $tn ($lineData->keylist()) {
                _eraseFunctions($source_file, $reader,
                                $funcData->value($tn), $lineData->value($tn),
                                $branchData->value($tn), $checkData->value($tn),
                                0);
            }
            _eraseFunctions($source_file, $reader,
                            $traceInfo->func(), $traceInfo->sum(),
                            $traceInfo->sumbr(), $traceInfo->check(),
                            1);
        }

        next
            unless (is_c_file($source_file) &&
                    $srcReader->notEmpty() &&
                    lcovutil::is_filter_enabled());

        my ($testdata, $sumcount, $funcdata, $checkdata,
            $testfncdata, $testbrdata, $sumbrcount) = $traceInfo->get_info();

        foreach my $testname (sort($testdata->keylist())) {
            my $testcount    = $testdata->value($testname);
            my $testfnccount = $testfncdata->value($testname);
            my $testbrcount  = $testbrdata->value($testname);

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
                                           " '" . $srcReader->getLine($line) .
                                           "' " . $data->file() . ":$line\n");
                        ++$region->[0];    # one location where this applied
                    } elsif ($region && $srcReader->isExcluded($line)) {
                        $remove = 1;
                        $region->[2] += scalar(keys %{$data->aliases()});
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
                        next;
                    }    # if excluded
                }    # foreach function
            }    # if func_coverage
                 # $testbrcount is undef if there are no branches in the scope
            if ($lcovutil::br_coverage &&
                defined($testbrcount) &&
                ($branch_histogram || $region || $range)) {
                foreach my $line ($testbrcount->keylist()) {
                    my $remove;
                    # omit if line excluded or branches excluded on this line
                    if ($srcReader->isOutOfRange($line, 'branch')) {
                        $remove = 1;
                    } elsif ($region &&
                             $srcReader->isExcluded($line, 2)) {
                        # all branches here
                        $remove = 1;
                    } elsif ($branch_histogram &&
                             !$srcReader->containsConditional($line)) {
                        $remove = 1;
                        my $brdata = $testbrcount->value($line);
                        ++$branch_histogram->[0];    # one line where we skip
                        $branch_histogram->[1] += scalar($brdata->blocks());
                        lcovutil::info(2,
                                       "filter BRDA '" .
                                           $srcReader->getLine($line) .
                                           "' $source_file:$line\n");
                    }
                    if ($remove) {
                        # now remove this branch everywhere...
                        foreach my $tn ($testbrdata->keylist()) {
                            my $d = $testbrdata->value($tn);
                            $d->remove($line, 1);    # remove if present
                        }
                        # remove at top
                        $sumbrcount->remove($line);
                    } else {
                        # exclude exception branches here
                        if ($lcovutil::exclude_exception_branch ||
                            ($region && $srcReader->isExcluded($line, 4))) {
                            # skip exception branches in this region..
                            $testbrcount->removeExceptionBranches($line);

                            # now remove this branch everywhere...
                            foreach my $tn ($testbrdata->keylist()) {
                                $testbrdata->value($tn)
                                    ->removeExceptionBranches($line);
                            }
                        }
                    }
                }    # foreach line
            }    # if branch_coverage
                 # Line related data
            next
                unless $region   ||
                $range           ||
                $brace_histogram ||
                $branch_histogram;
            foreach my $line ($testcount->keylist()) {

                # don't suppresss if this line has associated branch data
                next if (defined($sumbrcount->value($line)));

                my $outOfRange = $srcReader->isOutOfRange($line, 'line');
                my $excluded   = $srcReader->isExcluded($line)
                    unless $outOfRange;
                my $l_hit = $testcount->value($line);
                my $isCloseBrace = (
                             $brace_histogram && $srcReader->suppressCloseBrace(
                                                       $line, $l_hit, $testcount
                             ))
                    unless $outOfRange ||
                    $excluded;
                my $isBlank =
                    ($blank_histogram &&
                     $l_hit == 0 &&
                     $srcReader->isBlank($line))
                    unless $outOfRange ||
                    $excluded;
                next
                    unless $outOfRange ||
                    $excluded          ||
                    $isCloseBrace      ||
                    $isBlank;

                lcovutil::info(2,
                               "filter DA "
                                   .
                                   (defined($srcReader->getLine($line)) ?
                                        ("'" . $srcReader->getLine($line) . "'")
                                    :
                                        "") .
                                   " $source_file:$line\n");

                if (defined($isCloseBrace) && $isCloseBrace) {
                    # one location where this applied
                    ++$brace_histogram->[0];
                    ++$brace_histogram->[1];    # one coverpoint suppressed
                } elsif (defined($isBlank) && $isBlank) {
                    # one location where this applied
                    ++$blank_histogram->[0];
                    ++$blank_histogram->[1];    # one coverpoint suppressed
                }

                # now remove everywhere
                foreach my $tn ($testdata->keylist()) {
                    my $d = $testdata->value($tn);
                    $d->remove($line, 1);       # remove if present
                }
                $sumcount->remove($line);
                if (exists($checkdata->{$line})) {
                    delete($checkdata->{$line});
                }
            }    # foreach line
        }    #foreach test
             # count the number of function aliases..
        if ($function_alias_histogram) {
            $function_alias_histogram->[0] += $funcdata->numFunc(1);
            $function_alias_histogram->[1] += $funcdata->numFunc(0);
        }
    }    # foreach file
}

sub is_rtl_file
{
    my $filename = shift;
    return $filename =~ /\.($rtl_file_extensions)$/ ? 1 : 0;
}

sub is_java_file
{
    my $filename = shift;
    return $filename =~ /\.($java_file_extensions)$/ ? 1 : 0;
}

sub is_c_file
{
    my $filename = shift;
    return $filename =~ /\.($c_file_extensions)$/ ? 1 : 0;
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
#        "f_found" -> $fn_found (number of instrumented functions found in file)
#        "f_hit"   -> $fn_hit (number of executed functions in file)
#        "b_found" -> $br_found (number of instrumented branches found in file)
#        "b_hit"   -> $br_hit (number of executed branches in file)
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

    my $testdata;     #       "             "
    my $testcount;    #       "             "
    my $sumcount;     #       "             "
    my $funcdata;     #       "             "
    my $checkdata;    #       "             "
    my $testfncdata;
    my $testfnccount;
    my $testbrdata;
    my $testbrcount;
    my $sumbrcount;
    my $testname;            # Current test name
    my $filename;            # Current filename
    my $changed_testname;    # If set, warn about changed testname

    lcovutil::info(1, "Reading data file $tracefile\n");

    # Check if file exists and is readable
    stat($tracefile);
    if (!(-r _)) {
        die("ERROR: cannot read file $tracefile!\n");
    }

    # Check if this is really a plain file
    if (!(-f _)) {
        die("ERROR: not a plain file: $tracefile!\n");
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
    my %branchRenumber;    # line -> block -> branch -> branchentry
    my ($currentBranchLine, $skipBranch);
    my $functionMap;
    my %excludedFunction;
    my $skipCurrentFile = 0;
    while (<$infoHdl>) {
        chomp($_);
        my $line = $_;

        if ($line =~ /^[SK]F:(.*)/) {
            # Filename information found
            $filename = lcovutil::subst_file_name($1);
            # should this one be skipped?
            $skipCurrentFile = skipCurrentFile($filename);
            if ($skipCurrentFile &&
                !exists($lcovutil::excluded_files{$filename})) {
                $lcovutil::excluded_files{$filename} = 1;
                lcovutil::info("Excluding $filename\n");
                next;
            }

            # Retrieve data for new entry
            %branchRenumber   = ();
            %excludedFunction = ();

            if ($verify_checksum) {
                # unconditionally 'close' the current file - in case we don't
                #   open a new one.  If that happened, then we would be looking
                #   at the source for some previous file.
                $readSourceCallback->close();
                undef $currentBranchLine;
                if (is_c_file($filename)) {
                    $readSourceCallback->open($filename);
                }
            }
            $fileData = $self->data($filename);
            # record line number where file entry found - can use it in error messsages
            $fileData->location($tracefile, $.);
            ($testdata, $sumcount, $funcdata, $checkdata,
             $testfncdata, $testbrdata, $sumbrcount) = $fileData->get_info();
            $functionMap = defined($testname) ? FunctionMap->new() : $funcdata;

            if (defined($testname)) {
                $testcount    = $fileData->test($testname);
                $testfnccount = $fileData->testfnc($testname);
                $testbrcount  = $fileData->testbr($testname);
            } else {
                $testcount    = CountData->new(1);
                $testfnccount = CountData->new(0);
                $testbrcount  = BranchData->new();
            }
            next;
        }
        next if $skipCurrentFile;

        # Switch statement
        # Please note:  if you add or change something here (lcov info file format) -
        #   then please make corresponding changes to the 'write_info' method, below
        #   and update the format description found in .../man/geninfo.1.
        foreach ($line) {
            /^VER:(.+)$/ && do {
                # revision control version string found
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

            /^DA:(\d+),(-?\d+)(,([^,\s]+))?/ && do {
                my ($line, $count, $checksum) = ($1, $2, $4);
                if ($readSourceCallback->notEmpty()) {
                    # does the source checksum match the recorded checksum?
                    if ($verify_checksum) {
                        if (defined($checksum)) {
                            my $content = $readSourceCallback->getLine($line);
                            my $chk     = Digest::MD5::md5_base64($content);
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

                if ($count < 0) {
                    lcovutil::ignorable_error($lcovutil::ERROR_NEGATIVE,
                        "\"$tracefile\":$.: Unexpected negative line hit count '$count' for \"$filename\":$line"
                    );
                    $count = 0;
                }

                # Execution count found, add to structure
                # Add summary counts
                $linesum->append($line, $count);

                # Add test-specific counts
                if (defined($testname)) {
                    $fileData->test($testname)->append($line, $count);
                }

                # Store line checksum if available
                if (defined($checksum)) {
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
                # the function may already be defined by another testcase
                #  (for the same file)
                $functionMap->define_function($fnName, $filename, $lineNo,
                                              $end_line ? $end_line : undef)
                    unless defined($functionMap->findName($fnName));

                last;
            };

            /^FNDA:(\d+),(.+)$/ && do {
                last if (!$lcovutil::func_coverage);
                my $fnName = $2;
                my $hit    = $1;
                # we expect to find a function with ths name...
                if ($hit < 0) {
                    my $line = $functionMap->findName($fnName)->line();
                    lcovutil::ignorable_error($lcovutil::ERROR_NEGATIVE,
                        "\"$tracefile\":$.: Unexpected negative hit count '$hit' for function $fnName at \"$filename\":$line."
                    );
                    $hit = 0;
                }
                $functionMap->add_count($fnName, $hit);

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

                last if $is_exception && $lcovutil::exclude_exception_branch;
                my $comma = rindex($d, ',');
                my $taken = substr($d, $comma + 1);
                my $expr  = substr($d, 0, $comma);
                # hold line, block, expr etc - to process when we get to end of file
                #  (for parallelism support...)

                if ($taken ne '-' && $taken < 0) {
                    lcovutil::ignorable_error($lcovutil::ERROR_NEGATIVE,
                        "\"$tracefile\":$.: Unexpected negative taken count '$taken' for branch $block at \"$filename\":$line: "
                    );
                    $taken = 0;
                }

                # Notes:
                #   - there may be other branches on the same line (..the next
                #     contiguous BRDA entry).
                #     There should always be at least 2.
                #   - not sure what the $block is used for.
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

                $block = -1 if ($block == $UNNAMED_BLOCK);

                if (!is_c_file($filename)) {
                    # At least at present, Verilog/SystemVerilog/VHDL,
                    # java, python, etc don't need branch number fixing
                    my $key = "$line,$block";
                    my $branch =
                        exists($branchRenumber{$key}) ?
                        $branchRenumber{$key} :
                        0;
                    $branchRenumber{$key} = $branch + 1;

                    my $br =
                        BranchBlock->new($branch, $taken, $expr, $is_exception);
                    $fileData->sumbr()->append($line, $block, $br, $filename);

                    # Add test-specific counts
                    if (defined($testname)) {
                        #$testbrcount->{$line} .=  "$block,$branch,$taken:";
                        $fileData->testbr($testname)
                            ->append($line, $block, $br, $filename);
                    }
                } else {
                    # only C code might need renumbering - but this
                    #   is an artifact of some very old geninfo code,
                    #   so any new data files will be OK
                    $branchRenumber{$line} = {}
                        unless exists($branchRenumber{$line});
                    $branchRenumber{$line}->{$block} = {}
                        unless exists($branchRenumber{$line}->{$block});
                    my $table = $branchRenumber{$line}->{$block};

                    my $entry =
                        BranchBlock->new($expr, $taken, $expr, $is_exception);
                    if (exists($table->{$expr})) {
                        # merge
                        $table->{$expr}->merge($entry);
                    } else {
                        $table->{$expr} = $entry;
                    }
                }
                last;
            };

            /^end_of_record/ && do {
                # Found end of section marker
                if ($filename) {
                    if (is_c_file($filename)) {
                        # RTL code was added directly - no issue with
                        #  duplicate data entries in geninfo result
                        foreach my $line (sort { $a <=> $b }
                                          keys(%branchRenumber)
                        ) {
                            my $l_data = $branchRenumber{$line};
                            foreach my $block (sort { $a <=> $b }
                                               keys(%$l_data)
                            ) {
                                my $bdata    = $l_data->{$block};
                                my $branchId = 0;
                                foreach my $b_id (sort { $a <=> $b }
                                                  keys(%$bdata)
                                ) {
                                    my $br = $bdata->{$b_id};
                                    my $b =
                                        BranchBlock->new($branchId, $br->data(),
                                                    undef, $br->is_exception());
                                    $fileData->sumbr()
                                        ->append($line, $block, $b, $filename);

                                    if (defined($testname)) {
                                        #$testbrcount->{$line} .=  "$block,$branch,$taken:";
                                        $fileData->testbr($testname)
                                            ->append($line, $block, $b,
                                                     $filename);
                                    }
                                    ++$branchId;
                                }
                            }
                        }
                    }    # end "if (! rtl)"
                    if ($lcovutil::func_coverage) {

                        if ($funcdata != $functionMap) {
                            $funcdata->merge($functionMap);
                        }
                        if (defined($testname)) {
                            $fileData->testfnc($testname)->merge($functionMap);
                        }
                    }
                    # Store current section data
                    if (defined($testname)) {
                        $testdata->{$testname}    = $testcount;
                        $testfncdata->{$testname} = $testfnccount;
                        $testbrdata->{$testname}  = $testbrcount;
                    }

                    $self->data($filename)->set_info(
                                    $testdata, $sumcount, $funcdata, $checkdata,
                                    $testfncdata, $testbrdata, $sumbrcount);
                    last;
                }
            };
            /^(FN|BR|L)[HF]/ && do {
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
            delete($self->{$filename});
            next;
        }
        my $filedata = $self->data($filename);
        # Filter out empty test cases
        foreach $testname ($filedata->test()->keylist()) {
            if (!$filedata->test()->mapped($testname) ||
                scalar($filedata->test($testname)->keylist()) == 0) {
                $filedata->test()->remove($testname);
                $filedata->testfnc()->remove($testname);
            }
        }

        next;

        $filedata->{_found} = scalar(keys(%{$filedata->{_sumcount}}));
        my $hitcount = 0;

        foreach (keys(%{$filedata->{_sumcount}})) {
            if ($filedata->{_sumcount}->{$_} > 0) { $hitcount++; }
        }

        $filedata->{_hit} = $hitcount;

        # Get found/hit values for function call data
        my $funcData = $filedata->func();
        $fileData->{_f_found} = $filedata->f_found();
        $hitcount             = $filedata->f_hit();
        $filedata->{_f_hit}   = $hitcount;

        # Combine branch data for the same branches
        (undef, $filedata->{_b_found}, $filedata->{_b_hit}) =
            compress_brcount($filedata->{_sumbrcount});
        foreach $testname (keys(%{$filedata->{_testbrdata}})) {
            compress_brcount($filedata->{_testbrdata}->{$testname});
        }
    }

    if (scalar(keys(%$self)) == 0) {
        lcovutil::ignorable_error($lcovutil::ERROR_EMPTY,
                              "no valid records found in tracefile $tracefile");
    }
    if (defined($changed_testname)) {
        warn("WARNING: invalid characters removed from testname in " .
             "tracefile $tracefile: '$changed_testname'->'$testname'\n");
    }
}

#  write data to filename (stdout if '-')
# returns array of (lines found, lines hit, functions found, functions hit,
#                   branches found, branches_hit)
sub write_info_file($$$)
{
    my ($self, $filename, $do_checksum) = @_;

    my $file = InOutFile->out($filename);
    my $hdl  = $file->hdl();
    return $self->write_info($hdl, $do_checksum);
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
    my $ln_total_found = 0;
    my $ln_total_hit   = 0;
    my $fn_total_found = 0;
    my $fn_total_hit   = 0;
    my $br_total_found = 0;
    my $br_total_hit   = 0;

    my $srcReader = ReadCurrentSource->new()
        if ($verify_checksum);
    foreach my $filename (sort($self->files())) {
        my $entry       = $self->data($filename);
        my $source_file = $entry->filename();
        die("expected to have have filtered $source_file out")
            if lcovutil::is_external($source_file);
        die("expected TraceInfo, got '" . ref($entry) . "'")
            unless ('TraceInfo' eq ref($entry));

        my ($testdata, $sumcount, $funcdata, $checkdata,
            $testfncdata, $testbrdata, $sumbrcount, $found,
            $hit, $f_found, $f_hit, $br_found,
            $br_hit) = $entry->get_info();

        # munge the source file name, if requested
        $source_file = lcovutil::subst_file_name($source_file);
        # Add to totals
        $ln_total_found += $found;
        $ln_total_hit   += $hit;
        $fn_total_found += $f_found;
        $fn_total_hit   += $f_hit;
        $br_total_found += $br_found;
        $br_total_hit   += $br_hit;

        # Please note:  if you add or change something here (lcov info file format) -
        #   then please make corresponding changes to the '_read_info' method, above
        #   and update the format description found in .../man/geninfo.1.
        foreach my $testname (sort($testdata->keylist())) {
            my $testcount    = $testdata->value($testname);
            my $testfnccount = $testfncdata->value($testname);
            my $testbrcount  = $testbrdata->value($testname);
            $found = 0;
            $hit   = 0;

            print(INFO_HANDLE "TN:$testname\n");
            print(INFO_HANDLE "SF:$source_file\n");
            print(INFO_HANDLE "VER:" . $entry->version() . "\n")
                if defined($entry->version());
            if (defined($srcReader)) {
                $srcReader->close();
                if (is_c_file($source_file)) {
                    lcovutil::info(1,
                                   "reading $source_file for lcov checksum\n");
                    $srcReader->open($source_file);
                } else {
                    lcovutil::debug("not reading $source_file: no ext match\n");
                }
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

                foreach my $key (@functionOrder) {
                    my $data = $functionMap->findKey($key);
                    my $line = $data->line();

                    my $aliases = $data->aliases();
                    my $endLine =
                        defined($data->end_line()) ?
                        ',' . $data->end_line() :
                        '';
                    foreach my $alias (sort keys %$aliases) {
                        print(INFO_HANDLE "FN:$line$endLine,$alias\n");
                    }
                }
                my $f_found = 0;
                my $f_hit   = 0;
                foreach my $key (@functionOrder) {
                    my $data    = $functionMap->findKey($key);
                    my $line    = $data->line();
                    my $aliases = $data->aliases();
                    foreach my $alias (sort keys %$aliases) {
                        my $hit = $aliases->{$alias};
                        if ($hit < 0) {
                            lcovutil::ignorable_error($lcovutil::ERROR_NEGATIVE,
                                "Unexpected negative count '$hit' for function $alias at $."
                            );
                            $hit = 0;
                        }
                        ++$f_found;
                        ++$f_hit if $hit > 0;
                        print(INFO_HANDLE "FNDA:$hit,$alias\n");
                    }
                }
                print(INFO_HANDLE "FNF:$f_found\n");
                print(INFO_HANDLE "FNH:$f_hit\n");
            }
            # $testbrcount is undef if there are no branches in the scope
            if ($lcovutil::br_coverage &&
                defined($testbrcount)) {
                # Write branch related data
                $br_found = 0;
                $br_hit   = 0;

                foreach my $line (sort({ $a <=> $b } $testbrcount->keylist())) {

                    my $brdata = $testbrcount->value($line);
                    # want the block_id to be treated as 32-bit unsigned integer
                    #  (need masking to match regression tests)
                    my $mask = (1 << 32) - 1;
                    foreach my $block_id ($brdata->blocks()) {
                        my $blockData = $brdata->getBlock($block_id);
                        $block_id &= $mask;
                        foreach my $br (@$blockData) {
                            my $taken       = $br->data();
                            my $branch_id   = $br->id();
                            my $branch_expr = $br->expr();
                            # mostly for Verilog:  if there is a branch expression: use it.
                            if ($taken ne '-' && $taken < 0) {
                                lcovutil::ignorable_error(
                                    $lcovutil::ERROR_NEGATIVE,
                                    "Unexpected negative count '$taken' for branch $branch_id at $."
                                );
                                $taken = 0;
                            }
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
            # Write line related data
            foreach my $line (sort({ $a <=> $b } $testcount->keylist())) {
                my $l_hit = $testcount->value($line);
                my $chk   = '';
                if ($verify_checksum) {
                    if (exists($checkdata->{$line})) {
                        $chk = $checkdata->{$line};
                    } elsif (defined($srcReader)) {
                        my $content = $srcReader->getLine($line);
                        $chk = Digest::MD5::md5_base64($content);
                    }
                    $chk = ',' . $chk if ($chk);
                }

                if ($l_hit < 0) {
                    lcovutil::ignorable_error($lcovutil::ERROR_NEGATIVE,
                     "Unexpected negative count '$l_hit' for line $line at $.");
                    $l_hit = 0;
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

    return ($ln_total_found, $ln_total_hit, $fn_total_found,
            $fn_total_hit, $br_total_found, $br_total_hit);
}

#
# rename_functions(info, conv)
#
# Rename all function names in TraceFile according to CONV: OLD_NAME -> NEW_NAME.
# In case two functions demangle to the same name, assume that they are
# different object code implementations for the same source function.
#

sub rename_functions($$)
{
    my ($self, $conv) = @_;

    foreach my $filename ($self->files()) {
        my $data = $self->data($filename)->rename_functions($conv, $filename);
    }
}

1;
