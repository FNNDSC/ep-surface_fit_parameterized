# surface_fit experiment

[![Version](https://img.shields.io/docker/v/fnndsc/ep-surface_fit_parameterized?sort=semver)](https://hub.docker.com/r/fnndsc/ep-surface_fit_parameterized)
[![MIT License](https://img.shields.io/github/license/fnndsc/ep-surface_fit_parameterized)](https://github.com/FNNDSC/ep-surface_fit_parameterized/blob/main/LICENSE)
[![ci](https://github.com/FNNDSC/ep-surface_fit_parameterized/actions/workflows/ci.yml/badge.svg)](https://github.com/FNNDSC/ep-surface_fit_parameterized/actions/workflows/ci.yml)

`ep-surface_fit_parameterized` is a [_ChRIS_](https://chrisproject.org/) plugin
for experimenting with the parameters of `surface_fit` (ASP algorithm from CIVET).

## Usage

`surface_fit_script.pl` is a Perl wrapper for `surface_fit`.
`ep_surface_fit(.py)` is a Python script for running `surface_fit_script.pl`
as a _ChRIS_ _ds_-plugin on multiple subjects.

`ep_surface_fit` processes every laplacian grid (`*.mnc`) + starting surface (`*.obj`)
pair found in its input directory. For every `*.mnc` file found, `ep_surface_fit` will
search for a `*.obj` surface file in the same directory to use as a starting surface.

When multiple inputs are found, they are processed in parallel.

### Parameters

Multiple stages of `surface_fit` can be run by specifying multiple values
as a comma-separated list.
If some parameter values are given as CSV whereas others are given as singular,
the singular value is reused for later iterations. Example:

```shell
ep_surface_fit --iter-outer 100,100,400 --stretch-weight 80,60,40 --laplacian-weight 1e-4 ...
```

The schedule is interpreted as:

1. 100 iterations with sw=80 lw=1e-4
2. 100 iterations with sw=60 lw=1e-4
3. 400 iterations with sw=40 lw=1e-4

#### `--size`

Number of triangles in the surface mesh, i.e. resolution

- 20480 improves performance and is more suitable for fetal brains 20-28 GA
- 81920 is standard
- 327680 is used for high-resolution adult human brain

...
