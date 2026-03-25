module control #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int NB_READ_PORTS = 1,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32
)(
  input logic clk_i,
  input logic rst_ni,

  // APB target IF
  input logic 					            penable_i,
  input logic 					            pwrite_i,
  input logic [APB_ADDR_WIDTH-1:0]  paddr_i,
  input logic                       psel_i,
  input logic [APB_DATA_WIDTH-1:0]  pwdata_i,
  output logic [APB_DATA_WIDTH-1:0] prdata_o,
  output logic 					            pready_o,
  output logic 					            pslverr_o,

  // Ingress IF
  output logic [N_STREAMS-1:0]        stream_en_o,
  output logic [ADDR_WIDTH-1:0]       window_size_o,
  output logic [$clog2(M_MACROS)-1:0] start_macro_o [N_STREAMS],
  output logic [$clog2(M_MACROS)-1:0] next_point_o  [M_MACROS]

  // Egress IF
);
endmodule
