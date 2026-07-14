FROM mambaorg/micromamba:2.8.1

WORKDIR /work

# The canonical lockfile contains the complete multi-platform environment,
# including both conda and PyPI dependencies.
COPY --chown=$MAMBA_USER:$MAMBA_USER \
    conda-lock.yml \
    /tmp/conda-lock.yml

# Include the canonical runtime smoke test in the image so CI can validate
# the exact built container.
COPY --chown=$MAMBA_USER:$MAMBA_USER \
    scripts/smoke_test.py \
    /opt/ai-research-env/smoke_test.py

# Install conda-lock into the base environment, then use the same installation
# mechanism validated by environment-install-check.
RUN micromamba install \
      -y \
      -n base \
      -c conda-forge \
      "conda-lock=3.*" && \
    micromamba run \
      -n base \
      conda-lock install \
      --conda "$(command -v micromamba)" \
      --name ai-research-env \
      /tmp/conda-lock.yml && \
    micromamba clean --all --yes && \
    rm -f /tmp/conda-lock.yml

# Activate the research environment for container commands and startup.
ENV ENV_NAME=ai-research-env
ENV MAMBA_DOCKERFILE_ACTIVATE=1
ENV PYTHONUNBUFFERED=1

EXPOSE 8888

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--notebook-dir=/work"]
