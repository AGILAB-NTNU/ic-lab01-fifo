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
// Description: PE負責 8-bit 乘加運算與向東/向南資料轉發單元
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
    // 系統時脈與重置訊號
    input  logic i_clk,
    input  logic i_rst_n,

    // 控制訊號
    input  logic i_clr_acc,  // 清除累加器與轉發暫存器
    input  logic i_step_en,  // 計算與轉發致能

    // 運算元輸入 (A: 來自西方, B: 來自北方)
    input  logic signed [DATA_WIDTH-1:0] i_a,
    input  logic signed [DATA_WIDTH-1:0] i_b,

    // 資料轉發輸出 (A 向東傳遞, B 向南傳遞)
    output logic signed [DATA_WIDTH-1:0] o_pe_data_east,
    output logic signed [DATA_WIDTH-1:0] o_pe_data_south,

    // 累加器數值讀出 (32-bit 高精度輸出至 result_drain)
    output logic signed [ACC_WIDTH-1:0]  o_acc_data
);

    // 內部轉發暫存器與累加器
    logic signed [DATA_WIDTH-1:0] a_r;
    logic signed [DATA_WIDTH-1:0] b_r;
    logic signed [ACC_WIDTH-1:0]  acc_r;

    // 當拍輸入直接計算乘積 (INT8 x INT8 -> INT16)
    logic signed [PRODUCT_WIDTH-1:0] cur_product;

    always_comb begin
        cur_product = i_a * i_b;
    end

    // 輸出指派
    assign o_pe_data_east  = a_r;
    assign o_pe_data_south = b_r;
    assign o_acc_data      = acc_r;

    // 循序邏輯：資料轉發與 MAC 累加運算 (同步重置)
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            a_r   <= '0;
            b_r   <= '0;
            acc_r <= '0;
        end else begin
            // 收到清零指令時，累加器與暫存器同步歸零
            if (i_clr_acc) begin
                a_r   <= '0;
                b_r   <= '0;
                acc_r <= '0;
            end else if (i_step_en) begin
                // 當拍輸入打一拍向右/向下傳遞
                a_r   <= i_a;
                b_r   <= i_b;
                // 當拍乘積直接累加進 acc_r
                acc_r <= acc_r + ACC_WIDTH'(cur_product);
            end
        end
    end

endmodule
