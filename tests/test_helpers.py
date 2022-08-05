"""
Unit tests for helper functions.
"""

from pathlib import Path
from ep_surface_fit import locate_surface_for


def test_locate_mask_for(tmp_path: Path):
    mask_wo_surface = tmp_path / 'mask.mnc'
    mask_wo_surface.touch()
    assert locate_surface_for(mask_wo_surface) is None

    surface = tmp_path / 'something._81920.extra.obj'
    mask = tmp_path / 'something.extra.mnc'
    surface.touch()
    mask.touch()
    assert locate_surface_for(mask) == surface
