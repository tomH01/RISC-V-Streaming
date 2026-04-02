module rr_arbiter #(
  parameter int N = 4
)(
  input logic clk_i,
  input logic rst_ni,

  input logic          req_i,
  input logic  [N-1:0] ready_i,
  output logic [N-1:0] gnt_o,
  output logic         valid_o
);

  logic [N-1:0] pointer, pointer_next;
  logic [N-1:0] mask;
  logic [N-1:0] choose_high, choose_low;
  logic [N-1:0] grant;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pointer <= '0;
    end else begin
      pointer <= pointer_next;
    end
  end

  always_comb begin
    mask = ~(pointer | (pointer - 1'b1));
  
    choose_high = ready_i & mask;
    choose_low  = ready_i;

    if (req_i && |ready_i) begin
      if (|choose_high) begin
        grant = choose_high & (-choose_high);
      end else begin
        grant = choose_low & (-choose_low);
      end

      gnt_o = grant;
      valid_o = 1'b1;
      pointer_next = grant;
      
    end else begin
      gnt_o   = '0;
      valid_o = 1'b0;
      pointer_next = pointer;
    end
  end
endmodule
