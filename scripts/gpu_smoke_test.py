#!/usr/bin/env python3
"""Validate the CUDA-capable ai-research-env image.

GitHub-hosted CI runs this without a GPU to confirm that the image contains a
CUDA-enabled PyTorch build. GPU-backed systems such as EFabric run it with
``--require-cuda`` to validate real device execution.
"""

from __future__ import annotations

import argparse
import math
import os
import subprocess
import sys
import textwrap

import torch


def section(title: str) -> None:
    print("\n" + "=" * 79)
    print(title)
    print("=" * 79)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def validate_runtime_defaults() -> None:
    section("PyTorch-first Transformers defaults")

    expected = {
        "USE_TORCH": "1",
        "USE_TF": "0",
    }

    for name, value in expected.items():
        actual = os.environ.get(name)
        require(
            actual == value,
            f"Expected {name}={value!r}, found {actual!r}.",
        )
        print(f"{name}={actual}")

    code = textwrap.dedent(
        """
        import sys

        from transformers import BertConfig, BertModel
        from transformers.utils import is_tf_available, is_torch_available

        if not is_torch_available():
            raise RuntimeError("Transformers does not report PyTorch as available.")
        if is_tf_available():
            raise RuntimeError("Transformers unexpectedly reports TensorFlow as available.")
        if "tensorflow" in sys.modules:
            raise RuntimeError("TensorFlow was imported during a PyTorch-only Transformers import.")

        config = BertConfig(
            vocab_size=128,
            hidden_size=32,
            num_hidden_layers=1,
            num_attention_heads=4,
            intermediate_size=64,
            max_position_embeddings=64,
        )
        model = BertModel(config)

        if "tensorflow" in sys.modules:
            raise RuntimeError("TensorFlow was imported while constructing a PyTorch model.")

        print("Transformers backend: PyTorch")
        print("TensorFlow imported: no")
        """
    )

    result = subprocess.run(
        [sys.executable, "-c", code],
        check=False,
        capture_output=True,
        text=True,
        env=os.environ.copy(),
    )

    if result.returncode != 0:
        raise RuntimeError(
            "PyTorch-first Transformers isolation check failed.\n"
            f"stdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )

    print(result.stdout.strip())
    print("PASS: Transformers uses PyTorch without importing TensorFlow.")


def validate_cuda_build() -> None:
    section("CUDA-enabled PyTorch build")

    print(f"PyTorch version:       {torch.__version__}")
    print(f"Compiled CUDA runtime: {torch.version.cuda}")
    print(f"CUDA backend built:    {torch.backends.cuda.is_built()}")
    print(f"CUDA available now:    {torch.cuda.is_available()}")

    require(torch.backends.cuda.is_built(), "PyTorch was not built with CUDA support.")
    require(torch.version.cuda is not None, "PyTorch does not report a CUDA runtime.")
    require(
        torch.version.cuda.startswith("12.4"),
        f"Expected CUDA 12.4 build, found {torch.version.cuda!r}.",
    )

    print("PASS: CUDA-enabled PyTorch build is present.")


def validate_device() -> None:
    section("CUDA device")

    require(torch.cuda.is_available(), "No CUDA device is visible to PyTorch.")
    require(torch.cuda.device_count() >= 1, "CUDA reported no usable devices.")

    index = torch.cuda.current_device()
    props = torch.cuda.get_device_properties(index)

    print(f"Device index:          {index}")
    print(f"Device name:           {props.name}")
    print(f"Compute capability:    {props.major}.{props.minor}")
    print(f"Total memory (GiB):    {props.total_memory / (1024 ** 3):.2f}")
    print(f"BF16 supported:        {torch.cuda.is_bf16_supported()}")

    print("PASS: CUDA device is visible.")


def validate_bf16_matmul() -> None:
    section("BF16 matrix multiplication")

    require(torch.cuda.is_bf16_supported(), "Visible CUDA device does not support BF16.")

    torch.manual_seed(7)
    a = torch.randn((512, 512), device="cuda", dtype=torch.bfloat16)
    b = torch.randn((512, 512), device="cuda", dtype=torch.bfloat16)
    out = a @ b

    require(out.dtype == torch.bfloat16, f"Unexpected output dtype: {out.dtype}")
    require(torch.isfinite(out.float()).all().item(), "BF16 matmul produced non-finite values.")

    print(f"Output shape: {tuple(out.shape)}")
    print("PASS: BF16 matrix multiplication succeeded.")


def validate_sdpa() -> None:
    section("Scaled dot-product attention")

    torch.manual_seed(11)
    q = torch.randn((2, 4, 64, 64), device="cuda", dtype=torch.bfloat16)
    k = torch.randn((2, 4, 64, 64), device="cuda", dtype=torch.bfloat16)
    v = torch.randn((2, 4, 64, 64), device="cuda", dtype=torch.bfloat16)

    out = torch.nn.functional.scaled_dot_product_attention(q, k, v)

    require(out.shape == q.shape, f"Unexpected SDPA output shape: {tuple(out.shape)}")
    require(torch.isfinite(out.float()).all().item(), "SDPA produced non-finite values.")

    print(f"Output shape: {tuple(out.shape)}")
    print("PASS: scaled dot-product attention succeeded.")


def validate_transformers_forward() -> None:
    section("Transformers CUDA forward pass")

    from transformers import GPT2Config, GPT2LMHeadModel

    config = GPT2Config(
        vocab_size=256,
        n_positions=128,
        n_ctx=128,
        n_embd=64,
        n_layer=2,
        n_head=4,
        use_cache=False,
    )
    model = GPT2LMHeadModel(config).to(device="cuda", dtype=torch.bfloat16)
    model.eval()

    input_ids = torch.randint(0, config.vocab_size, (2, 64), device="cuda")

    with torch.inference_mode():
        logits = model(input_ids=input_ids).logits

    require(logits.device.type == "cuda", f"Model output is on {logits.device}.")
    require(logits.shape == (2, 64, config.vocab_size), f"Unexpected logits shape: {logits.shape}")
    require(torch.isfinite(logits.float()).all().item(), "Transformer forward pass produced non-finite values.")

    checksum = logits.float().abs().mean().item()
    require(math.isfinite(checksum), "Transformer checksum is not finite.")

    print(f"Output shape: {tuple(logits.shape)}")
    print(f"Mean |logit|: {checksum:.6f}")
    print("PASS: Transformers CUDA forward pass succeeded.")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--require-cuda",
        action="store_true",
        help="Require a visible GPU and execute CUDA/BF16 runtime tests.",
    )
    args = parser.parse_args()

    try:
        validate_runtime_defaults()
        validate_cuda_build()

        if args.require_cuda:
            validate_device()
            validate_bf16_matmul()
            validate_sdpa()
            validate_transformers_forward()
        else:
            section("Hardware qualification")
            print("CUDA execution was not required for this run.")
            print("Run with --require-cuda on EFabric or another GPU-backed host.")

        section("GPU smoke test")
        print("PASS: all requested GPU smoke tests succeeded.")
        return 0

    except Exception as exc:  # noqa: BLE001
        print(f"\nFAIL: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
