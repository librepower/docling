# LibrePower Docling

**LibrePower - Unlocking Power Systems through open source. Unmatched RAS and TCO. Minimal footprint.**

Document AI for AIX, IBM i, and Linux on Power - powered by IBM's Docling framework.

> **Early Release**: These packages are provided as-is for testing and evaluation. While we use them in production, bugs may exist.

---

## Join the Community

LibrePower is more than AIX—we're building open source support across the entire IBM Power ecosystem: AIX, IBM i, and Linux on Power (ppc64le).

**[Subscribe to our newsletter](https://librepower.substack.com/subscribe)** for releases, technical articles, and community updates.

**[librepower.org](https://librepower.substack.com/subscribe)** — Launching February 2026

---

## Overview

LibrePower Docling brings enterprise document intelligence to IBM Power systems. Process PDFs, extract text and tables, and build document AI applications - all on-premise with your existing infrastructure.

## Features

- 📄 **PDF Processing**: Extract text, tables, and document structure
- 🤖 **AI-Powered**: HuggingFace transformers and tokenizers for NLP
- 🖥️ **Multi-Platform**: Works on AIX (IBM Power) and Ubuntu Linux ppc64le
- 🔒 **On-Premise**: Data stays in-house - no cloud dependency
- ⚡ **Power Optimized**: Compiled for POWER9+ (runs on POWER9, POWER10, POWER11)

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
| AIX 7.3+ | ✅ Supported | POWER9, POWER10, POWER11 |
| Ubuntu 22.04+ | ✅ Supported | ppc64le (Little Endian) |

## Installation Options

```bash
./install.sh              # Full installation (auto-detects processor)
./install.sh --power9     # Force POWER9 wheels (compatible with P9/P10/P11)
./install.sh --power10    # Use POWER10 wheels (MMA enabled, P10/P11 only)
./install.sh --deps-only  # System dependencies only
./install.sh --python-only # Python packages only
./install.sh --wheels-only # Install pre-built wheels only
./install.sh --verify     # Verify installation
./install.sh --demo       # Run demonstration
./install.sh --platform   # Show detected platform
./install.sh --help       # Show help
```

The installer auto-detects your processor and selects the appropriate optimized wheels.

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

## Pre-built Wheels

Pre-compiled wheels for AIX ppc64 are included in `wheels/aix/`.

### POWER9 Wheels (Default - Compatible with P9/P10/P11)

Located in `wheels/aix/`:

| Package | Version | Size | Compiler Flags |
|---------|---------|------|----------------|
| numpy | 2.4.1 | 7.9 MB | `-mcpu=power9 -mtune=power9 -mvsx` |
| scipy | 1.17.0 | 33 MB | `-mcpu=power9 -mtune=power9` |
| scikit-learn | 1.8.0 | 10 MB | `-mcpu=power9` |
| hnswlib | 0.8.0 | 3.1 MB | `-mcpu=power9 -O3` |
| annoy | 1.17.3 | 102 KB | `-mcpu=power9` |
| libopenblas | 0.3.28 | 18 MB | **POWER9 BLAS library** |

### POWER10 Wheels (Optimized for P10/P11)

Located in `wheels/aix/power10/`:

| Package | Version | Size | Compiler Flags |
|---------|---------|------|----------------|
| numpy | 2.4.1 | 7.9 MB | `-mcpu=power10 -mtune=power10 -O3` |
| hnswlib | 0.8.0 | 438 KB | `-mcpu=power10 -mtune=power10 -O3` |
| scipy | 1.17.0 | 33 MB | P9 fallback* |
| scikit-learn | 1.8.0 | 10 MB | P9 fallback* |
| annoy | 1.17.3 | 102 KB | P9 fallback* |

*Some packages use POWER9 wheels as fallback (compilation issues with -mcpu=power10)

**Note**: OpenBLAS POWER9 was compiled specifically for this project - it did not exist for AIX before.

### Processor Auto-Detection

The installer automatically detects your processor:

```bash
./install.sh              # Auto-detects P9/P10/P11
./install.sh --power9     # Force POWER9 wheels
./install.sh --power10    # Force POWER10 wheels (P10/P11 only)
```

If POWER10 wheels fail to install, the installer automatically falls back to POWER9 wheels.

### POWER9/10/11 Compatibility

| Processor | POWER9 Wheels | POWER10 Wheels |
|-----------|---------------|----------------|
| POWER9 | ✅ Native | ❌ Won't run |
| POWER10 | ✅ Compatible | ✅ Native + MMA potential |
| POWER11 | ✅ Compatible | ✅ Native + MMA potential |

**POWER9 wheels** provide:
- Full binary compatibility across P9/P10/P11
- VSX vector extensions for SIMD acceleration
- Major performance improvement over POWER7 binaries

**POWER10 wheels** additionally enable:
- MMA (Matrix Math Accelerator) potential for future NumPy/SciPy optimizations
- Native instruction scheduling for P10/P11 microarchitecture

## Benchmarks

Performance comparison on **POWER9** (same hardware, 12 threads):

| Test | AIX 7.3 | Ubuntu 22.04 ppc64le | Notes |
|------|---------|----------------------|-------|
| PDF Parsing | 6.04 pages/s | 4.56 pages/s | AIX 1.32x faster |
| Multiprocessing (32 workers) | 19.41 files/s | 4.34 files/s | AIX 4.47x faster |

*Benchmark conditions: POWER9, 12 threads, same LPAR configuration. AIX demonstrates superior multiprocessing and I/O performance for document processing workloads.*

## Project Structure

```
librepower-docling/
├── install.sh           # Universal installer (auto-detects P9/P10/P11)
├── wheels/
│   └── aix/             # POWER9 wheels (default)
│       ├── numpy-2.4.1-cp312-cp312-aix_ppc64.whl
│       ├── scipy-1.17.0-cp312-cp312-aix_ppc64.whl
│       ├── ...
│       └── power10/     # POWER10 optimized wheels
│           ├── numpy-2.4.1-cp312-cp312-aix_ppc64.whl
│           └── hnswlib-0.8.0-cp312-cp312-aix_ppc64.whl
├── lib/
│   ├── aix/
│   │   ├── install.sh   # AIX installer with P9/P10 support
│   │   ├── patches/     # XCOFF binary patches
│   │   └── shims/       # Compatibility shims
│   └── ubuntu/
│       └── install.sh   # Ubuntu installer
├── examples/
│   ├── quick_start.py   # Basic usage
│   └── rag_demo.py      # Enterprise RAG system
└── docs/
    └── SETUP_GUIDE.md
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
- sklearn has import issues on AIX (investigating)
- Some packages may have version metadata mismatches

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

**Developed by [SIXE](https://sixe.eu)** as part of the [LibrePower](https://librepower.org) initiative.

### Technologies
- [IBM Docling](https://github.com/DS4SD/docling) - Document AI framework
- [IBM pyeco](https://github.com/ppc64le/pyeco) - Optimized Python packages for POWER
- [HuggingFace](https://huggingface.co/) - Tokenizers and Transformers
- [OpenBLAS](https://github.com/OpenMathLib/OpenBLAS) - BLAS library

---

*LibrePower - Unlocking Power Systems through open source*

*[librepower.org](https://librepower.org)* | *[Newsletter](https://librepower.substack.com/subscribe)* | *[GitLab](https://gitlab.com/librepower)*
