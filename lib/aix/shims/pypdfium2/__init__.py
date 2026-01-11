"""
pypdfium2 compatibility shim for AIX using Ghostscript.
========================================================

PDFium cannot be built for AIX (it's a large C++ project with many dependencies).
This shim provides the pypdfium2 API using Ghostscript for PDF rendering.

Usage:
    import pypdfium2
    doc = pypdfium2.PdfDocument("file.pdf")
    page = doc[0]
    img = page.render(scale=2.0)
    img.save("page.png")

Requirements:
    - Ghostscript: /opt/freeware/bin/gs
    - pypdf: pip install pypdf
    - Pillow: pip install pillow
"""
import subprocess
import tempfile
import os
from pathlib import Path
from typing import Optional, Union
from io import BytesIO

from PIL import Image
import pypdf


class BitmapConv:
    """Bitmap conversion types (for API compatibility)."""
    pil_image = "pil_image"
    numpy_ndarray = "numpy_ndarray"


class PdfPage:
    """
    Shim for pypdfium2.PdfPage using Ghostscript for rendering.

    Ghostscript provides high-quality PDF rendering and is available
    in the AIX Toolbox.
    """

    def __init__(self, pdf_path: str, page_index: int, pypdf_page):
        self._pdf_path = pdf_path
        self._page_index = page_index
        self._pypdf_page = pypdf_page
        self._width = float(pypdf_page.mediabox.width)
        self._height = float(pypdf_page.mediabox.height)

    def get_width(self) -> float:
        return self._width

    def get_height(self) -> float:
        return self._height

    @property
    def width(self) -> float:
        return self._width

    @property
    def height(self) -> float:
        return self._height

    def render(
        self,
        scale: float = 1.0,
        rotation: int = 0,
        crop: tuple = None,
        grayscale: bool = False,
        fill_color: tuple = (255, 255, 255, 255),
        color_scheme=None,
        optimise_mode=None,
        draw_annots: bool = True,
        draw_forms: bool = True,
        no_smoothtext: bool = False,
        no_smoothimage: bool = False,
        no_smoothpath: bool = False,
        force_halftone: bool = False,
        rev_byteorder: bool = False,
        prefer_bgrx: bool = False,
        force_bitmap_format=None,
        extra_flags: int = 0,
        allocator=None,
        memory_limit: int = 2**30,
        pass_info: bool = False,
        may_draw_forms=None,
    ):
        """Render page to PIL Image using Ghostscript."""
        # Calculate DPI from scale (72 DPI is base PDF resolution)
        dpi = int(72 * scale)

        with tempfile.TemporaryDirectory() as tmpdir:
            output_path = os.path.join(tmpdir, "page.png")

            # Ghostscript command for rendering
            device = "pnggray" if grayscale else "png16m"
            cmd = [
                "/opt/freeware/bin/gs",
                "-q",                      # Quiet mode
                "-dNOPAUSE",               # No pause between pages
                "-dBATCH",                 # Exit after processing
                "-dSAFER",                 # Sandbox mode
                f"-dFirstPage={self._page_index + 1}",
                f"-dLastPage={self._page_index + 1}",
                f"-sDEVICE={device}",
                f"-r{dpi}",
                f"-sOutputFile={output_path}",
                self._pdf_path
            ]

            try:
                result = subprocess.run(
                    cmd,
                    capture_output=True,
                    timeout=120  # 2 minute timeout per page
                )

                if os.path.exists(output_path):
                    img = Image.open(output_path)
                    img.load()  # Load into memory before tempdir cleanup

                    # Apply rotation if needed
                    if rotation:
                        img = img.rotate(-rotation, expand=True)

                    # Apply crop if specified
                    if crop:
                        img = img.crop(crop)

                    return img
                else:
                    # Return blank image if rendering fails
                    width = int(self._width * scale)
                    height = int(self._height * scale)
                    return Image.new('RGB', (width, height), fill_color[:3])

            except subprocess.TimeoutExpired:
                # Return blank image on timeout
                width = int(self._width * scale)
                height = int(self._height * scale)
                return Image.new('RGB', (width, height), fill_color[:3])
            except Exception as e:
                # Return blank image on other errors
                width = int(self._width * scale)
                height = int(self._height * scale)
                return Image.new('RGB', (width, height), fill_color[:3])

    def render_to(
        self,
        buffer,
        scale: float = 1.0,
        rotation: int = 0,
        **kwargs
    ):
        """Render page to an existing buffer."""
        img = self.render(scale=scale, rotation=rotation, **kwargs)
        buffer[:] = img.tobytes()

    def close(self):
        """Close the page (no-op for this shim)."""
        pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


class PdfDocument:
    """
    Shim for pypdfium2.PdfDocument.

    Uses pypdf for PDF metadata and Ghostscript for rendering.
    """

    def __init__(
        self,
        input_data: Union[str, Path, bytes, BytesIO],
        password: Optional[str] = None,
        autoclose: bool = False,
    ):
        self._pages = []
        self._pdf_path = None
        self._temp_file = None
        self._autoclose = autoclose

        # Handle different input types
        if isinstance(input_data, (str, Path)):
            self._pdf_path = str(input_data)
            self._reader = pypdf.PdfReader(input_data, password=password)
        elif isinstance(input_data, bytes):
            self._temp_file = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
            self._temp_file.write(input_data)
            self._temp_file.close()
            self._pdf_path = self._temp_file.name
            self._reader = pypdf.PdfReader(BytesIO(input_data), password=password)
        elif isinstance(input_data, BytesIO):
            self._temp_file = tempfile.NamedTemporaryFile(suffix='.pdf', delete=False)
            self._temp_file.write(input_data.read())
            self._temp_file.close()
            self._pdf_path = self._temp_file.name
            input_data.seek(0)
            self._reader = pypdf.PdfReader(input_data, password=password)
        else:
            raise TypeError(f"Unsupported input type: {type(input_data)}")

        # Create page objects
        for i, page in enumerate(self._reader.pages):
            self._pages.append(PdfPage(self._pdf_path, i, page))

    def __len__(self) -> int:
        return len(self._pages)

    def __getitem__(self, index: int) -> PdfPage:
        return self._pages[index]

    def __iter__(self):
        return iter(self._pages)

    def get_page(self, index: int) -> PdfPage:
        """Get page by index."""
        return self._pages[index]

    @property
    def page_count(self) -> int:
        """Return number of pages."""
        return len(self._pages)

    def close(self):
        """Clean up temporary files."""
        if self._temp_file and os.path.exists(self._temp_file.name):
            try:
                os.unlink(self._temp_file.name)
            except OSError:
                pass

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()

    def __del__(self):
        if self._autoclose:
            self.close()


# Module-level function to match pypdfium2 API
def PdfDocument_new(input_data, password=None, autoclose=False):
    """Create a new PdfDocument (alternate API)."""
    return PdfDocument(input_data, password, autoclose)


# Version info (claim compatible version)
__version__ = "4.30.0"
version = (4, 30, 0)
V_LIBPDFIUM = "ghostscript-shim"
V_BUILDNAME = "aix-ghostscript"
PDFIUM_INFO = {
    'origin': 'ghostscript-shim',
    'build': 'aix',
    'flags': [],
    'n_features': 0,
}
