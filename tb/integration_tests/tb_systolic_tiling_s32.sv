// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/09/06 15:45:08
// Design Type: Testbench (Simulation Only)
// Design Name: Project_Name
// Module Name: tb_systolic_tiling_s32
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
// Coding Rules:
//   Type       : Testbench (Simulation Only)
//   SV Syntax  : Testbench (Simulation Only)Full SystemVerilog syntax allowed for simulation
//   Ports      : i_* = inputs, o_* = outputs (e.g. i_clk, i_rst_n, i_a, i_b, o_y)
//   Regs       : *_r = registers, *_next = combinational next-state signals
//   Reset      : active-low synchronous reset (i_rst_n), posedge i_clk only
//   FSM        : strict 3-block style; assign defaults in always_comb; no latches
//   Handshake  : *_vld / *_rdy naming
//   Systolic   : u_PE_R[r]_C[c], pe_data_east/south, *_ping / *_pong
//   Safety     : avoid bit-width mismatches
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
// verilog_lint: waive-stop

// 模組名稱: tb_systolic_tiling_s32
// 模組說明: 大矩陣切塊測試平台 (64x32x64 矩陣拆解為 4 塊 32x32 Tile 連續運算驗證)

`timescale 1ns / 1ps

module tb_systolic_tiling_s32;

    // -------------------------------------------------------------
    // 參數定義
    // -------------------------------------------------------------
    parameter int S_MAX          = 32;
    parameter int MAX_M          = 256;
    parameter int MAX_K          = 256;
    parameter int MAX_N          = 64;
    parameter int FIFO_DEPTH     = 16;
    parameter int DATA_WIDTH     = 8;
    parameter int PRODUCT_WIDTH  = 16;
    parameter int ACC_WIDTH      = 32;
    parameter int OUT_DATA_WIDTH = 8;

    // 大矩陣維度: 64x32x64，共切為 4 個 32x32 Tiles
    parameter int BIG_M         = 64;
    parameter int BIG_K         = 32;
    parameter int BIG_N         = 64;
    parameter int NUM_TILES     = 4;
    parameter int TOTAL_C_ELEMS = BIG_M * BIG_N; // 4096 筆

    // -------------------------------------------------------------
    // DUT 介面訊號
    // -------------------------------------------------------------
    logic                               clk;
    logic                               rst_n;
    logic                               cmd_vld;
    logic                               cmd_rdy;
    logic [$clog2(MAX_M+1)-1:0]         cmd_matrix_m;
    logic [$clog2(MAX_K+1)-1:0]         cmd_matrix_k;
    logic [$clog2(MAX_N+1)-1:0]         cmd_matrix_n;

    logic [S_MAX-1:0]                   a_wren;
    logic [S_MAX-1:0][DATA_WIDTH-1:0]   a_wdata;
    logic [S_MAX-1:0]                   a_full;

    logic [S_MAX-1:0]                   b_wren;
    logic [S_MAX-1:0][DATA_WIDTH-1:0]   b_wdata;
    logic [S_MAX-1:0]                   b_full;

    logic signed [OUT_DATA_WIDTH-1:0]   result_data;
    logic                               result_vld;
    logic                               result_rdy;
    logic [$clog2(MAX_M+1)-1:0]         c_row;
    logic [$clog2(MAX_N+1)-1:0]         c_col;
    logic                               tile_last;
    logic                               dut_busy;
    logic                               dut_done;

    // -------------------------------------------------------------
    // 測資與比對陣列 (顯式宣告相容 xvlog)
    // -------------------------------------------------------------
    // verilog_lint: waive-start unpacked-dimensions-range-ordering
    logic signed [DATA_WIDTH-1:0] hex_mem_a [0:NUM_TILES*1024-1];
    logic signed [DATA_WIDTH-1:0] hex_mem_b [0:NUM_TILES*1024-1];
    logic signed [DATA_WIDTH-1:0] hex_gold_c[0:NUM_TILES*1024-1];

    // 當前 Tile 資料暫存
    logic signed [DATA_WIDTH-1:0] tile_a    [0:S_MAX-1][0:S_MAX-1];
    logic signed [DATA_WIDTH-1:0] tile_b    [0:S_MAX-1][0:S_MAX-1];

    // 最終拼裝的大矩陣 C (64x64)
    logic signed [DATA_WIDTH-1:0] assembled_c [0:BIG_M-1][0:BIG_N-1];
    // verilog_lint: waive-stop unpacked-dimensions-range-ordering

    int total_matches = 0;
    int total_errors  = 0;

    // -------------------------------------------------------------
    // 時脈產生 (100MHz, 週期 10ns)
    // -------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // -------------------------------------------------------------
    // DUT 例化
    // -------------------------------------------------------------
    systolic_top #(
        .S_MAX          (S_MAX),
        .MAX_M          (MAX_M),
        .MAX_K          (MAX_K),
        .MAX_N          (MAX_N),
        .FIFO_DEPTH     (FIFO_DEPTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .PRODUCT_WIDTH  (PRODUCT_WIDTH),
        .ACC_WIDTH      (ACC_WIDTH),
        .OUT_DATA_WIDTH (OUT_DATA_WIDTH)
    ) u_dut (
        .i_clk         (clk),
        .i_rst_n       (rst_n),
        .i_cmd_vld     (cmd_vld),
        .o_cmd_rdy     (cmd_rdy),
        .i_matrix_m    (cmd_matrix_m),
        .i_matrix_k    (cmd_matrix_k),
        .i_matrix_n    (cmd_matrix_n),
        .i_a_wren      (a_wren),
        .i_a_wdata     (a_wdata),
        .o_a_full      (a_full),
        .i_b_wren      (b_wren),
        .i_b_wdata     (b_wdata),
        .o_b_full      (b_full),
        .o_result_data (result_data),
        .o_result_vld  (result_vld),
        .i_result_rdy  (result_rdy),
        .o_c_row       (c_row),
        .o_c_col       (c_col),
        .o_tile_last   (tile_last),
        .o_busy        (dut_busy),
        .o_done        (dut_done)
    );

    // -------------------------------------------------------------
    // 重置任務
    // -------------------------------------------------------------
    task automatic reset_dut();
        rst_n        = 1'b0;
        cmd_vld      = 1'b0;
        cmd_matrix_m = '0;
        cmd_matrix_k = '0;
        cmd_matrix_n = '0;
        a_wren       = '0;
        a_wdata      = '0;
        b_wren       = '0;
        b_wdata      = '0;
        result_rdy   = 1'b1;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (2) @(posedge clk);
    endtask

    // -------------------------------------------------------------
    // 單一 Tile 計算並接收回填至 assembled_c
    // -------------------------------------------------------------
    task automatic run_single_tile(
        input int tm_idx,
        input int tn_idx
    );
        int drain_idx;
        int local_r, local_c;
        int global_r, global_c;

        $display(">> Starting Tile (%0d, %0d) Execution...", tm_idx, tn_idx);

        @(posedge clk);
        while (!cmd_rdy) @(posedge clk);
        cmd_vld      <= 1'b1;
        cmd_matrix_m <= S_MAX;
        cmd_matrix_k <= S_MAX;
        cmd_matrix_n <= S_MAX;
        @(posedge clk);
        cmd_vld      <= 1'b0;

        fork
            // 寫入 A FIFO (32 通道)
            begin
                for (int step = 0; step < S_MAX; step++) begin
                    @(posedge clk);
                    while (|a_full) @(posedge clk);
                    a_wren <= {S_MAX{1'b1}};
                    for (int r = 0; r < S_MAX; r++) begin
                        a_wdata[r] <= tile_a[r][step];
                    end
                end
                @(posedge clk);
                a_wren  <= '0;
                a_wdata <= '0;
            end

            // 寫入 B FIFO (32 通道)
            begin
                for (int step = 0; step < S_MAX; step++) begin
                    @(posedge clk);
                    while (|b_full) @(posedge clk);
                    b_wren <= {S_MAX{1'b1}};
                    for (int c = 0; c < S_MAX; c++) begin
                        b_wdata[c] <= tile_b[step][c];
                    end
                end
                @(posedge clk);
                b_wren  <= '0;
                b_wdata <= '0;
            end

            // 接收結果並依照 (tm_idx, tn_idx) 拼裝回大矩陣
            begin
                drain_idx = 0;
                while (drain_idx < (S_MAX * S_MAX)) begin
                    @(posedge clk);
                    result_rdy <= 1'b1;

                    if (result_vld && result_rdy) begin
                        local_r = drain_idx / S_MAX;
                        local_c = drain_idx % S_MAX;

                        global_r = tm_idx * S_MAX + local_r;
                        global_c = tn_idx * S_MAX + local_c;

                        assembled_c[global_r][global_c] = result_data;
                        drain_idx++;
                    end
                end
            end
        join

        // 等候硬體舉起 done 完成握手
        while (!dut_done) @(posedge clk);
        @(posedge clk);
        $display("   Tile (%0d, %0d) completed successfully.", tm_idx, tn_idx);
    endtask

    // -------------------------------------------------------------
    // 主測試流程
    // -------------------------------------------------------------
    initial begin
        int tile_cnt;
        logic signed [DATA_WIDTH-1:0] exp_val;

        // 1. 讀取測資
        $readmemh("C:/github/ic-lab01-fifo/tb/patterns/tiling_input_a.hex", hex_mem_a);
        $readmemh("C:/github/ic-lab01-fifo/tb/patterns/tiling_input_b.hex", hex_mem_b);
        $readmemh("C:/github/ic-lab01-fifo/tb/patterns/tiling_golden_c.hex", hex_gold_c);

        reset_dut();

        $display("\n==================================================");
        $display("       STARTING 64x32x64 MATRIX TILING TEST       ");
        $display("==================================================");

        // 2. 外部雙重迴圈：切出 4 塊 Tile 依序運算
        tile_cnt = 0;
        for (int tm = 0; tm < 2; tm++) begin
            for (int tn = 0; tn < 2; tn++) begin
                // 載入當前 Tile 的 32x32 測資
                for (int r = 0; r < S_MAX; r++) begin
                    for (int c = 0; c < S_MAX; c++) begin
                        tile_a[r][c] = hex_mem_a[tile_cnt * 1024 + r * 32 + c];
                        tile_b[r][c] = hex_mem_b[tile_cnt * 1024 + r * 32 + c];
                    end
                end

                // 呼叫硬體執行該 Tile
                run_single_tile(tm, tn);
                tile_cnt++;
            end
        end

        // 3. 完整大矩陣 C (64x64 = 4096 筆) 與 Golden 逐點比對
        $display("\n>> Assembled 64x64 Matrix. Starting Full Verification...");
        tile_cnt = 0;
        for (int tm = 0; tm < 2; tm++) begin
            for (int tn = 0; tn < 2; tn++) begin
                for (int r = 0; r < S_MAX; r++) begin
                    for (int c = 0; c < S_MAX; c++) begin
                        exp_val = hex_gold_c[tile_cnt * 1024 + r * 32 + c];
                        if (assembled_c[tm * 32 + r][tn * 32 + c] === exp_val) begin
                            total_matches++;
                        end else begin
                            total_errors++;
                    $display("[ERROR] Mismatch at Big Matrix (R:%0d, C:%0d) | Got: %d, Exp: %d",
                                     tm * 32 + r, tn * 32 + c,
                                     $signed(assembled_c[tm * 32 + r][tn * 32 + c]), exp_val);
                        end
                    end
                end
                tile_cnt++;
            end
        end

        // 4. 輸出總結報告
        $display("\n==================================================");
        $display("             TILING TEST REPORT                   ");
        $display("==================================================");
        $display("Total Matches : %0d / %0d", total_matches, TOTAL_C_ELEMS);
        $display("Total Errors  : %0d", total_errors);
        if (total_errors == 0 && total_matches == TOTAL_C_ELEMS) begin
            $display(">> [TEST PASSED] 64x32x64 Matrix (4 Tiles) Verified! <<");
        end else begin
            $display(">> [TEST FAILED] Tiling simulation finished with mismatches! <<");
        end
        $display("==================================================\n");

        $finish;
    end

endmodule
