import collections
import random

DATA_WIDTH = 32
DEPTH = 8


class FIFOGoldenModel:
    def __init__(self, depth):
        self.depth = depth
        self.fifo = collections.deque()

    def write_valid(self, wr_en):
        return wr_en and len(self.fifo) < self.depth

    def read_valid(self, rd_en):
        return rd_en and len(self.fifo) > 0

    def apply(self, wr_en, rd_en, din):

        # 必須先根據 clock edge 前的狀態判斷
        do_write = self.write_valid(wr_en)
        do_read = self.read_valid(rd_en)

        expected_dout = None

        # DUT read
        if do_read:
            expected_dout = self.fifo.popleft()

        # DUT write
        if do_write:
            self.fifo.append(din)

        return do_write, do_read, expected_dout

    def count(self):
        return len(self.fifo)

    def is_empty(self):
        return len(self.fifo) == 0

    def is_full(self):
        return len(self.fifo) == self.depth


def write_operation(f_in, f_gold, model, wr_en, rd_en, din):

    do_write, do_read, expected = model.apply(wr_en, rd_en, din)

    # input_vectors.hex
    f_in.write(f"{int(wr_en)} {int(rd_en)} {din:08X}\n")

    # 只有真正 Read 才產生 Golden Output
    if do_read:
        f_gold.write(f"{expected:08X}\n")

    return do_write, do_read


def directed_tests(f_in, f_gold, model):

    print("[1] Empty state")

    # Empty + 00
    write_operation(f_in, f_gold, model, 0, 0, 0x00000000)

    # Empty + Read
    write_operation(f_in, f_gold, model, 0, 1, 0x00000000)

    # Empty + Write
    write_operation(f_in, f_gold, model, 1, 0, 0xAAAAAAAA)

    print("[2] Count = 1")

    # count = 1
    write_operation(f_in, f_gold, model, 0, 0, 0)

    # count = 1 + Write
    write_operation(f_in, f_gold, model, 1, 0, 0x55555555)

    # count = 2 + Read
    write_operation(f_in, f_gold, model, 0, 1, 0)

    # count = 1 + simultaneous R/W
    write_operation(f_in, f_gold, model, 1, 1, 0x12345678)

    # Read
    write_operation(f_in, f_gold, model, 0, 1, 0)

    print("[3] Empty + simultaneous R/W")

    # Empty + 11
    #
    # DUT:
    # Write = YES
    # Read  = NO
    #
    write_operation(f_in, f_gold, model, 1, 1, 0xDEADBEEF)

    # Read DEADBEEF
    write_operation(f_in, f_gold, model, 0, 1, 0)

    print("[4] Fill FIFO")

    patterns = [
        0x00000000,
        0xFFFFFFFF,
        0x00000001,
        0x00000002,
        0x7FFFFFFF,
        0x80000000,
        0xAAAAAAAA,
        0x55555555,
    ]

    for data in patterns:
        write_operation(f_in, f_gold, model, 1, 0, data)

    print("[5] Full state")

    # Full + 00
    write_operation(f_in, f_gold, model, 0, 0, 0)

    # Full + Write
    #
    # Write 應該被拒絕
    write_operation(f_in, f_gold, model, 1, 0, 0xCAFEBABE)

    # Full + Read
    write_operation(f_in, f_gold, model, 0, 1, 0)

    print("[6] Depth-1 state")

    # 現在 count = DEPTH - 1
    #
    # Write 回 Full
    write_operation(f_in, f_gold, model, 1, 0, 0x13572468)

    print("[7] Full + simultaneous R/W")

    # Full + 11
    #
    # Write = NO
    # Read  = YES
    #
    write_operation(f_in, f_gold, model, 1, 1, 0xFACE1234)

    print("[8] Normal simultaneous R/W")

    # 先確保不是 Empty / Full
    if model.count() == 0:
        write_operation(f_in, f_gold, model, 1, 0, 0x11111111)

    if model.count() == model.depth:
        write_operation(f_in, f_gold, model, 0, 1, 0)

    # Normal state 連續 R/W
    for data in [
        0x11111111,
        0x22222222,
        0x33333333,
        0x44444444,
        0x55555555,
    ]:
        write_operation(f_in, f_gold, model, 1, 1, data)

    print("[9] Drain FIFO")

    while not model.is_empty():
        write_operation(f_in, f_gold, model, 0, 1, 0)

    print("[10] Empty again")

    # Empty + Read
    write_operation(f_in, f_gold, model, 0, 1, 0)

    # Empty + R/W
    write_operation(f_in, f_gold, model, 1, 1, 0xABCDEF01)

    # Read newly written data
    write_operation(f_in, f_gold, model, 0, 1, 0)

    print("[11] Data patterns")

    patterns = [
        0x00000000,
        0xFFFFFFFF,
        0x00000001,
        0x00000002,
        0x00000003,
        0xFFFFFFFE,
        0xFFFFFFFD,
        0x7FFFFFFF,
        0x80000000,
        0xAAAAAAAA,
        0x55555555,
        0x12345678,
        0x87654321,
        0xDEADBEEF,
        0xCAFEBABE,
        0x13579BDF,
        0x2468ACE0,
    ]

    for data in patterns:
        # FIFO 滿了就先讀
        if model.is_full():
            write_operation(f_in, f_gold, model, 0, 1, 0)

        write_operation(f_in, f_gold, model, 1, 0, data)

    print("[12] Drain pattern data")

    while not model.is_empty():
        write_operation(f_in, f_gold, model, 0, 1, 0)


def random_tests(f_in, f_gold, model, num_operations, seed):

    print("[13] Random testing")

    random.seed(seed)

    for _ in range(num_operations):
        # 四種組合都有機會出現
        wr_en = random.randint(0, 1)
        rd_en = random.randint(0, 1)

        din = random.randint(0, 0xFFFFFFFF)

        write_operation(f_in, f_gold, model, wr_en, rd_en, din)


def generate_test_vectors(random_operations=5000, depth=8, seed=12345):

    model = FIFOGoldenModel(depth)

    with open("input_vectors.hex", "w") as f_in, open(
        "golden_outputs.hex", "w"
    ) as f_gold:
        directed_tests(f_in, f_gold, model)

        random_tests(f_in, f_gold, model, random_operations, seed)

    print()
    print("==========================================")
    print(" Test Vector Generation Complete")
    print("==========================================")
    print(f"FIFO Depth       : {depth}")
    print(f"Random Operations: {random_operations}")
    print(f"Random Seed      : {seed}")
    print("==========================================")
    print("Generated:")
    print("  input_vectors.hex")
    print("  golden_outputs.hex")
    print("==========================================")


if __name__ == "__main__":
    generate_test_vectors(random_operations=5000, depth=8, seed=12345)
