FROM mambaorg/micromamba:1.5.10

WORKDIR /work

COPY locks/conda-linux-64.lock /tmp/conda-linux-64.lock
COPY locks/conda-linux-aarch64.lock /tmp/conda-linux-aarch64.lock

ARG TARGETARCH

RUN if [ "$TARGETARCH" = "arm64" ]; then \
      LOCK=/tmp/conda-linux-aarch64.lock; \
    else \
      LOCK=/tmp/conda-linux-64.lock; \
    fi && \
    micromamba create -y -n ai-research-env -f "$LOCK" && \
    micromamba clean -a -y

# Make micromamba activate the right env on container start
ENV ENV_NAME=ai-research-env
ENV MAMBA_DOCKERFILE_ACTIVATE=1

EXPOSE 8888
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--allow-root", "--notebook-dir=/work"]
