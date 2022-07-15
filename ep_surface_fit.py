#!/usr/bin/env python

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

    nproc = len(os.sched_getaffinity(0))
    logger.info('Using {} threads.', nproc)
    mapper = PathMapper.file_mapper(inputdir, outputdir, glob='**/*.obj', suffix='.obj')
    with ThreadPoolExecutor(max_workers=nproc) as pool:
        results = pool.map(lambda t: run_surface_fit(*t), mapper)

    if not options.no_fail and not all(results):
        sys.exit(1)


def run_surface_fit(surface: Path, output: Path) -> bool:
    """
    :return: True if successful
    """
    mask = locate_mask_for(surface)
    if mask is None:
        logger.error('No mask found for {}', surface)
        return False
    cmd = ['surface_fit_script.pl', mask, surface, output]
    log_file = output.with_name(output.name + '.log')
    try:
        logger.info('Starting: {}', ' '.join(map(str, cmd)))
        with log_file.open('wb') as log_handle:
            sp.run(cmd, check=True, stdout=log_handle, stderr=log_handle)
        logger.info('Finished: {}', output)
    except sp.CalledProcessError as e:
        logger.error('FAILED: {} -- {}', surface, str(e))
        return False
    return True


def locate_mask_for(surface: Path) -> Optional[Path]:
    name = surface.with_suffix('.mnc').name.replace('._81920', '')
    mask = surface.with_name(name)
    if mask.exists():
        return mask
    return None


if __name__ == '__main__':
    main()
