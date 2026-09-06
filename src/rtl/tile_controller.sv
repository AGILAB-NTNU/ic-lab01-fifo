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
    // 系統時脈與重置訊號
    input  logic i_clk,
    input  logic i_rst_n,

    // 指令與參數設定介面 (Command Interface)
    input  logic                             i_cmd_vld,
    output logic                             o_cmd_rdy,
    input  logic [$clog2(MAX_M+1)-1:0]       i_matrix_m,
    input  logic [$clog2(MAX_K+1)-1:0]       i_matrix_k,
    input  logic [$clog2(MAX_N+1)-1:0]       i_matrix_n,

    // FIFO 狀態輸入 (來自 fifo_bank 聚合訊號)
    input  logic i_a_fifo_rdy,
    input  logic i_b_fifo_rdy,

    // 脈動陣列控制輸出
    output logic o_step_en,
    output logic o_clr_acc,
    output logic o_clr_skew,
    output logic o_fifo_rden,

    // Drain 控制介面 (送往 result_drain)
    output logic                             o_drain_start,
    input  logic                             i_drain_done,
    output logic [$clog2(MAX_M+1)-1:0]       o_m_base,
    output logic [$clog2(MAX_N+1)-1:0]       o_n_base,
    output logic [$clog2(S_MAX+1)-1:0]       o_active_rows,
    output logic [$clog2(S_MAX+1)-1:0]       o_active_cols,

    // 全域狀態輸出
    output logic o_busy,
    output logic o_done
);

    // 狀態機定義 (FSM)
    typedef enum logic [2:0] {
        ST_IDLE,       // 閒置等待指令
        ST_INIT_TILE,  // 初始化 Tile 參數與清除累加器
        ST_COMPUTE,    // 步進計算與饋入資料
        ST_FLUSH,      // 等待陣列波前清空完成
        ST_DRAIN_TRIG, // 產生 1-Cycle Drain 啟動脈衝
        ST_DRAIN_WAIT, // 等待結果讀出完成
        ST_NEXT_TILE,  // 推進下一個 Tile 座標
        ST_FINISH      // 全矩陣計算完成
    } state_t;

    state_t state_r;
    state_t state_next;

    // 內部暫存器
    logic [$clog2(MAX_M+1)-1:0]   m_len_r;
    logic [$clog2(MAX_K+1)-1:0]   k_len_r;
    logic [$clog2(MAX_N+1)-1:0]   n_len_r;

    logic [$clog2(MAX_M+1)-1:0]   m_base_r;
    logic [$clog2(MAX_N+1)-1:0]   n_base_r;

    logic [$clog2(MAX_K+1)-1:0]   k_cnt_r;
    logic [$clog2(2*S_MAX+4)-1:0] flush_cnt_r;

    // 計算目前 Tile 的有效長寬
    logic [$clog2(S_MAX+1)-1:0] cur_active_rows;
    logic [$clog2(S_MAX+1)-1:0] cur_active_cols;

    always_comb begin
        cur_active_rows = ((m_base_r + S_MAX) <= m_len_r)
                          ? ($clog2(S_MAX+1))'(S_MAX)
                          : ($clog2(S_MAX+1))'(m_len_r - m_base_r);
        cur_active_cols = ((n_base_r + S_MAX) <= n_len_r)
                          ? ($clog2(S_MAX+1))'(S_MAX)
                          : ($clog2(S_MAX+1))'(n_len_r - n_base_r);
    end

    // 3-Block FSM - 區塊 1: 下一狀態組合邏輯
    always_comb begin
        state_next = state_r;

        case (state_r)
            ST_IDLE: begin
                if (i_cmd_vld) begin
                    state_next = ST_INIT_TILE;
                end
            end

            ST_INIT_TILE: begin
                state_next = ST_COMPUTE;
            end

            ST_COMPUTE: begin
                // 當 K 維度全部資料饋入完畢，進入 Flush 狀態
                if (i_a_fifo_rdy && i_b_fifo_rdy && (k_cnt_r == (k_len_r - 1'b1))) begin
                    state_next = ST_FLUSH;
                end
            end

            ST_FLUSH: begin
                // 等待階梯波前完全穿透整個陣列 (2*S_MAX 週期)
                if (flush_cnt_r >= ($clog2(2*S_MAX+4))'(2 * S_MAX)) begin
                    state_next = ST_DRAIN_TRIG;
                end
            end

            ST_DRAIN_TRIG: begin
                state_next = ST_DRAIN_WAIT;
            end

            ST_DRAIN_WAIT: begin
                if (i_drain_done) begin
                    state_next = ST_NEXT_TILE;
                end
            end

            ST_NEXT_TILE: begin
                if ((m_base_r + cur_active_rows >= m_len_r) &&
                    (n_base_r + cur_active_cols >= n_len_r)) begin
                    state_next = ST_FINISH;
                end else begin
                    state_next = ST_INIT_TILE;
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

    // 3-Block FSM - 區塊 2: 循序暫存器邏輯 (同步重置)
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            state_r     <= ST_IDLE;
            m_len_r     <= '0;
            k_len_r     <= '0;
            n_len_r     <= '0;
            m_base_r    <= '0;
            n_base_r    <= '0;
            k_cnt_r     <= '0;
            flush_cnt_r <= '0;
        end else begin
            state_r <= state_next;

            // 接收新指令
            if ((state_r == ST_IDLE) && i_cmd_vld) begin
                m_len_r  <= i_matrix_m;
                k_len_r  <= i_matrix_k;
                n_len_r  <= i_matrix_n;
                m_base_r <= '0;
                n_base_r <= '0;
            end

            // 進入 Tile 初始化時重置計數器
            if (state_r == ST_INIT_TILE) begin
                k_cnt_r     <= '0;
                flush_cnt_r <= '0;
            end

            // 計算階段計數
            if ((state_r == ST_COMPUTE) && i_a_fifo_rdy && i_b_fifo_rdy) begin
                k_cnt_r <= k_cnt_r + 1'b1;
            end

            // 波前排空計數
            if (state_r == ST_FLUSH) begin
                flush_cnt_r <= flush_cnt_r + 1'b1;
            end

            // 推進至下一個 Tile 座標 (先掃 N 再掃 M)
            if (state_r == ST_NEXT_TILE) begin
                if (n_base_r + cur_active_cols < n_len_r) begin
                    n_base_r <= n_base_r + cur_active_cols;
                end else begin
                    n_base_r <= '0;
                    m_base_r <= m_base_r + cur_active_rows;
                end
            end
        end
    end

    // 3-Block FSM - 區塊 3: 輸出組合邏輯
    always_comb begin
        o_cmd_rdy     = (state_r == ST_IDLE);
        o_busy        = (state_r != ST_IDLE);
        o_done        = (state_r == ST_FINISH);

        o_step_en     = 1'b0;
        o_clr_acc     = 1'b0;
        o_clr_skew    = 1'b0;
        o_fifo_rden   = 1'b0;
        o_drain_start = 1'b0;

        o_m_base      = m_base_r;
        o_n_base      = n_base_r;
        o_active_rows = cur_active_rows;
        o_active_cols = cur_active_cols;

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
                o_drain_start = 1'b1; // 單週期 Pulse 啟動讀出
            end

            ST_DRAIN_WAIT: begin
                o_drain_start = 1'b0;
            end

            default: /* default values already assigned */;
        endcase
    end

endmodule
