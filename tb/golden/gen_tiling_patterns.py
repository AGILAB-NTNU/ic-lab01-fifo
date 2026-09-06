#!/usr/bin/env python3
import os
import random


def saturate_int8(val: int) -> int:
    if val > 127:
        return 127
    elif val < -128:
        return -128
    return int(val)


def run():
    out_dir = os.path.join(os.path.dirname(__file__), "..", "patterns")
    os.makedirs(out_dir, exist_ok=True)

    random.seed(2026)

    # 矩陣維度: M=64, K=32, N=64
    M, K, N = 64, 32, 64
    TILE = 32

    # 1. 隨機生成大矩陣
    mat_a = [[random.randint(-128, 127) for _ in range(K)] for _ in range(M)]
    mat_b = [[random.randint(-128, 127) for _ in range(N)] for _ in range(K)]

    # 2. 計算大矩陣乘法 Golden C (64x64)
    mat_c = [[0] * N for _ in range(M)]
    for r in range(M):
        for c in range(N):
            acc = sum(mat_a[r][k] * mat_b[k][c] for k in range(K))
            mat_c[r][c] = saturate_int8(acc)

    # 3. 輸出 Hex 檔案 (按 4 個 Tile: (0,0), (0,1), (1,0), (1,1) 依序寫出)
    fa = open(os.path.join(out_dir, "tiling_input_a.hex"), "w")
    fb = open(os.path.join(out_dir, "tiling_input_b.hex"), "w")
    fc = open(os.path.join(out_dir, "tiling_golden_c.hex"), "w")

    for tm in range(M // TILE):  # tm = 0, 1
        for tn in range(N // TILE):  # tn = 0, 1
            # 寫入當前 Tile 的 A (32x32)
            for r in range(TILE):
                for k in range(TILE):
                    val_a = mat_a[tm * TILE + r][k]
                    fa.write(f"{(val_a & 0xFF):02X}\n")

            # 寫入當前 Tile 的 B (32x32)
            for k in range(TILE):
                for c in range(TILE):
                    val_b = mat_b[k][tn * TILE + c]
                    fb.write(f"{(val_b & 0xFF):02X}\n")

            # 寫入當前 Tile 的 Golden C (32x32)
            for r in range(TILE):
                for c in range(TILE):
                    val_c = mat_c[tm * TILE + r][tn * TILE + c]
                    fc.write(f"{(val_c & 0xFF):02X}\n")

    fa.close()
    fb.close()
    fc.close()
    print("[Success] Generated tiling patterns (64x32x64 -> 4 Tiles)!")


if __name__ == "__main__":
    run()
    