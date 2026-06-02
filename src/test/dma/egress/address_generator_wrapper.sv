module address_generator_wrapper #(
  parameter int N_STREAMS  = 4,
  parameter int M_MACROS   = 8,
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 32,
  parameter int B_BANKS    = 2,
  parameter int MACRO_DEPTH = 256,
)(
  input logic clk_i,
  input logic rst_ni,

  // Allocator IF
  input logic                      sel_i,
  input logic                      job_assign_valid_i,
  input logic [STREAM_PTR_WIDTH-1:0] job_assign_stream_id,


  job_if.rx_push                   job_assign_i,
  input logic [ADDR_WIDTH-1:0]     job_addr_i,
  input logic [BANK_PTR_WIDTH-1:0] job_bank_i,
  output logic                     done_o,

  // Control IF
  input logic [MACRO_PTR_WIDTH-1:0] next_pointer_i [M_MACROS],

  // Buffer Pool IF
  output logic [M_MACROS-1:0]        bp_release_o,
  output logic                       bp_req_o,
  output logic [ADDR_WIDTH-1:0]      bp_addr_o,
  output logic [MACRO_PTR_WIDTH-1:0] bp_macro_select_o,
  input  logic                       bp_gnt_i,
  input  logic                       bp_r_opc_i,
  input  logic [DATA_WIDTH-1:0]      bp_r_rdata_i,
  input  logic                       bp_r_valid_i,

  // Bus IF
  input logic                   bus_ready_i,
  output logic                  bus_valid_o,
  output logic [ADDR_WIDTH-1:0] bus_addr_o,
  output logic [DATA_WIDTH-1:0] bus_wdata_o
);



endmodule
