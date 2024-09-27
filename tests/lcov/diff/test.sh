#!/usr/bin/env bash
#
# Copyright IBM Corp. 2017
#
# Check lcov's diff function:
# - Compile two slightly different test programs
# - Run the programs and collect coverage data
# - Generate a patch containing the difference between the source code
# - Apply the patch to the coverage data
# - Compare the resulting patched coverage data file with the data from the
#   patched source file
#

function die()
{
        echo "Error: $@" >&2
        exit 1
}

KEEP_GOING=0
while [ $# -gt 0 ] ; do

    OPT=$1
    case $OPT in

        --coverage )
            shift
            COVER_DB=$1
            shift

            COVER="perl -MDevel::Cover=-db,${COVER_DB},-coverage,statement,branch,condition,subroutine "
            KEEP_GOING=1

            ;;

        --verbose | -v )
            set -x
            shift
            ;;

        * )
            break
            ;;
    esac
done


make -C old || die "Failed to compile old source"
make -C new || die "Failed to compile new source"
diff -u $PWD/old/prog.c $PWD/new/prog.c > diff

$LCOV --diff old/prog.info diff --convert-filenames -o patched.info -t bla --ignore deprecated || \
        die "Failed to apply patch to coverage data file"
norminfo new/prog.info > new_normalized.info
norminfo patched.info > patched_normalized.info
sed -i -e 's/^TN:.*$/TN:/' patched_normalized.info

diff -u patched_normalized.info new_normalized.info || \
        die "Mismatch in patched coverage data file"

echo "Patched coverage data file matches expected file"
