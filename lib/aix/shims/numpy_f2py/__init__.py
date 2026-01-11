"""
numpy.f2py stub for AIX.
========================

f2py (Fortran to Python interface generator) is not available on AIX.
This stub prevents import errors when packages check for f2py availability.

f2py is typically only needed at build time for Fortran extensions,
not at runtime for pure Python usage.
"""

__version__ = "2.0.0"

def compile(*args, **kwargs):
    """f2py compile is not available on AIX."""
    raise NotImplementedError(
        "f2py is not available on AIX. "
        "Fortran extension compilation is not supported."
    )

def run_main(*args, **kwargs):
    """f2py run_main is not available on AIX."""
    raise NotImplementedError(
        "f2py is not available on AIX. "
        "Fortran extension compilation is not supported."
    )

def get_include():
    """Return empty include path."""
    return ""
