/* Tabels:
- Per Stream: current pointer, next_pointer table (torus)
- 

*/

module alloc_manager #(
  parameter int N_STREAMS   = 4,
  parameter int M_MACROS    = 16,
  parameter int MACRO_DEPTH = 256

)(
  input logic clk_i,
  input logic rst_ni,

  input logic [M_MACROS-1:0] macro_req_i,
  input logic [M_MACROS-1:0] macro_gnt_i,
  output logic [31:0] macro_w_addr_o [M_MACROS-1:0],
  output logic [M_MACROS-1:0] 
);


endmodule