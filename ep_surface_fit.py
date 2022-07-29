#!/usr/bin/env python
import itertools
import os
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
 ___ _   _ _ __| |_ __ _  ___ ___  | |_ _| |_
/ __| | | | '__|  _/ _` |/ __/ _ \ |  _| | __|
\__ \ |_| | |  | || (_| | (_|  __/ | | | | |_
|___/\__,_|_|  |_| \__,_|\___\___| |_| |_|\__|
                               ______
                              |______|

        Parameterized batch experiment

"""

parser = ArgumentParser(description='surface_fit wrapper',
                        formatter_class=ArgumentDefaultsHelpFormatter)
parser.add_argument('--no-fail', dest='no_fail', action='store_true',
                    help='Produce exit code 0 even if any subprocesses do not.')
parser.add_argument('--sw', type=int, default=200, help='stretch weight')
parser.add_argument('--lw', type=float, default=5e-6, help='laplacian weight')
parser.add_argument('--iter', type=int, default=600, help='iterations')


parser.add_argument('-V', '--version', action='version',
                    version=f'%(prog)s {__version__}')


@chris_plugin(
    parser=parser,
    title='surface_fit experiment',
    category='Experimental',
    min_memory_limit='1Gi',
    min_cpu_limit='1000m',
)
def main(options: Namespace, inputdir: Path, outputdir: Path):
    print(DISPLAY_TITLE, file=sys.stderr, flush=True)

    params = [
        '-lw',
        str(options.lw),
        '-sw',
        str(options.sw),
        '-iter',
        str(options.iter)
    ]

    nproc = len(os.sched_getaffinity(0))
    logger.info('Using {} threads.', nproc)
    mapper = PathMapper.file_mapper(inputdir, outputdir, glob='**/*.obj', suffix='.obj')
    with ThreadPoolExecutor(max_workers=nproc) as pool:
        results = pool.map(lambda t, p: run_surface_fit(*t, p), mapper, itertools.repeat(params))

    if not options.no_fail and not all(results):
        sys.exit(1)


def run_surface_fit(surface: Path, output: Path, params: list[str]) -> bool:
    """
    :return: True if successful
    """
    mask = locate_mask_for(surface)
    if mask is None:
        logger.error('No mask found for {}', surface)
        return False

    cmd = ['surface_fit_script.pl', *params, mask, surface, output]
    log_file = output.with_name(output.name + '.log')
    logger.info('Starting: {}', ' '.join(map(str, cmd)))
    with log_file.open('wb') as log_handle:
        job = sp.run(cmd, stdout=log_handle, stderr=log_handle)
    rc_file = log_file.with_suffix('.rc')
    rc_file.write_text(str(job.returncode))

    if job.returncode == 0:
        logger.info('Finished: {} -> {}', mask, output)
        return True

    logger.error('FAILED -- check log file for details: {}', log_file)
    return False


def locate_mask_for(surface: Path) -> Optional[Path]:
    name = surface.with_suffix('.mnc').name.replace('._81920', '')
    mask = surface.with_name(name)
    if mask.exists():
        return mask

    glob = surface.parent.glob('*.mnc')
    first = next(glob, None)
    second = next(glob, None)
    if second is not None:
        return None
    return first


if __name__ == '__main__':
    main()
