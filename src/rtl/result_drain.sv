// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/09/01 16:23:50
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab_systolic_array
// Module Name: result_drain
// Project Name:
// Target Devices:
// Tool Versions:
// Description:  依序讀取 PE 累加值，經 INT8 飽和限制後串流輸出。
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

module result_drain #(
    parameter integer S_MAX          = 32,
    parameter integer MAX_M          = 256,
    parameter integer MAX_N          = 64,
    parameter integer ACC_WIDTH      = 32,  // 內部 32-bit 高精度累加寬度
    parameter integer OUT_DATA_WIDTH = 8   // 最終飽和截斷輸出的 8-bit 資料寬度
)(
    // 系統時脈與重置訊號
    input  logic i_clk,
    input  logic i_rst_n,

    // 讀出控制介面
    input  logic i_drain_start,

    // 來自 tile_controller 的目前 Tile 座標與邊界資訊
    input  logic [$clog2(MAX_M+1)-1:0] i_m_base,
    input  logic [$clog2(MAX_N+1)-1:0] i_n_base,

    input  logic [$clog2(S_MAX+1)-1:0] i_active_rows,
    input  logic [$clog2(S_MAX+1)-1:0] i_active_cols,

    // 脈動陣列累加器讀取介面
    output logic [((S_MAX <= 1) ? 1 : $clog2(S_MAX))-1:0] o_pe_row,
    output logic [((S_MAX <= 1) ? 1 : $clog2(S_MAX))-1:0] o_pe_col,

    // 選定 PE 的 32-bit 累加值輸入
    input  logic signed [ACC_WIDTH-1:0] i_pe_acc_data,

    // 結果輸出串流 (INT8 飽和輸出)
    output logic signed [OUT_DATA_WIDTH-1:0] o_result_data,
    output logic                             o_result_vld,
    input  logic                             i_result_rdy,

    // 結果全域座標與邊界標記
    output logic [$clog2(MAX_M+1)-1:0] o_c_row,
    output logic [$clog2(MAX_N+1)-1:0] o_c_col,
    output logic                       o_tile_last,

    // 狀態輸出
    output logic o_busy,
    output logic o_drain_done
);

    // 區域參數定義
    localparam integer MW     = $clog2(MAX_M + 1);
    localparam integer NW     = $clog2(MAX_N + 1);
    localparam integer SW     = $clog2(S_MAX + 1);
    localparam integer PEIDXW = (S_MAX <= 1) ? 1 : $clog2(S_MAX);

    // 狀態機定義 (FSM)
    typedef enum logic [1:0] {
        ST_IDLE,  // 閒置狀態
        ST_SEND,  // 依序讀出並輸出資料
        ST_DONE   // 讀出完成脈衝狀態
    } state_t;

    state_t state_r;
    state_t state_next;

    // 鎖存之 Tile 配置與座標暫存器
    logic [MW-1:0] m_base_r;
    logic [NW-1:0] n_base_r;

    logic [SW-1:0] active_rows_r;
    logic [SW-1:0] active_cols_r;

    logic [SW-1:0] row_idx_r;
    logic [SW-1:0] col_idx_r;

    // 握手與邊界旗標
    logic result_fire;
    logic last_element;
    logic tile_valid;

    // 飽和限制器函式: 32-bit Signed 截斷至 8-bit Signed
    function automatic logic signed [OUT_DATA_WIDTH-1:0] saturate_int8(
        input logic signed [ACC_WIDTH-1:0] val
    );
        if (val > 32'sd127) begin
            return 8'sd127;          // 正溢位飽和 (Clamp 至 +127)
        end else if (val < -32'sd128) begin
            return -8'sd128;         // 負溢位飽和 (Clamp 至 -128)
        end else begin
            return val[OUT_DATA_WIDTH-1:0]; // 正常範圍內截取低 8 位元
        end
    endfunction

    // 邊界條件判斷
    always_comb begin
        tile_valid = (active_rows_r != '0) && (active_cols_r != '0);
        last_element = tile_valid &&
                       (row_idx_r == (active_rows_r - 1'b1)) &&
                       (col_idx_r == (active_cols_r - 1'b1));
        result_fire  = (state_r == ST_SEND) && tile_valid && i_result_rdy;
    end

    // 3-Block FSM - 區塊 1: 下一狀態組合邏輯
    always_comb begin
        state_next = state_r;

        case (state_r)
            ST_IDLE: begin
                if (i_drain_start) begin
                    state_next = ST_SEND;
                end
            end

            ST_SEND: begin
                if (!tile_valid) begin
                    state_next = ST_DONE;
                end else if (result_fire && last_element) begin
                    state_next = ST_DONE;
                end
            end

            ST_DONE: begin
                state_next = ST_IDLE;
            end

            default: begin
                state_next = ST_IDLE;
            end
        endcase
    end

    // 3-Block FSM - 區塊 2: 狀態暫存器與資料路徑循序邏輯
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            state_r       <= ST_IDLE;
            m_base_r      <= '0;
            n_base_r      <= '0;
            active_rows_r <= '0;
            active_cols_r <= '0;
            row_idx_r     <= '0;
            col_idx_r     <= '0;
        end else begin
            state_r <= state_next;

            // 收到啟動訊號時，立即鎖存目前的 Tile 參數並清零內部計數
            if ((state_r == ST_IDLE) && i_drain_start) begin
                m_base_r      <= i_m_base;
                n_base_r      <= i_n_base;
                active_rows_r <= i_active_rows;
                active_cols_r <= i_active_cols;
                row_idx_r     <= '0;
                col_idx_r     <= '0;
            end

            // 成功握手後推進 PE 讀取座標 (Row-major 掃描)
            if ((state_r == ST_SEND) && result_fire) begin
                if (!last_element) begin
                    if (col_idx_r == (active_cols_r - 1'b1)) begin
                        col_idx_r <= '0;
                        row_idx_r <= row_idx_r + 1'b1;
                    end else begin
                        col_idx_r <= col_idx_r + 1'b1;
                    end
                end
            end
        end
    end

    // 3-Block FSM - 區塊 3: 輸出組合邏輯
    always_comb begin
        o_pe_row      = row_idx_r[PEIDXW-1:0];
        o_pe_col      = col_idx_r[PEIDXW-1:0];

        o_c_row       = m_base_r + MW'(row_idx_r);
        o_c_col       = n_base_r + NW'(col_idx_r);

        o_result_data = saturate_int8(i_pe_acc_data);
        o_result_vld  = 1'b0;
        o_tile_last   = 1'b0;

        o_busy        = (state_r != ST_IDLE);
        o_drain_done  = (state_r == ST_DONE);

        case (state_r)
            ST_IDLE: begin
                o_result_vld = 1'b0;
                o_tile_last  = 1'b0;
            end

            ST_SEND: begin
                if (tile_valid) begin
                    o_result_vld = 1'b1;
                    o_tile_last  = last_element;
                end
            end

            ST_DONE: begin
                o_result_vld = 1'b0;
                o_tile_last  = 1'b0;
            end

            default: begin
                o_result_vld = 1'b0;
                o_tile_last  = 1'b0;
            end
        endcase
    end

endmodule
