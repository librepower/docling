# LibrePower Docling Architecture

## Overview

LibrePower Docling provides a unified interface for document AI across multiple platforms, with platform-specific optimizations handled transparently.

```
┌─────────────────────────────────────────────────────────────┐
│                    User Application                         │
│         (Python code using docling APIs)                    │
├─────────────────────────────────────────────────────────────┤
│                   LibrePower Docling                        │
│    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│    │   docling   │  │ transformers│  │   docling   │       │
│    │    core     │  │  tokenizers │  │    parse    │       │
│    └─────────────┘  └─────────────┘  └─────────────┘       │
├─────────────────────────────────────────────────────────────┤
│              Platform Abstraction Layer                     │
│    ┌─────────────┐  ┌─────────────┐  ┌─────────────┐       │
│    │  pypdfium2  │  │    rtree    │  │  numpy/f2py │       │
│    │   (shim)    │  │   (shim)    │  │   (stub)    │       │
│    └─────────────┘  └─────────────┘  └─────────────┘       │
├───────────────────────┬─────────────────────────────────────┤
│        AIX            │           Linux                     │
│  ┌─────────────────┐  │  ┌─────────────────┐               │
│  │   Ghostscript   │  │  │    PDFium       │               │
│  │   XCOFF patch   │  │  │  libspatialindex│               │
│  │   IBM Rust SDK  │  │  │    Standard     │               │
│  └─────────────────┘  │  └─────────────────┘               │
└───────────────────────┴─────────────────────────────────────┘
```

## Platform-Specific Components

### AIX (IBM Power)

#### XCOFF Binary Patching

**Problem**: IBM Rust SDK 1.88 generates XCOFF binaries with invalid loader relocations.

```
Error: "invalid l_rsecnm field 1 for relocation entry"
```

**Root Cause**: The LLVM backend generates R_POS/R_NEG relocation pairs targeting the .text (code) section. AIX loader doesn't support runtime relocations in read-only sections.

**Solution**: Remove relocations with `rsecnm=1` from the loader relocation table.

```python
# patches/patch_xcoff_tokenizers.py
for reloc in relocations:
    if reloc.rsecnm == 1:  # .text section
        remove(reloc)
    else:
        keep(reloc)
update_relocation_count()
```

#### pypdfium2 Shim

**Problem**: PDFium (Chromium's PDF library) cannot be built for AIX.

**Solution**: Ghostscript-based implementation providing the same API:

```python
# shims/pypdfium2/__init__.py
class PdfPage:
    def render(self, scale=1.0):
        # Use Ghostscript subprocess
        cmd = ["gs", "-sDEVICE=png16m", f"-r{72*scale}", ...]
        subprocess.run(cmd)
        return Image.open(output)
```

#### rtree Shim

**Problem**: libspatialindex build fails with TLS linking errors on AIX.

**Solution**: Pure Python implementation using linear search:

```python
# shims/rtree/index.py
class Index:
    def intersection(self, bbox):
        for item in self._items:
            if boxes_intersect(item.bbox, bbox):
                yield item
```

### Ubuntu/Linux

Standard installation using native packages:
- pypdfium2 with native PDFium
- rtree with libspatialindex
- Standard pip packages

## Data Flow

```
PDF Document
     │
     ▼
┌─────────────┐
│docling-parse│ ──── QPDF/internal parser
└─────────────┘
     │
     ▼
┌─────────────┐
│   Cells     │ ──── Character-level bounding boxes
│   Tables    │ ──── Detected table structures
│  Structure  │ ──── Document hierarchy
└─────────────┘
     │
     ▼
┌─────────────┐
│ Chunking    │ ──── Split into RAG-friendly chunks
└─────────────┘
     │
     ▼
┌─────────────┐
│ Embeddings  │ ──── sentence-transformers
└─────────────┘      (MMA accelerated on Power10)
     │
     ▼
┌─────────────┐
│ Vector DB   │ ──── Storage and retrieval
└─────────────┘
```

## Performance Considerations

### AIX
- Ghostscript rendering is slower than native PDFium (~2-3x)
- rtree linear search acceptable for < 10K items per document
- XCOFF patching is one-time operation during install

### Power10 MMA
- Matrix Math Accelerator provides hardware AI inference
- ONNX Runtime can leverage MMA for transformer models
- sentence-transformers embedding generation is accelerated

### Optimization Tips
1. Process documents in parallel (multiprocessing)
2. Cache embeddings for repeated queries
3. Use smaller embedding models for faster processing
4. Consider document pre-processing to reduce complexity

## Security

### Data Privacy
- All processing is on-premise
- No cloud calls required
- Network access only needed for initial package download

### Audit Trail
- Document processing can be logged
- Chunk provenance tracked to source documents
- Compatible with enterprise audit requirements
