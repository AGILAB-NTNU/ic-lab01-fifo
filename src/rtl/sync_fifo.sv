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
    parameter int DATA_WIDTH = 32,  // 資料位元寬度
    parameter int DEPTH      = 8    // FIFO 深度
) (
    input i_clk,   // 系統時脈
    input i_rst_n, // 低準位同步復位

    input                   i_wr_en,  // 寫入致能訊號
    input  [DATA_WIDTH-1:0] i_din,    // 輸入資料
    output                  o_full,   // FIFO 滿旗標

    input                       i_rd_en,  // 讀取致能訊號
    output reg [DATA_WIDTH-1:0] o_dout,   // 輸出資料
    output                      o_empty   // FIFO 空旗標
);

  // 自動計算定址所需的位元數
  localparam int AddWidth = $clog2(DEPTH);

  // 內部記憶體陣列與指標
  reg [DATA_WIDTH-1:0] mem_r [DEPTH];
  reg [AddWidth-1:0]  wr_ptr_r;
  reg [AddWidth-1:0]  rd_ptr_r;
  reg [AddWidth:0]    count_r;

  // 組合邏輯判斷 FIFO 的 Empty / Full 狀態
  assign o_empty = (count_r == 0);
  assign o_full  = (count_r == DEPTH[AddWidth:0]);

  // 正邊緣時脈觸發（改為「同步復位」，移除 negedge i_rst_n）
  always @(posedge i_clk) begin
    if (!i_rst_n) begin
      // 系統復位：重置指標與計數器
      wr_ptr_r <= 0;
      rd_ptr_r <= 0;
      count_r  <= 0;
      o_dout   <= 0;
    end else begin
      // 寫入邏輯
      if (i_wr_en && !o_full) begin
        mem_r[wr_ptr_r] <= i_din;
        wr_ptr_r        <= wr_ptr_r + 1'b1;
      end

      // 讀取邏輯
      if (i_rd_en && !o_empty) begin
        o_dout   <= mem_r[rd_ptr_r];
        rd_ptr_r <= rd_ptr_r + 1'b1;
      end

      // 更新內部資料總筆數
      case ({
        i_wr_en && !o_full, i_rd_en && !o_empty
      })
        2'b10:   count_r <= count_r + 1'b1;
        2'b01:   count_r <= count_r - 1'b1;
        default: count_r <= count_r;
      endcase
    end
  end

endmodule
