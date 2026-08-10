#   Copyright (c) MediaTek USA Inc., 2026
#
#   This program is free software;  you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation; either version 2 of the License, or (at
#   your option) any later version.
#
#   This program is distributed in the hope that it will be useful, but
#   WITHOUT ANY WARRANTY;  without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#   General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program;  if not, see
#   <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Config;
use Cwd;
use File::Basename;
use File::Spec;
use File::Temp;
use FindBin;
use ExtUtils::MakeMaker;

my $cov_flags = '';
my $define = '';
my @objects = ('LcovUtil.o');

# The C++ compiler to build the extension with.  Overridable so a caller can
# point the build at a specific toolchain (see the CXX/LCOV_CXX handling below).
my $cxx = $ENV{LCOV_CXX} || $ENV{CXX} || 'g++';

# ---------------------------------------------------------------------------
# Derive lcov error-code constants from the canonical source (lcovutil.pm).
#
# The C++ implementation needs a handful of numeric error codes (e.g.
# ERROR_MISMATCH) that must agree with the ids lcovutil.pm assigns from its
# @lcovErrs array.  Those ids are positional, so hard-coding them in C++ is
# fragile: reordering @lcovErrs would silently desync the two.  Instead, load
# lcovutil.pm here, let it assign the ids, and emit one -DLCOV_ERROR_<NAME>=<id>
# define per error so the C++ code compiles against the real values.
# ---------------------------------------------------------------------------
{
    my $lib_dir = File::Spec->catdir($FindBin::Bin, File::Spec->updir());
    local @INC = ($lib_dir, @INC);
    # lcovutil.pm computes $VERSION by running "$tool_dir"/get_version.sh, where
    # $tool_dir is $FindBin::RealBin -- which is this directory when it is loaded
    # from here rather than from a tool in bin/.  Point it at the real bin/ so
    # the backtick finds the script instead of printing a spurious
    # 'get_version.sh: No such file or directory' on every Makefile.PL run.  We
    # only want the error ids, but a bare require is enough to trigger it.
    local $FindBin::RealBin = File::Spec->catdir($FindBin::Bin, File::Spec->updir(),
                                                File::Spec->updir(), 'bin');
    my %error_id;
    my $ok = eval {
        require lcovutil;
        lcovutil::define_errors();          # populate %lcovutil::ERROR_ID
        no warnings 'once';
        %error_id = %lcovutil::ERROR_ID;
        1;
    };
    if ($ok && %error_id) {
        foreach my $name (sort keys %error_id) {
            (my $macro = uc($name)) =~ s/[^A-Z0-9_]/_/g;
            $define .= " -DLCOV_ERROR_$macro=" . int($error_id{$name});
        }
    } else {
        # The C++ sources #error out when these ids are missing rather than
        # guessing, so there is no point generating a Makefile that cannot build.
        die "Makefile.PL: could not load lcovutil.pm to derive error ids" .
            ($@ ? " ($@)" : "") . "\n";
    }
}

