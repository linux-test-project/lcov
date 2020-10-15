# some common utilities for lcov-related scripts

use strict;
use warnings;
require Exporter;

package lcovutil;

use File::Temp qw(tempfile tempdir);

our @ISA = qw(Exporter);
our @EXPORT_OK =
  qw($tool_name $quiet @temp_dirs set_tool_name set_info_callback $quiet
     append_tempdir temp_cleanup
     define_errors parse_ignore_errors ignorable_error info
     die_handler warn_handler abort_handler

     verbose debug $debug $verbose

     $FILTER_BRANCH_NO_COND $FILTER_LINE_CLOSE_BRACE $FILTER_FUNCTION_ALIAS
     @cov_filter
     parse_cov_filters summarize_cov_filters
     filterStringsAndComments simplifyCode balancedParens

     %geninfoErrs $ERROR_GCOV $ERROR_SOURCE $ERROR_GRAPH $ERROR_MISMATCH
     $ERROR_BRANCH $ERROR_EMPTY

     is_external @internal_dirs $opt_external
     rate $default_precision check_precision

     system_no_output

     %tlaColor %tlaTextColor use_vanilla_color
);

our @ignore;
our %ERROR_ID;
our %ERROR_NAME;
our $tool_name;
our @temp_dirs;
our $quiet = "";        # If set, suppress information messages

our $debug = 0;  # if set, emit debug messages
our $verbose = 0;  # if set, enable additional logging

# geninfo errors are shared by 'lcov' - so we put them in a common location
our $ERROR_GCOV         = 0;
our $ERROR_SOURCE       = 1;
our $ERROR_GRAPH        = 2;
our $ERROR_MISMATCH     = 3;
our $ERROR_BRANCH       = 4; # branch numbering is not correct
our $ERROR_EMPTY        = 10; # no records found in info file
our %geninfoErrs = (
    "gcov" => $ERROR_GCOV,
    "source" => $ERROR_SOURCE,
    "graph" => $ERROR_GRAPH,
);

# for external file filtering
our @internal_dirs;
our $opt_external;

# Specify coverage rate default precision
our $default_precision = 1;

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
our %COVERAGE_FILTERS = (
  "branch" => $FILTER_BRANCH_NO_COND,
  'line' => $FILTER_LINE_CLOSE_BRACE,
  'function' => $FILTER_FUNCTION_ALIAS,
);
our @cov_filter;        # 'undef' if filter is not enabled,
                        # [line_count, coverpoint_count] histogram if
                        #   filter is enabled: nubmer of applications
                        #   of this filter


our %tlaColor = (
    "UBC" => "#FDE007",
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
    "DCB" => "#FFFFFF",
    );
# colors for the text in the PNG image of the corresponding TLA line
our %tlaTextColor = (
    "UBC" => "#aaa005",
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
    "DCB" => "#FFFFFF",
  );

sub set_tool_name($) {
  $tool_name = shift;
}

#
# system_no_output(mode, parameters)
#
# Call an external program using PARAMETERS while suppressing depending on
# the value of MODE:
#
#   MODE & 1: suppress STDOUT
#   MODE & 2: suppress STDERR
#   MODE & 4: redirect to temporary files instead of suppressing
#
# Return (stdout, stderr, rc):
#    stdout: path to tempfile containing stdout or undef
#    stderr: path to tempfile containing stderr or undef
#    0 on success, non-zero otherwise
#

sub system_no_output($@)
{
  my $mode = shift;
  my $result;
  local *OLD_STDERR;
  local *OLD_STDOUT;
  my $stdout_file;
  my $stderr_file;
  my $fd;

  # Save old stdout and stderr handles
  ($mode & 1) && open(OLD_STDOUT, ">>&", "STDOUT");
  ($mode & 2) && open(OLD_STDERR, ">>&", "STDERR");

  if ($mode & 4) {
    # Redirect to temporary files
    if ($mode & 1) {
      ($fd, $stdout_file) = tempfile(UNLINK => 1);
      open(STDOUT, ">", $stdout_file) || warn("$!\n");
      close($fd);
    }
    if ($mode & 2) {
      ($fd, $stderr_file) = tempfile(UNLINK => 1);
      open(STDERR, ">", $stderr_file) || warn("$!\n");
      close($fd);
    }
  } else {
    # Redirect to /dev/null
    ($mode & 1) && open(STDOUT, ">", "/dev/null");
    ($mode & 2) && open(STDERR, ">", "/dev/null");
  }

  debug("system(".join(' ', @_).")\n");
  system(@_);
  $result = $?;

  # Close redirected handles
  ($mode & 1) && close(STDOUT);
  ($mode & 2) && close(STDERR);

  # Restore old handles
  ($mode & 1) && open(STDOUT, ">>&", "OLD_STDOUT");
  ($mode & 2) && open(STDERR, ">>&", "OLD_STDERR");

  # Remove empty output files
  if (defined($stdout_file) && -z $stdout_file) {
    unlink($stdout_file);
    $stdout_file = undef;
  }
  if (defined($stderr_file) && -z $stderr_file) {
    unlink($stderr_file);
    $stderr_file = undef;
  }

  return ($stdout_file, $stderr_file, $result);
}


#
# info(printf_parameter)
#
# Use printf to write PRINTF_PARAMETER to stdout only when the $quiet flag
# is not set.
#

sub default_info_impl(@) {
  # Print info string
  printf(@_)
    if (!$quiet);
}

sub set_info_callback($) {
    $info_callback = shift;
}

sub info(@)
{
  &{$info_callback}(@_);
}

sub debug($) {
  my $msg = shift;

  print(STDERR "DEBUG: $msg")
    if ($debug);
}

sub verbose(@)
{
  # Print info string
    printf(@_)
        if ($verbose);
}

sub temp_cleanup() {
  # Ensure temp directory is not in use by current process
  chdir("/");

  if (@temp_dirs) {
    info("Removing temporary directories.\n");
    foreach (@temp_dirs) {
      rmtree($_);
    }
    @temp_dirs = ();
  }
}

sub append_tempdir($) {
  push(@temp_dirs, $_);
}

sub warn_handler($)
{
  my ($msg) = @_;

  warn("$tool_name: $msg");
}

sub die_handler($)
{
  my ($msg) = @_;

  temp_cleanup();
  die("$tool_name: $msg");
}

sub abort_handler($)
{
  temp_cleanup();
  exit(1);
}

sub define_errors($)
{
  my $hash = shift;
  foreach my $k (keys(%$hash)) {
    my $id = $hash->{$k};
    $ERROR_ID{$k} = $id;
    $ERROR_NAME{$id} = $k;
    $ignore[$ERROR_ID{$k}] = 0;
  }
}

sub parse_ignore_errors(@)
{
  my @ignore_errors = split(',', join(',', @_));

  # first, mark that all known errors are not ignored
  foreach my $item (keys(%ERROR_ID)) {
    my $id = $ERROR_ID{$item};
    $ignore[$id] = 0;
  }

  return if (!@ignore_errors);

  foreach my $item (@ignore_errors) {
    die("ERROR: unknown argument for --ignore-errors: '$item'")
      unless exists($ERROR_ID{lc($item)});
    my $item_id = $ERROR_ID{lc($item)};
    $ignore[$item_id] += 1;
  }
}


our %didwarning;

