"""Jupyter Server configuration for ai-research-env containers."""

c = get_config()  # noqa: F821

# Always launch a full Zsh login shell in JupyterLab terminals. This avoids
# minimal /bin/sh terminal behavior and provides normal history/editing keys.
c.ServerApp.terminado_settings = {
    "shell_command": ["/bin/zsh", "-l"],
}
