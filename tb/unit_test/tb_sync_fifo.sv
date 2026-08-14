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

    // 測試參數設定 (必須與待測物 FIFO 規格一致)
    parameter data_width = 32;
    parameter depth      = 8;

    // Testbench 訊號宣告 (連接至 FIFO 埠)
    reg clk;
    reg rst_n;

    reg wr_en;
    reg [data_width-1:0] din;
    wire full;

    reg rd_en;
    wire [data_width-1:0] dout;
    wire empty;

    // 實體化同步 FIFO 模組 (DUT: Design Under Test)
    sync_fifo #(
        .data_width(data_width),
        .depth(depth)
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

    // 時脈產生器：每 4ns 翻轉一次，週期 8ns (125MHz)
    always #4 clk = ~clk;

    // 檔案指標與驗證統計變數
    integer in_file, gold_file; //記住哪一個檔案被開啟
    integer status_in, status_gold; //記錄這次讀檔有沒有成功
    integer expected_dout; //代表Golden Answer（正確答案）
    integer error_count = 0; //錯誤幾次
    integer match_count = 0; //成功幾次

    initial begin
        // 1. 初始化所有控制訊號
        clk   = 0;
        rst_n = 0;
        wr_en = 0;
        rd_en = 0;
        din   = 0;

        // 2. 開啟 Python 產生的測試向量檔 (只讀模式 "r")
        in_file   = $fopen("input_vectors.hex", "r");
        gold_file = $fopen("golden_outputs.hex", "r");

        // 檢查檔案是否順利開啟
        if (in_file == 0 || gold_file == 0) begin
            $display("[ERROR] Failed to open input files! Please make sure input_vectors.hex and golden_outputs.hex exist in xsim directory.");
            $finish;
        end

        // 3. 執行系統 Reset (維持 15ns 後釋放 Reset)
        #15 rst_n = 1; //Reset 保持 0 狀態 15ns，15ns 後把它拉高，讓 FIFO 開始正常工作
        @(posedge clk); //等到 clk 出現下一次正緣

        $display("===========================================");
        $display("   Starting Python - Verilog Verification   ");
        $display("===========================================");

        // 4. 逐行讀取輸入測試檔，直到檔案結尾 ($feof)
        while (!$feof(in_file)) begin
            @(posedge clk);
            // 讀取一行的控制訊號：wr_en, rd_en, din
            status_in = $fscanf(in_file, "%b %b %h\n", wr_en, rd_en, din);

            // 若觸發讀取指令且 FIFO 非空，執行自動比對
            if (rd_en && !empty) begin
                @(negedge clk); // 在時脈下降沿採樣，確保硬體 dout 資料已穩定輸出
                status_gold = $fscanf(gold_file, "%h\n", expected_dout); // 讀取 Python 期望值

                // 比對 RTL 輸出與 Python 期望值
                if (dout === expected_dout[data_width-1:0]) begin
                    $display("[PASS] Read: 0x%08X | Expected: 0x%08X", dout, expected_dout);
                    match_count = match_count + 1;
                end
                else begin
                    $display("[FAIL] Read: 0x%08X | Expected: 0x%08X <--- ERROR!", dout, expected_dout);
                    error_count = error_count + 1;
                end
            end
        end

        // 5. 測試完成，關閉檔案
        $fclose(in_file);
        $fclose(gold_file);

        // 6. 印出最終統計總結
        $display("===========================================");
        $display(" Verification Summary:");
        $display(" Total Passed : %0d", match_count);
        $display(" Total Failed : %0d", error_count);
        $display("===========================================");

        if (error_count == 0 && match_count > 0)
            $display(">>> TEST PASSED: All vectors matched perfectly! <<<");
        else
            $display(">>> TEST FAILED: Discrepancy found between RTL and Golden Model! <<<");

        // 結束 Vivado 模擬
        $finish;
    end

endmodule
