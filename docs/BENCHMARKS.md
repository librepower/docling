# Benchmark Methodology

**LibrePower - Unlocking Power Systems through open source. Unmatched RAS and TCO. Minimal footprint 🌍**

This document describes the benchmark methodology for comparing AIX and Ubuntu performance on IBM Power systems.

---

## Important Caveats

> **Same hardware ≠ identical performance.** While raw compute (FLOPS) should be similar, OS-level differences in scheduling, I/O, memory management, and multiprocessing implementation can produce significant variance.

The benchmarks below measure **end-to-end workload performance**, not raw CPU performance. Differences are likely due to:

- OS kernel scheduling and process management
- I/O subsystem (JFS2 vs ext4)
- Python multiprocessing implementation (`fork` behavior)
- Memory allocation patterns
- NUMA topology handling

---

## Test Environment

### Hardware Configuration

Both systems run on the **same physical POWER9 server** with identical LPAR configuration:

| Parameter | Value |
|-----------|-------|
| Processor | IBM POWER9 |
| Cores allocated | 12 |
| SMT | 8 (96 threads total) |
| Memory | 64 GB |
| NUMA | Single node |

### Software Configuration

| Parameter | AIX 7.3 | Ubuntu 22.04 |
|-----------|---------|--------------|
| Kernel | AIX 7.3 TL04 | 5.15.0-164-generic |
| Python | 3.12.12 | 3.12.x |
| Docling | 2.66.0 | 2.66.0 |
| NumPy | 2.4.1 (POWER9 wheel) | 2.4.1 (IBM pyeco) |
| OpenBLAS | 0.3.28 (**custom POWER9 build**) | 0.3.28 (system ppc64le) |

### OpenBLAS Configuration (Important)

AIX system OpenBLAS (`/opt/freeware/lib/libopenblas.a`) uses **POWER7 kernels** which are 3-5x slower on POWER9 hardware.

For these benchmarks, we use a **custom-compiled POWER9 OpenBLAS**:

```
File: libopenblas_power9p-r0.3.28.so (18 MB)
Target: POWER9
Flags: -mcpu=power9 -mtune=power9 -mvsx
Location: wheels/aix/libopenblas_power9p-r0.3.28.so
```

This was the **first-ever OpenBLAS build for AIX ppc64 with POWER9 optimization**.

| OpenBLAS Build | GFLOPS (DGEMM) | vs POWER7 |
|----------------|----------------|-----------|
| AIX System (POWER7) | 56.23 | baseline |
| AIX Custom (POWER9) | 274.59 | **4.9x faster** |
| Ubuntu (ppc64le) | 192.20 | 3.4x faster |

> **Note:** AIX POWER9 OpenBLAS outperforms Ubuntu's because we compiled with explicit `-mcpu=power9` while Ubuntu's ppc64le build uses generic settings.

---

## Benchmark Tests

### 1. PDF Parsing (Single Document)

**What it measures:** Time to parse PDF pages using docling-parse.

**Command:**
```python
from docling_parse.pdf_parsers import pdf_parser_v2
import time

parser = pdf_parser_v2()
parser.load_document("doc", "test.pdf")

start = time.time()
for page in range(num_pages):
    result = parser.parse_pdf_from_key_on_page("doc", page)
elapsed = time.time() - start

pages_per_sec = num_pages / elapsed
```

**Test document:** 100-page technical PDF (consistent across both platforms)

### 2. Multiprocessing (Batch Processing)

**What it measures:** Throughput when processing multiple documents in parallel.

**Command:**
```python
from multiprocessing import Pool
from docling.document_converter import DocumentConverter

def process_file(path):
    converter = DocumentConverter()
    return converter.convert(path)

with Pool(32) as pool:
    results = pool.map(process_file, file_list)
```

**Test set:** 100 PDF files, ~10 pages each

---

## Results (v1.0 - January 2026)

| Test | AIX 7.3 | Ubuntu 22.04 | Ratio | Likely Cause |
|------|---------|--------------|-------|--------------|
| PDF Parsing | 6.04 pages/s | 4.56 pages/s | AIX 1.32x | I/O patterns, JFS2 caching |
| Multiprocessing | 19.41 files/s | 4.34 files/s | AIX 4.47x | Process fork/scheduling |

---

## Reproducing the Benchmarks

### Prerequisites

