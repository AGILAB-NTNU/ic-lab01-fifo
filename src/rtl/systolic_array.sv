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
    parameter int S_MAX         = 32,
    parameter int DATA_WIDTH    = 8,
    parameter int PRODUCT_WIDTH = 16,
    parameter int ACC_WIDTH     = 32
) (
    input  logic                                            i_clk,
    input  logic                                            i_rst_n,

    // 控制信號 (完全吻合 systolic_top 接線)
    input  logic                                            i_clr_acc,
    input  logic                                            i_step_en,
    input  logic                                            i_snapshot,
    input  logic                                            i_drain_en,

    // 階梯對齊後的輸入資料 (由 input_skew 饋入)
    input  logic signed [DATA_WIDTH-1:0]                    i_a_skew [S_MAX],
    input  logic signed [DATA_WIDTH-1:0]                    i_b_skew [S_MAX],

    // 垂直並行排空介面 (完全吻合 systolic_top 接線)
    output logic signed [ACC_WIDTH-1:0]                     o_drain_data [S_MAX]
);

    // 水平與垂直脈動互連線
    logic signed [DATA_WIDTH-1:0] a_mesh [S_MAX][S_MAX+1];
    logic signed [DATA_WIDTH-1:0] b_mesh [S_MAX+1][S_MAX];

    // 垂直排空移位鏈互連線 (由北向南移位輸出)
    logic signed [ACC_WIDTH-1:0]  drain_chain [S_MAX+1][S_MAX];

    // -------------------------------------------------------------
    // 輸入邊界連接：將傾斜後的資料接入第 0 欄與第 0 列
    // -------------------------------------------------------------
    genvar r_in, c_in;
    generate
        for (r_in = 0; r_in < S_MAX; r_in++) begin : gen_input_a_connect
            assign a_mesh[r_in][0] = i_a_skew[r_in];
        end

        for (c_in = 0; c_in < S_MAX; c_in++) begin : gen_input_b_connect
            assign b_mesh[0][c_in] = i_b_skew[c_in];
        end
    endgenerate

    // 最頂端的垂直排空鏈輸入端補 0
    genvar c_top;
    generate
        for (c_top = 0; c_top < S_MAX; c_top++) begin : gen_drain_top_zero
            assign drain_chain[0][c_top] = '0;
        end
    endgenerate

    // -------------------------------------------------------------
    // 二維 Processing Element (PE) 陣列實例化
    // -------------------------------------------------------------
    genvar r, c;
    generate
        for (r = 0; r < S_MAX; r++) begin : gen_row
            for (c = 0; c < S_MAX; c++) begin : gen_col

                // verilog_lint: waive-start signal-name-style
                logic signed [ACC_WIDTH-1:0] pe_acc_out;
                // verilog_lint: waive-stop signal-name-style

                pe_unit #(
                    .DATA_WIDTH    (DATA_WIDTH),
                    .PRODUCT_WIDTH (PRODUCT_WIDTH),
                    .ACC_WIDTH     (ACC_WIDTH)
                ) u_pe (
                    .i_clk           (i_clk),
                    .i_rst_n         (i_rst_n),
                    .i_clr_acc       (i_clr_acc),
                    .i_step_en       (i_step_en),
                    .i_snapshot      (i_snapshot),
                    .i_drain_en      (i_drain_en),

                    // 水平 A 資料流 (由西向東傳遞)
                    .i_a             (a_mesh[r][c]),
                    .o_pe_data_east  (a_mesh[r][c+1]),

                    // 垂直 B 資料流 (由北向南傳遞)
                    .i_b             (b_mesh[r][c]),
                    .o_pe_data_south (b_mesh[r+1][c]),

                    // 垂直移位排空鏈 (雙緩衝移位)
                    .i_drain_data    (drain_chain[r][c]),
                    .o_drain_data    (drain_chain[r+1][c]),

                    // 累加器即時監視 (未連接)
                    .o_acc_data      (pe_acc_out)
                );

            end
        end
    endgenerate

    // -------------------------------------------------------------
    // 最底層排空匯流排：將最後一列輸出對接至 o_drain_data
    // -------------------------------------------------------------
    genvar c_out;
    generate
        for (c_out = 0; c_out < S_MAX; c_out++) begin : gen_drain_output
            assign o_drain_data[c_out] = drain_chain[S_MAX][c_out];
        end
    endgenerate

endmodule
