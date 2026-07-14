"""Runtime smoke test for ai-research-env.

This script verifies that the complete installed environment is usable, not
merely that dependency resolution succeeded.
"""

from __future__ import annotations

import importlib
import importlib.metadata
import shutil
import subprocess
import sys
from collections.abc import Callable


EXPECTED_PYTHON_MAJOR = 3
EXPECTED_PYTHON_MINOR = 12


DISTRIBUTIONS = [
    "numpy",
    "pandas",
    "scipy",
    "scikit-learn",
    "polars",
    "pyarrow",
    "torch",
    "transformers",
    "accelerate",
    "lightning",
    "torchmetrics",
    "safetensors",
    "meds",
    "MEDS-transforms",
    "MEDS-extract",
    "MEDS-trajectory-evaluation",
]


MODULES = [
    "numpy",
    "pandas",
    "scipy",
    "sklearn",
    "polars",
    "pyarrow",
    "torch",
    "tensorflow",
    "transformers",
    "accelerate",
    "lightning",
    "torchmetrics",
    "safetensors",
    "meds",
    "MEDS_transforms",
    "MEDS_extract",
    "MEDS_trajectory_evaluation",
]


COMMANDS = [
    "java",
    "jupyter",
    "MEDS_transform-pipeline",
    "ZSACES_label",
]


def print_section(title: str) -> None:
    """Print a readable section heading."""
    print()
    print("=" * 79)
    print(title)
    print("=" * 79)


def check_python_version() -> None:
    """Verify the expected Python major and minor version."""
    actual = (sys.version_info.major, sys.version_info.minor)
    expected = (EXPECTED_PYTHON_MAJOR, EXPECTED_PYTHON_MINOR)

    print(f"Python executable: {sys.executable}")
    print(f"Python version:    {sys.version}")

    if actual != expected:
        raise RuntimeError(
            f"Expected Python {expected[0]}.{expected[1]}, "
            f"but found {actual[0]}.{actual[1]}."
        )


def check_distribution_versions() -> None:
    """Verify expected distributions are installed and print their versions."""
    for distribution in DISTRIBUTIONS:
        try:
            version = importlib.metadata.version(distribution)
        except importlib.metadata.PackageNotFoundError as exc:
            raise RuntimeError(
                f"Required distribution is not installed: {distribution}"
            ) from exc

        print(f"{distribution}: {version}")


def check_imports() -> None:
    """Import all expected top-level Python modules."""

    failures: list[tuple[str, Exception]] = []

    for module_name in MODULES:
        try:
            importlib.import_module(module_name)
        except Exception as exc:
            failures.append((module_name, exc))
            print(f"FAILED: {module_name}: {exc}")
        else:
            print(f"Imported: {module_name}")

    if failures:
        details = "\n".join(
            f"- {module_name}: {type(exc).__name__}: {exc}"
            for module_name, exc in failures
        )

        raise RuntimeError(
            "One or more required modules failed to import:\n"
            f"{details}"
        )


def check_commands() -> None:
    """Verify expected command-line tools are available."""
    for command in COMMANDS:
        executable = shutil.which(command)

        if executable is None:
            raise RuntimeError(
                f"Required command was not found on PATH: {command}"
            )

        print(f"{command}: {executable}")


def check_java() -> None:
    """Verify that the Java runtime starts successfully."""
    result = subprocess.run(
        ["java", "-version"],
        check=False,
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        raise RuntimeError(
            "Java runtime check failed.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )

    version_output = result.stderr.strip() or result.stdout.strip()
    print(version_output)


def check_pytorch() -> None:
    """Run a small PyTorch transformer forward pass."""
    import torch

    torch.manual_seed(0)

    encoder_layer = torch.nn.TransformerEncoderLayer(
        d_model=32,
        nhead=4,
        dim_feedforward=64,
        batch_first=True,
    )

    model = torch.nn.TransformerEncoder(
        encoder_layer,
        num_layers=2,
    )

    x = torch.randn(2, 16, 32)

    with torch.no_grad():
        y = model(x)

    if y.shape != x.shape:
        raise RuntimeError(
            f"Unexpected PyTorch output shape: {tuple(y.shape)}. "
            f"Expected: {tuple(x.shape)}."
        )

    if not torch.isfinite(y).all():
        raise RuntimeError(
            "PyTorch transformer forward pass produced non-finite values."
        )

    print(f"PyTorch version: {torch.__version__}")
    print(f"Output shape:    {tuple(y.shape)}")
    print("PyTorch transformer forward pass succeeded.")


def check_tensorflow() -> None:
    """Run a small TensorFlow computation."""
    import tensorflow as tf

    a = tf.constant(
        [
            [1.0, 2.0],
            [3.0, 4.0],
        ]
    )

    b = tf.constant(
        [
            [5.0, 6.0],
            [7.0, 8.0],
        ]
    )

    result = tf.matmul(a, b)

    expected_shape = (2, 2)

    if tuple(result.shape) != expected_shape:
        raise RuntimeError(
            f"Unexpected TensorFlow output shape: {tuple(result.shape)}. "
            f"Expected: {expected_shape}."
        )

    print(f"TensorFlow version: {tf.__version__}")
    print(f"Output shape:       {tuple(result.shape)}")
    print("TensorFlow matrix multiplication succeeded.")


def check_transformers() -> None:
    """Instantiate and run a tiny Hugging Face transformer without downloads."""
    import torch
    from transformers import BertConfig, BertModel

    config = BertConfig(
        vocab_size=128,
        hidden_size=32,
        num_hidden_layers=2,
        num_attention_heads=4,
        intermediate_size=64,
        max_position_embeddings=64,
    )

    model = BertModel(config)
    model.eval()

    input_ids = torch.randint(
        low=0,
        high=config.vocab_size,
        size=(2, 16),
    )

    with torch.no_grad():
        output = model(input_ids=input_ids)

    expected_shape = (2, 16, 32)
    actual_shape = tuple(output.last_hidden_state.shape)

    if actual_shape != expected_shape:
        raise RuntimeError(
            f"Unexpected Transformers output shape: {actual_shape}. "
            f"Expected: {expected_shape}."
        )

    print(f"Output shape: {actual_shape}")
    print("Transformers forward pass succeeded.")


def run_check(name: str, check: Callable[[], None]) -> None:
    """Run one named smoke-test component."""
    print_section(name)
    check()
    print(f"\nPASS: {name}")


def main() -> None:
    """Run the complete environment smoke test."""
    checks: list[tuple[str, Callable[[], None]]] = [
        ("Python runtime", check_python_version),
        ("Installed distribution versions", check_distribution_versions),
        ("Python imports", check_imports),
        ("Command-line tools", check_commands),
        ("Java runtime", check_java),
        ("PyTorch computation", check_pytorch),
        ("TensorFlow computation", check_tensorflow),
        ("Transformers computation", check_transformers),
    ]

    for name, check in checks:
        run_check(name, check)

    print_section("Environment smoke test")
    print("PASS: all environment smoke tests succeeded.")


if __name__ == "__main__":
    main()
