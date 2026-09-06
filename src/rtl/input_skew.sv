// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/09/01 17:21:32
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab_systolc_array
// Module Name: input_skew
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 輸入資料階梯傾斜對齊模組，第 k 條通道延遲 k 個週期以配合脈動波前。
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

module input_skew #(
    parameter integer NUM_LANES  = 32,
    parameter integer DATA_WIDTH = 8
)(
    // 系統時脈與重置訊號
    input  logic i_clk,
    input  logic i_rst_n,

    // 控制訊號
    input  logic i_clr_skew,  // 清除內部移位暫存器
    input  logic i_step_en,   // 步進致能
    input  logic i_fifo_rden, // FIFO 讀取有效 (若為 0 則補 0)

    // 未傾斜的輸入資料 (來自 FIFO)
    input  logic signed [DATA_WIDTH-1:0] i_data [NUM_LANES],

    // 傾斜對齊後的輸出資料 (送往 Systolic Array)
    output logic signed [DATA_WIDTH-1:0] o_skew_data [NUM_LANES]
);

    // 當 FIFO 讀取無效時，輸入端強制補零
    logic signed [DATA_WIDTH-1:0] gated_data [NUM_LANES];
    always_comb begin
        for (int l = 0; l < NUM_LANES; l = l + 1) begin
            gated_data[l] = i_fifo_rden ? i_data[l] : '0;
        end
    end

    // 各通道獨立的移位暫存器階層
    genvar lane;
    generate
        for (lane = 0; lane < NUM_LANES; lane = lane + 1) begin : gen_lane_skew
            if (lane == 0) begin : gen_lane_zero
                // 第 0 通道直通輸出 Gated 資料 (非讀取期自動為 0)
                assign o_skew_data[0] = gated_data[0];
            end else begin : gen_lane_delay
                // 第 lane 條通道需要 lane 個延遲暫存器
                logic signed [DATA_WIDTH-1:0] shift_reg_r [lane];

                always_ff @(posedge i_clk) begin
                    if (!i_rst_n) begin
                        for (int k = 0; k < lane; k = k + 1) begin
                            shift_reg_r[k] <= '0;
                        end
                    end else begin
                        if (i_clr_skew) begin
                            for (int k = 0; k < lane; k = k + 1) begin
                                shift_reg_r[k] <= '0;
                            end
                        end else if (i_step_en) begin
                            shift_reg_r[0] <= gated_data[lane];
                            for (int k = 1; k < lane; k = k + 1) begin
                                shift_reg_r[k] <= shift_reg_r[k-1];
                            end
                        end
                    end
                end

                // 輸出為最後一級暫存器
                assign o_skew_data[lane] = shift_reg_r[lane-1];
            end
        end
    endgenerate

endmodule
