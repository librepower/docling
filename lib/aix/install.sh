#!/bin/bash
#
# LibrePower Docling - AIX Installer
# ===================================
# Platform-specific installer for AIX 7.3+ on IBM Power
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INSTALL_PREFIX="${INSTALL_PREFIX:-/opt/freeware}"
PYTHON="${INSTALL_PREFIX}/bin/python3.12"
PIP="${INSTALL_PREFIX}/bin/pip3.12"
DNF="${INSTALL_PREFIX}/bin/dnf"

# Detect processor and set wheel directory
detect_power_level() {
    PROC_TYPE=$(prtconf 2>/dev/null | grep 'Processor Type' | cut -d: -f2 | xargs)

    case "${PROC_TYPE}" in
        *POWER11*|*Power11*)
            DETECTED_POWER="power10"  # P11 uses P10 wheels (MMA support)
            ;;
        *POWER10*|*Power10*)
            DETECTED_POWER="power10"
            ;;
        *POWER9*|*Power9*)
            DETECTED_POWER="power9"
            ;;
        *)
            DETECTED_POWER="power9"  # Default to P9 (most compatible)
            ;;
    esac

    # Allow override via environment or argument
    POWER_LEVEL="${POWER_LEVEL:-${DETECTED_POWER}}"
}

# Set wheels directory based on power level
WHEELS_DIR="${REPO_ROOT}/wheels/aix"

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
    detect_power_level
    echo "Platform Details:"
    echo "  OS: AIX $(oslevel)"
    echo "  Arch: $(uname -p)"
    echo "  Processor: $(prtconf | grep 'Processor Type' | cut -d: -f2 | xargs)"
    echo "  Power Level: ${POWER_LEVEL} (wheels optimized for this architecture)"
    echo "  Install prefix: ${INSTALL_PREFIX}"
    echo ""
}

