import collections
import random


def generate_test_vectors(num_operations=300, depth=8):
    # 使用雙端佇列 (deque) 模擬 FIFO
    fifo = collections.deque()

    # 產生輸入向量與 Golden Output
    with open("input_vectors.hex", "w") as f_in, open(
        "golden_outputs.hex", "w"
    ) as f_gold:
        for i in range(num_operations):
            # 60% Push、40% Pop
            action = "push" if random.random() < 0.6 else "pop"

            wr_en = 0
            rd_en = 0
            din = 0

            # -------------------------
            # Push
            # -------------------------
            if action == "push":
                if len(fifo) < depth:
                    wr_en = 1
                    # 32-bit 隨機資料
                    din = random.randint(0, 0xFFFFFFFF)
                    fifo.append(din)

            # -------------------------
            # Pop
            # -------------------------
            else:
                if len(fifo) > 0:
                    rd_en = 1
                    expected_dout = fifo.popleft()
                    # 32-bit 輸出 (8 位十六進位)
                    f_gold.write(f"{expected_dout:08X}\n")

            # wr_en rd_en din(32-bit)
            f_in.write(f"{wr_en} {rd_en} {din:08X}\n")

    print("32-bit 測試向量已成功生成！")


if __name__ == "__main__":
    generate_test_vectors()
