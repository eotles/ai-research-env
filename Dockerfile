FROM mambaorg/micromamba:2.8.1-debian12-slim

WORKDIR /work

# Git, Zsh, GNU time, and related utilities are container-level tooling rather
# than scientific environment dependencies. Keep environment.yml shell-neutral
# and cross-platform. Include OpenSSH and CA certificates so Git works with both
# SSH and HTTPS remotes in remote research environments.
USER root
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      git \
      openssh-client \
      time \
      zsh && \
    rm -rf /var/lib/apt/lists/*
USER $MAMBA_USER

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

# Install the interactive-shell and Jupyter terminal configuration.
COPY --chown=$MAMBA_USER:$MAMBA_USER \
    config/zshrc \
    /home/$MAMBA_USER/.zshrc
COPY --chown=$MAMBA_USER:$MAMBA_USER \
    config/jupyter_server_config.py \
    /opt/ai-research-env/jupyter/jupyter_server_config.py

# Install conda-lock into the base environment, then use the same installation
# mechanism validated by environment-install-check.
RUN micromamba install \
      -y \
      -n base \
      -c conda-forge \
      "conda-lock=3.0.4" && \
    micromamba run \
      -n base \
      conda-lock install \
      --conda "$(command -v micromamba)" \
      --name ai-research-env \
      /tmp/conda-lock.yml && \
    micromamba clean --all --yes && \
    rm -f /tmp/conda-lock.yml

# The micromamba entrypoint activates ENV_NAME for normal container commands.
# Zsh also activates this environment explicitly for interactive sessions.
ENV ENV_NAME=ai-research-env
ENV SHELL=/bin/zsh
ENV JUPYTER_CONFIG_DIR=/opt/ai-research-env/jupyter
ENV PYTHONUNBUFFERED=1

EXPOSE 8888

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--notebook-dir=/work"]
