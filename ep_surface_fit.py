#!/usr/bin/env python
import itertools
import os
import shutil
import sys
from pathlib import Path
from argparse import ArgumentParser, Namespace, ArgumentDefaultsHelpFormatter
from importlib.metadata import Distribution
from typing import Optional
from concurrent.futures import ThreadPoolExecutor
import subprocess as sp
from chris_plugin import chris_plugin, PathMapper
from loguru import logger


__pkg = Distribution.from_name(__package__)
__version__ = __pkg.version


DISPLAY_TITLE = r"""
                                  __                  __ _ _   
                                 / _|                / _(_) |  
  ___ _ __ ______ ___ _   _ _ __| |_ __ _  ___ ___  | |_ _| |_ 
 / _ \ '_ \______/ __| | | | '__|  _/ _` |/ __/ _ \ |  _| | __|
|  __/ |_) |     \__ \ |_| | |  | || (_| | (_|  __/ | | | | |_ 
 \___| .__/      |___/\__,_|_|  |_| \__,_|\___\___| |_| |_|\__|
     | |                                        ______         
     |_|                                       |______|        

             Parameterized batch experiment

"""

parser = ArgumentParser(description='surface_fit wrapper',
                        formatter_class=ArgumentDefaultsHelpFormatter)
parser.add_argument('--no-fail', dest='no_fail', action='store_true',
                    help='Produce exit code 0 even if any subprocesses do not.')
parser.add_argument('-V', '--version', action='version',
                    version=f'%(prog)s {__version__}')

parser.add_argument('--size', type=str, default='81920', help='number of polygons')
parser.add_argument('--stretch-weight', type=str, default='100', help='stretch weight')
parser.add_argument('--laplacian-weight', type=str, default='5e-6', help='laplacian weight')
parser.add_argument('--iter-outer', type=str, default='1000', help='total number of iterations per stage')
parser.add_argument('--iter-inner', type=str, default='50', help='save every few iterations')
parser.add_argument('--iso-value', type=str, default='10',
                    help='Chamfer value of laplacian map indicating mask boundary (i.e. target value)')
parser.add_argument('--step-size', type=str, default='0.10', help='Step size per iteration')
parser.add_argument('--oversample', type=str, default='0', help='subsampling (0=none, n=#points extra along edge)')
parser.add_argument('--self-dist', type=str, default='0.01', help='distance to check for self-intersection')
parser.add_argument('--self-weight', type=str, default='1.0', help='weight for self-intersection constraint')
parser.add_argument('--taubin', type=str, default='0',
                    help='iterations of taubin smoothing to perform between cycles of surface_fit')


@chris_plugin(
    parser=parser,
    title='surface_fit experiment',
    category='Experiment',
    min_memory_limit='1Gi',
    min_cpu_limit='1000m',
)
def main(options: Namespace, inputdir: Path, outputdir: Path):
    print(DISPLAY_TITLE, file=sys.stderr, flush=True)

    params = [
        '-size',
        options.size,
        '-sw',
        options.stretch_weight,
        '-lw',
        options.laplacian_weight,
        '-iter-outer',
        options.iter_outer,
        '-iter-inner',
        options.iter_inner,
        '-iso-value',
        options.iso_value,
        '-step-size',
        options.step_size,
        '-oversample',
        options.oversample,
        '-self-dist',
        options.self_dist,
        '-self-weight',
        options.self_weight,
        '-taubin',
        options.taubin
    ]

    nproc = len(os.sched_getaffinity(0))
    logger.info('Using {} threads.', nproc)

    mapper = PathMapper.file_mapper(inputdir, outputdir, glob='**/*.mnc', suffix='.obj')
    with ThreadPoolExecutor(max_workers=nproc) as pool:
        results = pool.map(lambda t, p: run_surface_fit(*t, p), mapper, itertools.repeat(params))

    if not options.no_fail and not all(results):
        sys.exit(1)


def run_surface_fit(grid: Path, output_surf: Path, params: list[str]) -> bool:
    """
    :return: True if successful
    """
    starting_surface = locate_surface_for(grid)
    if starting_surface is None:
        logger.error('No starting surface found for {}', grid)
        return False

    cmd = ['surface_fit_script.pl', *params, grid, starting_surface, output_surf]
    log_file = output_surf.with_name(output_surf.name + '.log')
    logger.info('Starting: {}', ' '.join(map(str, cmd)))
    with log_file.open('wb') as log_handle:
        job = sp.run(cmd, stdout=log_handle, stderr=log_handle)
    rc_file = log_file.with_suffix('.rc')
    rc_file.write_text(str(job.returncode))

    if job.returncode == 0:
        logger.info('Finished: {} -> {}', starting_surface, output_surf)
        return True

    logger.error('FAILED -- check log file for details: {}', log_file)
    return False


def locate_surface_for(mask: Path) -> Optional[Path]:
    glob = mask.parent.glob('*.obj')
    first = next(glob, None)
    second = next(glob, None)
    if second is not None:
        return None
    return first


if __name__ == '__main__':
    main()
