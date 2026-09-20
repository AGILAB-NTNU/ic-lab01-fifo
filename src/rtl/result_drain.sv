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

module result_drain #(
    parameter integer S_MAX          = 32,
    parameter integer MAX_M          = 256,
    parameter integer MAX_N          = 64,
    parameter integer ACC_WIDTH      = 32, // 內部 32-bit 累加寬度
    parameter integer OUT_DATA_WIDTH = 8   // INT8 飽和輸出寬度
)(
    // 系統時脈與同步重置 (遵循 AGILAB 規範)
    input  logic i_clk,
    input  logic i_rst_n,

    // 讀出控制介面 (來自 tile_controller)
    input  logic i_drain_start,

    // Tile 邊界資訊 (保留向下相容介面)
    input  logic [$clog2(MAX_M+1)-1:0] i_m_base,
    input  logic [$clog2(MAX_N+1)-1:0] i_n_base,
    input  logic [$clog2(S_MAX+1)-1:0] i_active_rows,
    input  logic [$clog2(S_MAX+1)-1:0] i_active_cols,

    // 陣列移位控制 (驅動 systolic_array 垂直移位鏈)
    output logic o_drain_en,

    // 陣列底部並行 32-Lane 32-bit 輸入介面 (來自 systolic_array)
    input  logic signed [ACC_WIDTH-1:0] i_drain_data [S_MAX],

    // 結果輸出串流 (32 通道並行 INT8 飽和輸出，共 256-bit)
    output logic signed [OUT_DATA_WIDTH-1:0] o_result_data [S_MAX],
    output logic                             o_result_vld,
    input  logic                             i_result_rdy,

    // 結果座標與標記
    output logic [$clog2(MAX_M+1)-1:0] o_c_row,
    output logic [$clog2(MAX_N+1)-1:0] o_c_col,
    output logic                       o_tile_last,

    // 狀態輸出
    output logic o_busy,
    output logic o_drain_done
);

    // 區域參數定義
    localparam integer MW = $clog2(MAX_M + 1);
    localparam integer NW = $clog2(MAX_N + 1);
    localparam integer SW = $clog2(S_MAX + 1);

    // 狀態機定義 (嚴格 3-Block FSM)
    typedef enum logic [1:0] {
        ST_IDLE, // 閒置狀態
        ST_SEND, // 逐列垂直移位排空 (32 拍)
        ST_DONE  // 完成脈衝狀態
    } state_t;

    state_t state_r, state_next;

    // 鎖存暫存器宣告 (遵照 _r 與 _next 命名規範)
    logic [MW-1:0] m_base_r, m_base_next;
    logic [NW-1:0] n_base_r, n_base_next;
    logic [SW-1:0] active_rows_r, active_rows_next;
    logic [SW-1:0] active_cols_r, active_cols_next;
    logic [SW-1:0] row_cnt_r, row_cnt_next;

    // 握手與旗標訊號
    logic result_fire;
    logic is_last_row;
    logic tile_valid;

    // 32 通道飽和截斷暫存訊號
    logic signed [OUT_DATA_WIDTH-1:0] sat_comb [S_MAX];

    // 飽和限制器函式: 32-bit Signed Clamp 至 [-128, 127]
    function automatic logic signed [OUT_DATA_WIDTH-1:0] saturate_int8(
        input logic signed [ACC_WIDTH-1:0] val
    );
        if (val > 32'sd127) begin
            return 8'sd127;
        end else if (val < -32'sd128) begin
            return -8'sd128;
        end else begin
            return val[OUT_DATA_WIDTH-1:0];
        end
    endfunction

    // 32 組並行 Saturator (純組合邏輯)
    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < S_MAX; lane_idx = lane_idx + 1) begin : gen_saturators
            always_comb begin
                sat_comb[lane_idx] = saturate_int8(i_drain_data[lane_idx]);
            end
        end
    endgenerate

    // 邊界條件判斷
    always_comb begin
        tile_valid  = (active_rows_r != '0) && (active_cols_r != '0);
        // 整排移位排空：當數滿 active_rows 拍時代表整塊 Tile 吐完
        is_last_row = tile_valid && (row_cnt_r == (active_rows_r - 1'b1));
        result_fire = (state_r == ST_SEND) && tile_valid && i_result_rdy;
    end

    // -------------------------------------------------------------
    // 3-Block FSM - 區塊 1: 下一狀態組合邏輯 (次態轉移，防 Latch)
    // -------------------------------------------------------------
    always_comb begin
        state_next       = state_r;
        m_base_next      = m_base_r;
        n_base_next      = n_base_r;
        active_rows_next = active_rows_r;
        active_cols_next = active_cols_r;
        row_cnt_next     = row_cnt_r;

        case (state_r)
            ST_IDLE: begin
                if (i_drain_start) begin
                    state_next       = ST_SEND;
                    m_base_next      = i_m_base;
                    n_base_next      = i_n_base;
                    active_rows_next = i_active_rows;
                    active_cols_next = i_active_cols;
                    row_cnt_next     = '0;
                end
            end

            ST_SEND: begin
                if (!tile_valid) begin
                    state_next = ST_DONE;
                end else if (result_fire) begin
                    if (is_last_row) begin
                        state_next = ST_DONE;
                    end else begin
                        row_cnt_next = row_cnt_r + 1'b1;
                    end
                end
            end

            ST_DONE: begin
                state_next   = ST_IDLE;
                row_cnt_next = '0;
            end

            default: begin
                state_next   = ST_IDLE;
                row_cnt_next = '0;
            end
        endcase
    end

    // -------------------------------------------------------------
    // 3-Block FSM - 區塊 2: 循序狀態暫存器邏輯 (嚴格 Synchronous Reset)
    // -------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            state_r       <= ST_IDLE;
            m_base_r      <= '0;
            n_base_r      <= '0;
            active_rows_r <= '0;
            active_cols_r <= '0;
            row_cnt_r     <= '0;
        end else begin
            state_r       <= state_next;
            m_base_r      <= m_base_next;
            n_base_r      <= n_base_next;
            active_rows_r <= active_rows_next;
            active_cols_r <= active_cols_next;
            row_cnt_r     <= row_cnt_next;
        end
    end

    // -------------------------------------------------------------
    // 3-Block FSM - 區塊 3: 輸出組合邏輯 (預設賦值，杜絕 Latch)
    // -------------------------------------------------------------
    always_comb begin
        // 預設輸出賦值
        o_result_vld = 1'b0;
        o_tile_last  = 1'b0;
        o_drain_en   = 1'b0;
        o_c_row      = m_base_r + MW'(row_cnt_r);
        o_c_col      = n_base_r;
        o_busy       = (state_r != ST_IDLE);
        o_drain_done = (state_r == ST_DONE);

        for (int i = 0; i < S_MAX; i = i + 1) begin
            o_result_data[i] = sat_comb[i];
        end

        case (state_r)
            ST_IDLE: begin
                // 保持預設值
            end

            ST_SEND: begin
                if (tile_valid) begin
                    o_result_vld = 1'b1;
                    o_tile_last  = is_last_row;
                    // 下游接收端準備好 (i_result_rdy=1) 時，驅動陣列垂直往下移位一格
                    o_drain_en   = i_result_rdy;
                end
            end

            ST_DONE: begin
                o_drain_done = 1'b1;
            end

            default: begin
                // 保持預設值
            end
        endcase
    end

endmodule
