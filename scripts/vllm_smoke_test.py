#!/usr/bin/env python3

import argparse
import os
import shutil
import sys


MIN_NVIDIA_COMPUTE_CAPABILITY = (7, 5)


def section(title: str) -> None:
    print("=" * 79)
    print(title)
    print("=" * 79)


def configure_runtime_defaults(*, fast_model_smoke: bool) -> None:
    # vLLM collects anonymous usage statistics by default. Keep the project
    # research runtime quiet and deterministic unless a caller explicitly opts in.
    os.environ.setdefault("VLLM_NO_USAGE_STATS", "1")

    # FlashInfer's top-k/top-p sampler can JIT-compile CUDA extensions. Stock
    # EFabric GPU workspaces expose the CUDA runtime/driver but not nvcc, so use
    # vLLM's PyTorch-native sampler when a CUDA compiler is unavailable. This
    # does not disable FlashAttention or other optimized model-attention paths.
    if shutil.which("nvcc") is None:
        os.environ.setdefault("VLLM_USE_FLASHINFER_SAMPLER", "0")

    # A real-model smoke test is intended to validate that vLLM can load and
    # generate, not benchmark production startup. Keeping the V1 engine core in
    # process avoids a costly Python spawn/import cycle on EFabric. Production
    # vLLM usage is left at the upstream multiprocessing default.
    if fast_model_smoke:
        os.environ.setdefault("VLLM_ENABLE_V1_MULTIPROCESSING", "0")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Validate the isolated vLLM companion runtime."
    )
    parser.add_argument(
        "--require-cuda",
        action="store_true",
        help="Fail unless a supported NVIDIA CUDA device is visible.",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Optionally load a model and perform a real vLLM generation.",
    )
    parser.add_argument(
        "--full-engine",
        action="store_true",
        help=(
            "Use vLLM's normal multiprocessing/compiled engine for the model "
            "test instead of the faster smoke-test startup path."
        ),
    )
    args = parser.parse_args()

    configure_runtime_defaults(
        fast_model_smoke=bool(args.model) and not args.full_engine,
    )

    import torch
    import vllm

    section("vLLM runtime")
    print(f"Python:              {sys.version.splitlines()[0]}")
    print(f"vLLM version:        {vllm.__version__}")
    print(f"PyTorch version:     {torch.__version__}")
    print(f"Compiled CUDA:       {torch.version.cuda}")
    print(f"CUDA available:      {torch.cuda.is_available()}")
    print(
        "FlashInfer sampler:  "
        f"{os.environ.get('VLLM_USE_FLASHINFER_SAMPLER', 'upstream default')}"
    )
    print(f"Usage stats disabled: {os.environ.get('VLLM_NO_USAGE_STATS', '0')}")
    if args.model:
        print(
            "Engine smoke mode:   "
            + ("full" if args.full_engine else "fast (in-process/eager)")
        )

    expected_version = os.environ.get("AI_RESEARCH_ENV_VLLM_VERSION")
    if expected_version and vllm.__version__ != expected_version:
        raise RuntimeError(
            "vLLM version does not match the configured runtime: "
            f"expected {expected_version}, found {vllm.__version__}."
        )

    if args.require_cuda and not torch.cuda.is_available():
        raise RuntimeError("CUDA is required but no CUDA device is visible.")

    if torch.cuda.is_available():
        section("CUDA device")
        device = torch.cuda.current_device()
        props = torch.cuda.get_device_properties(device)
        capability = (props.major, props.minor)
        print(f"Device index:         {device}")
        print(f"Device name:          {props.name}")
        print(f"Compute capability:   {props.major}.{props.minor}")
        print(f"Total memory (GiB):   {props.total_memory / 2**30:.2f}")
        print(f"BF16 supported:       {torch.cuda.is_bf16_supported()}")

        if capability < MIN_NVIDIA_COMPUTE_CAPABILITY:
            minimum = ".".join(str(part) for part in MIN_NVIDIA_COMPUTE_CAPABILITY)
            raise RuntimeError(
                "Visible NVIDIA GPU is below the supported vLLM compute "
                f"capability: found {props.major}.{props.minor}, need >= {minimum}."
            )

    if args.model:
        if not torch.cuda.is_available():
            raise RuntimeError("A model smoke test requires a visible CUDA device.")

        section("Real vLLM generation")
        from vllm import LLM, SamplingParams

        print(f"Model:                {args.model}")
        llm_kwargs = {
            "model": args.model,
            "dtype": "auto",
            "max_model_len": 512,
            "gpu_memory_utilization": 0.35,
        }
        if not args.full_engine:
            # Avoid torch.compile and CUDA graph capture for the qualification
            # smoke test. The full production path was separately qualified and
            # remains vLLM's default outside this script.
            llm_kwargs["enforce_eager"] = True

        llm = LLM(**llm_kwargs)
        sampling_params = SamplingParams(temperature=0.0, max_tokens=16)
        outputs = llm.generate(
            ["The capital of France is"],
            sampling_params=sampling_params,
        )
        text = outputs[0].outputs[0].text
        print(f"Generated text:       {text!r}")
        if not text:
            raise RuntimeError("vLLM generation returned empty text.")
        print("PASS: real vLLM generation succeeded.")

    section("vLLM smoke test")
    print("PASS: requested vLLM smoke tests succeeded.")


if __name__ == "__main__":
    main()
