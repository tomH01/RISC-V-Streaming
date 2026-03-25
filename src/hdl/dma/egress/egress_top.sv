module ingress_top #(
  parameter int N_STREAMS  = 4,
  parameter int M_MACROS   = 8,
  parameter int DATA_WIDTH = 32,
  parameter int ADD_WIDTH  = 32,
  parameter int NB_READ_PORTS = 1 
)(
  input logic clk_i,
  input logic rst_ni,

  // Ingress IF
  input logic [N_STREAMS-1:0]        notify_valid_i,
  input logic [$clog2(M_MACROS)-1:0] notify_start_macro_i [N_STREAMS],

  // Buffer Pool IF
  input logic  [NB_READ_PORTS-1:0]    bp_gnt_i,
  input logic  [NB_READ_PORTS-1:0]    bp_r_opc_o,
  input logic  [DATA_WIDTH-1:0]       bp_r_rdata_o      [NB_READ_PORTS],
  input logic  [NB_READ_PORTS-1:0]    bp_r_valid_o,
  output logic [NB_READ_PORTS-1:0]    bp_req_o,
  output logic [ADDR_WIDTH-1:0]       bp_addr_o         [NB_READ_PORTS],
  output logic [$clog2(M_MACROS)-1:0] bp_macro_select_o [NB_READ_PORTS],
);

endmodule