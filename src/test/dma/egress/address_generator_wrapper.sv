module address_generator_wrapper #(
  parameter int N_STREAMS  = 4,
  parameter int M_MACROS   = 8,
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 32,
  parameter int B_BANKS    = 2,
  parameter int MACRO_DEPTH = 256,

  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS),
  localparam int STREAM_PTR_WIDTH = $clog2(N_STREAMS),
  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS)
)(
  input logic clk_i,
  input logic rst_ni,

  // Allocator IF
  input logic                        sel_i,

  input logic                        job_assign_valid_i,
  input logic [STREAM_PTR_WIDTH-1:0] job_assign_stream_id_i,
  input logic [MACRO_PTR_WIDTH-1:0]  job_assign_start_macro_i,
  input logic [ADDR_WIDTH-1:0]       job_assign_window_size_i,
  input logic [3:0]                  job_assign_mode_i,
  input logic [15:0]                 job_assign_window_id_i,
  input logic [95:0]                 job_assign_payload_i,

  input logic [ADDR_WIDTH-1:0]     job_addr_i,
  input logic [BANK_PTR_WIDTH-1:0] job_bank_i,
  output logic                     job_done_o,

  // Control IF
  input logic [MACRO_PTR_WIDTH-1:0] next_pointer_i [M_MACROS],

  // Buffer Pool IF
  output logic [M_MACROS-1:0]        bp_release_o,
  output logic                       bp_req_o,
  output logic [ADDR_WIDTH-1:0]      bp_addr_o,
  output logic [MACRO_PTR_WIDTH-1:0] bp_macro_sel_o,
  input  logic                       bp_gnt_i,
  input  logic [DATA_WIDTH-1:0]      bp_r_rdata_i,
  input  logic                       bp_r_valid_i,

  // Bus IF
  input logic                   bus_ready_i,
  output logic                  bus_valid_o,
  output logic [ADDR_WIDTH-1:0] bus_addr_o,
  output logic [DATA_WIDTH-1:0] bus_wdata_o
);

  job_if #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_job_assign_if();

  assign u_job_assign_if.valid           = job_assign_valid_i;
  assign u_job_assign_if.pkt.stream_id   = job_assign_stream_id_i;
  assign u_job_assign_if.pkt.start_macro = job_assign_start_macro_i;
  assign u_job_assign_if.pkt.window_size = job_assign_window_size_i;
  assign u_job_assign_if.pkt.mode        = job_assign_mode_i;
  assign u_job_assign_if.pkt.window_id   = job_assign_window_id_i;
  assign u_job_assign_if.pkt.payload     = job_assign_payload_i;

  address_generator #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .B_BANKS(B_BANKS),
    .MACRO_DEPTH(MACRO_DEPTH)
  ) u_address_generator (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .sel_i(sel_i),
    .job_assign_i(u_job_assign_if.rx_push),
    .job_addr_i(job_addr_i),
    .job_bank_i(job_bank_i),
    .job_done_o(job_done_o),

    .next_pointer_i(next_pointer_i),

    .bp_release_o(bp_release_o),
    .bp_req_o(bp_req_o),
    .bp_addr_o(bp_addr_o),
    .bp_macro_sel_o(bp_macro_sel_o),
    .bp_gnt_i(bp_gnt_i),
    .bp_r_rdata_i(bp_r_rdata_i),
    .bp_r_valid_i(bp_r_valid_i),

    .bus_ready_i(bus_ready_i),
    .bus_valid_o(bus_valid_o),
    .bus_addr_o(bus_addr_o),
    .bus_wdata_o(bus_wdata_o)
  );

endmodule
