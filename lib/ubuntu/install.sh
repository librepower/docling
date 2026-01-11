#!/bin/bash
#
# LibrePower Docling - Ubuntu Installer
# ======================================
# Platform-specific installer for Ubuntu 22.04+ and Debian-based systems
#
# Tested on:
#   - Ubuntu 22.04 LTS (x86_64, ppc64le)
#   - Ubuntu 24.04 LTS (x86_64)
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Installation options
USE_VENV="${USE_VENV:-1}"  # Use virtual environment by default
VENV_DIR="${VENV_DIR:-${HOME}/.librepower-docling}"
INSTALL_SYSTEM_WIDE="${INSTALL_SYSTEM_WIDE:-0}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_platform_info() {
    echo "Platform Details:"
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        echo "  OS: ${PRETTY_NAME}"
        echo "  Version: ${VERSION_ID}"
    fi
    echo "  Arch: $(uname -m)"
    echo "  Kernel: $(uname -r)"
    if [[ "${USE_VENV}" == "1" ]]; then
        echo "  Install mode: Virtual environment (${VENV_DIR})"
    else
        echo "  Install mode: System-wide"
    fi
    echo ""
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if running as root for system packages
    if [[ $EUID -eq 0 ]]; then
        SUDO=""
        log_warn "Running as root"
    else
        SUDO="sudo"
        # Check sudo access
        if ! ${SUDO} -n true 2>/dev/null; then
            log_info "sudo access required for system packages"
        fi
    fi

    # Check Ubuntu/Debian version
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "${ID}" in
            ubuntu)
                if [[ "${VERSION_ID}" < "22.04" ]]; then
                    log_error "Ubuntu 22.04 or later required. Found: ${VERSION_ID}"
                    exit 1
                fi
                log_success "Ubuntu ${VERSION_ID}"
                ;;
            debian)
                if [[ "${VERSION_ID}" -lt "11" ]]; then
                    log_error "Debian 11 or later required. Found: ${VERSION_ID}"
                    exit 1
                fi
                log_success "Debian ${VERSION_ID}"
                ;;
            *)
                log_warn "Untested distribution: ${ID} ${VERSION_ID}"
                log_info "Proceeding anyway..."
                ;;
        esac
    fi

    # Check apt
    if ! command -v apt &>/dev/null; then
        log_error "apt package manager not found"
        exit 1
    fi
    log_success "apt available"

    # Check disk space (need at least 5GB)
    FREE_SPACE=$(df -BG /home 2>/dev/null | tail -1 | awk '{print $4}' | tr -d 'G')
    if [[ -n "${FREE_SPACE}" && "${FREE_SPACE}" -lt 5 ]]; then
        log_error "Insufficient disk space. Need 5GB, have ${FREE_SPACE}GB"
        exit 1
    fi
    log_success "Disk space OK (${FREE_SPACE}GB available)"

    # Check Python
    if command -v python3 &>/dev/null; then
        PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
        PYTHON_MAJOR=$(echo "${PYTHON_VERSION}" | cut -d. -f1)
        PYTHON_MINOR=$(echo "${PYTHON_VERSION}" | cut -d. -f2)
        if [[ "${PYTHON_MAJOR}" -lt 3 || ("${PYTHON_MAJOR}" -eq 3 && "${PYTHON_MINOR}" -lt 10) ]]; then
            log_warn "Python 3.10+ recommended. Found: ${PYTHON_VERSION}"
        else
            log_success "Python ${PYTHON_VERSION}"
        fi
    else
        log_warn "Python not found, will install..."
    fi
}

