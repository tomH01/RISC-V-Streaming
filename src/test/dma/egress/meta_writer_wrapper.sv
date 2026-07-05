module meta_writer_wrapper #(
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int B_BANKS       = 2,

  localparam int BANK_PTR_WIDTH   = $clog2(B_BANKS)
)(
  input logic clk_i,
  input logic rst_ni,

  // L2 Allocator IF
  input  logic                      meta_valid_i,
  input  logic                      meta_close_bank_i,
  input  logic [BANK_PTR_WIDTH-1:0] meta_bank_idx_i,
  input  logic [DATA_WIDTH-1:0]     meta_window_id_i,
  input  logic [DATA_WIDTH-1:0]     meta_window_size_i,
  output logic                      meta_done_o,
  output logic                      meta_ready_o,

  // Control IF
  input logic [DATA_WIDTH-1:0] l2_bank_base_i [B_BANKS],

  // Bus IF
  input logic                       bus_ready_i,
  output logic                      bus_valid_o,
  output logic [BANK_PTR_WIDTH-1:0] bus_bank_o,
  output logic [ADDR_WIDTH-1:0]     bus_addr_o,
  output logic [DATA_WIDTH-1:0]     bus_wdata_o
);

  meta_if #(
    .DATA_WIDTH(DATA_WIDTH),
    .B_BANKS(B_BANKS)
  ) u_meta_req_if();

  meta_writer #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .B_BANKS(B_BANKS)
  ) u_meta_writer (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    // L2 Allocator IF
    .meta_req_i(u_meta_req_if),

    // Control IF
    .l2_bank_base_i(l2_bank_base_i),

    // Bus IF
    .bus_ready_i(bus_ready_i),
    .bus_valid_o(bus_valid_o),
    .bus_bank_o(bus_bank_o),
    .bus_addr_o(bus_addr_o),
    .bus_wdata_o(bus_wdata_o)
  );

  assign u_meta_req_if.valid           = meta_valid_i;
  assign u_meta_req_if.pkt.close_bank  = meta_close_bank_i;
  assign u_meta_req_if.pkt.bank_idx    = meta_bank_idx_i;
  assign u_meta_req_if.pkt.window_id   = meta_window_id_i;
  assign u_meta_req_if.pkt.window_size = meta_window_size_i;
  assign meta_ready_o                  = u_meta_req_if.ready;
  assign meta_done_o                   = u_meta_req_if.done;

endmodule
