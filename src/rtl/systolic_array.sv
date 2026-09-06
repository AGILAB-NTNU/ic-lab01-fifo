// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/09/01 17:06:38
// Design Type: RTL (Synthesizable Circuit)
// Design Name:  ic_lab_systolic_array
// Module Name: systolic_array
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 2D 脈動陣列網格，負責例化二維 PE 陣列並提供累加值尋址讀出。
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

module systolic_array #(
    parameter integer S_MAX         = 32,
    parameter integer DATA_WIDTH    = 8,
    parameter integer PRODUCT_WIDTH = 16,
    parameter integer ACC_WIDTH     = 32
)(
    // 系統時脈與重置訊號
    input  logic i_clk,
    input  logic i_rst_n,

    // 控制訊號
    input  logic i_clr_acc,
    input  logic i_step_en,

    // 邊界運算元輸入 (來自 Skew 暫存器)
    input  logic signed [DATA_WIDTH-1:0] i_a_skew [S_MAX],
    input  logic signed [DATA_WIDTH-1:0] i_b_skew [S_MAX],

    // 累加值讀取介面 (來自 result_drain 的座標選取)
    input  logic [((S_MAX <= 1) ? 1 : $clog2(S_MAX))-1:0] i_rd_row,
    input  logic [((S_MAX <= 1) ? 1 : $clog2(S_MAX))-1:0] i_rd_col,
    output logic signed [ACC_WIDTH-1:0]                   o_rd_acc_data
);

    // 內部網格傳遞訊號線
    logic signed [DATA_WIDTH-1:0] pe_data_east  [S_MAX][S_MAX];
    logic signed [DATA_WIDTH-1:0] pe_data_south [S_MAX][S_MAX];
    logic signed [ACC_WIDTH-1:0]  pe_acc_matrix [S_MAX][S_MAX];

    // 二維 PE 陣列例化
    genvar r, c;
    generate
        for (r = 0; r < S_MAX; r = r + 1) begin : gen_row
            for (c = 0; c < S_MAX; c = c + 1) begin : gen_col

                // 邊界資料流選擇
                logic signed [DATA_WIDTH-1:0] a_in;
                logic signed [DATA_WIDTH-1:0] b_in;

                assign a_in = (c == 0) ? i_a_skew[r] : pe_data_east[r][c-1];
                assign b_in = (r == 0) ? i_b_skew[c] : pe_data_south[r-1][c];

                // PE 例化
                pe_unit #(
                    .DATA_WIDTH    (DATA_WIDTH),
                    .PRODUCT_WIDTH (PRODUCT_WIDTH),
                    .ACC_WIDTH     (ACC_WIDTH)
                ) u_pe_unit (
                    .i_clk           (i_clk),
                    .i_rst_n         (i_rst_n),
                    .i_clr_acc       (i_clr_acc),
                    .i_step_en       (i_step_en),
                    .i_a             (a_in),
                    .i_b             (b_in),
                    .o_pe_data_east  (pe_data_east[r][c]),
                    .o_pe_data_south (pe_data_south[r][c]),
                    .o_acc_data      (pe_acc_matrix[r][c])
                );

            end
        end
    endgenerate

    // 讀出多工器：依據 row/col 選取指定 PE 的累加值
    assign o_rd_acc_data = pe_acc_matrix[i_rd_row][i_rd_col];

endmodule
