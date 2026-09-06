// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/09/01 16:33:04
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab_systolc_array
// Module Name: fifo_bank
// Project Name:
// Target Devices:
// Tool Versions:
// Description:  多通道 FIFO 緩衝陣列，支援多列平行讀寫與狀態訊號聚合 (AND-Tree)。
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

module fifo_bank #(
    parameter integer NUM_LANES  = 32,
    parameter integer DATA_WIDTH = 8,
    parameter integer FIFO_DEPTH = 32
)(
    // 系統時脈與重置訊號
    input  logic i_clk,
    input  logic i_rst_n,

    // 寫入介面 (多通道獨立寫入)
    input  logic [NUM_LANES-1:0]                  i_wren,
    input  logic [NUM_LANES-1:0][DATA_WIDTH-1:0]  i_wdata,

    // 讀取介面 (多通道獨立讀取)
    input  logic [NUM_LANES-1:0]                  i_rden,
    output logic [NUM_LANES-1:0][DATA_WIDTH-1:0]  o_rdata,

    // 各通道獨立狀態輸出
    output logic [NUM_LANES-1:0]                  o_full,
    output logic [NUM_LANES-1:0]                  o_empty,
    output logic [NUM_LANES-1:0]                  o_head_vld,

    // 狀態線聚合輸出 (給 FSM 與全域控制使用)
    output logic                                  o_all_ready, // 所有通道皆備妥資料
    output logic                                  o_any_full,  // 任一通道已滿 (反壓保護)
    output logic                                  o_all_empty  // 所有通道皆清空
);

    // 每個通道獨立的指標與計數暫存器
    logic [$clog2(FIFO_DEPTH)-1:0]   wr_ptr_r [NUM_LANES];
    logic [$clog2(FIFO_DEPTH)-1:0]   rd_ptr_r [NUM_LANES];
    logic [$clog2(FIFO_DEPTH+1)-1:0] count_r  [NUM_LANES];

    // 儲存陣列 (SRAM / Register Array)
    logic [DATA_WIDTH-1:0] mem [NUM_LANES][FIFO_DEPTH];

    // 各通道獨立狀態邏輯
    genvar lane;
    generate
        for (lane = 0; lane < NUM_LANES; lane = lane + 1) begin : gen_lane_fifo
            assign o_full[lane]     = (count_r[lane] == ($clog2(FIFO_DEPTH+1))'(FIFO_DEPTH));
            assign o_empty[lane]    = (count_r[lane] == '0);
            assign o_head_vld[lane] = ~o_empty[lane];
            assign o_rdata[lane]    = mem[lane][rd_ptr_r[lane]];

            always_ff @(posedge i_clk) begin
                if (!i_rst_n) begin
                    wr_ptr_r[lane] <= '0;
                    rd_ptr_r[lane] <= '0;
                    count_r[lane]  <= '0;
                end else begin
                    // 寫入邏輯
                    if (i_wren[lane] && !o_full[lane]) begin
                        mem[lane][wr_ptr_r[lane]] <= i_wdata[lane];
                        if (wr_ptr_r[lane] == ($clog2(FIFO_DEPTH))'(FIFO_DEPTH - 1)) begin
                            wr_ptr_r[lane] <= '0;
                        end else begin
                            wr_ptr_r[lane] <= wr_ptr_r[lane] + 1'b1;
                        end
                    end

                    // 讀取邏輯
                    if (i_rden[lane] && !o_empty[lane]) begin
                        if (rd_ptr_r[lane] == ($clog2(FIFO_DEPTH))'(FIFO_DEPTH - 1)) begin
                            rd_ptr_r[lane] <= '0;
                        end else begin
                            rd_ptr_r[lane] <= rd_ptr_r[lane] + 1'b1;
                        end
                    end

                    // 計數器更新
                    case ({i_wren[lane] && !o_full[lane], i_rden[lane] && !o_empty[lane]})
                        2'b10: count_r[lane] <= count_r[lane] + 1'b1;
                        2'b01: count_r[lane] <= count_r[lane] - 1'b1;
                        default: count_r[lane] <= count_r[lane];
                    endcase
                end
            end
        end
    endgenerate

    // 狀態訊號聚合邏輯
    always_comb begin
        o_all_ready = &o_head_vld;
        o_any_full  = |o_full;
        o_all_empty = &o_empty;
    end

endmodule
