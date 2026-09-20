// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/09/01 17:40:12
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab_systolic_array
// Module Name: tile_controller
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 脈動陣列 Tile 排程與狀態控制中心，採用 3-Block FSM 控制計算、排程與讀出。

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

module tile_controller #(
    parameter integer S_MAX = 32,
    parameter integer MAX_M = 256,
    parameter integer MAX_K = 256,
    parameter integer MAX_N = 64
)(
    // 系統時脈與同步重置 (遵循 AGILAB 規範：僅 posedge i_clk 採樣)
    input  logic i_clk,
    input  logic i_rst_n,

    // 指令與參數設定介面 (Command Interface)
    input  logic                                 i_cmd_vld,
    output logic                                 o_cmd_rdy,
    input  logic [$clog2(MAX_M+1)-1:0]           i_matrix_m,
    input  logic [$clog2(MAX_K+1)-1:0]           i_matrix_k,
    input  logic [$clog2(MAX_N+1)-1:0]           i_matrix_n,

    // FIFO 狀態輸入 (來自 fifo_bank 聚合訊號)
    input  logic i_a_fifo_rdy,
    input  logic i_b_fifo_rdy,

    // 脈動陣列控制輸出
    output logic o_step_en,
    output logic o_clr_acc,
    output logic o_clr_skew,
    output logic o_fifo_rden,
    output logic o_snapshot, // 單拍快照脈衝，鎖存結果至影子暫存器

    // Drain 控制介面 (送往 result_drain)
    output logic                                 o_drain_start,
    input  logic                                 i_drain_done,
    output logic [$clog2(MAX_M+1)-1:0]           o_m_base,
    output logic [$clog2(MAX_N+1)-1:0]           o_n_base,
    output logic [$clog2(S_MAX+1)-1:0]           o_active_rows,
    output logic [$clog2(S_MAX+1)-1:0]           o_active_cols,

    // 全域狀態輸出
    output logic o_busy,
    output logic o_done
);

    // 區域參數定義 (加入 waive 標籤，徹底消除 Verible localparam 命名樣式警告)
    // verilog_lint: waive-start localparam-name-style
    localparam integer FLUSH_CYCLES = 2 * S_MAX;
    localparam integer FLUSH_WIDTH  = $clog2(FLUSH_CYCLES + 4);
    // verilog_lint: waive-stop localparam-name-style

    // 狀態機定義 (嚴格 3-Block FSM，移除 ST_NEXT_TILE)
    typedef enum logic [2:0] {
        ST_IDLE,       // 閒置等待指令
        ST_INIT_TILE,  // 初始化 Tile 參數與清除陣列
        ST_COMPUTE,    // 步進計算與饋入資料 (K 拍)
        ST_FLUSH,      // 等待階梯波前排空 (64 拍)
        ST_DRAIN_TRIG, // 產生 1 拍 Snapshot 快照與 Drain 啟動脈衝
        ST_DRAIN_WAIT, // 等待 32 拍並行排空完成
        ST_FINISH      // 計算完成中斷脈衝
    } state_t;

    state_t state_r, state_next;

    // 內部暫存器宣告 (嚴格遵守 _r 與 _next 命名規範)
    logic [$clog2(MAX_M+1)-1:0] m_len_r, m_len_next;
    logic [$clog2(MAX_K+1)-1:0] k_len_r, k_len_next;
    logic [$clog2(MAX_N+1)-1:0] n_len_r, n_len_next;

    logic [$clog2(MAX_K+1)-1:0] k_cnt_r, k_cnt_next;
    logic [FLUSH_WIDTH-1:0]     flush_cnt_r, flush_cnt_next;

    // -------------------------------------------------------------
    // 3-Block FSM - 區塊 1: 次態轉移組合邏輯 (組合邏輯，防 Latch)
    // -------------------------------------------------------------
    always_comb begin
        state_next     = state_r;
        m_len_next     = m_len_r;
        k_len_next     = k_len_r;
        n_len_next     = n_len_r;
        k_cnt_next     = k_cnt_r;
        flush_cnt_next = flush_cnt_r;

        case (state_r)
            ST_IDLE: begin
                if (i_cmd_vld) begin
                    state_next = ST_INIT_TILE;
                    m_len_next = i_matrix_m;
                    k_len_next = i_matrix_k;
                    n_len_next = i_matrix_n;
                end
            end

            ST_INIT_TILE: begin
                state_next     = ST_COMPUTE;
                k_cnt_next     = '0;
                flush_cnt_next = '0;
            end

            ST_COMPUTE: begin
                // 當雙邊 FIFO 均備妥資料時推進步數
                if (i_a_fifo_rdy && i_b_fifo_rdy) begin
                    if (k_cnt_r == (k_len_r - 1'b1)) begin
                        state_next = ST_FLUSH;
                    end else begin
                        k_cnt_next = k_cnt_r + 1'b1;
                    end
                end
            end

            ST_FLUSH: begin
                // 等待波前完全穿透整個陣列
                if (flush_cnt_r >= FLUSH_WIDTH'(FLUSH_CYCLES)) begin
                    state_next = ST_DRAIN_TRIG;
                end else begin
                    flush_cnt_next = flush_cnt_r + 1'b1;
                end
            end

            ST_DRAIN_TRIG: begin
                // 當拍發出 Snapshot 脈衝鎖存至影子暫存器，並切入 DRAIN_WAIT
                state_next = ST_DRAIN_WAIT;
            end

            ST_DRAIN_WAIT: begin
                // 收到 result_drain 回傳的完成信號 (僅需 32 拍) 直接跳至 FINISH
                if (i_drain_done) begin
                    state_next = ST_FINISH;
                end
            end

            ST_FINISH: begin
                state_next = ST_IDLE;
            end

            default: begin
                state_next = ST_IDLE;
            end
        endcase
    end

    // -------------------------------------------------------------
    // 3-Block FSM - 區塊 2: 循序邏輯暫存器更新 (嚴格同步重置)
    // -------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            state_r     <= ST_IDLE;
            m_len_r     <= '0;
            k_len_r     <= '0;
            n_len_r     <= '0;
            k_cnt_r     <= '0;
            flush_cnt_r <= '0;
        end else begin
            state_r     <= state_next;
            m_len_r     <= m_len_next;
            k_len_r     <= k_len_next;
            n_len_r     <= n_len_next;
            k_cnt_r     <= k_cnt_next;
            flush_cnt_r <= flush_cnt_next;
        end
    end

    // -------------------------------------------------------------
    // 3-Block FSM - 區塊 3: 輸出組合邏輯 (預設賦值，防 Latch)
    // -------------------------------------------------------------
    always_comb begin
        // 預設控制信號
        o_cmd_rdy     = (state_r == ST_IDLE);
        o_busy        = (state_r != ST_IDLE);
        o_done        = (state_r == ST_FINISH);

        o_step_en     = 1'b0;
        o_clr_acc     = 1'b0;
        o_clr_skew    = 1'b0;
        o_fifo_rden   = 1'b0;
        o_snapshot    = 1'b0;
        o_drain_start = 1'b0;

        // 不需要硬體 Tiling 迴圈，座標固定為 0，邊界維度鎖定當前輸入長寬
        o_m_base      = '0;
        o_n_base      = '0;
        o_active_rows = ($clog2(S_MAX+1))'(m_len_r);
        o_active_cols = ($clog2(S_MAX+1))'(n_len_r);

        case (state_r)
            ST_INIT_TILE: begin
                o_clr_acc  = 1'b1;
                o_clr_skew = 1'b1;
            end

            ST_COMPUTE: begin
                if (i_a_fifo_rdy && i_b_fifo_rdy) begin
                    o_step_en   = 1'b1;
                    o_fifo_rden = 1'b1;
                end
            end

            ST_FLUSH: begin
                o_step_en = 1'b1;
            end

            ST_DRAIN_TRIG: begin
                o_snapshot    = 1'b1; // 發出 1 拍 Snapshot 快照脈衝至 PE 陣列
                o_drain_start = 1'b1; // 發出 1 拍啟動脈衝通知 result_drain
            end

            ST_DRAIN_WAIT: begin
                // result_drain 正在以 32 拍進行高速並行垂直排空
            end

            default: begin
                // 保持預設值
            end
        endcase
    end

endmodule