# ---------------------------------------------------------------------------
# Pick the -std flag, and fail loudly if the compiler cannot supply one.
#
# The sources need C++17 (std::optional, structured bindings); C++20 is what we
# build and test with.  Neither the flag spelling nor the availability is
# uniform: gcc names the C++20 mode '-std=c++2a' before gcc 10 and '-std=c++20'
# from gcc 10 on, and gcc before 8 has no C++20 mode at all.
#
# Getting this wrong is expensive to diagnose, because a failed extension build
# is not a failed run:  lcovutil.pm silently falls back to pure Perl when the
# library is missing, so the only symptom is a report that took several times
# longer to produce.  A bare '-std=c++20' handed to an older g++ yields
# "unrecognized command line option '-std=c++20'; did you mean '-std=c++03'?",
# which points at the standard rather than at the real problem -- the wrong
# compiler is on PATH.  So name the compiler and the requirement here instead.
# ---------------------------------------------------------------------------
my $cxx_version = `$cxx --version 2>/dev/null`;
my ($cxx_major) = $cxx_version =~ /(\d+)\.\d+\.\d+/;
my $std_flag;
if (!defined($cxx_major)) {
    # Unknown compiler:  assume it is current enough to know the modern
    # spelling rather than refusing to build for a vendor we cannot parse.
    $std_flag = '-std=c++20';
} elsif ($cxx_major >= 10) {
    $std_flag = '-std=c++20';
} elsif ($cxx_major >= 8) {
    $std_flag = '-std=c++2a';
} else {
    die <<"END_MSG";
Makefile.PL: '$cxx' is too old to build the lcov XS extension.
  found:    @{[ (split /\n/, $cxx_version)[0] || 'unknown version' ]}
  required: g++ 8 or later (C++20); g++ 14 or later is recommended
Set CXX (or LCOV_CXX) to a newer compiler, put one on PATH, or build with
LCOV_NO_XS=1 to skip the extension and use the pure-Perl implementation.
END_MSG
}