install_system_deps() {
    log_info "Installing system dependencies via apt..."

    ${SUDO} apt update

    # Core packages
    PACKAGES=(
        # Python
        python3
        python3-pip
        python3-venv
        python3-dev

        # Build tools
        build-essential
        cmake
        pkg-config

        # PDF processing
        ghostscript
        libgs-dev
        poppler-utils

        # Image processing
        libmagickwand-dev
        imagemagick

        # PDF libraries
        libpoppler-cpp-dev
        libqpdf-dev

        # Dependencies for Python packages
        libffi-dev
        libssl-dev
        zlib1g-dev
        libjpeg-dev
        libpng-dev
        libfreetype6-dev

        # For rtree (libspatialindex)
        libspatialindex-dev

        # For HDF5 (sometimes needed by scipy)
        libhdf5-dev

        # Rust (for building tokenizers if needed)
        # rustc
        # cargo
    )

    log_info "Installing: ${PACKAGES[*]}"
    ${SUDO} apt install -y "${PACKAGES[@]}" || {
        log_warn "Some packages may have failed, continuing..."
    }

    # Install Rust if not present (needed for some builds)
    if ! command -v rustc &>/dev/null; then
        log_info "Rust not found. Some packages may need pre-built wheels."
        log_info "To install Rust: curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh"
    else
        log_success "Rust $(rustc --version | cut -d' ' -f2) available"
    fi

    log_success "System dependencies installed"
}

setup_python_env() {
    log_info "Setting up Python environment..."

    if [[ "${USE_VENV}" == "1" ]]; then
        if [[ ! -d "${VENV_DIR}" ]]; then
            log_info "Creating virtual environment: ${VENV_DIR}"
            python3 -m venv "${VENV_DIR}"
        fi

        # Activate virtual environment
        source "${VENV_DIR}/bin/activate"
        PYTHON="${VENV_DIR}/bin/python3"
        PIP="${VENV_DIR}/bin/pip3"

        log_success "Virtual environment activated"
    else
        PYTHON="python3"
        PIP="pip3"
        if [[ $EUID -ne 0 ]]; then
            PIP="${PIP} --user"
        fi
    fi

    # Upgrade pip
    ${PIP} install --upgrade pip setuptools wheel

    log_success "Python environment ready"
}

install_python_packages() {
    log_info "Installing Python packages..."

    # Activate venv if using it
    if [[ "${USE_VENV}" == "1" && -d "${VENV_DIR}" ]]; then
        source "${VENV_DIR}/bin/activate"
        PIP="${VENV_DIR}/bin/pip3"
    else
        PIP="pip3"
    fi

    # Core scientific packages
    log_info "Installing core packages..."
    ${PIP} install \
        numpy \
        scipy \
        pandas \
        pillow \
        scikit-learn || log_warn "Some core packages failed"

    # HuggingFace ecosystem
    log_info "Installing HuggingFace packages..."
    ${PIP} install \
        tokenizers \
        transformers \
        huggingface-hub \
        sentence-transformers || log_warn "Some HuggingFace packages failed"

    # Docling
    log_info "Installing docling..."
    ${PIP} install \
        docling \
        docling-core || log_warn "docling install failed"

    # docling-parse (may need to build from source)
    log_info "Installing docling-parse..."
    ${PIP} install docling-parse || {
        log_warn "docling-parse pip install failed, trying from source..."
        install_docling_parse_from_source
    }

    # PDF processing
    log_info "Installing PDF packages..."
    ${PIP} install \
        pypdf \
        pypdfium2 \
        reportlab \
        pdf2image || log_warn "Some PDF packages failed"

    # Spatial indexing
    log_info "Installing rtree..."
    ${PIP} install rtree || log_warn "rtree install failed"

    # ML inference
    log_info "Installing ML packages..."
    ${PIP} install \
        onnxruntime || log_warn "onnxruntime failed"

    # Web/API
    log_info "Installing web packages..."
    ${PIP} install \
        pydantic \
        httpx \
        flask \
        tqdm \
        requests || log_warn "Some web packages failed"

    log_success "Python packages installed"
}

