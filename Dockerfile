FROM mambaorg/micromamba:1.5.10

WORKDIR /work

# Copy the Linux lockfile into the image
COPY locks/conda-linux-64.lock /tmp/conda-linux-64.lock

# Create the environment (name matches repo)
RUN micromamba create -y -n ai-research-env -f /tmp/conda-linux-64.lock && \
    micromamba clean -a -y

# Ensure the env is active for CMD/ENTRYPOINT commands
ENV MAMBA_DOCKERFILE_ACTIVATE=1
ENV ENV_NAME=ai-research-env

EXPOSE 8888

# Default: start JupyterLab (prints a token URL in logs)
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--notebook-dir=/work"]