# ---------------------------------------------------------------------------
# Make the extension independent of whichever C++ runtime is on the library
# search path when it is loaded.
#
# The extension is built once, by one compiler, but it has to load into
# whichever perl process the user runs - and that process may well have an
# older toolchain's libstdc++ ahead of ours on the runtime search path.  An
# environment-modules setup makes that the normal case rather than the
# exception: 'module load gcc/9' puts gcc/9's lib64 on LD_LIBRARY_PATH, and a
# shared object built by gcc/16 then fails to load with
#     version `GLIBCXX_3.4.31' not found (required by .../LcovUtil.so)
# libstdc++ is backward compatible, not forward compatible, so an older library
# cannot satisfy a newer object.  And because both lcovutil.pm and LcovUtil.pm
# fall back to pure Perl when the load fails, the only symptom is a run that is
# several times slower than it should be.
#
# Two things fix that, in order of preference:
#
#  1. -static-libstdc++.  The dependency simply goes away: what is left is
#     libgcc_s (needed at no more than GCC_4.2.0, which every gcc since 4.2
#     provides), libm and libc, so the object loads under any toolchain.  The
#     cost is roughly 1.5MB of text - cheap next to a silent fallback to pure
#     Perl.  Preferred because the result does not care whether the toolchain
#     which built it is still installed.
#
#  2. Failing that, an rpath naming the directory this compiler's libstdc++
#     came from - but it has to be DT_RPATH, not DT_RUNPATH.  Modern ld emits
#     DT_RUNPATH by default, and the loader searches DT_RUNPATH *after*
#     LD_LIBRARY_PATH, so precisely the module setup which creates the problem
#     would also defeat the fix.  DT_RPATH is searched *before*
#     LD_LIBRARY_PATH, so it wins; '--disable-new-dtags' is what asks for the
#     older tag.  This keeps the object small, and it is the answer when no
#     static C++ library is installed - several distributions ship libstdc++.a
#     in a separate package, or not at all.  The cost is that the built object
#     now depends on the build toolchain staying where it is; if that directory
#     goes away the loader falls through to its normal search, which is to say
#     back to the behaviour above.
#
# Do not extend this to -static-libgcc: a statically linked libgcc breaks
# exception propagation across shared-object boundaries, and GCC_4.2.0 is
# satisfied everywhere, so there would be nothing to gain.
#
# All of it is probed rather than assumed - the flags, the archive and the
# runtime directory all vary between platforms and compilers - and a trial link
# is the only honest test of whether this compiler accepts a flag.
# ---------------------------------------------------------------------------
my $cxx_runtime_flags = '';
{
    my $tmpdir = File::Temp::tempdir(CLEANUP => 1);
    my $src    = File::Spec->catfile($tmpdir, 'probe.cpp');
    my $out    = File::Spec->catfile($tmpdir, 'probe.so');
    open(my $probe, '>', $src) or
        die "Makefile.PL: cannot write $src: $!\n";
    print($probe "extern \"C\" int lcov_probe() { return 0; }\n");
    close($probe);

    # True when $cxx can build a shared object with these extra flags.
    my $can_link = sub {
        my $flags = shift;
        my $rc    = system("$cxx -shared -fPIC $src -o $out $flags >/dev/null 2>&1");
        unlink($out);
        return 0 == $rc;
    };

    # The full path of the first of these libraries which $cxx can find.
    # -print-file-name echoes its argument back unchanged when the compiler
    # cannot find the library, so require an answer which names a file that
    # really exists.
    my $find_lib = sub {
        foreach my $lib (@_) {
            my $path = `$cxx -print-file-name=$lib 2>/dev/null`;
            next if $?;
            chomp($path);
            next unless $path && $path ne $lib && -f $path;
            return $path;
        }
        return undef;
    };

    # Look for libc++ as well as libstdc++: clang spells the option the same
    # way but may be using libc++ instead, in which case that is the library to
    # ask about.
    if ($find_lib->('libstdc++.a', 'libc++.a') &&
        $can_link->('-static-libstdc++')) {
        $cxx_runtime_flags = ' -static-libstdc++';
    } else {
        # Name the versioned file rather than the 'libstdc++.so' link: that
        # link is sometimes a linker script living somewhere other than the
        # runtime library it names, and it is the runtime library's directory
        # which has to go into the rpath.
        my $runtime = $find_lib->('libstdc++.so.6', 'libc++.so.1');
        my $dir     = defined($runtime) ?
            Cwd::abs_path(File::Basename::dirname($runtime)) : undef;
        my $rpath = defined($dir) ? "-Wl,--disable-new-dtags,-rpath,$dir" : undef;
        if (defined($rpath) && $can_link->($rpath)) {
            $cxx_runtime_flags = " $rpath";
            print <<"END_MSG";
Makefile.PL: no static C++ library for '$cxx'; using an rpath instead.
The extension will look for its C++ runtime in
    $dir
before anything named by LD_LIBRARY_PATH.  Moving or removing that directory
stops the extension loading, and lcov then falls back to the (much slower)
pure-Perl implementation without saying so.
END_MSG
        } else {
            warn <<"END_MSG";
Makefile.PL: cannot make the extension independent of the C++ runtime with
'$cxx':  neither a static C++ library nor a usable rpath is available.
The extension will fail to load under any toolchain whose C++ runtime is older
than this one, and lcov will then fall back to the (much slower) pure-Perl
implementation without saying so.  Building with a toolchain no newer than the
one lcov will run under avoids that.
END_MSG
        }
    }
}

if ($ENV{COVERAGE}) {
    # enable MC/DC if gcc >= 14
    $cov_flags = ' --coverage';
    if (defined($cxx_major) && $cxx_major >= 14) {
        $cov_flags .= ' -fcondition-coverage';
    }
    # For coverage measurement, compile methods out-of-line in separate .cpp files
    push @objects, 'BranchData.o', 'MCDCData.o';
} else {
    # For normal XS build, use inline methods
    $define .= ' -DLCOV_XS_INLINE';
}

WriteMakefile(
    NAME          => 'LcovUtil',
    VERSION_FROM  => 'LcovUtil.pm',
    ABSTRACT      => 'C++ accelerated MapData and CountData for lcov',
    LIBS          => [''],
    DEFINE        => $define,
    INC           => '-I.',
    OBJECT        => join(' ', @objects),
    XSOPT         => '-C++',
    CC            => $cxx,
    LD            => $cxx,
    CCFLAGS       => "$std_flag -O2" . $cov_flags,
    LDDLFLAGS     => $Config{lddlflags} . $cov_flags . $cxx_runtime_flags,
    clean         => { FILES => 'LcovUtil.c *.gcno *.gcda *.o *.gcov' },
);
