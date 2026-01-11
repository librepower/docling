#!/bin/bash
#
# LibrePower Docling - Universal Installer
# =========================================
# Automatically detects platform and runs appropriate installation.
#
# Supported platforms:
#   - AIX 7.3+ (IBM Power)
#   - Ubuntu 22.04+ (coming soon)
#
# Usage:
#   ./install.sh              # Full install
#   ./install.sh --deps-only  # System dependencies only
#   ./install.sh --verify     # Verify installation
#   ./install.sh --demo       # Run demo
#   ./install.sh --help       # Show help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VERSION="1.0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║                                                               ║"
    echo "║   ██╗     ██╗██████╗ ██████╗ ███████╗██████╗  ██████╗ ██╗    ║"
    echo "║   ██║     ██║██╔══██╗██╔══██╗██╔════╝██╔══██╗██╔═══██╗██║    ║"
    echo "║   ██║     ██║██████╔╝██████╔╝█████╗  ██████╔╝██║   ██║██║    ║"
    echo "║   ██║     ██║██╔══██╗██╔══██╗██╔══╝  ██╔═══╝ ██║   ██║██║    ║"
    echo "║   ███████╗██║██████╔╝██║  ██║███████╗██║     ╚██████╔╝███████╗║"
    echo "║   ╚══════╝╚═╝╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝      ╚═════╝ ╚══════╝║"
    echo "║                                                               ║"
    echo "║              D O C L I N G   v${VERSION}                        ║"
    echo "║         Document AI for IBM Power & Linux                     ║"
    echo "║                                                               ║"
    echo "╚═══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

detect_platform() {
    OS_NAME=$(uname -s)

    case "${OS_NAME}" in
        AIX)
            # Verify AIX version
            AIX_VERSION=$(oslevel 2>/dev/null | cut -d. -f1,2)
            if [[ "${AIX_VERSION}" < "7.3" ]]; then
                log_error "AIX 7.3 or later required. Found: ${AIX_VERSION}"
                exit 1
            fi
            PLATFORM="aix"
            PLATFORM_NAME="AIX ${AIX_VERSION}"
            ARCH=$(uname -p)
            ;;
        Linux)
            # Detect Linux distribution
            if [[ -f /etc/os-release ]]; then
                . /etc/os-release
                DISTRO="${ID}"
                DISTRO_VERSION="${VERSION_ID}"
            else
                DISTRO="unknown"
                DISTRO_VERSION="unknown"
            fi

            case "${DISTRO}" in
                ubuntu)
                    PLATFORM="ubuntu"
                    PLATFORM_NAME="Ubuntu ${DISTRO_VERSION}"
                    ;;
                rhel|redhat)
                    PLATFORM="rhel"
                    PLATFORM_NAME="RHEL ${DISTRO_VERSION}"
                    ;;
                *)
                    PLATFORM="linux-generic"
                    PLATFORM_NAME="Linux (${DISTRO} ${DISTRO_VERSION})"
                    ;;
            esac
            ARCH=$(uname -m)
            ;;
        Darwin)
            PLATFORM="macos"
            PLATFORM_NAME="macOS $(sw_vers -productVersion 2>/dev/null || echo 'unknown')"
            ARCH=$(uname -m)
            ;;
        *)
            log_error "Unsupported operating system: ${OS_NAME}"
            exit 1
            ;;
    esac

    log_info "Detected platform: ${PLATFORM_NAME} (${ARCH})"
}

check_platform_support() {
    PLATFORM_DIR="${SCRIPT_DIR}/lib/${PLATFORM}"
    PLATFORM_INSTALLER="${PLATFORM_DIR}/install.sh"

    if [[ ! -d "${PLATFORM_DIR}" ]]; then
        log_error "Platform '${PLATFORM}' is not yet supported."
        log_info "Supported platforms:"
        for dir in "${SCRIPT_DIR}/lib/"*/; do
            if [[ -d "$dir" ]]; then
                basename "$dir"
            fi
        done
        exit 1
    fi

    if [[ ! -x "${PLATFORM_INSTALLER}" ]]; then
        log_error "Platform installer not found: ${PLATFORM_INSTALLER}"
        exit 1
    fi
}

show_help() {
    echo "LibrePower Docling v${VERSION}"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --deps-only     Install system dependencies only"
    echo "  --python-only   Install Python packages only"
    echo "  --patch-only    Apply platform patches only"
    echo "  --verify        Verify installation"
    echo "  --demo          Run demonstration"
    echo "  --platform      Show detected platform and exit"
    echo "  --help, -h      Show this help"
    echo ""
    echo "Examples:"
    echo "  $0              # Full installation"
    echo "  $0 --verify     # Check if everything works"
    echo "  $0 --demo       # Run the RAG demo"
    echo ""
    echo "Supported Platforms:"
    echo "  - AIX 7.3+ on IBM Power"
    echo "  - Ubuntu 22.04+ (coming soon)"
    echo ""
    echo "Documentation: ${SCRIPT_DIR}/docs/"
    echo "Examples: ${SCRIPT_DIR}/examples/"
}

main() {
    # Handle --help before banner
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
    esac

    print_banner
    detect_platform

    # Handle --platform
    if [[ "${1:-}" == "--platform" ]]; then
        echo ""
        echo "Platform: ${PLATFORM}"
        echo "Name: ${PLATFORM_NAME}"
        echo "Architecture: ${ARCH}"
        exit 0
    fi

    check_platform_support

    echo ""
    log_info "Running ${PLATFORM_NAME} installer..."
    echo ""

    # Pass all arguments to platform-specific installer
    exec "${PLATFORM_INSTALLER}" "$@"
}

main "$@"
