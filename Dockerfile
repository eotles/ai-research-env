FROM mambaorg/micromamba:1.5.10

WORKDIR /work

COPY locks/conda-linux-64.lock /tmp/conda-linux-64.lock
COPY locks/conda-linux-aarch64.lock /tmp/conda-linux-aarch64.lock
COPY requirements-docker.txt /tmp/requirements-docker.txt

ARG TARGETARCH

RUN if [ "$TARGETARCH" = "arm64" ]; then \
      LOCK=/tmp/conda-linux-aarch64.lock; \
    else \
      LOCK=/tmp/conda-linux-64.lock; \
    fi && \
    micromamba create -y -n ai-research-env -f "$LOCK" && \
    micromamba clean -a -y

# Install pip-only packages not captured in the conda explicit lockfile
RUN micromamba run -n ai-research-env pip install -r /tmp/requirements-docker.txt

# Make micromamba activate the right env on container start
ENV ENV_NAME=ai-research-env
ENV MAMBA_DOCKERFILE_ACTIVATE=1

EXPOSE 8888
EXPOSE 8000
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--notebook-dir=/work"]
