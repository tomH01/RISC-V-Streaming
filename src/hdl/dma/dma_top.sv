/* 
Ingress top
Buffer pool 
Egress top
Control
Bus IF
CPU Connection?
*/

module dma_top #(
  parameter int N_STREAMS     = 4,
  parameter int M_MACROS      = 8,
  parameter int NB_READ_PORTS = 1,
  parameter int DATA_WIDTH    = 32,
  parameter int ADD_WIDTH     = 32,
)(
  input logic clk_i,
  input logic rst_ni
)
endmodule