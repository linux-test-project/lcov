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

package LcovUtil;

use strict;
use warnings;
use Storable;

our $VERSION   = '1.00';
our $XS_LOADED = 0;
# Why the shared library did not load, or '' if it did (or if it was never
# tried).  See the note below.
our $XS_LOAD_ERROR = '';

# Binary serialization is always used when XS is loaded
# The LCOV_STORABLE_METHOD environment variable has been removed

unless ($ENV{LCOV_PURE_PERL}) {
    eval {
        require XSLoader;
        XSLoader::load('LcovUtil', $VERSION);
        $XS_LOADED = 1;
    };
    # Fall back to pure Perl if XS is not available - but keep the reason.
    # The fallback is deliberately silent (a missing extension is a legitimate
    # configuration, not an error), which means a *broken* extension is silent
    # too: the usual cause is a toolchain mismatch - an older libstdc++ ahead
    # of the one the extension was built against - and the only symptom is a
    # run several times slower than it should be.  Recording the message lets a
    # caller that does care ask which backend it actually got, and why.
    # $@ is '' after an eval which succeeded, so this needs no condition.
    $XS_LOAD_ERROR = $@;
}

# Install binary Storable hooks for CountData when XS is loaded
if ($XS_LOADED) {
    # Check if binary serialization is available
    my $has_binary = CountData->can('serialize_binary') ? 1 : 0;

    if ($has_binary) {
        # Use binary serialization for CountData Storable round-trips
        no warnings 'redefine';

        # Remove STORABLE_attach if it exists (forces Storable to use STORABLE_thaw)
        undef *CountData::STORABLE_attach
            if defined &CountData::STORABLE_attach;

        # Override the XS STORABLE hooks with binary serialization
        # Use STORABLE_freeze/thaw instead of STORABLE_attach
        *CountData::STORABLE_freeze = sub {
            my ($self, $cloning) = @_;
            # Serialize to binary format and return it directly
            my $binary = $self->serialize_binary();
            return $binary;
        };

        *CountData::STORABLE_thaw = sub {
            my ($self, $cloning, $binary) = @_;
            # Deserialize from binary format
            # $self is a blessed reference to a scalar (IV pointer)
            # We need to replace the pointer with the deserialized object's pointer
            my $restored = CountData->deserialize_binary($binary);

            # Get the inner scalars
            # Note: $$self might be undef if this is a fresh object
            my $restored_inner = $$restored;

            # Delete the old C++ object if it exists
            # Use Scalar::Util::looks_like_number to check if it's a valid IV
            if (defined($$self) &&
                Scalar::Util::looks_like_number($$self) &&
                $$self != 0) {
                # There's an old object - it will be freed when we replace the pointer
                # DESTROY will be called on the old pointer value
            }

            # Replace the pointer
            $$self = $restored_inner;
            $$restored =
                0;    # Prevent DESTROY from freeing the transferred object
        };
    }
}

1;
