"""
Pure Python R-tree implementation for AIX.
Simple but functional spatial index using brute-force search.
"""
from typing import Iterator, Optional, Tuple, Any, List, Union


class Property:
    """Properties for the R-tree index (API compatibility)."""

    def __init__(self):
        self.dimension = 2
        self.leaf_capacity = 100
        self.index_capacity = 100
        self.near_minimum_overlap_factor = 32
        self.fill_factor = 0.7
        self.split_distribution_factor = 0.4
        self.reinsert_factor = 0.3
        self.tight_mbr = True
        self.overwrite = True
        self.buffering_capacity = 10
        self.pagesize = 4096
        self.index_pool_capacity = 100
        self.point_pool_capacity = 500
        self.region_pool_capacity = 1000
        self.index_id = None
        self.dat_extension = 'dat'
        self.idx_extension = 'idx'


class Index:
    """
    Simple R-tree index implementation using linear search.

    Not as efficient as libspatialindex but works without native dependencies.
    Suitable for document processing where item counts are manageable.
    """

    def __init__(self, *args, properties: Optional[Property] = None, **kwargs):
        self._items: List[Tuple[int, Tuple[float, ...], Any]] = []
        self.properties = properties or Property()
        self.interleaved = kwargs.get('interleaved', True)

    def insert(self, id: int, coordinates: Tuple[float, ...], obj: Any = None):
        """
        Insert an item with bounding box coordinates.

        Args:
            id: Unique identifier for the item
            coordinates: Bounding box (minx, miny, maxx, maxy) if interleaved=True
                        or (minx, maxx, miny, maxy) if interleaved=False
            obj: Optional object to store with the item
        """
        self._items.append((id, coordinates, obj))

    def delete(self, id: int, coordinates: Tuple[float, ...]):
        """Delete an item from the index."""
        self._items = [(i, c, o) for i, c, o in self._items
                       if not (i == id and c == coordinates)]

    def intersection(
        self,
        coordinates: Tuple[float, ...],
        objects: bool = False
    ) -> Iterator[Union[int, Any]]:
        """
        Find all items that intersect with the given bounding box.

        Args:
            coordinates: Query bounding box
            objects: If True, yield stored objects instead of IDs

        Yields:
            Item IDs or objects that intersect the query box
        """
        if self.interleaved:
            qminx, qminy, qmaxx, qmaxy = coordinates[:4]
        else:
            qminx, qmaxx, qminy, qmaxy = coordinates[:4]

        for item_id, item_coords, obj in self._items:
            if self.interleaved:
                iminx, iminy, imaxx, imaxy = item_coords[:4]
            else:
                iminx, imaxx, iminy, imaxy = item_coords[:4]

            # Check for intersection (boxes overlap if no separation exists)
            if not (imaxx < qminx or iminx > qmaxx or
                    imaxy < qminy or iminy > qmaxy):
                if objects:
                    yield obj if obj is not None else item_id
                else:
                    yield item_id

    def nearest(
        self,
        coordinates: Tuple[float, ...],
        num_results: int = 1,
        objects: bool = False
    ) -> Iterator[Union[int, Any]]:
        """
        Find nearest items to the given point or bounding box.

        Args:
            coordinates: Query point or bounding box
            num_results: Maximum number of results to return
            objects: If True, yield stored objects instead of IDs

        Yields:
            Item IDs or objects, ordered by distance
        """
        # Calculate query center point
        if len(coordinates) >= 4:
            if self.interleaved:
                qx = (coordinates[0] + coordinates[2]) / 2
                qy = (coordinates[1] + coordinates[3]) / 2
            else:
                qx = (coordinates[0] + coordinates[1]) / 2
                qy = (coordinates[2] + coordinates[3]) / 2
        else:
            qx, qy = coordinates[0], coordinates[1] if len(coordinates) > 1 else 0

        # Calculate distances and sort
        distances = []
        for item_id, item_coords, obj in self._items:
            if self.interleaved:
                cx = (item_coords[0] + item_coords[2]) / 2
                cy = (item_coords[1] + item_coords[3]) / 2
            else:
                cx = (item_coords[0] + item_coords[1]) / 2
                cy = (item_coords[2] + item_coords[3]) / 2

            dist = ((cx - qx) ** 2 + (cy - qy) ** 2) ** 0.5
            distances.append((dist, item_id, obj))

        distances.sort(key=lambda x: x[0])

        for i, (dist, item_id, obj) in enumerate(distances[:num_results]):
            if objects:
                yield obj if obj is not None else item_id
            else:
                yield item_id

    def contains(
        self,
        coordinates: Tuple[float, ...],
        objects: bool = False
    ) -> Iterator[Union[int, Any]]:
        """
        Find all items that contain the given point or box.

        Args:
            coordinates: Query point or bounding box
            objects: If True, yield stored objects instead of IDs
        """
        if self.interleaved:
            qminx, qminy = coordinates[0], coordinates[1]
            qmaxx = coordinates[2] if len(coordinates) > 2 else qminx
            qmaxy = coordinates[3] if len(coordinates) > 3 else qminy
        else:
            qminx = coordinates[0]
            qmaxx = coordinates[1] if len(coordinates) > 1 else qminx
            qminy = coordinates[2] if len(coordinates) > 2 else 0
            qmaxy = coordinates[3] if len(coordinates) > 3 else qminy

        for item_id, item_coords, obj in self._items:
            if self.interleaved:
                iminx, iminy, imaxx, imaxy = item_coords[:4]
            else:
                iminx, imaxx, iminy, imaxy = item_coords[:4]

            # Check if item contains query box
            if iminx <= qminx and imaxx >= qmaxx and iminy <= qminy and imaxy >= qmaxy:
                if objects:
                    yield obj if obj is not None else item_id
                else:
                    yield item_id

    def count(self, coordinates: Tuple[float, ...]) -> int:
        """Count items intersecting with the given bounding box."""
        return sum(1 for _ in self.intersection(coordinates))

    def bounds(self) -> Optional[Tuple[float, ...]]:
        """Get the bounding box of all items."""
        if not self._items:
            return None

        if self.interleaved:
            minx = min(c[0] for _, c, _ in self._items)
            miny = min(c[1] for _, c, _ in self._items)
            maxx = max(c[2] for _, c, _ in self._items)
            maxy = max(c[3] for _, c, _ in self._items)
            return (minx, miny, maxx, maxy)
        else:
            minx = min(c[0] for _, c, _ in self._items)
            maxx = max(c[1] for _, c, _ in self._items)
            miny = min(c[2] for _, c, _ in self._items)
            maxy = max(c[3] for _, c, _ in self._items)
            return (minx, maxx, miny, maxy)

    def get_bounds(self) -> Optional[Tuple[float, ...]]:
        """Alias for bounds()."""
        return self.bounds()

    def __len__(self) -> int:
        return len(self._items)

    def close(self):
        """Close the index (no-op for in-memory index)."""
        pass

    def flush(self):
        """Flush changes (no-op for in-memory index)."""
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


# Alias for compatibility
Rtree = Index
