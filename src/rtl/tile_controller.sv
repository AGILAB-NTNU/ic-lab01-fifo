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
    parameter int S_MAX = 32,
    parameter int MAX_M = 256,
    parameter int MAX_K = 256,
    parameter int MAX_N = 64
) (
    input  logic                             i_clk,
    input  logic                             i_rst_n,

    // Command Interface (From Host / Top)
    input  logic                             i_cmd_vld,
    output logic                             o_cmd_rdy,
    input  logic [$clog2(MAX_M+1)-1:0]       i_matrix_m,
    input  logic [$clog2(MAX_K+1)-1:0]       i_matrix_k,
    input  logic [$clog2(MAX_N+1)-1:0]       i_matrix_n,

    // FIFO Buffer Status (From FIFO Banks)
    input  logic                             i_a_fifo_rdy,
    input  logic                             i_b_fifo_rdy,
    output logic                             o_fifo_rden,

    // Pipeline & Datapath Control (To Skew & Systolic Array)
    output logic                             o_step_en,
    output logic                             o_clr_acc,
    output logic                             o_clr_skew,
    output logic                             o_snapshot,

    // Drain Interface (To Result Drain)
    output logic                             o_drain_start,
    input  logic                             i_drain_done,
    output logic [$clog2(MAX_M+1)-1:0]       o_m_base,
    output logic [$clog2(MAX_N+1)-1:0]       o_n_base,
    output logic [$clog2(S_MAX+1)-1:0]       o_active_rows,
    output logic [$clog2(S_MAX+1)-1:0]       o_active_cols,

    // System Status
    output logic                             o_busy,
    output logic                             o_done
);

    // 狀態機定義 (One-hot 或 Enum)
    typedef enum logic [2:0] {
        ST_IDLE       = 3'b000,
        ST_INIT_TILE  = 3'b001,
        ST_COMPUTE    = 3'b010,
        ST_FLUSH      = 3'b011,
        ST_SNAPSHOT   = 3'b100,
        ST_DRAIN_WAIT = 3'b101,
        ST_FINISH     = 3'b110
    } state_t;

    state_t state_r, state_nxt;

    // 內部暫存器
    logic [$clog2(MAX_M+1)-1:0] reg_m_r;
    logic [$clog2(MAX_K+1)-1:0] reg_k_r;
    logic [$clog2(MAX_N+1)-1:0] reg_n_r;

    logic [15:0] step_cnt_r;
    logic [15:0] flush_cnt_r;

    // -------------------------------------------------------------
    // Linter Waive: 豁免全大寫 localparam 命名樣式檢查
    // -------------------------------------------------------------
    // verilog_lint: waive-start parameter-name-style
    localparam int unsigned FLUSH_CYCLES = 2 * S_MAX;
    localparam int unsigned DRAIN_CYCLES = S_MAX;
    // verilog_lint: waive-stop parameter-name-style

    // 狀態機跳轉
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state_r <= ST_IDLE;
        end else begin
            state_r <= state_nxt;
        end
    end

    // 狀態機組合邏輯
    always_comb begin
        state_nxt = state_r;

        case (state_r)
            ST_IDLE: begin
                if (i_cmd_vld && o_cmd_rdy) begin
                    state_nxt = ST_INIT_TILE;
                end
            end

            ST_INIT_TILE: begin
                state_nxt = ST_COMPUTE;
            end

            ST_COMPUTE: begin
                // 當 K 維度步數走完時進入波前清空排空期
                if (i_a_fifo_rdy && i_b_fifo_rdy && (step_cnt_r == reg_k_r - 1'b1)) begin
                    state_nxt = ST_FLUSH;
                end
            end

            ST_FLUSH: begin
                // 等待階梯波前完全穿過整座陣列
                if (flush_cnt_r == FLUSH_CYCLES - 1'b1) begin
                    state_nxt = ST_SNAPSHOT;
                end
            end

            ST_SNAPSHOT: begin
                // 發出 1 拍快照脈衝將累加值扣進影子暫存器，緊接著啟動排空
                state_nxt = ST_DRAIN_WAIT;
            end

            ST_DRAIN_WAIT: begin
                if (i_drain_done) begin
                    state_nxt = ST_FINISH;
                end
            end

            ST_FINISH: begin
                state_nxt = ST_IDLE;
            end

            default: state_nxt = ST_IDLE;
        endcase
    end

    // 內部計數器與資料路徑暫存
    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            reg_m_r     <= '0;
            reg_k_r     <= '0;
            reg_n_r     <= '0;
            step_cnt_r  <= '0;
            flush_cnt_r <= '0;
        end else begin
            case (state_r)
                ST_IDLE: begin
                    step_cnt_r  <= '0;
                    flush_cnt_r <= '0;
                    if (i_cmd_vld && o_cmd_rdy) begin
                        reg_m_r <= i_matrix_m;
                        reg_k_r <= i_matrix_k;
                        reg_n_r <= i_matrix_n;
                    end
                end

                ST_INIT_TILE: begin
                    step_cnt_r  <= '0;
                    flush_cnt_r <= '0;
                end

                ST_COMPUTE: begin
                    if (i_a_fifo_rdy && i_b_fifo_rdy) begin
                        step_cnt_r <= step_cnt_r + 1'b1;
                    end
                end

                ST_FLUSH: begin
                    flush_cnt_r <= flush_cnt_r + 1'b1;
                end

                ST_DRAIN_WAIT: begin
                    step_cnt_r  <= '0;
                    flush_cnt_r <= '0;
                end

                default: ;
            endcase
        end
    end

    // 輸出控制信號指派
    assign o_cmd_rdy      = (state_r == ST_IDLE);
    assign o_busy         = (state_r != ST_IDLE);
    assign o_done         = (state_r == ST_FINISH);

    // 當兩端 FIFO 都有料時同步發起抽料
    assign o_fifo_rden    = (state_r == ST_COMPUTE) && i_a_fifo_rdy && i_b_fifo_rdy;

    // 波前與陣列推進致能
    assign o_step_en      = ((state_r == ST_COMPUTE) && i_a_fifo_rdy && i_b_fifo_rdy) ||
                            (state_r == ST_FLUSH);

    // 新 Tile 啟動時清零
    assign o_clr_acc      = (state_r == ST_INIT_TILE);
    assign o_clr_skew     = (state_r == ST_INIT_TILE);

    // 快照脈衝 (僅在 ST_SNAPSHOT 狀態拉高 1 拍)
    assign o_snapshot     = (state_r == ST_SNAPSHOT);

    // 啟動排空
    assign o_drain_start  = (state_r == ST_SNAPSHOT);

    // 動態幾何維度傳遞
    assign o_m_base       = '0;
    assign o_n_base       = '0;
    assign o_active_rows  = (reg_m_r > S_MAX) ? S_MAX[$clog2(S_MAX+1)-1:0] : reg_m_r[$clog2(S_MAX+1)-1:0];
    assign o_active_cols  = (reg_n_r > S_MAX) ? S_MAX[$clog2(S_MAX+1)-1:0] : reg_n_r[$clog2(S_MAX+1)-1:0];

endmodule


