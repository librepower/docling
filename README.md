# LibrePower Docling

Document AI for IBM Power and Linux - powered by IBM's Docling framework.

## Overview

LibrePower Docling brings enterprise document intelligence to IBM Power systems (AIX) and Linux. Process PDFs, extract text and tables, and build document AI applications - all on-premise with your existing infrastructure.

## Features

- **PDF Processing**: Extract text, tables, and document structure
- **AI-Powered**: HuggingFace transformers and tokenizers for NLP
- **Multi-Platform**: Works on AIX (IBM Power) and Ubuntu Linux
- **On-Premise**: Data stays in-house - no cloud dependency
- **Power Optimized**: Ready for Power10/11 MMA acceleration

## Quick Start

```bash
# Clone the repository
git clone https://gitlab.com/librepower/docling.git
cd docling

# Run the installer (auto-detects platform)
./install.sh

# Verify installation
./install.sh --verify

# Run the demo
./install.sh --demo
```

## Supported Platforms

| Platform | Status | Notes |
|----------|--------|-------|
| AIX 7.3+ | ✓ Supported | IBM Power, requires AIX Toolbox |
| Ubuntu 22.04+ | ✓ Supported | x86_64 and ppc64le |
| RHEL 9+ | Planned | Coming soon |
| macOS | Dev only | For development/testing |

## Installation Options

```bash
./install.sh              # Full installation
./install.sh --deps-only  # System dependencies only
./install.sh --python-only # Python packages only
./install.sh --verify     # Verify installation
./install.sh --demo       # Run demonstration
./install.sh --platform   # Show detected platform
./install.sh --help       # Show help
```

## Usage

### Basic PDF Processing

```python
from docling.document_converter import DocumentConverter

converter = DocumentConverter()
result = converter.convert("document.pdf")

# Get markdown output
print(result.document.export_to_markdown())
```

### Low-Level API (docling-parse)

```python
from docling_parse.pdf_parsers import pdf_parser_v2

parser = pdf_parser_v2()
parser.load_document("doc", "document.pdf")
result = parser.parse_pdf_from_key_on_page("doc", 0)

# Extract text from cells
cells = result['pages'][0]['original']['cells']['data']
text = ''.join([cell[12] for cell in cells])
print(text)
```

### Enterprise RAG System

See `examples/rag_demo.py` for a complete Retrieval-Augmented Generation system.

```python
from examples.rag_demo import PowerDocIntelligence

system = PowerDocIntelligence()
system.ingest_directory("/path/to/pdfs")
results = system.search("What are the AI capabilities?")
```

## Pre-built Wheels (POWER9 Optimized)

Pre-compiled wheels for AIX ppc64 are included in `wheels/aix/`:

| Package | Version | Size | Notes |
|---------|---------|------|-------|
| numpy | 2.4.1 | 7.6 MB | `-mcpu=power9 -mtune=power9 -mvsx` |
| scipy | 1.17.0 | 32 MB | POWER9 optimized |
| hnswlib | 0.8.0 | 3.0 MB | Vector search |
| annoy | 1.17.3 | 100 KB | Approximate nearest neighbors |
| libopenblas | 0.3.28 | 17 MB | **POWER9 BLAS library** |

**Note**: OpenBLAS POWER9 was compiled specifically for this project - it did not exist for AIX before.

## Benchmarks (AIX vs Ubuntu ppc64le)

| Test | AIX 7.3 | Ubuntu 22.04 | Winner |
|------|---------|--------------|--------|
| PDF Parsing (pages/sec) | 6.04 | 4.56 | **AIX 1.32x** |
| Multiprocessing 32w | 19.41 files/s | 4.34 files/s | **AIX 4.47x** |
| VectorDB Query | 2583 qps | 2919 qps | Ubuntu 1.13x |
| NumPy MatMul 12t | 167 GFLOPS | 216 GFLOPS | Ubuntu 1.29x |

AIX excels at PDF processing and multiprocessing workloads.

## Project Structure

```
librepower-docling/
├── install.sh           # Universal installer (platform detection)
├── wheels/
│   └── aix/             # Pre-built AIX wheels (POWER9)
├── lib/
│   ├── aix/             # AIX-specific components
│   │   ├── install.sh   # AIX installer
│   │   ├── patches/     # XCOFF binary patches
│   │   └── shims/       # Compatibility shims
│   └── ubuntu/          # Ubuntu-specific components
│       └── install.sh   # Ubuntu installer
├── examples/
│   ├── quick_start.py   # Basic usage example
│   └── rag_demo.py      # Enterprise RAG system
└── docs/
    └── SETUP_GUIDE.md   # Detailed setup guide
```

## AIX-Specific Notes

### XCOFF Binary Patching
The IBM Rust SDK generates XCOFF binaries with a loader relocation bug. The installer automatically patches the tokenizers binary.

### Compatibility Shims
- **pypdfium2**: Uses Ghostscript for PDF rendering (PDFium not available on AIX)
- **rtree**: Pure Python spatial index (libspatialindex not available)
- **numpy.f2py**: Stub module (f2py not needed at runtime)

### Known Issues
- docling-parse may segfault during cleanup (use `os._exit(0)` workaround)
- Some packages may have version metadata mismatches

## Power10 MMA Acceleration

For Power10/11 systems with Matrix Math Accelerator:

1. Ensure ONNX Runtime is compiled with MMA support
2. sentence-transformers will automatically use optimized kernels
3. Monitor utilization: `lparstat -E | grep MMA`

## Contributing

Contributions welcome! Please see CONTRIBUTING.md for guidelines.

## External Resources

### IBM Python Ecosystem for POWER
For Ubuntu ppc64le, IBM provides optimized wheels at [github.com/ppc64le/pyeco](https://github.com/ppc64le/pyeco):

```bash
pip install --extra-index-url https://wheels.developerfirst.ibm.com/ppc64le/linux numpy scipy
```

LibrePower complements this with AIX ppc64 (Big Endian) support.

## License

GPL-3.0 - See LICENSE file

## Credits

- [IBM Docling](https://github.com/DS4SD/docling) - Document AI framework
- [IBM pyeco](https://github.com/ppc64le/pyeco) - Optimized Python packages for POWER
- [HuggingFace](https://huggingface.co/) - Tokenizers and Transformers
- [OpenBLAS](https://github.com/OpenMathLib/OpenBLAS) - BLAS library
- LibrePower Community

---
*LibrePower - Open Source Software for IBM Power*
*[librepower.org](https://librepower.org)*
