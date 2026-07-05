module egress_top #(
  parameter int N_STREAMS  = 4,
  parameter int M_MACROS   = 8,
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH  = 32,
  parameter int W_WORKERS  = 2,
  parameter int B_BANKS    = 2,

  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS),
  localparam int STREAM_PTR_WIDTH = (N_STREAMS > 1) ? $clog2(N_STREAMS) : 1,
  localparam int WORKER_PTR_WIDTH = (W_WORKERS > 1) ? $clog2(W_WORKERS) : 1,
  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int META_MASTER      = 1,
  localparam int NUM_MASTERS      = W_WORKERS + META_MASTER,
  localparam int META_WRT_BUS_IDX = NUM_MASTERS - META_MASTER
)(
  input logic clk_i,
  input logic rst_ni,

  // Ingress IF
  input logic [N_STREAMS-1:0]        notif_valid_i,
  input logic [MACRO_PTR_WIDTH-1:0]  notif_start_macro_i [N_STREAMS],

  // Buffer Pool IF
  input  logic [W_WORKERS-1:0]       bp_gnt_i,
  input  logic [DATA_WIDTH-1:0]      bp_r_rdata_o   [W_WORKERS],
  input  logic [W_WORKERS-1:0]       bp_r_valid_o,
  output logic [M_MACROS-1:0]        bp_release_o,
  output logic [W_WORKERS-1:0]       bp_req_o,
  output logic [ADDR_WIDTH-1:0]      bp_addr_o      [W_WORKERS],
  output logic [MACRO_PTR_WIDTH-1:0] bp_macro_sel_o [W_WORKERS],

  // Control IF
  input logic                   start_bank_idx_i,
  input logic  [DATA_WIDTH-1:0] l2_bank_base_i [B_BANKS],
  input logic  [DATA_WIDTH-1:0] bank_limit_b_i,
  input logic  [DATA_WIDTH-1:0] bank_header_size_b_i,
  input logic  [B_BANKS-1:0]    bank_owner_i,
  output logic [B_BANKS-1:0]    bank_full_o,

  input logic [N_STREAMS-1:0]       stream_en_i,
  input logic [ADDR_WIDTH-1:0]      window_size_i  [N_STREAMS],
  input logic [MACRO_PTR_WIDTH-1:0] start_macro_i  [N_STREAMS],
  input logic [MACRO_PTR_WIDTH-1:0] next_pointer_i [M_MACROS],

  input logic [N_STREAMS-1:0]    cfg_push_i,
  input logic [4*DATA_WIDTH-1:0] cfg_wdata_i [N_STREAMS],

  // Bus IF
  input  logic [NUM_MASTERS-1:0]    bus_ready_i,
  output logic [NUM_MASTERS-1:0]    bus_valid_o,
  output logic [BANK_PTR_WIDTH-1:0] bus_bank_o  [NUM_MASTERS],
  output logic [ADDR_WIDTH-1:0]     bus_addr_o  [NUM_MASTERS],
  output logic [DATA_WIDTH-1:0]     bus_wdata_o [NUM_MASTERS]
);

  // ############
  // Interfaces

  job_if #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_job_req_if();

  job_if #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_job_assign_if();

  meta_if #(
    .DATA_WIDTH(DATA_WIDTH),
    .B_BANKS(B_BANKS)
  ) u_meta_req_if();


  // ############
  // Job Manager

  job_manager #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_job_manager (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .notif_valid_i(notif_valid_i),
    .notif_start_macro_i(notif_start_macro_i),

    .cfg_push_i(cfg_push_i),
    .cfg_wdata_i(cfg_wdata_i),

    .window_size_i(window_size_i),

    .job_req_o(u_job_req_if.tx_ready)
  );


  // ############
  // L2 Allocator

  logic [W_WORKERS-1:0]        worker_done;
  logic [WORKER_PTR_WIDTH-1:0] job_wid;
  logic [ADDR_WIDTH-1:0]       job_addr;
  logic [BANK_PTR_WIDTH-1:0]   job_bank;

  l2_allocator #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS)
  ) u_l2_allocator (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .job_req_i(u_job_req_if.rx_ready),

    .start_bank_idx_i(start_bank_idx_i),
    .l2_bank_base_i(l2_bank_base_i),
    .bank_limit_b_i(bank_limit_b_i),
    .bank_header_size_b_i(bank_header_size_b_i),
    .bank_owner_i(bank_owner_i),
    .bank_full_o(bank_full_o),

    .worker_done_i(worker_done),
    .job_wid_o(job_wid),
    .job_addr_o(job_addr),
    .job_bank_o(job_bank),
    .job_assign_o(u_job_assign_if.tx_push),

    .meta_req_o(u_meta_req_if.tx_ready)
  );


  // ###########
  // Meta Writer

  meta_writer #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .B_BANKS(B_BANKS)
  ) u_meta_writer (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .meta_req_i(u_meta_req_if.rx_ready),

    .l2_bank_base_i(l2_bank_base_i),

    .bus_ready_i(bus_ready_i[META_WRT_BUS_IDX]),
    .bus_valid_o(bus_valid_o[META_WRT_BUS_IDX]),
    .bus_bank_o(bus_bank_o[META_WRT_BUS_IDX]),
    .bus_addr_o(bus_addr_o[META_WRT_BUS_IDX]),
    .bus_wdata_o(bus_wdata_o[META_WRT_BUS_IDX])
  );



  // ############
  // W Workers

  logic [W_WORKERS-1:0] worker_sel;
  always_comb begin
    worker_sel = '0;
    worker_sel[job_wid] = 1'b1;
  end

  logic [M_MACROS-1:0] bp_release_all_o [W_WORKERS-1:0];

  generate
    for (genvar i = 0; i < W_WORKERS; i++) begin : gen_workers
      address_generator #(
        .N_STREAMS(N_STREAMS),
        .M_MACROS(M_MACROS),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .B_BANKS(B_BANKS)
      ) u_addr_generator (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .sel_i(worker_sel[i]),
        .job_assign_i(u_job_assign_if.rx_push),
        .job_addr_i(job_addr),
        .job_bank_i(job_bank),
        .job_done_o(worker_done[i]),

        .next_pointer_i(next_pointer_i),

        .bp_release_o(bp_release_all_o[i]),
        .bp_req_o(bp_req_o[i]),
        .bp_addr_o(bp_addr_o[i]),
        .bp_macro_sel_o(bp_macro_sel_o[i]),
        .bp_gnt_i(bp_gnt_i[i]),
        .bp_r_rdata_i(bp_r_rdata_o[i]),
        .bp_r_valid_i(bp_r_valid_o[i]),

        .bus_ready_i(bus_ready_i[i]),
        .bus_valid_o(bus_valid_o[i]),
        .bus_bank_o(bus_bank_o[i]),
        .bus_addr_o(bus_addr_o[i]),
        .bus_wdata_o(bus_wdata_o[i])
      );
    end
  endgenerate

  always_comb begin
    bp_release_o = '0;
    foreach (bp_release_all_o[i]) begin
      bp_release_o |= bp_release_all_o[i];
    end
  end

endmodule