install_docling_parse_from_source() {
    log_info "Building docling-parse from source..."

    BUILD_DIR="/tmp/docling-parse-build"
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    if [[ ! -d "docling-parse" ]]; then
        if command -v git &>/dev/null; then
            git clone https://github.com/DS4SD/docling-parse.git
        else
            curl -L -o docling-parse.tar.gz \
                https://github.com/DS4SD/docling-parse/archive/refs/heads/main.tar.gz
            tar xzf docling-parse.tar.gz
            mv docling-parse-main docling-parse
        fi
    fi

    cd docling-parse

    if [[ "${USE_VENV}" == "1" && -d "${VENV_DIR}" ]]; then
        source "${VENV_DIR}/bin/activate"
    fi

    pip install -e . || {
        log_error "docling-parse build failed"
        log_info "You may need to install additional build dependencies"
        return 1
    }

    cd "${SCRIPT_DIR}"
    log_success "docling-parse built from source"
}

verify_installation() {
    log_info "Verifying installation..."

    # Activate venv if using it
    if [[ "${USE_VENV}" == "1" && -d "${VENV_DIR}" ]]; then
        source "${VENV_DIR}/bin/activate"
        PYTHON="${VENV_DIR}/bin/python3"
    else
        PYTHON="python3"
    fi

    ${PYTHON} << 'VERIFY_SCRIPT'
import sys

def check(name, test_func):
    try:
        result = test_func()
        print(f"  [OK] {name}: {result}")
        return True
    except Exception as e:
        print(f"  [FAIL] {name}: {e}")
        return False

print("\nVerification Results:")
print("=" * 60)

all_ok = True

# Core packages
all_ok &= check("numpy", lambda: __import__('numpy').__version__)
all_ok &= check("scipy", lambda: __import__('scipy').__version__)
all_ok &= check("pandas", lambda: __import__('pandas').__version__)
all_ok &= check("pillow", lambda: __import__('PIL').__version__)

# HuggingFace
all_ok &= check("tokenizers", lambda: __import__('tokenizers').__version__)
all_ok &= check("transformers", lambda: __import__('transformers').__version__)
all_ok &= check("sentence-transformers", lambda: __import__('sentence_transformers').__version__)

# Docling
all_ok &= check("docling", lambda: "OK" if __import__('docling') else "FAIL")
all_ok &= check("docling-core", lambda: "OK" if __import__('docling_core') else "FAIL")
all_ok &= check("docling-parse", lambda: "OK" if __import__('docling_parse') else "FAIL")

# PDF processing
all_ok &= check("pypdf", lambda: __import__('pypdf').__version__)
all_ok &= check("pypdfium2", lambda: __import__('pypdfium2').__version__)
all_ok &= check("reportlab", lambda: "OK" if __import__('reportlab') else "FAIL")

# Spatial indexing
all_ok &= check("rtree", lambda: __import__('rtree').__version__)

# ML
all_ok &= check("onnxruntime", lambda: __import__('onnxruntime').__version__)

# Test actual functionality
print("\n" + "-" * 60)
print("Functional Tests:")
print("-" * 60)

def test_pdf_parse():
    from docling_parse.pdf_parsers import pdf_parser_v2
    parser = pdf_parser_v2()
    return "Parser initialized"

def test_tokenizer():
    from tokenizers import Tokenizer
    return "Tokenizer class available"

def test_transformer():
    from transformers import AutoTokenizer
    return "AutoTokenizer available"

all_ok &= check("docling-parse functional", test_pdf_parse)
all_ok &= check("tokenizers functional", test_tokenizer)
all_ok &= check("transformers functional", test_transformer)

print("=" * 60)
if all_ok:
    print("\n  ALL CHECKS PASSED - Docling is ready!")
    sys.exit(0)
else:
    print("\n  SOME CHECKS FAILED - Review errors above")
    sys.exit(1)
VERIFY_SCRIPT
}

