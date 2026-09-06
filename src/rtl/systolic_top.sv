// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/09/01 17:42:10
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab_systolc_array
// Module Name: systolic_top
// Project Name:
// Target Devices:
// Tool Versions:
// Description:  INT8 2D 脈動陣列頂層整合模組，包含 FIFO 緩衝、傾斜對齊、計算核心、讀出與控制器
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

module systolic_top #(
    parameter integer S_MAX          = 32,
    parameter integer MAX_M          = 256,
    parameter integer MAX_K          = 256,
    parameter integer MAX_N          = 64,
    parameter integer FIFO_DEPTH     = 32,
    parameter integer DATA_WIDTH     = 8,
    parameter integer PRODUCT_WIDTH  = 16,
    parameter integer ACC_WIDTH      = 32,
    parameter integer OUT_DATA_WIDTH = 8
)(
    // 系統時脈與重置訊號
    input  logic i_clk,
    input  logic i_rst_n,

    // 任務指令介面 (Command)
    input  logic                             i_cmd_vld,
    output logic                             o_cmd_rdy,
    input  logic [$clog2(MAX_M+1)-1:0]       i_matrix_m,
    input  logic [$clog2(MAX_K+1)-1:0]       i_matrix_k,
    input  logic [$clog2(MAX_N+1)-1:0]       i_matrix_n,

    // 矩陣 A 輸入介面 (Stream In)
    input  logic [S_MAX-1:0]                 i_a_wren,
    input  logic [S_MAX-1:0][DATA_WIDTH-1:0] i_a_wdata,
    output logic [S_MAX-1:0]                 o_a_full,

    // 矩陣 B 輸入介面 (Stream In)
    input  logic [S_MAX-1:0]                 i_b_wren,
    input  logic [S_MAX-1:0][DATA_WIDTH-1:0] i_b_wdata,
    output logic [S_MAX-1:0]                 o_b_full,

    // 矩陣 C 結果輸出介面 (INT8 Saturated Stream Out)
    output logic signed [OUT_DATA_WIDTH-1:0] o_result_data,
    output logic                             o_result_vld,
    input  logic                             i_result_rdy,
    output logic [$clog2(MAX_M+1)-1:0]       o_c_row,
    output logic [$clog2(MAX_N+1)-1:0]       o_c_col,
    output logic                             o_tile_last,

    // 狀態指示訊號
    output logic o_busy,
    output logic o_done
);

    // 區域參數定義
    localparam integer PEIDXW = (S_MAX <= 1) ? 1 : $clog2(S_MAX);

    // 控制訊號連線
    logic step_en;
    logic clr_acc;
    logic clr_skew;
    logic fifo_rden;

    logic a_fifo_all_rdy;
    logic b_fifo_all_rdy;

    logic drain_start;
    logic drain_done;

    logic [$clog2(MAX_M+1)-1:0] m_base;
    logic [$clog2(MAX_N+1)-1:0] n_base;
    logic [$clog2(S_MAX+1)-1:0] active_rows;
    logic [$clog2(S_MAX+1)-1:0] active_cols;

    // FIFO 讀出資料線
    logic [S_MAX-1:0][DATA_WIDTH-1:0] a_fifo_rdata;
    logic [S_MAX-1:0][DATA_WIDTH-1:0] b_fifo_rdata;

    // Skew 模組輸入陣列轉換
    logic signed [DATA_WIDTH-1:0] a_unskewed [S_MAX];
    logic signed [DATA_WIDTH-1:0] b_unskewed [S_MAX];

    // Skew 輸出至 Systolic Array 之連線
    logic signed [DATA_WIDTH-1:0] a_skewed [S_MAX];
    logic signed [DATA_WIDTH-1:0] b_skewed [S_MAX];

    // Systolic Array 累加器讀取連線
    logic [PEIDXW-1:0]           pe_rd_row;
    logic [PEIDXW-1:0]           pe_rd_col;
    logic signed [ACC_WIDTH-1:0] pe_rd_acc_data;

    // 資料型態轉換 (Packed -> Unpacked)
    genvar idx;
    generate
        for (idx = 0; idx < S_MAX; idx = idx + 1) begin : gen_data_unpack
            assign a_unskewed[idx] = a_fifo_rdata[idx];
            assign b_unskewed[idx] = b_fifo_rdata[idx];
        end
    endgenerate

    // 1. Tile 控制器
    tile_controller #(
        .S_MAX (S_MAX),
        .MAX_M (MAX_M),
        .MAX_K (MAX_K),
        .MAX_N (MAX_N)
    ) u_tile_controller (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_cmd_vld     (i_cmd_vld),
        .o_cmd_rdy     (o_cmd_rdy),
        .i_matrix_m    (i_matrix_m),
        .i_matrix_k    (i_matrix_k),
        .i_matrix_n    (i_matrix_n),
        .i_a_fifo_rdy  (a_fifo_all_rdy),
        .i_b_fifo_rdy  (b_fifo_all_rdy),
        .o_step_en     (step_en),
        .o_clr_acc     (clr_acc),
        .o_clr_skew    (clr_skew),
        .o_fifo_rden   (fifo_rden),
        .o_drain_start (drain_start),
        .i_drain_done  (drain_done),
        .o_m_base      (m_base),
        .o_n_base      (n_base),
        .o_active_rows (active_rows),
        .o_active_cols (active_cols),
        .o_busy        (o_busy),
        .o_done        (o_done)
    );

    // 2. 矩陣 A FIFO 緩衝陣列
    fifo_bank #(
        .NUM_LANES  (S_MAX),
        .DATA_WIDTH (DATA_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_fifo_a (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .i_wren      (i_a_wren),
        .i_wdata     (i_a_wdata),
        .i_rden      ({S_MAX{fifo_rden}}),
        .o_rdata     (a_fifo_rdata),
        .o_full      (o_a_full),
        .o_empty     (/* unused */),
        .o_head_vld  (/* unused */),
        .o_all_ready (a_fifo_all_rdy),
        .o_any_full  (/* unused */),
        .o_all_empty (/* unused */)
    );

    // 3. 矩陣 B FIFO 緩衝陣列
    fifo_bank #(
        .NUM_LANES  (S_MAX),
        .DATA_WIDTH (DATA_WIDTH),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_fifo_b (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .i_wren      (i_b_wren),
        .i_wdata     (i_b_wdata),
        .i_rden      ({S_MAX{fifo_rden}}),
        .o_rdata     (b_fifo_rdata),
        .o_full      (o_b_full),
        .o_empty     (/* unused */),
        .o_head_vld  (/* unused */),
        .o_all_ready (b_fifo_all_rdy),
        .o_any_full  (/* unused */),
        .o_all_empty (/* unused */)
    );

    // 4. 矩陣 A 傾斜延遲對齊 (連接 i_fifo_rden 補零)
    input_skew #(
        .NUM_LANES  (S_MAX),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_skew_a (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .i_clr_skew  (clr_skew),
        .i_step_en   (step_en),
        .i_fifo_rden (fifo_rden),
        .i_data      (a_unskewed),
        .o_skew_data (a_skewed)
    );

    // 5. 矩陣 B 傾斜延遲對齊 (連接 i_fifo_rden 補零)
    input_skew #(
        .NUM_LANES  (S_MAX),
        .DATA_WIDTH (DATA_WIDTH)
    ) u_skew_b (
        .i_clk       (i_clk),
        .i_rst_n     (i_rst_n),
        .i_clr_skew  (clr_skew),
        .i_step_en   (step_en),
        .i_fifo_rden (fifo_rden),
        .i_data      (b_unskewed),
        .o_skew_data (b_skewed)
    );

    // 6. 2D 脈動陣列核心
    systolic_array #(
        .S_MAX         (S_MAX),
        .DATA_WIDTH    (DATA_WIDTH),
        .PRODUCT_WIDTH (PRODUCT_WIDTH),
        .ACC_WIDTH     (ACC_WIDTH)
    ) u_systolic_array (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_clr_acc     (clr_acc),
        .i_step_en     (step_en),
        .i_a_skew      (a_skewed),
        .i_b_skew      (b_skewed),
        .i_rd_row      (pe_rd_row),
        .i_rd_col      (pe_rd_col),
        .o_rd_acc_data (pe_rd_acc_data)
    );

    // 7. 結果讀出與 INT8 飽和輸出模組
    result_drain #(
        .S_MAX          (S_MAX),
        .MAX_M          (MAX_M),
        .MAX_N          (MAX_N),
        .ACC_WIDTH      (ACC_WIDTH),
        .OUT_DATA_WIDTH (OUT_DATA_WIDTH)
    ) u_result_drain (
        .i_clk         (i_clk),
        .i_rst_n       (i_rst_n),
        .i_drain_start (drain_start),
        .i_m_base      (m_base),
        .i_n_base      (n_base),
        .i_active_rows (active_rows),
        .i_active_cols (active_cols),
        .o_pe_row      (pe_rd_row),
        .o_pe_col      (pe_rd_col),
        .i_pe_acc_data (pe_rd_acc_data),
        .o_result_data (o_result_data),
        .o_result_vld  (o_result_vld),
        .i_result_rdy  (i_result_rdy),
        .o_c_row       (o_c_row),
        .o_c_col       (o_c_col),
        .o_tile_last   (o_tile_last),
        .o_busy        (/* unused */),
        .o_drain_done  (drain_done)
    );

endmodule
