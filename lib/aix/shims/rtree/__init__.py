"""
rtree shim for AIX - Pure Python implementation without libspatialindex.
=======================================================================

libspatialindex cannot be built on AIX due to TLS linking issues.
This shim provides a pure Python spatial index using simple list operations.

Performance Note:
    This uses O(n) linear search instead of R-tree O(log n).
    Acceptable for document processing (typically < 10K items per page).
    For large-scale spatial queries, consider alternative solutions.

Usage:
    from rtree import index
    idx = index.Index()
    idx.insert(1, (0, 0, 10, 10))
    hits = list(idx.intersection((5, 5, 15, 15)))
"""
from .index import Index, Rtree, Property

__version__ = "1.0.0"
__all__ = ['Index', 'Rtree', 'Property', 'index']

# Compatibility: rtree.index module
class _IndexModule:
    Index = Index
    Rtree = Rtree
    Property = Property

index = _IndexModule()