run_demo() {
    log_info "Running demo..."

    # Activate venv if using it
    if [[ "${USE_VENV}" == "1" && -d "${VENV_DIR}" ]]; then
        source "${VENV_DIR}/bin/activate"
        PYTHON="${VENV_DIR}/bin/python3"
    else
        PYTHON="python3"
    fi

    # Check if demo exists
    if [[ -f "${REPO_ROOT}/examples/rag_demo.py" ]]; then
        log_info "Running RAG demo..."
        ${PYTHON} "${REPO_ROOT}/examples/rag_demo.py"
    elif [[ -f "${REPO_ROOT}/examples/quick_start.py" ]]; then
        log_info "Running quick start demo..."
        ${PYTHON} "${REPO_ROOT}/examples/quick_start.py"
    else
        # Inline demo
        log_info "Running inline demo..."
        ${PYTHON} << 'DEMO_SCRIPT'
import sys
import os

print("\n" + "=" * 60)
print("LibrePower Docling Demo - Ubuntu")
print("=" * 60)

# Create test PDF
print("\n[1] Creating test PDF...")
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import letter

test_pdf = "/tmp/librepower_ubuntu_demo.pdf"
c = canvas.Canvas(test_pdf, pagesize=letter)
c.setFont("Helvetica-Bold", 16)
c.drawString(72, 750, "LibrePower Docling Demo")
c.setFont("Helvetica", 12)
c.drawString(72, 720, "Document AI running on Ubuntu Linux")
c.drawString(72, 700, "This text will be extracted by docling-parse.")
c.save()
print(f"  Created: {test_pdf}")

# Parse with docling-parse
print("\n[2] Parsing PDF with docling-parse...")
from docling_parse.pdf_parsers import pdf_parser_v2

parser = pdf_parser_v2()
parser.load_document("demo", test_pdf)
result = parser.parse_pdf_from_key_on_page("demo", 0)

cells = result['pages'][0]['original']['cells']['data']
text = ''.join([cell[12] for cell in cells])
parser.unload_document("demo")

print(f"  Extracted: {text[:100]}...")

# Test tokenizers
print("\n[3] Testing tokenizers...")
from tokenizers import Tokenizer
from tokenizers.models import BPE
tokenizer = Tokenizer(BPE())
print("  Tokenizer initialized OK")

# Test transformers
print("\n[4] Testing transformers...")
from transformers import AutoTokenizer
print("  Transformers available OK")

print("\n" + "=" * 60)
print("DEMO COMPLETE - All components working!")
print("=" * 60)
DEMO_SCRIPT
    fi
}

show_completion() {
    echo ""
    echo "============================================================"
    echo "  Installation Complete!"
    echo "============================================================"
    echo ""
    if [[ "${USE_VENV}" == "1" ]]; then
        echo "  Activate environment:"
        echo "    source ${VENV_DIR}/bin/activate"
        echo ""
    fi
    echo "  Quick Start:"
    echo "    from docling.document_converter import DocumentConverter"
    echo "    converter = DocumentConverter()"
    echo "    result = converter.convert('document.pdf')"
    echo ""
    echo "  Run demo:"
    echo "    ${REPO_ROOT}/install.sh --demo"
    echo ""
    echo "  Examples: ${REPO_ROOT}/examples/"
    echo "  Docs: ${REPO_ROOT}/docs/"
    echo "============================================================"
}

show_help() {
    echo "LibrePower Docling - Ubuntu Installer"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --deps-only     Install system dependencies only"
    echo "  --python-only   Install Python packages only"
    echo "  --verify        Verify installation"
    echo "  --demo          Run demonstration"
    echo "  --no-venv       Install system-wide instead of virtualenv"
    echo "  --help          Show this help"
    echo ""
    echo "Environment variables:"
    echo "  USE_VENV=0      Disable virtual environment"
    echo "  VENV_DIR=path   Custom virtualenv location"
    echo ""
}

# Main
main() {
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        --no-venv)
            USE_VENV=0
            shift
            ;;
    esac

    print_platform_info

    case "${1:-}" in
        --deps-only)
            check_prerequisites
            install_system_deps
            ;;
        --python-only)
            setup_python_env
            install_python_packages
            ;;
        --verify)
            verify_installation
            ;;
        --demo)
            run_demo
            ;;
        *)
            # Full installation
            check_prerequisites
            install_system_deps
            setup_python_env
            install_python_packages
            verify_installation
            run_demo
            show_completion
            ;;
    esac
}

main "$@"