sub ignorable_error($$;$) {
  my ($code, $msg, $quiet) = @_;

  my $errName = $ERROR_NAME{$code};
  if ($code >= scalar(@ignore) ||
      ! $ignore[$code] ) {
    my $ignoreOpt = "\t(use \"$tool_name --ignore-errors $errName ...\" to bypass this error)\n";
    die_handler("Error: $msg\n$ignoreOpt");
  }
  # only tell the user how to suppress this on the first occurrence
  my $ignoreOpt = exists($didwarning{$code}) ? "" : "\t(use \"$tool_name --ignore-errors $errName,$errName ...\" to suppress this warning)\n";
  $didwarning{$code} = 1;
  warn_handler("Warning: ($errName') $msg\n$ignoreOpt")
    unless $ignore[$code] > 1 || (defined($quiet) && $quiet);
}


sub parse_cov_filters(@)
{
  my @filters = split(',', join(',', @_));

  # first, mark that all known filters are disabled
  foreach my $item (keys(%COVERAGE_FILTERS)) {
    my $id = $COVERAGE_FILTERS{$item};
    $cov_filter[$id] = undef;
  }

  return if (!@filters);

  foreach my $item (@filters) {
    die("ERROR: unknown argument for --filter: '$item'\n")
      unless exists($COVERAGE_FILTERS{lc($item)});
    my $item_id = $COVERAGE_FILTERS{lc($item)};

    $cov_filter[$item_id] = [0, 0];
  }
}

sub summarize_cov_filters {
  for my $key (keys(%COVERAGE_FILTERS)) {
    my $id = $COVERAGE_FILTERS{$key};
    next unless defined($lcovutil::cov_filter[$id]);
    my $histogram = $lcovutil::cov_filter[$id];
    next if 0 == $histogram->[0];
    info("Filter suppressions '$key':\n    "
         . $histogram->[0] . " instance"
         . ($histogram->[0] > 1 ? "s" : "") . "\n    "
         . $histogram->[1] . " coverpoint"
         . ($histogram->[1] > 1 ? "s" : "") . "\n");
  }
}

sub filterStringsAndComments {
  my $src_line = shift;

  # remove compiler directives
  $src_line =~ s/\s*#.*$//g;
  # remove comments
  $src_line =~ s#(/\*.*?\*/|//.*$)##g;
  # remove strings
  $src_line =~ s/\\"//g;
  $src_line =~ s/"[^"]*"//g;

  return $src_line;
}

sub simplifyCode {
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
  # C-style cast
  $src_line =~ s/\(\s*${id}[*&]\s*\)//g;

  # remove some characters which might look like conditionals
  $src_line =~ s/(->|>>|<<|::)//g;

  return $src_line;
}


