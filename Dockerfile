FROM docker.io/fnndsc/mni-conda-base:civet2.1.1-python3.10.5

LABEL org.opencontainers.image.authors="Jennings Zhang <Jennings.Zhang@childrens.harvard.edu>" \
      org.opencontainers.image.title="surface_fit experiment" \
      org.opencontainers.image.description="surface_fit ChRIS plugin wrapper"

WORKDIR /usr/local/src/ep-radial_surface_fit_parameterized

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .
ARG extras_require=none
RUN pip install ".[${extras_require}]"

CMD ["ep_surface_fit", "--help"]