1. **Identical LPAR configuration** - Same cores, memory, SMT settings
2. **NUMA binding** - Use `numactl` on Linux, `bindprocessor` on AIX
3. **Cold start** - Reboot or clear caches before each run
4. **Same test data** - Use identical PDF files

### AIX

```bash
# Clear filesystem cache
sync; echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || sync

# Pin to specific processors (optional)
bindprocessor -q  # List available processors

# Run benchmark
cd /path/to/docling
python3 benchmark.py --output results_aix.json
```

### Ubuntu

```bash
# Clear filesystem cache
sync; echo 3 | sudo tee /proc/sys/vm/drop_caches

# Pin to NUMA node 0
numactl --cpunodebind=0 --membind=0 python3 benchmark.py --output results_ubuntu.json
```

### Benchmark Script

```python
#!/usr/bin/env python3
"""
LibrePower Docling Benchmark
Usage: python3 benchmark.py --output results.json
"""

import argparse
import json
import time
import os
from multiprocessing import Pool, cpu_count

def benchmark_pdf_parsing(pdf_path, iterations=3):
    """Benchmark single-document PDF parsing."""
    from docling_parse.pdf_parsers import pdf_parser_v2

    parser = pdf_parser_v2()
    parser.load_document("doc", pdf_path)

    # Get page count
    # (implementation depends on docling version)
    num_pages = 100  # Adjust based on test document

    times = []
    for _ in range(iterations):
        start = time.time()
        for page in range(num_pages):
            parser.parse_pdf_from_key_on_page("doc", page)
        times.append(time.time() - start)

    avg_time = sum(times) / len(times)
    return {
        "test": "pdf_parsing",
        "pages": num_pages,
        "avg_time_sec": avg_time,
        "pages_per_sec": num_pages / avg_time
    }

def process_single_file(path):
    """Process a single file (for multiprocessing test)."""
    from docling.document_converter import DocumentConverter
    converter = DocumentConverter()
    result = converter.convert(path)
    return len(result.document.export_to_markdown())

def benchmark_multiprocessing(pdf_dir, workers=32):
    """Benchmark parallel document processing."""
    files = [os.path.join(pdf_dir, f) for f in os.listdir(pdf_dir) if f.endswith('.pdf')]

    start = time.time()
    with Pool(workers) as pool:
        results = pool.map(process_single_file, files)
    elapsed = time.time() - start

    return {
        "test": "multiprocessing",
        "files": len(files),
        "workers": workers,
        "total_time_sec": elapsed,
        "files_per_sec": len(files) / elapsed
    }

def main():
    parser = argparse.ArgumentParser(description="LibrePower Docling Benchmark")
    parser.add_argument("--output", default="results.json", help="Output file")
    parser.add_argument("--pdf", default="test.pdf", help="Test PDF for parsing")
    parser.add_argument("--pdf-dir", default="test_pdfs/", help="Directory for multiprocessing")
    parser.add_argument("--workers", type=int, default=32, help="Worker count")
    args = parser.parse_args()

    results = {
        "platform": os.uname().sysname,
        "hostname": os.uname().nodename,
        "cpu_count": cpu_count(),
        "timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "tests": []
    }

    # Run benchmarks
    if os.path.exists(args.pdf):
        results["tests"].append(benchmark_pdf_parsing(args.pdf))

    if os.path.isdir(args.pdf_dir):
        results["tests"].append(benchmark_multiprocessing(args.pdf_dir, args.workers))

    # Save results
    with open(args.output, "w") as f:
        json.dump(results, f, indent=2)

    print(json.dumps(results, indent=2))

if __name__ == "__main__":
    main()
```

---

## Known Limitations

1. **Not isolated CPU benchmarks** - Results include I/O, OS overhead
2. **NUMA not strictly controlled** - May vary between runs
3. **Different OpenBLAS builds** - AIX uses custom POWER9 build
4. **Python GIL** - Multiprocessing bypasses GIL but fork behavior differs

---

## Future Improvements

- [ ] Add `numactl`/`bindprocessor` to benchmark script
- [ ] Include memory bandwidth tests (STREAM)
- [ ] Add pure compute benchmark (matrix multiply)
- [ ] Test with identical OpenBLAS configuration
- [ ] Document exact LPAR XML configuration

---

## Contributing

If you can reproduce these benchmarks on your Power systems, please share results:
- Open an issue on [GitLab](https://gitlab.com/librepower/docling/-/issues)
- Email: hello@librepower.org

---

*Maintained by [LibrePower](https://librepower.org)*
