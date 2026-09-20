#!/usr/bin/env python3
"""Systolic Array Tiling Pattern Generator.

Generates 64x32x64 matrix multiplication patterns split into 4 discrete
32x32 tiles for hardware tiling verification. Compatible with Python 3.7+.
"""

import os
import random


def saturate_int8(val: int) -> int:
    """Clamp 32-bit signed accumulation to INT8 [-128, 127]."""
    if val > 127:
        return 127
    elif val < -128:
        return -128
    return int(val)


def run() -> None:
    """Generate matrices and output sliced 32x32 tiles into hex files."""
    out_dir = os.path.join(os.path.dirname(__file__), "..", "patterns")
    os.makedirs(out_dir, exist_ok=True)

    random.seed(2026)

    # 矩陣維度: M=64, K=32, N=64 (全小寫符合 PEP 8 N806 規範)
    dim_m, dim_k, dim_n = 64, 32, 64
    tile_size = 32

    # 1. 隨機生成大矩陣
    mat_a = [
        [random.randint(-128, 127) for _ in range(dim_k)] for _ in range(dim_m)
    ]
    mat_b = [
        [random.randint(-128, 127) for _ in range(dim_n)] for _ in range(dim_k)
    ]

    # 2. 計算大矩陣乘法 Golden C (64x64)
    mat_c = [[0] * dim_n for _ in range(dim_m)]
    for r in range(dim_m):
        for c in range(dim_n):
            acc = sum(mat_a[r][k] * mat_b[k][c] for k in range(dim_k))
            mat_c[r][c] = saturate_int8(acc)

    # 3. 輸出 Hex 檔案 (使用傳統巢狀 with 結構，相容 Python 3.7)
    path_a = os.path.join(out_dir, "tiling_input_a.hex")
    path_b = os.path.join(out_dir, "tiling_input_b.hex")
    path_c = os.path.join(out_dir, "tiling_golden_c.hex")

    with open(path_a, "w", encoding="utf-8") as fa:
        with open(path_b, "w", encoding="utf-8") as fb:
            with open(path_c, "w", encoding="utf-8") as fc:
                for tm in range(dim_m // tile_size):  # tm = 0, 1
                    for tn in range(dim_n // tile_size):  # tn = 0, 1
                        # 寫入當前 Tile 的 A (32x32)
                        for r in range(tile_size):
                            for k in range(tile_size):
                                val_a = mat_a[tm * tile_size + r][k]
                                fa.write(f"{(val_a & 0xFF):02X}\n")

                        # 寫入當前 Tile 的 B (32x32)
                        for k in range(tile_size):
                            for c in range(tile_size):
                                val_b = mat_b[k][tn * tile_size + c]
                                fb.write(f"{(val_b & 0xFF):02X}\n")

                        # 寫入當前 Tile 的 Golden C (32x32)
                        for r in range(tile_size):
                            for c in range(tile_size):
                                val_c = mat_c[tm * tile_size + r][tn * tile_size + c]
                                fc.write(f"{(val_c & 0xFF):02X}\n")

    print("[Success] Generated tiling patterns (64x32x64 -> 4 Tiles)!")


if __name__ == "__main__":
    run()