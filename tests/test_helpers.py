"""
Unit tests for helper functions.
"""

from pathlib import Path
from ep_surface_fit import locate_mask_for


def test_locate_mask_for(tmp_path: Path):
    surface_wo_mask = tmp_path / 'another._81920.extra.obj'
    surface_wo_mask.touch()
    assert locate_mask_for(surface_wo_mask) is None

    surface = tmp_path / 'something._81920.extra.obj'
    mask = tmp_path / 'something.extra.mnc'
    surface.touch()
    mask.touch()
    assert locate_mask_for(surface) == mask
