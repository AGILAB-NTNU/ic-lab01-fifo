#!/usr/bin/env python3
import os
import random


def saturate_int8(val: int) -> int:
    if val > 127:
        return 127
    elif val < -128:
        return -128
    return int(val)


def matmul_golden(mat_a, mat_b):
    m, k_len, n = len(mat_a), len(mat_a[0]), len(mat_b[0])
    mat_c = [[0] * n for _ in range(m)]
    for r in range(m):
        for c in range(n):
            acc = sum(mat_a[r][k] * mat_b[k][c] for k in range(k_len))
            mat_c[r][c] = saturate_int8(acc)
    return mat_c


def write_hex(f_a, f_b, f_c, mat_a, mat_b, mat_c, dim):
    for r in range(dim):
        for c in range(dim):
            f_a.write(f"{(mat_a[r][c] & 0xFF):02X}\n")
            f_b.write(f"{(mat_b[r][c] & 0xFF):02X}\n")
            f_c.write(f"{(mat_c[r][c] & 0xFF):02X}\n")


def run():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "patterns")
    os.makedirs(out_dir, exist_ok=True)

    # 1. 產生 S=4 的 5 組特徵測資
    fa_4 = open(os.path.join(out_dir, "s4_input_a.hex"), "w")
    fb_4 = open(os.path.join(out_dir, "s4_input_b.hex"), "w")
    fc_4 = open(os.path.join(out_dir, "s4_golden_c.hex"), "w")

    # 5 組特徵 (Baseline, 單位矩陣, 正向飽和, 負向飽和, 反壓資料)
    test_cases = [
        (
            [
                [1, 2, -1, 0],
                [0, 1, 2, -1],
                [-1, 0, 1, 2],
                [2, -1, 0, 1],
            ],  # 易手算隨機
            [[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1]],
        ),
        (
            [[1 if r == c else 0 for c in range(4)] for r in range(4)],  # 單位
            [[127 for _ in range(4)] for _ in range(4)],
        ),
        (
            [[50 for _ in range(4)] for _ in range(4)],  # 正飽和
            [[50 for _ in range(4)] for _ in range(4)],
        ),
        (
            [[-50 for _ in range(4)] for _ in range(4)],  # 負飽和
            [[50 for _ in range(4)] for _ in range(4)],
        ),
        (
            [[random.randint(-8, 8) for _ in range(4)] for _ in range(4)],  # 反壓
            [[random.randint(-8, 8) for _ in range(4)] for _ in range(4)],
        ),
    ]
    for a, b in test_cases:
        write_hex(fa_4, fb_4, fc_4, a, b, matmul_golden(a, b), 4)
    fa_4.close()
    fb_4.close()
    fc_4.close()

    # 2. 產生 S=32 的 100 組全規模壓測
    fa_32 = open(os.path.join(out_dir, "s32_input_a.hex"), "w")
    fb_32 = open(os.path.join(out_dir, "s32_input_b.hex"), "w")
    fc_32 = open(os.path.join(out_dir, "s32_golden_c.hex"), "w")
    random.seed(2026)
    for _ in range(100):
        a32 = [[random.randint(-128, 127) for _ in range(32)] for _ in range(32)]
        b32 = [[random.randint(-128, 127) for _ in range(32)] for _ in range(32)]
        write_hex(fa_32, fb_32, fc_32, a32, b32, matmul_golden(a32, b32), 32)
    fa_32.close()
    fb_32.close()
    fc_32.close()
    print("All patterns (s4 & s32) generated successfully!")


if __name__ == "__main__":
    run()