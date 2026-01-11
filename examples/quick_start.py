#!/usr/bin/env python3
"""
LibrePower Docling - Quick Start Example
=========================================

Cross-platform example that works on both AIX and Ubuntu.
Demonstrates basic PDF processing with docling.
"""

import sys
import os
import platform

# Platform detection
IS_AIX = platform.system() == "AIX"
IS_LINUX = platform.system() == "Linux"

# Handle cleanup segfault on AIX (docling-parse issue)
if IS_AIX:
    import atexit
    atexit.register(lambda: os._exit(0))


def get_platform_info() -> str:
    """Get platform information string."""
    system = platform.system()
    if system == "AIX":
        try:
            import subprocess
            version = subprocess.check_output(["oslevel"], text=True).strip()
            return f"AIX {version} ({platform.processor()})"
        except Exception:
            return f"AIX ({platform.processor()})"
    elif system == "Linux":
        try:
            with open("/etc/os-release") as f:
                for line in f:
                    if line.startswith("PRETTY_NAME="):
                        return line.split("=")[1].strip().strip('"')
        except Exception:
            pass
        return f"Linux ({platform.machine()})"
    else:
        return f"{system} ({platform.machine()})"


def create_sample_pdf(output_path: str) -> None:
    """Create a sample PDF for testing."""
    from reportlab.pdfgen import canvas
    from reportlab.lib.pagesizes import letter

    c = canvas.Canvas(output_path, pagesize=letter)

    # Title
    c.setFont("Helvetica-Bold", 18)
    c.drawString(72, 750, "LibrePower Docling Demo")

    # Platform info
    c.setFont("Helvetica", 12)
    c.drawString(72, 720, f"Running on: {get_platform_info()}")

    # Content
    c.drawString(72, 680, "This is a sample PDF document for testing.")
    c.drawString(72, 660, "Docling can extract text, tables, and structure.")

    c.drawString(72, 620, "Key Features:")
    c.drawString(90, 600, "- PDF text extraction with docling-parse")
    c.drawString(90, 580, "- Table detection and extraction")
    c.drawString(90, 560, "- Document structure analysis")
    c.drawString(90, 540, "- AI-powered processing with transformers")

    # Page 2 for multi-page test
    c.showPage()
    c.setFont("Helvetica-Bold", 14)
    c.drawString(72, 750, "Page 2 - Additional Content")
    c.setFont("Helvetica", 12)
    c.drawString(72, 720, "Multi-page document support is fully functional.")
    c.drawString(72, 700, "Each page is processed independently.")

    c.save()
    print(f"  Created sample PDF: {output_path}")


def extract_with_docling_parse(pdf_path: str) -> str:
    """
    Extract text using docling-parse (low-level API).

    This is the core PDF parsing engine used by docling.
    Works identically on AIX and Linux.
    """
    from docling_parse.pdf_parsers import pdf_parser_v2

    parser = pdf_parser_v2()

    # Load document
    load_success = parser.load_document("doc", pdf_path)
    if not load_success:
        raise RuntimeError(f"Failed to load PDF: {pdf_path}")

    num_pages = parser.number_of_pages("doc")
    print(f"  Document has {num_pages} page(s)")

    all_text = []
    for page_num in range(num_pages):
        result = parser.parse_pdf_from_key_on_page("doc", page_num)

        if 'pages' not in result or not result['pages']:
            continue

        page = result['pages'][0]
        cells_data = page.get('original', {}).get('cells', {})

        if not cells_data or 'data' not in cells_data:
            continue

        # Extract text from cells (column 12 is the text content)
        page_chars = []
        for cell in cells_data['data']:
            if len(cell) > 12:
                page_chars.append(cell[12])

        page_text = ''.join(page_chars)
        all_text.append(f"[Page {page_num + 1}]\n{page_text}")

    # Unload document to free memory
    parser.unload_document("doc")

    return '\n\n'.join(all_text)


