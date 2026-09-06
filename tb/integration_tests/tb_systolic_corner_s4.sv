// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/09/03 14:33:19
// Design Type: Testbench (Simulation Only)
// Design Name: Project_Name
// Module Name: tb_systolic_corner_s4
// Project Name:
// Target Devices:
// Tool Versions:
// Description:專用功能驗證平台 (S=4)，透過 $readmemh 讀入 Python 生成的 5 組特徵 Hex 測資進行手算比對與波形排查
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

// 模組名稱: tb_systolic_corner_s4
// 模組說明: 專用功能驗證平台 (S=4)，透過 $readmemh 讀入 Python 生成的 5 組特徵 Hex 測資進行手算比對與波形排查

`timescale 1ns / 1ps

module tb_systolic_corner_s4;

    // -------------------------------------------------------------
    // 參數定義 (完全吻合 RTL 與 Linter 規範)
    // -------------------------------------------------------------
    parameter int S_MAX          = 4;
    parameter int MAX_M          = 256;
    parameter int MAX_K          = 256;
    parameter int MAX_N          = 64;
    parameter int FIFO_DEPTH     = 16;
    parameter int DATA_WIDTH     = 8;
    parameter int PRODUCT_WIDTH  = 16;
    parameter int ACC_WIDTH      = 32;
    parameter int OUT_DATA_WIDTH = 8;
    parameter int TOTAL_PATTERNS = 5;
    parameter int TOTAL_ELEMENTS = TOTAL_PATTERNS * S_MAX * S_MAX; // 80 筆

    // -------------------------------------------------------------
    // DUT 介面訊號
    // -------------------------------------------------------------
    logic                                       clk;
    logic                                       rst_n;

    logic                                       cmd_vld;
    logic                                       cmd_rdy;
    logic [$clog2(MAX_M+1)-1:0]                 cmd_matrix_m;
    logic [$clog2(MAX_K+1)-1:0]                 cmd_matrix_k;
    logic [$clog2(MAX_N+1)-1:0]                 cmd_matrix_n;

    logic [S_MAX-1:0]                           a_wren;
    logic [S_MAX-1:0][DATA_WIDTH-1:0]           a_wdata;
    logic [S_MAX-1:0]                           a_full;

    logic [S_MAX-1:0]                           b_wren;
    logic [S_MAX-1:0][DATA_WIDTH-1:0]           b_wdata;
    logic [S_MAX-1:0]                           b_full;

    logic signed [OUT_DATA_WIDTH-1:0]           result_data;
    logic                                       result_vld;
    logic                                       result_rdy;
    logic [$clog2(MAX_M+1)-1:0]                 c_row;
    logic [$clog2(MAX_N+1)-1:0]                 c_col;
    logic                                       tile_last;
    logic                                       dut_busy;
    logic                                       dut_done;

    // -------------------------------------------------------------
    // 測資與比對陣列 (顯式範圍宣告相容 xvlog)
    // -------------------------------------------------------------
    // verilog_lint: waive-start unpacked-dimensions-range-ordering
    logic signed [DATA_WIDTH-1:0] hex_mem_a    [0:TOTAL_ELEMENTS-1];
    logic signed [DATA_WIDTH-1:0] hex_mem_b    [0:TOTAL_ELEMENTS-1];
    logic signed [DATA_WIDTH-1:0] hex_golden_c [0:TOTAL_ELEMENTS-1];

    logic signed [DATA_WIDTH-1:0] mem_a        [0:S_MAX-1][0:S_MAX-1];
    logic signed [DATA_WIDTH-1:0] mem_b        [0:S_MAX-1][0:S_MAX-1];
    logic signed [DATA_WIDTH-1:0] golden_c     [0:S_MAX-1][0:S_MAX-1];
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
    // DUT 例化 (對齊 systolic_top FIFO 埠規範)
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
    // 矩陣運算與驗證任務
    // -------------------------------------------------------------
    task automatic run_and_verify(
        input string tc_name,
        input int    m,
        input int    k_dim,
        input int    n,
        input int    backpressure_prob
    );
        int drain_idx;
        int exp_r, exp_c;
        logic signed [DATA_WIDTH-1:0] exp_val;

        $display("\n==================================================");
        $display("[TC Start] %s (Dim: %0dx%0dx%0d, BP: %0d%%)",
                 tc_name, m, k_dim, n, backpressure_prob);
        $display("==================================================");

        // 1. 發送運算尺寸與指令
        @(posedge clk);
        while (!cmd_rdy) @(posedge clk);
        cmd_vld      <= 1'b1;
        cmd_matrix_m <= m;
        cmd_matrix_k <= k_dim;
        cmd_matrix_n <= n;
        @(posedge clk);
        cmd_vld      <= 1'b0;

        // 2. 驅動輸入資料與接收輸出
        fork
            // 寫入 A FIFO (4 通道)
            begin
                for (int step = 0; step < k_dim; step++) begin
                    @(posedge clk);
                    while (|a_full) @(posedge clk);
                    a_wren <= {S_MAX{1'b1}};
                    for (int r = 0; r < S_MAX; r++) begin
                        a_wdata[r] <= (r < m) ? mem_a[r][step] : '0;
                    end
                end
                @(posedge clk);
                a_wren  <= '0;
                a_wdata <= '0;
            end

            // 寫入 B FIFO (4 通道)
            begin
                for (int step = 0; step < k_dim; step++) begin
                    @(posedge clk);
                    while (|b_full) @(posedge clk);
                    b_wren <= {S_MAX{1'b1}};
                    for (int c = 0; c < S_MAX; c++) begin
                        b_wdata[c] <= (c < n) ? mem_b[step][c] : '0;
                    end
                end
                @(posedge clk);
                b_wren  <= '0;
                b_wdata <= '0;
            end

            // 接收結果並比對
            begin
                drain_idx = 0;
                while (drain_idx < (m * n)) begin
                    @(posedge clk);
                    result_rdy <= ($urandom_range(1, 100) > backpressure_prob);

                    if (result_vld && result_rdy) begin
                        exp_r   = drain_idx / n;
                        exp_c   = drain_idx % n;
                        exp_val = golden_c[exp_r][exp_c];

                        if (result_data === exp_val) begin
                            total_matches++;
                        end else begin
                            total_errors++;
                            $display("[ERROR] Mismatch at %0d (R:%0d, C:%0d) | Got: %d, Exp: %d",
                                     drain_idx, exp_r, exp_c,
                                     $signed(result_data), exp_val);
                        end
                        drain_idx++;
                    end
                end
                result_rdy <= 1'b1;
            end
        join

        $display("[TC Completed] %s finished.", tc_name);
    endtask

    // -------------------------------------------------------------
    // 主測試流程
    // -------------------------------------------------------------
    initial begin
        // 1. 使用絕對路徑讀取專屬 S=4 特徵測資
        $readmemh("C:/github/ic-lab01-fifo/tb/patterns/s4_input_a.hex", hex_mem_a);
        $readmemh("C:/github/ic-lab01-fifo/tb/patterns/s4_input_b.hex", hex_mem_b);
        $readmemh("C:/github/ic-lab01-fifo/tb/patterns/s4_golden_c.hex", hex_golden_c);

        reset_dut();

        // 2. 執行 5 組 Corner 測試
        for (int p = 0; p < TOTAL_PATTERNS; p++) begin
            for (int r = 0; r < S_MAX; r++) begin
                for (int c = 0; c < S_MAX; c++) begin
                    mem_a[r][c]    = hex_mem_a[p * 16 + r * 4 + c];
                    mem_b[r][c]    = hex_mem_b[p * 16 + r * 4 + c];
                    golden_c[r][c] = hex_golden_c[p * 16 + r * 4 + c];
                end
            end

            case (p)
                0: run_and_verify("TC 1: Baseline Random (Hand-check)", 4, 4, 4, 0);
                1: run_and_verify("TC 2: Identity Matrix x Max (+127)", 4, 4, 4, 0);
                2: run_and_verify("TC 3: Positive Overflow Saturation (+127 Clamp)", 4, 4, 4, 0);
                3: run_and_verify("TC 4: Negative Overflow Saturation (-128 Clamp)", 4, 4, 4, 0);
                4: run_and_verify("TC 5: Backpressure Flow Control (BP 50%)", 4, 4, 4, 50);
                default: run_and_verify($sformatf("Corner Case TC %0d", p + 1), 4, 4, 4, 0);
            endcase
        end

        // 3. 輸出總結報告 (折行排版符合 Linter < 100 字元規範)
        $display("\n==================================================");
        $display("          S=4 CORNER TEST REPORT                  ");
        $display("==================================================");
        $display("Total Matches : %0d", total_matches);
        $display("Total Errors  : %0d", total_errors);
        if (total_errors == 0 && total_matches == TOTAL_ELEMENTS) begin
            $display(">> [TEST PASSED] All %0d corner cases (80 elements) verified! <<",
                     TOTAL_PATTERNS);
        end else begin
            $display(">> [TEST FAILED] Simulation finished with errors! <<");
        end
        $display("==================================================\n");

        $finish;
    end

endmodule