sub balancedParens {
  my $line = shift;

  my $open = 0;
  my $close = 0;

  foreach my $char (split('', $line)) {
    if ($char eq '(') {
      ++ $open;
    } elsif ($char eq ')' ) {
      ++ $close;
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

  return 0 unless (defined($opt_external) && $opt_external);

  foreach my $dir (@internal_dirs) {
    return 0 if ($filename =~ /^\Q$dir\/\E/);
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
        $precision      = $default_precision
          if (!defined($precision));
        $suffix         = ""    if (!defined($suffix));
        $width          = 0     if (!defined($width));

        return sprintf("%*s", $width, "-") if (!defined($found) || $found == 0);
        my $rate = sprintf("%.*f", $precision, $hit * 100 / $found);

        # Adjust rates if necessary
        if ($rate == 0 && $hit > 0) {
                $rate = sprintf("%.*f", $precision, 1 / 10 ** $precision);
        } elsif ($rate == 100 && $hit != $found) {
                $rate = sprintf("%.*f", $precision, 100 - 1 / 10 ** $precision);
        }

        return sprintf("%*s", $width, $rate.$suffix);
}

# Make sure precision is within valid range [1:4]
sub check_precision() {
  die("ERROR: specified precision is out of range (1 to 4)\n")
    if ($default_precision < 1 || $default_precision > 4);
}

# use vanilla color palette.
sub use_vanilla_color()
{
  for my $tla (('CBC', 'GNC', 'GIC', 'GBC')) {
    $lcovutil::tlaColor{$tla} = "#CAD7FE";
    $lcovutil::tlaTextColor{$tla} = "#98A0AA";
  }
  for my $tla (('UBC', 'UNC', 'UIC', 'LBC')) {
    $lcovutil::tlaColor{$tla} = "#FF6230";
    $lcovutil::tlaTextColor{$tla} = "#AA4020";
  }
  for my $tla (('EUB', 'ECB')) {
    $lcovutil::tlaColor{$tla} = "#FFFFFF";
    $lcovutil::tlaTextColor{$tla} = "#AAAAAA";
  }
}

package MapData;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  $self->{_data} = {};
  $self->{_modified} = 0;

  return $self;
}

sub append_if_unset {
  my $self = shift;
  my $key = shift;
  my $data = shift;

  if (!defined($self->{_data}->{$key})) {
    $self->{_data}->{$key} = $data;
  }

  return $self;
}

sub replace {
  my $self = shift;
  my $key = shift;
  my $data = shift;

  $self->{_data}->{$key} = $data;

  return $self;
}

sub value {
  my $self = shift;
  my $key = shift;

  if (!defined($self->{_data}->{$key})) {
    return undef;
  }

  return $self->{_data}->{$key};
}

sub remove {
  my $self = shift;
  my $key = shift;

  delete $self->{_data}->{$key};
  $self->{_modified} = 1;
  return $self;
}

sub mapped {
  my $self = shift;
  my $key = shift;

  return defined($self->{_data}->{$key}) ? 1 : 0;
}

sub keylist {
  my $self = shift;
  return keys(%{$self->{_data}});
}

sub entries {
  my $self = shift;
  return scalar(keys(%{$self->{_data}}));
}

sub _summary {
  # dummy method - to parallelize calling sequence with CountData, BranchData
  my $self = shift;
  return $self;
}

# Class definitions
package CountData;

our $UNSORTED = 0;
our $SORTED = 1;

sub new {
  my $class = shift;
  my $sortable = defined($_[0]) ? shift : $UNSORTED;
  my $self = {};
  bless $self, $class;

  $self->{_data} = {};
  $self->{_sortable} = $sortable;
  $self->{_found} = 0;
  $self->{_hit} = 0;
  $self->{_modified} = 0;

  return $self;
}

sub append {
  my $self = shift;
  my $key = shift;
  my $count = shift;

  if (!defined($self->{_data}->{$key})) {
    $self->{_data}->{$key} = 0;
  }
  $self->{_data}->{$key} += $count;
  $self->{_modified} = 1;
  return $self;
}

sub value {
  my $self = shift;
  my $key = shift;

  if (!defined($self->{_data}->{$key})) {
    return undef;
  }
  return $self->{_data}->{$key};
}

sub remove {
  my $self = shift;
  my $key = shift;

  delete $self->{_data}->{$key};
  $self->{_modified} = 1;
  return $self;
}

sub _summary {
  my $self = shift;

  if (!$self->{_modified}) {
    return $self;
  }

  $self->{_found} = 0;
  $self->{_hit} = 0;
  foreach my $key ($self->keylist()) {
    my $count = $self->{_data}->{$key};
    $self->{_found}++;
    $self->{_hit}++ if ($count > 0);
  }
  $self->{_modified} = 0;
  return $self;
}

sub found {
  my $self = shift;

  return $self->_summary()->{_found};
}

sub hit {
  my $self = shift;

  return $self->_summary()->{_hit};
}

sub keylist {
  my $self = shift;
  return keys(%{$self->{_data}});
}

sub entries {
  my $self = shift;
  return scalar(keys(%{$self->{_data}}));
}

sub merge {
  my $self = shift;
  my $info = shift;

  foreach my $key ($info->keylist()) {
    $self->append($key, $info->value($key));
  }
}

#
# get_found_and_hit(hash)
#
# Return the count for entries (found) and entries with an execution count
# greater than zero (hit) in a hash (linenumber -> execution count) as
# a list (found, hit)
#
sub get_found_and_hit {
  my $self = shift;
  $self->_summary();
  return ($self->{_found}, $self->{_hit});
}

package BranchBlock;
# branch element:  index, taken/not-taken count, optional expression
# for baseline or current data, 'taken' is just a number (or '-')
# for differential data: 'taken' is an array [$taken, tla]

sub new {
  my ($class, $id, $taken, $expr) = @_;
  # if branchID is not an expression - go back to legacy behaviour
  my $self = [$id, $taken, (defined($expr) && $expr eq $id) ? undef : $expr];
  bless $self, $class;
  return $self;
}

sub isTaken {
  my $self = shift;
  return $self->[1] ne '-';
}

sub id {
  my $self = shift;
  return $self->[0];
}

sub data {
  my $self = shift;
  return $self->[1];
}

sub count {
  my $self = shift;
  return $self->[1] eq '-' ? 0 : $self->[1];
}

sub expr {
  my $self = shift;
  return $self->[2];
}

sub exprString {
  my $self = shift;
  my $e = $self->[2];
  return defined($e) ? $e : 'undef';
}

sub merge {
  my ($self, $that) = @_;
  if ($self->exprString() ne $that->exprString()) {
    lcovutil::ignorable_error($ERROR_MISMATCH, "mismatched expressions for id "
                              . $self->id() . ", " . $that->id() . ": '"
                              . $self->exprString() . "' -> '" . $that->exprString()
                              . "'");
    # else - ngore the issue and merge data even thought the expressions
    #  look different
  }
  my $t = $that->[1];
  return if $t eq '-';

  my $count = $self->[1];
  if ($count ne '-') {
    $count += $t
  } else {
    $count = $t;
  }
  $self->[1] = $count;
}


package BranchEntry;
# hash of blockID -> array of BranchBlock refs for each sequential branch ID

sub new {
  my ($class, $line) = @_;
  my $self = [$line, {}];
  bless $self, $class;
  return $self;
}

sub line {
  my $self = shift;
  return $self->[0];
}

sub hasBlock {
  my ($self, $id) = @_;
  return exists($self->[1]->{$id});
}

sub getBlock {
  my ($self, $id) = @_;
  $self->hasBlock($id) or die("unknown block $id");
  return $self->[1]->{$id};
}

sub blocks {
  my $self = shift;
  return keys %{$self->[1]};
}

sub addBlock {
  my ($self, $blockId) = @_;

  ! exists($self->[1]->{$blockId}) or die "duplicate blockID";
  my $blockData = [];
  $self->[1]->{$blockId} = $blockData;
  return $blockData;
}


package BranchData;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  $self->{_data} = {}; #  hash of lineNo -> BranchEntry
                       #      hash of blockID ->
                       #         array of 'taken' entries for each sequential
                       #           branch ID
  $self->{_br_found} = 0; # number branches found
  $self->{_br_hit} = 0;   # number branches executed
  $self->{_modified} = 0; # "map is modified" flag - to indicate need for update

  return $self;
}

sub append {
  my ($self, $line, $block, $br) = @_;

  if (! defined($br) ) {
    die("expected 'BranchEntry' or 'integer, BranchBlock'")
      unless ('BranchEntry' eq ref($block));

    die("line $line already contains element")
      if exists($self->{_data}->{$line});
    $self->{_data}->{$line} = $block;
    return $self;
  }
  die("BranchData::append expected BranchBock got '" . ref($br) . "'")
    unless ('BranchBlock' eq ref($br));
  my $branch = $br->id();
  my $branchElem;
  if (exists($self->{_data}->{$line})) {
    $branchElem = $self->{_data}->{$line};
    $line == $branchElem->line() or die("wrong line mapping");
  } else {
    $branchElem = BranchEntry->new($line);
    $self->{_data}->{$line} = $branchElem;
  }

  if (! $branchElem->hasBlock($block)) {
    $branch == 0 or
      lcovutil::ignorable_error($ERROR_BRANCH,
                                "unexpected non-zero initial branch");
    $branch = 0;
    my $l = $branchElem->addBlock($block);
    push(@$l, BranchBlock->new($branch, $br->data(), $br->expr()));
  } else {
    $block = $branchElem->getBlock($block);

    if ( $branch > scalar(@$block) ) {
      lcovutil::ignorable_error($ERROR_BRANCH,
                                "unexpected non-sequential branch ID $branch for block $block of line $line: " . scalar(@$block));
      $branch = scalar(@$block);
    }

    if (! exists($block->[$branch])) {
      $block->[$branch] = BranchBlock->new($branch,
                                           $br->data(), $br->expr());
      $self->{_modified} = 1;
    } else {
      my $me = $block->[$branch];
      $self->{_modified} = 1
        if (0 == $me->count() && 0 != $br->count());
      $me->merge($br);
    }
  }
  return $self;
}

sub _summary {
  my $self = shift;

  if (!$self->{_modified}) {
    return $self;
  }

  $self->{_br_found} = 0;
  $self->{_br_hit} = 0;

  # why are we bothering to sort?
  #  for that matter - why do this calculation at all?
  #  just keep track of counts when we insert data.
  foreach my $line (sort({$a <=> $b} keys(%{$self->{_data}}))) {
    my $branch = $self->{_data}->{$line};
    $line == $branch->line() or die("lost track of line");
    foreach my $blockId (sort($branch->blocks())) {
      my $bdata = $branch->getBlock($blockId);

      foreach my $br (@$bdata) {
        my $count = $br->count();
        $self->{_br_found}++;
        $self->{_br_hit}++ if (0 != $count);
      }
    }
  }
  $self->{_modified} = 0;
  return $self;
}

sub found {
  my $self = shift;

  return $self->_summary()->{_br_found};
}

sub hit {
  my $self = shift;

  return $self->_summary()->{_br_hit};
}

sub merge {
  my $self = shift;
  my $info = shift;

  foreach my $line ($info->keylist()) {
    my $branch = $info->{_data}->{$line};
    foreach my $blockId ($branch->blocks()) {
      my $bdata = $branch->getBlock($blockId);
      foreach my $br (@$bdata) {
        $self->append($line, $blockId, $br);
      }
    }
  }
}

# return BranchEntry struct (or undef)
sub value {
  my ($self, $lineNo) = @_;

  my $map = $self->{_data};
  return exists($map->{$lineNo}) ? $map->{$lineNo} : undef;
}

# return list of lines which contain branch data
sub keylist {
  my $self = shift;
  return keys(%{$self->{_data}});
}

sub get_found_and_hit {
  my $self = shift;
  $self->_summary();

  return ($self->{_br_found}, $self->{_br_hit});
}

package TraceInfo;

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  # _testdata          : test name  -> CountData ( line number -> execution count )
  $self->{_testdata} = MapData->new();
  # _sumcount          : line number  -> execution count
  $self->{_sumcount} = CountData->new($CountData::SORTED);
  # _funcdata          : function name  -> line number
  $self->{_funcdata} = MapData->new();
  $self->{_found} = 0;
  $self->{_hit} = 0;
  $self->{_f_found} = 0;
  $self->{_f_hit} = 0;
  $self->{_b_found} = 0;
  $self->{_b_hit} = 0;
  # _checkdata         : line number  -> source line checksum
  $self->{_checkdata} = MapData->new();
  # _testfncdata       : test name  -> CountData ( function name -> execution count )
  $self->{_testfncdata} = MapData->new();
  # _sumfnccount       : function name  -> CountData ( line number -> execution count )
  $self->{_sumfnccount} = CountData->new($CountData::UNSORTED);
  # _testbrdata        : test name  -> BranchData ( line number -> branch coverage )
  $self->{_testbrdata} = MapData->new();
  # _sumbrcount        : line number  -> branch coverage
  $self->{_sumbrcount} = BranchData->new();

  return $self;
}

