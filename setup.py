from setuptools import setup

setup(
    name='ep_surface_fit',
    version='0.4.0',
    description='surface_fit wrapper',
    author='Jennings Zhang',
    author_email='Jennings.Zhang@childrens.harvard.edu',
    url='https://github.com/FNNDSC/ep-surface_fit_parameterized',
    py_modules=['ep_surface_fit'],
    scripts=['surface_fit_script.pl'],
    install_requires=['chris_plugin'],
    license='MIT',
    entry_points={
        'console_scripts': [
            'ep_surface_fit = ep_surface_fit:main'
        ]
    },
    classifiers=[
        'License :: OSI Approved :: MIT License',
        'Topic :: Scientific/Engineering',
        'Topic :: Scientific/Engineering :: Bio-Informatics',
        'Topic :: Scientific/Engineering :: Medical Science Apps.'
    ],
    extras_require={
        'none': [],
        'dev': [
            'pytest~=7.1'
        ]
    }
)
