#!/usr/bin/env python3
"""
XCOFF64 Patcher for IBM Rust SDK binaries on AIX.
=================================================

This script fixes a bug in the IBM Rust SDK 1.88 LLVM backend that generates
invalid XCOFF loader relocations targeting the .text (code) section.

The Problem:
- IBM Rust SDK's LLVM generates R_POS/R_NEG relocation pairs with rsecnm=1
- rsecnm=1 means the relocation targets section 1 (usually .text)
- AIX loader doesn't support runtime relocations in read-only code sections
- Error: "invalid l_rsecnm field 1 for relocation entry"

The Solution:
- Remove all relocations with rsecnm=1 (targeting .text)
- Update the relocation count in the loader header
- These relocations appear to be unused/redundant - removing them works

Usage:
    python3 patch_xcoff_tokenizers.py <input.so> [output.so]

If output is not specified, input is patched in-place (backup created).
"""
import struct
import sys
import shutil
import os

# XCOFF64 magic numbers and constants
XCOFF64_MAGIC = 0x01F7
STYP_LOADER = 0x1000  # Loader section flag

def find_loader_section(data):
    """Find the loader section in an XCOFF64 binary."""
    # XCOFF64 file header is 24 bytes
    if len(data) < 24:
        raise ValueError("File too small for XCOFF64 header")

    magic = struct.unpack('>H', data[0:2])[0]
    if magic != XCOFF64_MAGIC:
        raise ValueError(f"Not an XCOFF64 file (magic: 0x{magic:04x})")

    f_nscns = struct.unpack('>H', data[2:4])[0]  # Number of sections
    f_opthdr = struct.unpack('>H', data[16:18])[0]  # Optional header size

    # Section headers start after file header + optional header
    # File header is 24 bytes in XCOFF64
    section_offset = 24 + f_opthdr

    # Each XCOFF64 section header is 72 bytes
    for i in range(f_nscns):
        sh_offset = section_offset + i * 72

        # s_name is 8 bytes at offset 0
        s_name = data[sh_offset:sh_offset+8].rstrip(b'\x00').decode('ascii', errors='replace')

        # s_flags at offset 64 (4 bytes)
        s_flags = struct.unpack('>I', data[sh_offset+64:sh_offset+68])[0]

        # s_scnptr at offset 24 (8 bytes) - file offset to section data
        s_scnptr = struct.unpack('>Q', data[sh_offset+24:sh_offset+32])[0]

        # s_size at offset 32 (8 bytes)
        s_size = struct.unpack('>Q', data[sh_offset+32:sh_offset+40])[0]

        if s_flags & STYP_LOADER:
            return s_scnptr, s_size, s_name

    raise ValueError("No loader section found in XCOFF64 file")

def patch_xcoff(input_file, output_file=None, verbose=True):
    """
    Patch an XCOFF64 binary to remove .text section relocations.

    Args:
        input_file: Path to input XCOFF64 binary
        output_file: Path to output file (default: patch in-place with backup)
        verbose: Print progress messages

    Returns:
        Number of relocations removed
    """
    if output_file is None:
        output_file = input_file
        backup_file = input_file + '.orig'
        shutil.copy2(input_file, backup_file)
        if verbose:
            print(f"Backup created: {backup_file}")

    with open(input_file, 'rb') as f:
        data = bytearray(f.read())

    # Find loader section
    loader_start, loader_size, loader_name = find_loader_section(data)
    if verbose:
        print(f"Loader section '{loader_name}' at offset 0x{loader_start:x}, size {loader_size}")

    # Parse loader header (LDHDR64)
    # l_version at offset 0 (4 bytes)
    l_version = struct.unpack('>I', data[loader_start:loader_start+4])[0]
    if l_version != 2:
        raise ValueError(f"Unexpected loader version: {l_version} (expected 2 for XCOFF64)")

    # l_nreloc at offset 8 (4 bytes) - number of relocations
    l_nreloc = struct.unpack('>I', data[loader_start+8:loader_start+12])[0]

    # l_rldoff at offset 48 (8 bytes) - offset to relocation table from loader header
    l_rldoff = struct.unpack('>Q', data[loader_start+48:loader_start+56])[0]

    reloc_start = loader_start + l_rldoff
    reloc_size = 16  # Each relocation entry is 16 bytes

    if verbose:
        print(f"Original relocation count: {l_nreloc}")
        print(f"Relocation table at: 0x{reloc_start:x}")

    # Find all relocations, separate good (rsecnm != 1) from bad (rsecnm == 1)
    good_relocs = []
    bad_count = 0

    for i in range(l_nreloc):
        offset = reloc_start + i * reloc_size
        reloc_data = bytes(data[offset:offset+reloc_size])

        # l_rsecnm at offset 10 (2 bytes) - section number
        rsecnm = struct.unpack('>H', reloc_data[10:12])[0]

        if rsecnm == 1:  # Targeting .text section
            bad_count += 1
        else:
            good_relocs.append(reloc_data)

    if bad_count == 0:
        if verbose:
            print("No problematic relocations found (rsecnm=1)")
        return 0

    if verbose:
        print(f"Removing {bad_count} broken relocations (rsecnm=1)")
        print(f"Keeping {len(good_relocs)} good relocations")

    # Rewrite relocation table with only good relocations
    for i, reloc_data in enumerate(good_relocs):
        offset = reloc_start + i * reloc_size
        data[offset:offset+reloc_size] = reloc_data

    # Zero out the remaining space (where bad relocs were)
    remaining_start = reloc_start + len(good_relocs) * reloc_size
    remaining_end = reloc_start + l_nreloc * reloc_size
    for i in range(remaining_start, remaining_end):
        data[i] = 0

    # Update l_nreloc in header
    new_nreloc = len(good_relocs)
    data[loader_start+8:loader_start+12] = struct.pack('>I', new_nreloc)

    if verbose:
        print(f"New relocation count: {new_nreloc}")

    # Write patched file
    with open(output_file, 'wb') as f:
        f.write(data)

    if verbose:
        print(f"Patched binary written to: {output_file}")

    return bad_count

def main():
    if len(sys.argv) < 2:
        print(__doc__)
        print("\nUsage: python3 patch_xcoff_tokenizers.py <input.so> [output.so]")
        sys.exit(1)

    input_file = sys.argv[1]
    output_file = sys.argv[2] if len(sys.argv) > 2 else None

    if not os.path.exists(input_file):
        print(f"Error: File not found: {input_file}")
        sys.exit(1)

    try:
        removed = patch_xcoff(input_file, output_file)
        print(f"\nSuccess! Removed {removed} problematic relocations.")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == '__main__':
    main()
