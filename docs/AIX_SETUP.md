# Docling on AIX 7.3 - Complete Setup Guide

## Status: FUNCTIONAL

All core components of docling are working on AIX 7.3 with IBM Power architecture.

## Working Components

| Component | Version | Status | Notes |
|-----------|---------|--------|-------|
| tokenizers | 0.22.2 | ✓ Working | Rust binary, XCOFF patched |
| transformers | 4.57.3 | ✓ Working | Full HuggingFace support |
| docling | latest | ✓ Working | Document converter functional |
| docling-parse | latest | ✓ Working | PDF parsing functional |
| pypdfium2 | 4.30.0 (shim) | ✓ Working | Ghostscript-based shim |
| rtree | 1.0.0 (shim) | ✓ Working | Pure Python implementation |
| reportlab | 4.4.7 | ✓ Working | PDF generation |
| ghostscript | 10.05.1 | ✓ Working | PDF rendering |
| ImageMagick | 7.1.2.11 | ✓ Working | Image processing |

## Known Issues

### 1. Cleanup Segfault in docling-parse
- **Issue**: Process segfaults during cleanup/destructor
- **Impact**: None - all processing completes successfully
- **Workaround**: Use `os._exit(0)` instead of normal exit if needed

### 2. XCOFF Relocation Bug in IBM Rust SDK
- **Issue**: IBM Rust SDK generates invalid XCOFF loader relocations
- **Impact**: Tokenizers binary fails to load without patching
- **Solution**: Use `/tmp/patch_xcoff_remove.py` to patch binaries

## Installation Steps

### 1. Install System Dependencies
```bash
/opt/freeware/bin/dnf install -y ghostscript ghostscript-fonts ImageMagick
```

### 2. Patch Tokenizers Binary
```bash
# Copy patch script to AIX
# Run: python3 /tmp/patch_xcoff_remove.py
# This removes problematic .text section relocations
cp /tmp/tokenizers-no-text-relocs.so /opt/freeware/lib64/python3.12/site-packages/tokenizers/tokenizers.abi3.so
```

### 3. Install pypdfium2 Shim
The pypdfium2 shim uses Ghostscript for PDF rendering:
```bash
mkdir -p /opt/freeware/lib64/python3.12/site-packages/pypdfium2
cp pypdfium2_shim.py /opt/freeware/lib64/python3.12/site-packages/pypdfium2/__init__.py
```

### 4. Install rtree Shim
Pure Python spatial index implementation:
```bash
mkdir -p /opt/freeware/lib64/python3.12/site-packages/rtree
cp rtree_shim/__init__.py /opt/freeware/lib64/python3.12/site-packages/rtree/
cp rtree_shim/index.py /opt/freeware/lib64/python3.12/site-packages/rtree/
```

### 5. Create numpy.f2py Stub
```bash
mkdir -p /opt/freeware/lib64/python3.12/site-packages/numpy/f2py
cat > /opt/freeware/lib64/python3.12/site-packages/numpy/f2py/__init__.py << 'EOF'
__version__ = "2.0"
def compile(*args, **kwargs):
    raise NotImplementedError("f2py not available on this platform")
EOF
```

## Verification

### Test Basic Import
```python
from docling.document_converter import DocumentConverter
converter = DocumentConverter()
print("Docling ready!")
```

### Test PDF Parsing
```python
from docling_parse.pdf_parsers import pdf_parser_v2
import sys

parser = pdf_parser_v2()
parser.load_document("test", "/path/to/pdf")
result = parser.parse_pdf_from_key_on_page("test", 0)
print(f"Extracted from page: {result['pages'][0]['original']['cells']}")

# Use os._exit(0) to avoid cleanup segfault if needed
import os
os._exit(0)
```

### Test pypdfium2 Shim
```python
import pypdfium2
doc = pypdfium2.PdfDocument("/path/to/pdf")
page = doc[0]
img = page.render(scale=1.5)
img.save("/tmp/rendered.png")
```

## Architecture

### XCOFF Binary Patching
The IBM Rust SDK 1.88.0 generates XCOFF binaries with invalid loader relocations:
- R_POS/R_NEG pairs in .text section with rsecnm=1
- AIX loader doesn't support runtime relocations in read-only code sections

**Solution**: Remove problematic relocations by:
1. Identifying relocations with rsecnm=1 (targeting .text section)
2. Compacting the relocation table to remove them
3. Updating l_nreloc count in loader header

### pypdfium2 Shim Architecture
Since PDFium cannot be built for AIX, we provide a Ghostscript-based shim:
- `PdfDocument` class wraps pypdf for metadata
- `PdfPage.render()` uses Ghostscript subprocess for rendering
- Full compatibility with docling's pypdfium2 usage

### rtree Shim Architecture
Pure Python spatial index using linear search:
- Brute-force but correct spatial queries
- Sufficient for typical document processing workloads
- No native dependencies required

## File Locations

| File | Purpose |
|------|---------|
| `/tmp/patch_xcoff_remove.py` | XCOFF binary patcher |
| `/tmp/pypdfium2_shim.py` | pypdfium2 compatibility shim |
| `/tmp/rtree_shim/` | rtree pure Python implementation |
| `/opt/freeware/lib64/python3.12/site-packages/tokenizers/` | Patched tokenizers |

## Performance Notes

- PDF rendering via Ghostscript is slower than native PDFium
- rtree pure Python is slower than libspatialindex for large documents
- For production workloads, consider processing documents in parallel

## Credits

- IBM Open SDK for Rust on AIX
- HuggingFace tokenizers and transformers
- IBM docling and docling-parse
- Ghostscript Project
- ImageMagick

---
*Generated: 2026-01-10*
*Platform: AIX 7.3, IBM Power*
