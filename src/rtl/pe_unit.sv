// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/09/01 17:04:11
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab_systolc_array
// Module Name: pe_unit
// Project Name:
// Target Devices:
// Tool Versions:
// Description: PE負責 8-bit 乘加運算與向東/向南資料轉發單元，且增加了影子讀出暫存器 (shadow_acc_r) 以支援垂直排空功能。
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


`timescale 1ns / 1ps

module pe_unit #(
    parameter integer DATA_WIDTH    = 8,
    parameter integer PRODUCT_WIDTH = 16,
    parameter integer ACC_WIDTH     = 32
)(
    // 系統時脈與同步重置訊號
    input  logic i_clk,
    input  logic i_rst_n,

    // 控制訊號
    input  logic i_clr_acc,   // 清除運算累加器與轉發暫存器
    input  logic i_step_en,   // 計算與轉發致能

    // 雙緩衝影子暫存器與垂直移位排空控制訊號
    input  logic i_snapshot,  // 算完當拍將 acc_r 存入 shadow_acc_r
    input  logic i_drain_en,  // 垂直移位致能 (驅動整列垂直往下移)

    // 運算元輸入 (A: 來自西方, B: 來自北方)
    input  logic signed [DATA_WIDTH-1:0] i_a,
    input  logic signed [DATA_WIDTH-1:0] i_b,

    // 資料轉發輸出 (A 向東傳遞, B 向南傳遞，符合規範命名)
    output logic signed [DATA_WIDTH-1:0] o_pe_data_east,
    output logic signed [DATA_WIDTH-1:0] o_pe_data_south,

    // 垂直排空通道 (來自北方的影子資料 / 輸出至南方的影子資料)
    input  logic signed [ACC_WIDTH-1:0]  i_drain_data,
    output logic signed [ACC_WIDTH-1:0]  o_drain_data,

    // 原有累加值輸出 (保留向下相容)
    output logic signed [ACC_WIDTH-1:0]  o_acc_data
);

    // 暫存器宣告 (一律使用 _r 後綴)
    logic signed [DATA_WIDTH-1:0] a_r;
    logic signed [DATA_WIDTH-1:0] b_r;
    logic signed [ACC_WIDTH-1:0]  acc_r;         // 運算累加暫存器
    logic signed [ACC_WIDTH-1:0]  shadow_acc_r;  // 影子讀出暫存器 (垂直移位鏈)

    // 組合邏輯訊號
    logic signed [PRODUCT_WIDTH-1:0] cur_product;

    // 當拍輸入直接計算乘積 (INT8 x INT8 -> INT16)
    always_comb begin
        cur_product = i_a * i_b;
    end

    // 輸出指派
    assign o_pe_data_east  = a_r;
    assign o_pe_data_south = b_r;
    assign o_acc_data      = acc_r;
    assign o_drain_data    = shadow_acc_r;

    // 循序邏輯：運算累加與資料轉發 (嚴格遵守 active-low synchronous reset: posedge i_clk only)
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            a_r   <= '0;
            b_r   <= '0;
            acc_r <= '0;
        end else begin
            if (i_clr_acc) begin
                a_r   <= '0;
                b_r   <= '0;
                acc_r <= '0;
            end else if (i_step_en) begin
                a_r   <= i_a;
                b_r   <= i_b;
                // 顯式位元寬度轉換，避免 Bit-width mismatch 警告
                acc_r <= acc_r + ACC_WIDTH'(cur_product);
            end
        end
    end

    // 循序邏輯：影子暫存器快照與垂直移位排空 (同步重置)
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            shadow_acc_r <= '0;
        end else begin
            if (i_snapshot) begin
                // Tile 算完當拍單拍鎖存保存結果
                shadow_acc_r <= acc_r;
            end else if (i_drain_en) begin
                // 垂直排空移位：接收北方傳來的數值，整排往下移
                shadow_acc_r <= i_drain_data;
            end
        end
    end

endmodule