# line coverage data
sub test {
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

sub sum {
  my $self = shift;
  return $self->{_sumcount};
}

sub func {
  my $self = shift;
  return $self->{_funcdata};
}

sub found {
  my $self = shift;
  return $self->sum()->found();
}

sub hit {
  my $self = shift;
  return $self->sum()->hit();
}

sub f_found {
  my $self = shift;
  return $self->sumfnc()->found();
}

sub f_hit {
  my $self = shift;
  return $self->sumfnc()->hit();
}

sub b_found {
  my $self = shift;
  return $self->sumbr()->found();
}

sub b_hit {
  my $self = shift;
  return $self->sumbr()->hit();
}

sub check {
  my $self = shift;
  return $self->{_checkdata};
}

# function coverage
sub testfnc {
  my $self = shift;
  my $name = defined($_[0]) ? shift : undef;

  if (!defined($name)) {
    return $self->{_testfncdata};
  }

  if (!$self->{_testfncdata}->mapped($name)) {
    $self->{_testfncdata}->append_if_unset($name, CountData->new(0));
  }

  return $self->{_testfncdata}->value($name);
}

sub sumfnc {
  my $self = shift;
  return $self->{_sumfnccount};
}

# branch coverage
sub testbr {
  my $self = shift;
  my $name = defined($_[0]) ? shift : undef;

  if (!defined($name)) {
    return $self->{_testbrdata};
  }

  if (!$self->{_testbrdata}->mapped($name)) {
    $self->{_testbrdata}->append_if_unset($name, BranchData->new());
  }

  return $self->{_testbrdata}->value($name);
}

sub sumbr {
  my $self = shift;
  return $self->{_sumbrcount};
}


#
# set_info_entry(hash_ref, testdata_ref, sumcount_ref, funcdata_ref,
#                checkdata_ref, testfncdata_ref, sumfcncount_ref,
#                testbrdata_ref, sumbrcount_ref[,lines_found,
#                lines_hit, f_found, f_hit, $b_found, $b_hit])
#
# Update the hash referenced by HASH_REF with the provided data references.
#

sub set_info($$$$$$$$$;$$$$$$)
{
  my $self = shift;

  $self->{_testdata} = shift;
  $self->{_sumcount} = shift;
  $self->{_funcdata} = shift;
  $self->{_checkdata} = shift;
  $self->{_testfncdata} = shift;
  $self->{_sumfnccount} = shift;
  $self->{_testbrdata} = shift;
  $self->{_sumbrcount} = shift;

  if (defined($_[0])) { $self->{_found} = shift; }
  if (defined($_[0])) { $self->{_hit} = shift; }
  if (defined($_[0])) { $self->{_f_found} = shift; }
  if (defined($_[0])) { $self->{_f_hit} = shift; }
  if (defined($_[0])) { $self->{_b_found} = shift; }
  if (defined($_[0])) { $self->{_b_hit} = shift; }
}

#
# get_info_entry(hash_ref)
#
# Retrieve data from an entry of the structure generated by TraceFile::_read_info().
# Return a list of references to hashes:
# (test data hash ref, sum count hash ref, funcdata hash ref, checkdata hash
#  ref, testfncdata hash ref, sumfnccount hash ref, lines found, lines hit,
#  functions found, functions hit)
#

sub get_info($)
{
  my $self = shift;
  my $testdata_ref = $self->{_testdata};
  my $sumcount_ref = $self->{_sumcount};
  my $funcdata_ref = $self->{_funcdata};
  my $checkdata_ref = $self->{_checkdata};
  my $testfncdata = $self->{_testfncdata};
  my $sumfnccount = $self->{_sumfnccount};
  my $testbrdata = $self->{_testbrdata};
  my $sumbrcount = $self->{_sumbrcount};
  my $lines_found = $self->found();
  my $lines_hit = $self->hit();
  my $fn_found = $self->f_found();
  my $fn_hit = $self->f_hit();
  my $br_found = $self->b_found();
  my $br_hit = $self->b_hit();

  return ($testdata_ref, $sumcount_ref, $funcdata_ref, $checkdata_ref,
          $testfncdata, $sumfnccount, $testbrdata, $sumbrcount,
          $lines_found, $lines_hit, $fn_found, $fn_hit,
          $br_found, $br_hit);
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

  my $newfuncdata = MapData->new();
  my $newsumfnccount = CountData->new(0);

  # funcdata: function name -> line number
  my $funcdata = $self->func();
  foreach my $fn ($funcdata->keylist()) {
    my $cn = $conv->{$fn};

    # Abort if two functions on different lines map to the
    # same demangled name.
    die("ERROR: Demangled function name $cn maps to different lines (".
        $newfuncdata->value($cn) . " vs " . $funcdata->value($fn) .
        ") in $filename\n")
      if ($newfuncdata->mapped($cn) &&
          $newfuncdata->value($cn) != $funcdata->value($fn));

    $newfuncdata->replace($cn, $funcdata->value($fn));
  }
  #$data->{"func"} = \%newfuncdata;

  # testfncdata: test name -> testfnccount
  # testfnccount: function name -> execution count
  my $testfncdata = $self->testfnc();
  foreach my $tn ($testfncdata->keylist()) {
    my $testfnccount = $testfncdata->value($tn);
    my $newtestfnccount = CountData->new(1);

    foreach my $fn ($testfnccount->keylist()) {
      my $cn = $conv->{$fn};

      # Add counts for different functions that map
      # to the same name.
      $newtestfnccount->append($cn, $testfnccount->value($fn));
    }
    $testfncdata->replace($tn, $newtestfnccount);
  }

  # sumfnccount: function name -> execution count
  my $sumfnccount = $self->sumfnc();
  foreach my $fn ($sumfnccount->keylist()) {
    my $cn = $conv->{$fn};

    # Add counts for different functions that map
    # to the same name.
    $newsumfnccount->append($cn, $sumfnccount->value($fn));
  }
  $self->{_sumfnccount} = $newsumfnccount;
}

sub _merge_funcdata {
  my $self = shift;
  my $info = shift;
  my $filename = shift;

  foreach my $func ($info->func()->keylist()) {
    my $line2 = $info->func()->value($func);
    if ($self->func()->mapped($func) &&
        $self->func()->value($func) != $line2) {
      warn("ERROR: function data mismatch at $filename:$line2\n");
      next
    }
    $self->func()->replace($func, $line2);
  }
}

sub _merge_checksums {
  my $self = shift;
  my $info = shift;
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

sub merge {
  my $self = shift;
  my $info = shift;
  my $filename = shift;

  foreach my $name ($info->test()->keylist()) {
    $self->test($name)->merge($info->test($name));
  }
  $self->sum()->merge($info->sum());

  $self->_merge_funcdata($info, $filename);
  $self->_merge_checksums($info, $filename);

  foreach my $name ($info->testfnc()->keylist()) {
    $self->testfnc($name)->merge($info->testfnc($name));
  }
  $self->sumfnc()->merge($info->sumfnc());

  foreach my $name ($info->testbr()->keylist()) {
    $self->testbr($name)->merge($info->testbr($name));
  }
  $self->sumbr()->merge($info->sumbr());

  return $self;
}


# this package merely reads sourcefiles as they are found on the current
#  filesystem - ie., the baseline version might have been modified/might
#  have diffs - but the current version does not.
package ReadCurrentSource;

sub new {
  my ($class, $filename) = @_;

  my $self = [];
  bless $self, $class;

  self->open($filename) if defined($filename);
  return $self;
}

sub close {
  my $self = shift;
  while (scalar(@$self)) {
    pop(@$self);
  }
}

sub open {
  my ($self, $filename, $version) = @_;

  $version = "" unless defined($version);
  if (open(SRC, "<", $filename)) {
    lcovutil::info("reading $version$filename (for bogus branch filtering)\n");
    my @sourceLines;
    while (<SRC>) {
      chomp($_);
      push(@sourceLines, $_);
    }
    $self->setData($filename, \@sourceLines);
  } else {
    lcovutil::info("unable to open $filename (for bogus branch filtering)\n");
    $self->close();
  }
}

sub setData {
  my ($self, $filename, $data) = @_;
  die("expected array")
    unless (ref($data) eq 'ARRAY');
  $self->[0] = $filename;
  $self->[1] = $data;
}

sub notEmpty {
  my $self = shift;
  return 0 != scalar(@$self);
}

sub filename {
  return $_[0]->[0];
}

sub getLine {
  my ($self, $line) = @_;

  return $self->[1]->[$line-1];
}

sub isCharacter {
  my ($self, $line, $char) = @_;

  my $code = $self->getLine($line);
  return 0
    unless defined($code);
  # remove comments
  $code =~ s|//.*$||;
  $code =~ s|/\*.*\*/||g;
  return ($code =~ /^\s*${char}\s*$/ );
}

# is line empty
sub isBlank {
  my ($self, $line) = @_;

  my $code = $self->getLine($line);
  return 0
    unless defined($code);
  # remove comments
  $code =~ s|//.*$||;
  $code =~ s|/\*.*\*/||g;
  return ($code =~ /^\s*$/ );
}

sub containsConditional {
  my ($self, $line) = @_;

  my $src = $self->getLine($line);
  return 1
    unless defined($src);
  my $foundCond = 1;

  my $code = "";
  my $limit = 5; # don't look more than 5 lines ahead
  for (my $next = $line+1
       ; defined($src) && ($next - $line) < $limit
       ; ++ $next) {

    $src = lcovutil::filterStringsAndComments($src);

    $src = lcovutil::simplifyCode($src);

    last if ($src =~ /([?|!~><]|&&|==|!=|\b(if|switch|case|while|for)\b)/);

    $code = $code . $src;

    if (lcovutil::balancedParens($code) ||
        # assume we got to the end of the statement if we see semicolon
        # or brace.
        $src =~ /[{;]\s*$/) {
      $foundCond = 0;
      last;
    }
    $src = $self->getLine($next);
  }
  return $foundCond;
}

package TraceFile;

# Block value used for unnamed blocks
our $UNNAMED_BLOCK = vec(pack('b*', 1 x 32), 0, 32);

sub load {
  my ($class, $tracefile, $readSource) = @_;
  my $self = {};
  bless $self, $class;

  $self->{_data} = {};
  $self->_read_info($tracefile, $readSource);
  return $self;
}

sub new {
  my $class = shift;
  my $self = {};
  bless $self, $class;

  $self->{_data} = {};
  return $self;
}

sub empty {
  my $self = shift;

  return ! keys(%{$self->{_data}});
}

sub files {
  my $self = shift;

  return keys %{$self->{_data}};
}

sub file_exists {
  my ($self, $name) = @_;

  return exists($self->{_data}->{$name});
}

sub data {
  my $self = shift;
  my $file = shift;

  if (!defined($self->{_data}->{$file})) {
    $self->{_data}->{$file} = TraceInfo->new();
  }

  return $self->{_data}->{$file};
}

sub remove {
  my ($self, $filename) = @_;
  $self->file_exists($filename)
    or die("remove nonexistent file $filename");
  delete($self->{_data}->{$filename});
}

sub insert {
  my ($self, $filename, $data) = @_;
  die("insert existing file $filename")
    if $self->file_exists($filename);
  die("expected TraceInfo got '" . ref($data) . "'")
    unless (ref($data) eq 'TraceInfo');
  $self->{_data}->{$filename} = $data;
}

sub append_tracefile {
  my $self = shift;
  my $trace = shift;

  foreach my $filename ($trace->files()) {
    if (defined($self->{_data}->{$filename})) {
      $self->data($filename)->merge($trace->data($filename), $filename);
    } else {
      $self->{_data}->{$filename} = $trace->data($filename);
    }
  }
  return $self;
}

sub is_rtl_file {
  my $filename = shift;
  return $filename =~ /\.(v|sv|vhdl?)$/;
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
#        "sumfnc"  -> \%sumfnccount
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
# %sumfnccount : function name -> execution count for all tests
# %sumbrcount  : line number   -> branch coverage data for all tests
# %funcdata    : function name -> line number
# %checkdata   : line number   -> checksum of source code line
# $brdata      : vector of items: block, branch, taken
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
sub _read_info {
  my ($self, $tracefile, $readSourceCallback) = @_;

  if (! defined($readSourceCallback)) {
    $readSourceCallback = ReadCurrentSource->new();
  }

  my $testdata;                   #       "             "
  my $testcount;                  #       "             "
  my $sumcount;                   #       "             "
  my $funcdata;                   #       "             "
  my $checkdata;                  #       "             "
  my $testfncdata;
  my $testfnccount;
  my $sumfnccount;
  my $testbrdata;
  my $testbrcount;
  my $sumbrcount;
  my $line;              # Current line read from .info file
  my $testname;          # Current test name
  my $filename;          # Current filename
  my $hitcount;          # Count for lines hit
  my $count;             # Execution count of current line
  my $negative;          # If set, warn about negative counts
  my $changed_testname;  # If set, warn about changed testname
  my $line_checksum;     # Checksum of current line
  my $notified_about_relative_paths;
  local *INFO_HANDLE;    # Filehandle for .info file

  lcovutil::info("Reading data file $tracefile\n");

  # Check if file exists and is readable
  stat($tracefile);
  if (!(-r _))
  {
    die("ERROR: cannot read file $tracefile!\n");
  }

  # Check if this is really a plain file
  if (!(-f _))
  {
    die("ERROR: not a plain file: $tracefile!\n");
  }

  # Check for .gz extension
  if ($tracefile =~ /\.gz$/)
  {
    # Check for availability of GZIP tool
    lcovutil::system_no_output(1, "gunzip" ,"-h")
      and die("ERROR: gunzip command not available!\n");

    # Check integrity of compressed file
    lcovutil::system_no_output(1, "gunzip", "-t", $tracefile)
      and die("ERROR: integrity check failed for compressed file "
              . $tracefile . "!\n");

    # Open compressed file
    open(INFO_HANDLE, "-|", "gunzip -c '$tracefile'")
      or die("ERROR: cannot start gunzip to decompress file $tracefile!\n");
  }
  else
  {
    # Open decompressed file
    open(INFO_HANDLE, "<", $tracefile)
      or die("ERROR: cannot read file $tracefile!\n");
  }

  $testname = "";
  my $data;
  # HGC:  somewhat of a hack.
  # There are duplicate lines in the geninfo output result - for example,
  #   line '2095' may have multiple DA (line) entries, and may have multiple
  #   'BRDA' entries - each with a different number of branches and different
  #   count
  # The hack is to put branches into a hash keyed by branch ID - and
  #   merge elements with the same key if we run into them in the multiple
  #   times in the same 'file' data (within an SF entry).
  my %branchRenumber; # line -> block -> branch -> branchentry
  my ($currentBranchLine, $skipBranch);
  my %functionData; # "file:line" -> [file, line, count, {name -> count}]
  my %functionAlias; # name -> functionDataElement
  while (<INFO_HANDLE>)
  {
    chomp($_);
    $line = $_;

    # Switch statement
    foreach ($line)
    {
      /^TN:([^,]*)(,diff)?/ && do
      {
        # Test name information found
        $testname = defined($1) ? $1 : "";
        my $orig = $testname;
        if ($testname =~ s/\W/_/g)
        {
          $changed_testname = $orig;
        }
        $testname .= $2 if (defined($2));
        last;
      };

      /^[SK]F:(.*)/ && do
      {
        # Filename information found
        # Retrieve data for new entry
        $filename = File::Spec->rel2abs($1, $main::cwd);

        if (!File::Spec->file_name_is_absolute($1) &&
            !$notified_about_relative_paths)
        {
          lcovutil::info("Resolved relative source file ".
                         "path \"$1\" with CWD to ".
                         "\"$filename\".\n");
          $notified_about_relative_paths = 1;
        }

        %branchRenumber = ();

        if (defined($lcovutil::cov_filter[$lcovutil::FILTER_BRANCH_NO_COND]) ||
            defined($lcovutil::cov_filter[$lcovutil::FILTER_LINE_CLOSE_BRACE])) {
          # unconditionally 'close' the current file - in case we don't
          #   open a new one.  If that happened, then we would be looking
          #   at the source for some previous file.
          $readSourceCallback->close();
          undef $currentBranchLine;
          if ($filename =~ /\.(c|h|i||C|H|I|icc|cpp|cc|cxx|hh|hpp|hxx|H)$/) {
            $readSourceCallback->open($filename);
          }
        }
        $data = $self->data($filename);
        ($testdata, $sumcount, $funcdata, $checkdata, $testfncdata,
         $sumfnccount, $testbrdata, $sumbrcount) =
             $data->get_info();

        if (defined($testname))
        {
          $testcount = $data->test($testname);
          $testfnccount = $data->testfnc($testname);
          $testbrcount = $data->testbr($testname);
        }
        else
        {
          $testcount = CountData->new(1);
          $testfnccount = CountData->new(0);
          $testbrcount = BranchData->new();
        }
        last;
      };

      /^DA:(\d+),(-?\d+)(,[^,\s]+)?/ && do
      {
        my ($line, $count, $checksum) = ($1,$2,$3);
        # Fix negative counts
        if ($count < 0)
        {
          $count = 0;
          $negative = 1;
        }
        my $linesum = $data->sum();
        my $histogram = $lcovutil::cov_filter[$lcovutil::FILTER_LINE_CLOSE_BRACE];
        if (defined($histogram) &&
            $readSourceCallback->notEmpty()) {
          # does this line contain only a closing brace and
          #   - previous line is hit, OR
          #   - previous line is not an open-brace which has no associated
          #     count - i.e., this is not an empty block where the zero
          #     count is tagged to the closing brace.
          if ($readSourceCallback->isCharacter($line, '}')) {

            my $suppress = 0;
            for (my $prevLine = $line - 1 ; $prevLine >= 0 ; -- $prevLine) {
              my $prev = $linesum->value($prevLine);
              if (defined($prev)) {
                # previous line was executable
                $suppress = 1
                  if ($prev == $count ||
                      ($count == 0 &&
                       $prev > 0));
                last;
              } elsif ($count == 0 &&
                       # previous line not executable - was it an open brace?
                       $readSourceCallback->isCharacter($prevLine, '{')) {
                # look 'up' from the open brace to find the first
                #   line which has an associated count -
                my $code = "";
                for (my $l = $prevLine - 1 ; $l >= 0 ; -- $l) {
                  $code = $readSourceCallback->getLine($l) . $code;
                  my $prevCount = $linesum->value($l);
                  if (defined($prevCount)) {
                    # don't suppress if previous line not hit either
                    last
                      if $prevCount == 0;
                    # if first non-whitespace character is a colon -
                    #  then this looks like a C++ initialization list.
                    #  suppress.
                    if ( $code =~ /^\s*:(\s|[^:])/ ) {
                      $suppress = 1;
                    } else {
                      $code = lcovutil::filterStringsAndComments($code);
                      $code = lcovutil::simplifyCode($code);
                      # don't suppress if this looks like a conditional
                      $suppress = 1
                        unless ($code =~ /\b(if|switch|case|while|for)\b/);
                    }
                    last;
                  }
                } # for each prior line (looking for statement before block)
                last;
              } # if (line was an open brace
            } # for each prior line (looking for open brace)
            if ($suppress) {
              main::verbose("skip DA '" . $readSourceCallback->getLine($line)
                            . "' $filename:$line\n");
              ++ $histogram->[0]; # one location where this applied
              ++ $histogram->[1]; # one coverpoint suppressed
              last;
            }
          }
        }
        # Execution count found, add to structure
        # Add summary counts
        $linesum->append($line, $count);

        # Add test-specific counts
        if (defined($testname))
        {
          $data->test($testname)->append($line, $count);
        }

        # Store line checksum if available
        if (defined($checksum))
        {
          $line_checksum = substr($checksum, 1);

          # Does it match a previous definition
          if ($data->check()->mapped($1) &&
              ($data->check()->value($1) ne
               $line_checksum))
          {
            die("ERROR: checksum mismatch ".
                "at $filename:$1\n");
          }

          $data->check()->replace($line, $line_checksum);
        }
        last;
      };

      /^FN:(\d+),([^,]+)/ && do
      {
        last if (!$main::func_coverage);
        # Function data found, add to structure
        my $lineNo = $1;
        my $fnName = $2;

        # want to keep a list of all the functions/all the function aliases
        #  at a particular line in the file.  THey must all be the
        #  same function - perhaps just templatized differently.
        if (defined($lcovutil::cov_filter[$lcovutil::FILTER_FUNCTION_ALIAS])) {
          !defined($functionAlias{$fnName})
            or die("found duplicate function $fnName");
          my $key = $filename . ':' . $lineNo;
          $functionData{$key} = [$filename, $lineNo, 0, {}]
            unless exists($functionData{$key});
          my $data = $functionData{$key};
          $data->[3]->{$fnName} = 0;
          $functionAlias{$fnName} = $data;
        } else {
          $data->func()->replace($fnName, $lineNo);

          # Also initialize function call data
          $data->sumfnc()->append($fnName, 0);
          $data->testfnc($testname)->append($fnName, 0)
            if (defined($testname));
        }
        last;
      };

      /^FNDA:(\d+),([^,]+)/ && do
      {
        last if (!$main::func_coverage);
        my $fnName = $2;
        my $hit = $1;

        if (defined($lcovutil::cov_filter[$lcovutil::FILTER_FUNCTION_ALIAS])) {
          my $data = $functionAlias{$fnName};
          $data->[2] += $hit;
          $data->[3]->{$fnName} += $hit;
        } else {
          # Function call count found, add to structure
          # Add summary counts
          $data->sumfnc()->append($fnName, $hit);

          # Add test-specific counts
          $data->testfnc($testname)->append($fnName, $hit)
            if (defined($testname));
        }
        last;
      };

      /^BRDA:(\d+),(\d+),(.+)$/ && do {
        last if (!$main::br_coverage);

        # Branch coverage data found
        # line data is "lineNo,blockId,(branchIdx|branchExpr),taken
        #   - so grab the last two elements, split on the last comma,
        #     and check whether we found an integer or an expression
        my ($line, $block, $d) = ($1, $2, $3);
        my $comma = rindex($d, ',');
        my $taken = substr($d, $comma + 1);
        my $expr = substr($d, 0, $comma);

        my $histogram = $lcovutil::cov_filter[$lcovutil::FILTER_BRANCH_NO_COND];
        if (defined($histogram) &&
            $readSourceCallback->notEmpty()) {
          # look though source the first time we see the line -
          #   skip branches defined here if it seems to contain no
          #   conditionals
          if (! defined($currentBranchLine) ||
              $currentBranchLine != $line) {
            $currentBranchLine = $line;
            $skipBranch = ! $readSourceCallback->containsConditional($line);
            if ($skipBranch) {
              lcovutil::verbose("skip BRDA '" .
                                $readSourceCallback->getLine($line) .
                                "' $filename:$line\n");
              ++ $histogram->[0]; # one location where filter applied
            }
          }
          if ($skipBranch) {
            ++ $histogram->[1]; # one coverpoint suppressed
            last;
          }
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

        if ( is_rtl_file($filename) ) {
          # Verilog/SystemVerilog/VHDL
          my $key = "$line,$block";
          my $branch = exists($branchRenumber{$key}) ? $branchRenumber{$key} : 0;
          $branchRenumber{$key} = $branch + 1;

          my $br = BranchBlock->new($branch, $taken, $expr);
          $data->sumbr()->append($line, $block, $br);

          # Add test-specific counts
          if (defined($testname)) {
            #$testbrcount->{$line} .=  "$block,$branch,$taken:";
            $data->testbr($testname)->append($line, $block, $br);
          }
        } else {
          # not an HDL file
          $branchRenumber{$line} = {}
            unless exists($branchRenumber{$line});
          $branchRenumber{$line}->{$block} = {}
            unless exists($branchRenumber{$line}->{$block});
          my $table = $branchRenumber{$line}->{$block};

          my $entry = BranchBlock->new($expr, $taken, $expr);
          if (exists($table->{$expr})) {
             # merge
             $table->{$expr}->merge($entry);
          } else {
            $table->{$expr} = $entry;
          }
        }
        last;
      };

      /^end_of_record/ && do
      {
        # Found end of section marker
        if ($filename) {
          if (! is_rtl_file($filename)) {
            # RTL code was added directly - no issue with duplicate
            #  data entries in geninfo result
            foreach my $line (sort {$a <=> $b} keys(%branchRenumber)) {
              my $l_data = $branchRenumber{$line};
              foreach my $block (sort {$a <=> $b} keys(%$l_data)) {
                my $bdata = $l_data->{$block};
                my $branchId = 0;
                foreach my $b_id (sort {$a <=> $b} keys(%$bdata)) {
                  my $br = $bdata->{$b_id};
                  my $b = BranchBlock->new($branchId, $br->data());
                  $data->sumbr()->append($line, $block, $b);

                  if (defined($testname)) {
                    #$testbrcount->{$line} .=  "$block,$branch,$taken:";
                    $data->testbr($testname)->append($line, $block, $b);
                  }
                  ++ $branchId;
                }
              }
            }
          } # end "if (! rtl)"
          if (defined($lcovutil::cov_filter[$lcovutil::FILTER_FUNCTION_ALIAS])) {
            my $histogram = $lcovutil::cov_filter[$lcovutil::FILTER_FUNCTION_ALIAS];
            for my $key (keys(%functionData)) {
              my ($fileName, $lineNo, $hit, $aliases) = @{$functionData{$key}};
              ++$histogram->[0];
              # pick the shortest name...
              my $name = "";
              my $len = 1000000;
              foreach my $alias (keys(%$aliases)) {
                ++$histogram->[1];
                my $l = length($alias);
                if ($l < $len) {
                  $len = $l;
                  $name = $alias;
                }
              }
              $data->func()->replace($name, $lineNo);
              $data->sumfnc()->append($name, $hit);
              $data->testfnc($testname)->append($name, $hit)
                if defined($testname);
            }
            %functionAlias = ();
            %functionData = ();
          }
          # Store current section data
          if (defined($testname))
          {
            $testdata->{$testname} = $testcount;
            $testfncdata->{$testname} = $testfnccount;
            $testbrdata->{$testname} = $testbrcount;
          }

          $self->data($filename)->set_info($testdata, $sumcount, $funcdata,
                                           $checkdata, $testfncdata,
                                           $sumfnccount, $testbrdata,
                                           $sumbrcount);
          # $result{$filename} = $data;
          last;
        }
      };

      # default
      last;
    }
  }
  close(INFO_HANDLE);

  # Calculate lines_found and lines_hit for each file
  foreach $filename ($self->files())
  {
    #$data = $result{$filename};

    ($testdata, $sumcount, undef, undef, $testfncdata,
     $sumfnccount, $testbrdata, $sumbrcount) =
      $self->data($filename)->get_info();

    # Filter out empty files
    if ($self->data($filename)->sum()->entries() == 0)
    {
      delete($self->{_data}->{$filename});
      next;
    }
    # Filter out empty test cases
    foreach $testname ($self->data($filename)->test()->keylist())
    {
      if (!$self->data($filename)->test()->mapped($testname) ||
          scalar($self->data($filename)->test($testname)->keylist()) == 0)
      {
        $self->data($filename)->test()->remove($testname);
        $self->data($filename)->testfnc()->remove($testname);
      }
    }

    next;

    $self->data($filename)->{_found} = scalar(keys(%{$self->data($filename)->{_sumcount}}));
    $hitcount = 0;

    foreach (keys(%{$self->data($filename)->{_sumcount}}))
    {
      if ($self->data($filename)->{_sumcount}->{$_} > 0) { $hitcount++; }
    }

    $self->data($filename)->{_hit} = $hitcount;

    # Get found/hit values for function call data
    $data->{_f_found} = scalar(keys(%{$self->data($filename)->{_sumfnccount}}));
    $hitcount = 0;

    foreach (keys(%{$self->data($filename)->{_sumfnccount}})) {
      if ($self->data($filename)->{_sumfnccount}->{$_} > 0) {
        $hitcount++;
      }
    }
    $self->data($filename)->{_f_hit} = $hitcount;

    # Combine branch data for the same branches
    (undef, $self->data($filename)->{_b_found}, $self->data($filename)->{_b_hit}) =
      compress_brcount($self->data($filename)->{_sumbrcount});
    foreach $testname (keys(%{$self->data($filename)->{_testbrdata}})) {
      compress_brcount($self->data($filename)->{_testbrdata}->{$testname});
    }
  }

  if (scalar(keys(%{$self->{_data}})) == 0)
  {
    ignorable_error($lcovutil::ERROR_EMPTY,
                    "no valid records found in tracefile $tracefile\n");
  }
  if ($negative)
  {
    warn("WARNING: negative counts found in tracefile ".
         "$tracefile\n");
  }
  if (defined($changed_testname))
  {
    warn("WARNING: invalid characters removed from testname in ".
         "tracefile $tracefile: '$changed_testname'->'$testname'\n");
  }
}

#
# write data in .info format
#
sub write_info($$$) {
  my $self = $_[0];
  local *INFO_HANDLE = $_[1];
  my $checksum = defined($_[2]) ? $_[2] : 0;
  my $br_found;
  my $br_hit;
  my $ln_total_found = 0;
  my $ln_total_hit = 0;
  my $fn_total_found = 0;
  my $fn_total_hit = 0;
  my $br_total_found = 0;
  my $br_total_hit = 0;

  my $srcReader = ReadCurrentSource->new()
    if (defined($cov_filter[$FILTER_LINE_CLOSE_BRACE]) ||
        defined($cov_filter[$FILTER_BRANCH_NO_COND]));

  foreach my $source_file (sort($self->files())) {
    next if lcovutil::is_external($source_file);
    my $entry = $self->data($source_file);
    die("expected TraceInfo, got '" . ref($entry) . "'")
      unless('TraceInfo' eq ref($entry));

    my ($testdata, $sumcount, $funcdata, $checkdata, $testfncdata,
        $sumfnccount, $testbrdata, $sumbrcount, $found, $hit,
        $f_found, $f_hit, $br_found, $br_hit) = $entry->get_info();

    # Add to totals
    $ln_total_found += $found;
    $ln_total_hit += $hit;
    $fn_total_found += $f_found;
    $fn_total_hit += $f_hit;
    $br_total_found += $br_found;
    $br_total_hit += $br_hit;

    foreach my $testname (sort($testdata->keylist())) {
      my $testcount = $testdata->value($testname);
      my $testfnccount = $testfncdata->value($testname);
      my $testbrcount = $testbrdata->value($testname);
      $found = 0;
      $hit   = 0;

      print(INFO_HANDLE "TN:$testname\n");
      print(INFO_HANDLE "SF:$source_file\n");
      if (defined($srcReader)) {
        $srcReader->close();
        if ($source_file =~ /\.(c|h|i||C|H|I|icc|cpp|cc|cxx|hh|hpp|hxx|H)$/) {
          lcovutil::debug("reading $source_file for lcov filtering\n");
          $srcReader->open($source_file);
        } else {
          lcovutil::debug("not reading $source_file: no ext match\n");
        }
      }

      # Write function related data - sort  by line number
      foreach my $func ( sort({$funcdata->value($a) <=> $funcdata->value($b)}
                              $funcdata->keylist())) {
        print(INFO_HANDLE "FN:".$funcdata->value($func). ",$func\n");
      }
      foreach my $func ($testfnccount->keylist()) {
        print(INFO_HANDLE "FNDA:".
              $testfnccount->value($func).
              ",$func\n");
      }
      my ($f_found, $f_hit) = $testfnccount->get_found_and_hit();
      print(INFO_HANDLE "FNF:$f_found\n");
      print(INFO_HANDLE "FNH:$f_hit\n");

      # Write branch related data
      $br_found = 0;
      $br_hit = 0;
      my $currentBranchLine;
      my $skipBranch = 0;
      my $branchHistogram = $cov_filter[$FILTER_BRANCH_NO_COND]
        if (defined($srcReader) && $srcReader->notEmpty());
      foreach my $line (sort({$a <=> $b}
                             $testbrcount->keylist())) {

        my $brdata = $testbrcount->value($line);
        if (defined($branchHistogram)) {
          $skipBranch = ! $srcReader->containsConditional($line);
          if ($skipBranch) {
            ++ $branchHistogram->[0]; # one line where we skip
            $branchHistogram->[1] += scalar($brdata->blocks());
            lcovutil::verbose("skip BRDA '" .
                              $srcReader->getLine($line) .
                              "' $source_file:$line\n");
            next;
          }
        }
        # want the block_id to be treated as 32-bit unsigned integer
        #  (need masking to match regression tests)
        my $mask =  (1<<32) -1;
        foreach my $block_id ($brdata->blocks()) {
          my $blockData = $brdata->getBlock($block_id);
          $block_id &= $mask;
          foreach my $br (@$blockData) {
            my $taken = $br->data();
            my $branch_id = $br->id();
            my $branch_expr = $br->expr();
            # mostly for Verilog:  if there is a branch expression: use it.
            printf(INFO_HANDLE "BRDA:%u,%u,%s,%s\n",
                   $line, $block_id,
                   defined($branch_expr) ? $branch_expr : $branch_id, $taken);
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

      # Write line related data
      my $lineHistogram = $cov_filter[$FILTER_LINE_CLOSE_BRACE]
        if (defined($srcReader) && $srcReader->notEmpty());
      my $prevCount;
      my $prevIsOpenBrace = 0;
      foreach my $line (sort({$a <=> $b} $testcount->keylist())) {
        my $l_hit = $testcount->value($line);
        if (defined($lineHistogram)) {
          if ($srcReader->isCharacter($line, '}')) {
            if ( (defined($prevCount) &&
                  $prevCount == $l_hit) ||
                 ($prevIsOpenBrace &&
                  0 == $l_hit) ) {
              lcovutil::verbose("skip DA '" . $srcReader->getLine($line)
                                . "' $source_file:$line\n");
              ++$lineHistogram->[0]; # one location where this applied
              ++$lineHistogram->[1]; # one coverpoint suppressed
              $prevIsOpenBrace = 0;
              next;
            }
          }
          $prevCount = $l_hit;
          $prevIsOpenBrace = $srcReader->isCharacter($line, '{')
            if ! $srcReader->isBlank($line);
        }
        my $chk = $checkdata->{$line};
        print(INFO_HANDLE "DA:$line,$l_hit" .
              (defined($chk) && $checksum ? ",". $chk : "")
              ."\n");
        $found++;
        $hit++
          if ($l_hit > 0);
      }
      print(INFO_HANDLE "LF:$found\n");
      print(INFO_HANDLE "LH:$hit\n");
      print(INFO_HANDLE "end_of_record\n");
    }
  }

  return ($ln_total_found, $ln_total_hit, $fn_total_found, $fn_total_hit,
          $br_total_found, $br_total_hit);
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
