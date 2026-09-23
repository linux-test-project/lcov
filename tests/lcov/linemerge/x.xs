#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

# ----------------------------------------------------------------------------
# Alias
# ----------------------------------------------------------------------------

MODULE = X    PACKAGE = Alias

SV*
new(klass, name, count)
    char* klass
    SV* name
    SV* count
  CODE:
    Alias* w = make_alias(intern_sv(name),
                          sv_to_count(count),
                          SvOK(count) ? true : false,
                          false, 0);
    RETVAL = make_alias_sv(w, klass);
  OUTPUT:
    RETVAL
