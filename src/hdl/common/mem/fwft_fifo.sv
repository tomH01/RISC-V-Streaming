module fwft_fifo #(
  parameter int DATA_WIDTH = 32,
  parameter int DEPTH      = 8,

  localparam int USAGE_WIDTH = $clog2(DEPTH + 1)
)(
  input logic clk_i,
  input logic rst_ni,

  // Write
  input  logic                   push_i,
  input  logic [DATA_WIDTH-1:0]  data_i,
  output logic                   full_o,
  output logic [USAGE_WIDTH-1:0] usage_o,

  // Read
  input  logic                  pop_i,
  output logic [DATA_WIDTH-1:0] data_o,
  output logic                  empty_o
);

  logic [DATA_WIDTH-1:0]      mem [DEPTH];
  logic [$clog2(DEPTH+1)-1:0] count_q;
  logic [$clog2(DEPTH)-1:0]   wr_ptr_q, rd_ptr_q;

  assign full_o  = (count_q == DEPTH);
  assign empty_o = (count_q == 0);

  assign usage_o = count_q;
  assign data_o  = mem[rd_ptr_q];

  logic push, pop;
  assign push = push_i && !full_o;
  assign pop  = pop_i  && !empty_o;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mem      <= '{default:'0};
      count_q  <= '0;
      wr_ptr_q <= '0;
      rd_ptr_q <= '0;
    end else begin
      if (push) begin
        mem[wr_ptr_q] <= data_i;
        wr_ptr_q      <= (wr_ptr_q == DEPTH-1) ? '0 : wr_ptr_q + 1;
      end
      if (pop) begin
        rd_ptr_q <= (rd_ptr_q == DEPTH-1) ? '0 : rd_ptr_q + 1;
      end

      if (push && !pop) begin
        count_q <= count_q + 1;
      end else if (!push && pop) begin
        count_q <= count_q - 1;
      end
    end
  end

endmodule
