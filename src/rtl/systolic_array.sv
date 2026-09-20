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
    // 系統時脈與重置訊號 (遵循規範：僅 posedge i_clk 採樣同步重置)
    input  logic i_clk,
    input  logic i_rst_n,

    // 控制訊號 (由 tile_controller 廣播)
    input  logic i_clr_acc,
    input  logic i_step_en,

    // 新增：影子暫存器與排空移位控制訊號
    input  logic i_snapshot, // 算完當拍單拍鎖存
    input  logic i_drain_en,  // 垂直移位排空致能 (驅動整列資料垂直往下移)

    // 邊界運算元輸入 (來自 Skew 暫存器)
    input  logic signed [DATA_WIDTH-1:0] i_a_skew [S_MAX],
    input  logic signed [DATA_WIDTH-1:0] i_b_skew [S_MAX],

    // 新增：陣列底部 32 通道並行排空匯流排 (每拍由 Row S_MAX-1 整排吐出，共 32 拍排空整座陣列)
    output logic signed [ACC_WIDTH-1:0]  o_drain_data [S_MAX]
);

    // 內部網格運算元傳遞訊號線
    logic signed [DATA_WIDTH-1:0] pe_data_east  [S_MAX][S_MAX];
    logic signed [DATA_WIDTH-1:0] pe_data_south [S_MAX][S_MAX];

    // 新增：垂直影子暫存器移位鏈訊號 (縱向由 Row 0 串接至 Row S_MAX)
    logic signed [ACC_WIDTH-1:0]  pe_drain_chain [S_MAX+1][S_MAX];

    // 邊界條件：最頂部 (Row 0 之北) 移位進來的影子資料固定補零
    genvar top_c;
    generate
        for (top_c = 0; top_c < S_MAX; top_c = top_c + 1) begin : gen_drain_top_zero
            assign pe_drain_chain[0][top_c] = '0;
        end
    endgenerate

    // 邊界條件：最底層 (Row S_MAX-1 之南) 吐出的影子數值直接送給模組輸出埠
    genvar bot_c;
    generate
        for (bot_c = 0; bot_c < S_MAX; bot_c = bot_c + 1) begin : gen_drain_out
            assign o_drain_data[bot_c] = pe_drain_chain[S_MAX][bot_c];
        end
    endgenerate

    // 二維 PE 陣列例化 (例化名稱嚴格遵循 AGILAB 規範：u_PE_R[r]_C[c])
    genvar r, c;
        generate
            for (r = 0; r < S_MAX; r = r + 1) begin : gen_row
                for (c = 0; c < S_MAX; c = c + 1) begin : gen_col

                // 邊界資料流選擇
                logic signed [DATA_WIDTH-1:0] a_in;
                logic signed [DATA_WIDTH-1:0] b_in;

                assign a_in = (c == 0) ? i_a_skew[r] : pe_data_east[r][c-1];
                assign b_in = (r == 0) ? i_b_skew[c] : pe_data_south[r-1][c];

                // PE 例化 (合法的實例名稱)
                pe_unit #(
                    .DATA_WIDTH    (DATA_WIDTH),
                    .PRODUCT_WIDTH (PRODUCT_WIDTH),
                    .ACC_WIDTH     (ACC_WIDTH)
                ) u_PE (
                    .i_clk           (i_clk),
                    .i_rst_n         (i_rst_n),

                    // 計算控制
                    .i_clr_acc       (i_clr_acc),
                    .i_step_en       (i_step_en),

                    // 影子暫存器與排空移位控制
                    .i_snapshot      (i_snapshot),
                    .i_drain_en      (i_drain_en),

                    // 運算元資料流 (水平與垂直)
                    .i_a             (a_in),
                    .i_b             (b_in),
                    .o_pe_data_east  (pe_data_east[r][c]),
                    .o_pe_data_south (pe_data_south[r][c]),

                    // 垂直影子暫存器移位鏈
                    .i_drain_data    (pe_drain_chain[r][c]),
                    .o_drain_data    (pe_drain_chain[r+1][c]),

                    // 保留向下相容累加值端口 (接空)
                    .o_acc_data      ()
                );

            end
        end
    endgenerate

endmodule
