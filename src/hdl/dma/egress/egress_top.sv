module egress_top #(
  parameter int N_STREAMS  = 4,
  parameter int M_MACROS   = 8,
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 32,
  parameter int W_WORKERS  = 2,
  parameter int B_BANKS    = 2,
  parameter int BANK_DEPTH = 16384,

  localparam int MACRO_PTR_WIDTH  = $clog2(M_MACROS),
  localparam int STREAM_PTR_WIDTH = (N_STREAMS > 1) ? $clog2(N_STREAMS) : 1,
  localparam int WORKER_PTR_WIDTH = (W_WORKERS > 1) ? $clog2(W_WORKERS) : 1,
  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS),
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int DMA_MANAGERS     = W_WORKERS
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
  input logic                   enable_i,
  input logic  [DATA_WIDTH-1:0] l2_bank_base_i,

  input logic [N_STREAMS-1:0]       stream_en_i,
  input logic [ADDR_WIDTH-1:0]      window_size_i  [N_STREAMS],
  input logic [MACRO_PTR_WIDTH-1:0] start_macro_i  [N_STREAMS],
  input logic [MACRO_PTR_WIDTH-1:0] next_pointer_i [M_MACROS],

  output logic                    job_dispatched_o,
  input  logic [N_STREAMS-1:0]    cfg_push_i,
  input  logic [4*DATA_WIDTH-1:0] cfg_wdata_i [N_STREAMS],

  // Meta IF
  input  logic                        meta_req_i,
  input  logic [ADDR_WIDTH-1:0]       meta_addr_i,
  output logic                        meta_gnt_o,
  input  logic                        meta_wen_i ,
  input  logic [DATA_WIDTH-1:0]       meta_wdata_i,
  input  logic [DATA_WIDTH_BYTES-1:0] meta_be_i,

  output logic [DATA_WIDTH-1:0] meta_r_rdata_o,
  output logic                  meta_r_valid_o,

  // Bus IF
  input  logic [DMA_MANAGERS-1:0]   bus_ready_i,
  output logic [DMA_MANAGERS-1:0]   bus_valid_o,
  output logic [ADDR_WIDTH-1:0]     bus_addr_o  [DMA_MANAGERS],
  output logic [DATA_WIDTH-1:0]     bus_wdata_o [DMA_MANAGERS]
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

  logic                  fifo_ready;
  logic                  fifo_valid;
  logic [DATA_WIDTH-1:0] fifo_data;
  logic [ADDR_WIDTH-1:0] cpu_done_ptr;

  l2_allocator #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS)
  ) u_l2_allocator (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .job_req_i(u_job_req_if.rx_ready),

    .enable_i(enable_i),
    .l2_bank_base_i(l2_bank_base_i),
    .job_dispatched_o(job_dispatched_o),

    .worker_done_i(worker_done),
    .job_wid_o(job_wid),
    .job_addr_o(job_addr),
    .job_assign_o(u_job_assign_if.tx_push),

    .fifo_ready_i(fifo_ready),
    .fifo_valid_o(fifo_valid),
    .fifo_data_o(fifo_data),
    .cpu_done_ptr_i(cpu_done_ptr)
  );


  // #####
  // Meta

  logic [W_WORKERS-1:0]        ptr_valid;
  logic [STREAM_PTR_WIDTH-1:0] ptr_stream_id [W_WORKERS];
  logic [ADDR_WIDTH-1:0]       ptr           [W_WORKERS];

  meta #(
    .N_STREAMS(N_STREAMS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS),
    .BANK_DEPTH(BANK_DEPTH)
  ) u_meta (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .enable_i(enable_i),
    .l2_bank_base_i(l2_bank_base_i),

    .meta_req_i(meta_req_i),
    .meta_addr_i(meta_addr_i),
    .meta_gnt_o(meta_gnt_o),
    .meta_wen_i(meta_wen_i),
    .meta_wdata_i(meta_wdata_i),
    .meta_be_i(meta_be_i),

    .meta_r_rdata_o(meta_r_rdata_o),
    .meta_r_valid_o(meta_r_valid_o),

    .fifo_ready_o(fifo_ready),
    .fifo_valid_i(fifo_valid),
    .fifo_data_i(fifo_data),
    .cpu_done_ptr_o(cpu_done_ptr),

    .ptr_valid_i(ptr_valid),
    .ptr_stream_id_i(ptr_stream_id),
    .ptr_i(ptr)
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

        .next_pointer_i(next_pointer_i),

        .sel_i(worker_sel[i]),
        .job_assign_i(u_job_assign_if.rx_push),
        .job_addr_i(job_addr),
        .job_done_o(worker_done[i]),

        .ptr_valid_o(ptr_valid[i]),
        .ptr_stream_id_o(ptr_stream_id[i]),
        .ptr_o(ptr[i]),

        .bp_release_o(bp_release_all_o[i]),
        .bp_req_o(bp_req_o[i]),
        .bp_addr_o(bp_addr_o[i]),
        .bp_macro_sel_o(bp_macro_sel_o[i]),
        .bp_gnt_i(bp_gnt_i[i]),
        .bp_r_rdata_i(bp_r_rdata_o[i]),
        .bp_r_valid_i(bp_r_valid_o[i]),

        .bus_ready_i(bus_ready_i[i]),
        .bus_valid_o(bus_valid_o[i]),
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
