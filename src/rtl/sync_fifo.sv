// verilog_lint: waive-start
//////////////////////////////////////////////////////////////////////////////////
// Company: AGILAB
// Engineer: Undergraduate Student
//
// Create Date: 2026/08/13 13:57:33
// Design Type: RTL (Synthesizable Circuit)
// Design Name: ic_lab01_fifo
// Module Name: sync_fifo
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 建立資料位元寬度為data_width參數 深度為depth參數的sync_fifo
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

module sync_fifo #(
    parameter data_width = 32,   // 資料位元寬度 (32-bit)
    parameter depth      = 8     // FIFO 深度/容量 (8 個筆數)
)(
    input i_clk,    // 系統時脈
    input i_rst_n,  // 低準位非同步復位 (Reset)

    input i_wr_en,  // 寫入致能訊號
    input [data_width-1:0] i_din,    // 輸入資料
    output o_full,  // FIFO 滿旗標 (Full Flag)

    input i_rd_en,  // 讀取致能訊號
    output reg [data_width-1:0] o_dout,   // 輸出資料
    output o_empty   // FIFO 空旗標 (Empty Flag)
);

    // 自動計算定址所需的位元數 (例如 depth=16 則 add_width=4)
    localparam add_width = $clog2(depth);

    // 內部記憶體陣列 (Memory) 與 指標 (Pointers)
    reg [data_width-1:0] mem_r [0:depth-1]; // 儲存資料的 RAM 陣列
    reg [add_width-1:0] wr_ptr_r;          // 寫入指標
    reg [add_width-1:0] rd_ptr_r;          // 讀取指標
    reg [add_width:0] count_r;             // 當前 FIFO 內的資料總筆數 (比 add_width 多 1-bit 以儲存 FULL 狀態)

    // 組合邏輯判斷 FIFO 的 Empty / Full 狀態
    assign o_empty = (count_r == 0);          // 筆數為 0 時代表 FIFO 空了
    assign o_full  = (count_r == depth);      // 筆數等於深度時代表 FIFO 滿了

    // 正邊緣時脈觸發的主邏輯
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            // 系統復位：重置指標與計數器
            wr_ptr_r <= 0;
            rd_ptr_r <= 0;
            count_r  <= 0;
            o_dout   <= 0;
        end

        else begin
            // --- 寫入邏輯 ---
            if (i_wr_en && !o_full) begin     // 允許寫入且 FIFO 未滿
                mem_r[wr_ptr_r] <= i_din;     // 將資料寫入當前指標位置
                wr_ptr_r        <= wr_ptr_r + 1'b1; // 寫入指標 +1
            end

            // --- 讀取邏輯 ---
            if (i_rd_en && !o_empty) begin    // 允許讀取且 FIFO 非空
                o_dout   <= mem_r[rd_ptr_r];  // 將當前指標位置的資料讀出
                rd_ptr_r <= rd_ptr_r + 1'b1;  // 讀取指標 +1
            end

            // --- 更新內部資料總筆數 (count) ---
            case ({i_wr_en && !o_full, i_rd_en && !o_empty})
                2'b10: count_r <= count_r + 1'b1; // 只有寫入成功 -> 筆數 +1
                2'b01: count_r <= count_r - 1'b1; // 只有讀取成功 -> 筆數 -1
                default: count_r <= count_r;      // 無操作或同時讀寫 -> 筆數不變
            endcase
        end
    end

endmodule