def test_tokenizers() -> bool:
    """Test tokenizers library functionality."""
    try:
        from tokenizers import Tokenizer
        from tokenizers.models import BPE
        from tokenizers.trainers import BpeTrainer
        from tokenizers.pre_tokenizers import Whitespace

        # Create a simple tokenizer
        tokenizer = Tokenizer(BPE(unk_token="[UNK]"))
        tokenizer.pre_tokenizer = Whitespace()

        # Train on sample data
        trainer = BpeTrainer(special_tokens=["[UNK]", "[CLS]", "[SEP]", "[PAD]", "[MASK]"])
        tokenizer.train_from_iterator(
            ["Hello world", "LibrePower Docling", "Document AI on IBM Power"],
            trainer=trainer
        )

        # Test encoding
        output = tokenizer.encode("Hello LibrePower")

        print(f"  Tokenizer test: '{output.tokens}' -> IDs: {output.ids}")
        return True
    except Exception as e:
        print(f"  Tokenizer error: {e}")
        return False


def test_transformers() -> bool:
    """Test transformers library functionality."""
    try:
        from transformers import AutoTokenizer

        # Just verify the import works - don't download models
        print(f"  Transformers: AutoTokenizer available")

        # Check if we can access model loading (without downloading)
        from transformers import AutoModel, AutoConfig
        print(f"  Transformers: AutoModel, AutoConfig available")

        return True
    except Exception as e:
        print(f"  Transformers error: {e}")
        return False


def test_pypdfium2() -> bool:
    """Test pypdfium2 (or shim on AIX)."""
    try:
        import pypdfium2
        version = getattr(pypdfium2, '__version__', 'unknown')
        backend = getattr(pypdfium2, 'V_LIBPDFIUM', 'native')

        if 'ghostscript' in str(backend).lower():
            print(f"  pypdfium2: v{version} (Ghostscript shim)")
        else:
            print(f"  pypdfium2: v{version} (native PDFium)")

        return True
    except Exception as e:
        print(f"  pypdfium2 error: {e}")
        return False


def test_rtree() -> bool:
    """Test rtree (or shim on AIX)."""
    try:
        from rtree import index

        # Create a simple spatial index
        idx = index.Index()
        idx.insert(1, (0, 0, 10, 10))
        idx.insert(2, (5, 5, 15, 15))

        # Query intersection
        hits = list(idx.intersection((7, 7, 12, 12)))

        # Check if it's the shim or native
        is_shim = not hasattr(index.Index, '_props')  # Native rtree has _props

        if is_shim or len(hits) < 10000:  # Shim uses list-based storage
            print(f"  rtree: {len(hits)} hits found (may be shim)")
        else:
            print(f"  rtree: {len(hits)} hits found (native)")

        return True
    except Exception as e:
        print(f"  rtree error: {e}")
        return False


def main():
    print("=" * 60)
    print("LibrePower Docling - Quick Start")
    print("=" * 60)
    print(f"Platform: {get_platform_info()}")
    print(f"Python: {platform.python_version()}")
    print("=" * 60)

    # Create sample PDF
    print("\n[1] Creating sample PDF...")
    sample_pdf = "/tmp/librepower_quickstart.pdf"
    create_sample_pdf(sample_pdf)

    # Extract text with docling-parse
    print("\n[2] Extracting text with docling-parse...")
    try:
        text = extract_with_docling_parse(sample_pdf)
        print(f"  Extracted {len(text)} characters:")
        # Show first 200 chars
        preview = text[:200].replace('\n', ' ')
        print(f"  Preview: {preview}...")
    except Exception as e:
        print(f"  Error: {e}")
        return 1

    # Test tokenizers
    print("\n[3] Testing tokenizers...")
    if not test_tokenizers():
        print("  Warning: tokenizers not fully functional")

    # Test transformers
    print("\n[4] Testing transformers...")
    if not test_transformers():
        print("  Warning: transformers not fully functional")

    # Test pypdfium2
    print("\n[5] Testing pypdfium2...")
    test_pypdfium2()

    # Test rtree
    print("\n[6] Testing rtree...")
    test_rtree()

    # Summary
    print("\n" + "=" * 60)
    print("Quick Start Complete!")
    print("=" * 60)
    print("\nNext steps:")
    print("  - Run the RAG demo: python examples/rag_demo.py")
    print("  - Process your own PDFs with docling")
    print("  - Build document intelligence applications")
    print("=" * 60)

    return 0


if __name__ == "__main__":
    sys.exit(main())