install_optimized_wheels() {
    log_info "Installing pre-built wheels for ${POWER_LEVEL}..."

    # Determine which wheel directory to use
    if [[ "${POWER_LEVEL}" == "power10" && -d "${WHEELS_DIR}/power10" ]]; then
        WHEEL_PATH="${WHEELS_DIR}/power10"
        log_info "Using POWER10 optimized wheels (MMA enabled)"
        USE_P10=true
    else
        WHEEL_PATH="${WHEELS_DIR}"
        log_info "Using POWER9+ wheels (compatible with P9/P10/P11)"
        USE_P10=false
    fi

    # Install OpenBLAS library
    if [[ -f "${WHEEL_PATH}/libopenblas_power9p-r0.3.28.so" ]]; then
        log_info "Installing OpenBLAS library..."
        mkdir -p "${INSTALL_PREFIX}/lib64"
        cp "${WHEEL_PATH}/libopenblas_power9p-r0.3.28.so" "${INSTALL_PREFIX}/lib64/"
        ln -sf "${INSTALL_PREFIX}/lib64/libopenblas_power9p-r0.3.28.so" "${INSTALL_PREFIX}/lib64/libopenblas.so"
        ln -sf "${INSTALL_PREFIX}/lib64/libopenblas_power9p-r0.3.28.so" "${INSTALL_PREFIX}/lib64/libopenblas.so.0"
        log_success "OpenBLAS installed"
    fi

    # Install wheels
    WHEEL_FAILED=false
    for wheel in "${WHEEL_PATH}"/*.whl; do
        if [[ -f "$wheel" ]]; then
            pkg_name=$(basename "$wheel" | cut -d'-' -f1)
            log_info "Installing ${pkg_name}..."
            if ! ${PIP} install --force-reinstall "$wheel" 2>/dev/null; then
                log_warn "Failed: ${pkg_name}"
                WHEEL_FAILED=true
            fi
        fi
    done

    # Fallback to POWER9 wheels if POWER10 failed
    if [[ "${USE_P10}" == "true" && "${WHEEL_FAILED}" == "true" ]]; then
        log_warn "POWER10 wheels failed. Falling back to POWER9 wheels..."
        WHEEL_PATH="${WHEELS_DIR}"
        for wheel in "${WHEEL_PATH}"/*.whl; do
            if [[ -f "$wheel" ]]; then
                pkg_name=$(basename "$wheel" | cut -d'-' -f1)
                log_info "Installing ${pkg_name} (POWER9 fallback)..."
                ${PIP} install --force-reinstall "$wheel" || log_warn "Failed: ${pkg_name}"
            fi
        done
        log_success "Fallback to POWER9 wheels completed"
    else
        log_success "Optimized wheels installed"
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check dnf
    if [[ ! -x "${DNF}" ]]; then
        log_error "dnf not found at ${DNF}"
        log_info "Install AIX Toolbox: https://www.ibm.com/support/pages/aix-toolbox-open-source-software"
        exit 1
    fi
    log_success "dnf available"

    # Check Python (will install if missing)
    if [[ -x "${PYTHON}" ]]; then
        PYTHON_VERSION=$(${PYTHON} --version 2>&1 | cut -d' ' -f2)
        log_success "Python ${PYTHON_VERSION} found"
    else
        log_warn "Python 3.12 not found, will install..."
    fi

    # Check disk space (need at least 5GB)
    FREE_SPACE=$(df -g /opt 2>/dev/null | tail -1 | awk '{print $3}')
    if [[ -n "${FREE_SPACE}" && ${FREE_SPACE} -lt 5 ]]; then
        log_error "Insufficient disk space. Need 5GB, have ${FREE_SPACE}GB"
        exit 1
    fi
    log_success "Disk space OK"
}

install_system_deps() {
    log_info "Installing system dependencies via dnf..."

    PACKAGES=(
        # Python
        python3.12
        python3.12-devel
        python3.12-pip

        # Build tools
        gcc
        gcc-c++
        cmake
        make

        # PDF processing
        ghostscript
        ghostscript-fonts
        ImageMagick
        ImageMagick-libs

        # Libraries
        libffi
        libffi-devel
        zlib
        zlib-devel
        openssl
        openssl-devel
    )

    log_info "Packages: ${PACKAGES[*]}"
    ${DNF} install -y "${PACKAGES[@]}" || {
        log_warn "Some packages may have failed, continuing..."
    }

    log_success "System dependencies installed"
}

install_python_packages() {
    log_info "Installing Python packages..."

    # Upgrade pip
    ${PIP} install --upgrade pip setuptools wheel

    # Core packages
    PACKAGES=(
        numpy scipy pandas pillow scikit-learn
        tokenizers transformers huggingface-hub
        docling docling-core
        pypdf reportlab
        onnxruntime sentence-transformers
        pydantic httpx flask tqdm
    )

    for pkg in "${PACKAGES[@]}"; do
        log_info "Installing ${pkg}..."
        ${PIP} install "${pkg}" || log_warn "Failed: ${pkg}"
    done

    log_success "Python packages installed"
}

install_docling_parse() {
    log_info "Checking docling-parse..."

    if ${PYTHON} -c "import docling_parse" 2>/dev/null; then
        log_success "docling-parse already installed"
        return 0
    fi

    log_info "Installing docling-parse from source..."

    BUILD_DIR="/tmp/docling-parse-build"
    mkdir -p "${BUILD_DIR}"
    cd "${BUILD_DIR}"

    if [[ ! -d "docling-parse" ]]; then
        ${INSTALL_PREFIX}/bin/curl -L -o docling-parse.tar.gz \
            https://github.com/DS4SD/docling-parse/archive/refs/heads/main.tar.gz
        tar xzf docling-parse.tar.gz 2>/dev/null || {
            gunzip docling-parse.tar.gz && tar xf docling-parse.tar
        }
        mv docling-parse-main docling-parse
    fi

    cd docling-parse
    ${PIP} install -e . || log_warn "docling-parse build may need manual intervention"

    cd "${SCRIPT_DIR}"
    log_success "docling-parse installed"
}

patch_tokenizers() {
    log_info "Checking tokenizers binary..."

    # Find tokenizers .so file
    TOKENIZERS_SO=$(${PYTHON} -c "
import tokenizers
import os
so_path = os.path.join(os.path.dirname(tokenizers.__file__), 'tokenizers.abi3.so')
print(so_path)
" 2>/dev/null || echo "")

    if [[ -z "${TOKENIZERS_SO}" || ! -f "${TOKENIZERS_SO}" ]]; then
        log_warn "tokenizers binary not found"
        return 0
    fi

    # Test if it works
    if ${PYTHON} -c "import tokenizers; tokenizers.Tokenizer" 2>/dev/null; then
        log_success "tokenizers already working"
        return 0
    fi

    log_info "Patching tokenizers XCOFF binary..."

    # Backup
    cp "${TOKENIZERS_SO}" "${TOKENIZERS_SO}.backup"

    # Apply patch
    ${PYTHON} "${SCRIPT_DIR}/patches/patch_xcoff_tokenizers.py" "${TOKENIZERS_SO}" || {
        log_error "Patch failed, restoring backup"
        mv "${TOKENIZERS_SO}.backup" "${TOKENIZERS_SO}"
        return 1
    }

    # Verify
    if ${PYTHON} -c "import tokenizers; print(f'tokenizers {tokenizers.__version__} OK')" 2>/dev/null; then
        log_success "tokenizers patched successfully"
        rm -f "${TOKENIZERS_SO}.backup"
    else
        log_error "tokenizers still not working"
        mv "${TOKENIZERS_SO}.backup" "${TOKENIZERS_SO}"
        return 1
    fi
}

install_shims() {
    log_info "Installing AIX compatibility shims..."

    SITE_PACKAGES=$(${PYTHON} -c "import site; print(site.getsitepackages()[0])")

    # pypdfium2 shim (Ghostscript-based)
    log_info "  pypdfium2 shim..."
    mkdir -p "${SITE_PACKAGES}/pypdfium2"
    cp "${SCRIPT_DIR}/shims/pypdfium2/__init__.py" "${SITE_PACKAGES}/pypdfium2/"

    # rtree shim (pure Python)
    log_info "  rtree shim..."
    rm -rf "${SITE_PACKAGES}/rtree"
    cp -r "${SCRIPT_DIR}/shims/rtree" "${SITE_PACKAGES}/"

    # numpy.f2py stub
    log_info "  numpy.f2py stub..."
    mkdir -p "${SITE_PACKAGES}/numpy/f2py"
    cp "${SCRIPT_DIR}/shims/numpy_f2py/__init__.py" "${SITE_PACKAGES}/numpy/f2py/"

    log_success "Shims installed"
}

verify_installation() {
    log_info "Verifying installation..."

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
print("=" * 50)

all_ok = True

# Core
all_ok &= check("tokenizers", lambda: __import__('tokenizers').__version__)
all_ok &= check("transformers", lambda: __import__('transformers').__version__)
all_ok &= check("docling", lambda: "OK" if __import__('docling') else "FAIL")

# Shims
all_ok &= check("pypdfium2 (shim)", lambda: __import__('pypdfium2').__version__)
all_ok &= check("rtree (shim)", lambda: "OK" if __import__('rtree').index else "FAIL")

# PDF
all_ok &= check("docling-parse", lambda: "OK" if __import__('docling_parse') else "FAIL")
all_ok &= check("reportlab", lambda: "OK" if __import__('reportlab') else "FAIL")

# ML
all_ok &= check("numpy", lambda: __import__('numpy').__version__)
all_ok &= check("scipy", lambda: __import__('scipy').__version__)

print("=" * 50)
if all_ok:
    print("\n  ALL CHECKS PASSED - Docling ready!")
    sys.exit(0)
else:
    print("\n  SOME CHECKS FAILED")
    sys.exit(1)
VERIFY_SCRIPT
}

run_demo() {
    log_info "Running demo..."

    if [[ -f "${REPO_ROOT}/examples/rag_demo.py" ]]; then
        ${PYTHON} "${REPO_ROOT}/examples/rag_demo.py"
    else
        # Quick inline demo
        ${PYTHON} << 'DEMO'
import sys, os
import atexit
atexit.register(lambda: os._exit(0))

from docling_parse.pdf_parsers import pdf_parser_v2
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import letter

print("\n[Demo] Creating test PDF...")
test_pdf = "/tmp/librepower_demo.pdf"
c = canvas.Canvas(test_pdf, pagesize=letter)
c.drawString(72, 750, "LibrePower Docling Demo")
c.drawString(72, 720, "Document AI on IBM Power")
c.save()

print("[Demo] Parsing PDF...")
parser = pdf_parser_v2()
parser.load_document("demo", test_pdf)
result = parser.parse_pdf_from_key_on_page("demo", 0)

cells = result['pages'][0]['original']['cells']['data']
text = ''.join([c[12] for c in cells])

print(f"[Demo] Extracted: {text}")
print("[Demo] Success!")
DEMO
    fi
}

show_completion() {
    echo ""
    echo "============================================================"
    echo "  Installation Complete!"
    echo "============================================================"
    echo ""
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

# Main
main() {
    # Handle power level override first
    for arg in "$@"; do
        case "$arg" in
            --power9)
                export POWER_LEVEL="power9"
                ;;
            --power10|--power11)
                export POWER_LEVEL="power10"
                ;;
        esac
    done

    print_platform_info

    case "${1:-}" in
        --deps-only)
            check_prerequisites
            install_system_deps
            ;;
        --python-only)
            install_python_packages
            install_docling_parse
            ;;
        --wheels-only)
            install_optimized_wheels
            ;;
        --patch-only)
            patch_tokenizers
            install_shims
            ;;
        --verify)
            verify_installation
            ;;
        --demo)
            run_demo
            ;;
        --power9|--power10|--power11)
            # Full installation with specified power level
            check_prerequisites
            install_system_deps
            install_optimized_wheels
            install_python_packages
            install_docling_parse
            patch_tokenizers
            install_shims
            verify_installation
            run_demo
            show_completion
            ;;
        *)
            # Full installation (auto-detect power level)
            check_prerequisites
            install_system_deps
            install_optimized_wheels
            install_python_packages
            install_docling_parse
            patch_tokenizers
            install_shims
            verify_installation
            run_demo
            show_completion
            ;;
    esac
}

main "$@"
