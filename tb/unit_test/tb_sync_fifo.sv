// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/13 14:13:39
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab01_fifo
// Module Name: tb_sync_fifo
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立資料位元寬度為data_width參數 深度為depth參數的tb_sync_fifo
// Coding Rules:
//   Type       : RTL (Synthesizable Circuit)
//   SV Syntax  : Avoid new SystemVerilog syntax; keep it synthesizable and compatible.RTL (Synthesizable Circuit)
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

`timescale 1ns/1ps

module tb_sync_fifo;

    // 測試參數設定
    parameter DATA_WIDTH = 32;
    parameter DEPTH      = 8;

    // Testbench 訊號宣告
    reg                  clk;
    reg                  rst_n;

    reg                  wr_en;
    reg [DATA_WIDTH-1:0] din;
    wire                 full;

    reg                  rd_en;
    wire [DATA_WIDTH-1:0] dout;
    wire                 empty;

    // 實體化同步 FIFO 模組 (DUT)
    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH)
    ) u_fifo (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_wr_en(wr_en),
        .i_din(din),
        .o_full(full),
        .i_rd_en(rd_en),
        .o_dout(dout),
        .o_empty(empty)
    );

    // 時脈產生器
    always #4 clk = ~clk;

    // 檔案指標與驗證統計變數
    integer in_file, gold_file;
    integer status_in, status_gold;
    integer expected_dout;
    integer error_count = 0;
    integer match_count = 0;

    initial begin
        // 1. 初始化控制訊號
        clk   = 0;
        rst_n = 0;
        wr_en = 0;
        rd_en = 0;
        din   = 0;

        // 2. 開啟測試向量檔
        in_file   = $fopen("input_vectors.hex", "r");
        gold_file = $fopen("golden_outputs.hex", "r");

        if (in_file == 0 || gold_file == 0) begin
            $display("[ERROR] Failed to open input files!");
            $finish;
        end

        // 3. 執行系統 Reset
        #16 rst_n = 1'b1;
        @(posedge clk);

        $display("===========================================");
        $display("   Starting Python - Verilog Verification   ");
        $display("===========================================");

        // 4. 逐行讀取輸入測試檔
        while (!$feof(in_file)) begin
            @(posedge clk);
            status_in = $fscanf(in_file, "%b %b %h\n", wr_en, rd_en, din);

            // 若觸發讀取指令且 FIFO 非空，執行自動比對
            if (rd_en && !empty) begin
                @(negedge clk);
                status_gold = $fscanf(gold_file, "%h\n", expected_dout);

                if (status_in != -1 && status_gold != -1) begin
                    if (dout === expected_dout[DATA_WIDTH-1:0]) begin
                        $display("[PASS] Read: 0x%08X | Expected: 0x%08X", dout, expected_dout);
                        match_count = match_count + 1;
                    end else begin
                        $display("[FAIL] Read: 0x%08X | Expected: 0x%08X <--- ERROR!", dout, expected_dout);
                        error_count = error_count + 1;
                    end
                end
            end
        end

        // 5. 關閉檔案
        $fclose(in_file);
        $fclose(gold_file);

        // 6. 印出結果
        $display("===========================================");
        $display(" Verification Summary:");
        $display(" Total Passed : %0d", match_count);
        $display(" Total Failed : %0d", error_count);
        $display("===========================================");

        if (error_count == 0 && match_count > 0)
            $display(">>> TEST PASSED: All vectors matched perfectly! <<<");
        else
            $display(">>> TEST FAILED: Discrepancy found! <<<");

        $finish;
    end

endmodule
