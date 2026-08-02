`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "apb/assign.svh"
`include "apb/typedef.svh"
`include "common_cells/registers.svh"


module top_axi_wrapper #(
  parameter int N_STREAMS           = 4,
  parameter int M_MACROS            = 8,
  parameter int DATA_WIDTH          = 32,
  parameter int ADDR_WIDTH          = 32,
  parameter int W_WORKERS           = 1,
  parameter int B_BANKS             = 2,
  parameter int MACRO_DEPTH         = 256,
  parameter int BANK_DEPTH          = 16384,
  parameter int STREAM_OFFSET_WIDTH = 10,
  parameter int ID_WIDTH            = 12,
  parameter int USER_WIDTH          = 1,

  localparam int STRB_WIDTH = DATA_WIDTH / 8
)(
  input logic clk_i,
  input logic rst_ni,

  // ############################
  // AXI4 Subordinate IF (DATA)
  // ############################

  // Write Address Channel (AW)
  input  logic [ID_WIDTH-1:0]   s_axi_data_awid_i,
  input  logic [ADDR_WIDTH-1:0] s_axi_data_awaddr_i,
  input  logic [7:0]            s_axi_data_awlen_i,
  input  logic [2:0]            s_axi_data_awsize_i,
  input  logic [1:0]            s_axi_data_awburst_i,
  input  logic                  s_axi_data_awlock_i,
  input  logic [3:0]            s_axi_data_awcache_i,
  input  logic [2:0]            s_axi_data_awprot_i,
  input  logic [3:0]            s_axi_data_awqos_i,
  input  logic [3:0]            s_axi_data_awregion_i,
  input  logic [USER_WIDTH-1:0] s_axi_data_awuser_i,
  input  logic                  s_axi_data_awvalid_i,
  output logic                  s_axi_data_awready_o,

  // Write Data Channel (W)
  input  logic [DATA_WIDTH-1:0] s_axi_data_wdata_i,
  input  logic [STRB_WIDTH-1:0] s_axi_data_wstrb_i,
  input  logic                  s_axi_data_wlast_i,
  input  logic [USER_WIDTH-1:0] s_axi_data_wuser_i,
  input  logic                  s_axi_data_wvalid_i,
  output logic                  s_axi_data_wready_o,

  // Write Response Channel (B)
  output logic [ID_WIDTH-1:0]   s_axi_data_bid_o,
  output logic [1:0]            s_axi_data_bresp_o,
  output logic [USER_WIDTH-1:0] s_axi_data_buser_o,
  output logic                  s_axi_data_bvalid_o,
  input  logic                  s_axi_data_bready_i,

  // Read Address Channel (AR)
  input  logic [ID_WIDTH-1:0]   s_axi_data_arid_i,
  input  logic [ADDR_WIDTH-1:0] s_axi_data_araddr_i,
  input  logic [7:0]            s_axi_data_arlen_i,
  input  logic [2:0]            s_axi_data_arsize_i,
  input  logic [1:0]            s_axi_data_arburst_i,
  input  logic                  s_axi_data_arlock_i,
  input  logic [3:0]            s_axi_data_arcache_i,
  input  logic [2:0]            s_axi_data_arprot_i,
  input  logic [3:0]            s_axi_data_arqos_i,
  input  logic [3:0]            s_axi_data_arregion_i,
  input  logic [USER_WIDTH-1:0] s_axi_data_aruser_i,
  input  logic                  s_axi_data_arvalid_i,
  output logic                  s_axi_data_arready_o,

  // Read Data Channel (R)
  output logic [ID_WIDTH-1:0]   s_axi_data_rid_o,
  output logic [DATA_WIDTH-1:0] s_axi_data_rdata_o,
  output logic [1:0]            s_axi_data_rresp_o,
  output logic                  s_axi_data_rlast_o,
  output logic [USER_WIDTH-1:0] s_axi_data_ruser_o,
  output logic                  s_axi_data_rvalid_o,
  input  logic                  s_axi_data_rready_i,


  // ############################
  // AXI4-Lite Subordinate IF (CTRL)
  // ############################

  // Write Address Channel (AW)
  input  logic [ADDR_WIDTH-1:0] s_axi_ctrl_awaddr_i,
  input  logic [2:0]            s_axi_ctrl_awprot_i,
  input  logic                  s_axi_ctrl_awvalid_i,
  output logic                  s_axi_ctrl_awready_o,

  // Write Data Channel (W)
  input  logic [DATA_WIDTH-1:0] s_axi_ctrl_wdata_i,
  input  logic [STRB_WIDTH-1:0] s_axi_ctrl_wstrb_i,
  input  logic                  s_axi_ctrl_wvalid_i,
  output logic                  s_axi_ctrl_wready_o,

  // Write Response Channel (B)
  output logic [1:0]            s_axi_ctrl_bresp_o,
  output logic                  s_axi_ctrl_bvalid_o,
  input  logic                  s_axi_ctrl_bready_i,

  // Read Address Channel (AR)
  input  logic [ADDR_WIDTH-1:0] s_axi_ctrl_araddr_i,
  input  logic [2:0]            s_axi_ctrl_arprot_i,
  input  logic                  s_axi_ctrl_arvalid_i,
  output logic                  s_axi_ctrl_arready_o,

  // Read Data Channel (R)
  output logic [DATA_WIDTH-1:0] s_axi_ctrl_rdata_o,
  output logic [1:0]            s_axi_ctrl_rresp_o,
  output logic                  s_axi_ctrl_rvalid_o,
  input  logic                  s_axi_ctrl_rready_i,


  // Job Dispatch IF
  output logic job_dispatched_o
);

  // Type conversion to PULP structs
  typedef logic [ADDR_WIDTH-1:0] addr_t;
  typedef logic [DATA_WIDTH-1:0] data_t;
  typedef logic [STRB_WIDTH-1:0] strb_t;
  typedef logic [ID_WIDTH-1:0]   id_t;
  typedef logic [USER_WIDTH-1:0] user_t;

  `AXI_TYPEDEF_ALL(data_axi, addr_t, id_t, data_t, strb_t, user_t)
  `AXI_LITE_TYPEDEF_ALL(ctrl_axi_lite, addr_t, data_t, strb_t)

  data_axi_req_t       data_req;
  data_axi_resp_t      data_resp;
  ctrl_axi_lite_req_t  ctrl_req;
  ctrl_axi_lite_resp_t ctrl_resp;

  // AXI4 Full Mapping
  assign data_req.aw.id       = s_axi_data_awid_i;
  assign data_req.aw.addr     = s_axi_data_awaddr_i;
  assign data_req.aw.len      = s_axi_data_awlen_i;
  assign data_req.aw.size     = s_axi_data_awsize_i;
  assign data_req.aw.burst    = s_axi_data_awburst_i;
  assign data_req.aw.lock     = s_axi_data_awlock_i;
  assign data_req.aw.cache    = s_axi_data_awcache_i;
  assign data_req.aw.prot     = s_axi_data_awprot_i;
  assign data_req.aw.qos      = s_axi_data_awqos_i;
  assign data_req.aw.region   = s_axi_data_awregion_i;
  assign data_req.aw.atop     = '0;
  assign data_req.aw.user     = s_axi_data_awuser_i;
  assign data_req.aw_valid    = s_axi_data_awvalid_i;
  assign s_axi_data_awready_o = data_resp.aw_ready;

  assign data_req.w.data      = s_axi_data_wdata_i;
  assign data_req.w.strb      = s_axi_data_wstrb_i;
  assign data_req.w.last      = s_axi_data_wlast_i;
  assign data_req.w.user      = s_axi_data_wuser_i;
  assign data_req.w_valid     = s_axi_data_wvalid_i;
  assign s_axi_data_wready_o  = data_resp.w_ready;

  assign s_axi_data_bid_o     = data_resp.b.id;
  assign s_axi_data_bresp_o   = data_resp.b.resp;
  assign s_axi_data_buser_o   = data_resp.b.user;
  assign s_axi_data_bvalid_o  = data_resp.b_valid;
  assign data_req.b_ready     = s_axi_data_bready_i;

  assign data_req.ar.id       = s_axi_data_arid_i;
  assign data_req.ar.addr     = s_axi_data_araddr_i;
  assign data_req.ar.len      = s_axi_data_arlen_i;
  assign data_req.ar.size     = s_axi_data_arsize_i;
  assign data_req.ar.burst    = s_axi_data_arburst_i;
  assign data_req.ar.lock     = s_axi_data_arlock_i;
  assign data_req.ar.cache    = s_axi_data_arcache_i;
  assign data_req.ar.prot     = s_axi_data_arprot_i;
  assign data_req.ar.qos      = s_axi_data_arqos_i;
  assign data_req.ar.region   = s_axi_data_arregion_i;
  assign data_req.ar.user     = s_axi_data_aruser_i;
  assign data_req.ar_valid    = s_axi_data_arvalid_i;
  assign s_axi_data_arready_o = data_resp.ar_ready;

  assign s_axi_data_rid_o     = data_resp.r.id;
  assign s_axi_data_rdata_o   = data_resp.r.data;
  assign s_axi_data_rresp_o   = data_resp.r.resp;
  assign s_axi_data_rlast_o   = data_resp.r.last;
  assign s_axi_data_ruser_o   = data_resp.r.user;
  assign s_axi_data_rvalid_o  = data_resp.r_valid;
  assign data_req.r_ready     = s_axi_data_rready_i;

  // AXI4-Lite Mapping
  assign ctrl_req.aw.addr     = s_axi_ctrl_awaddr_i;
  assign ctrl_req.aw.prot     = s_axi_ctrl_awprot_i;
  assign ctrl_req.aw_valid    = s_axi_ctrl_awvalid_i;
  assign s_axi_ctrl_awready_o = ctrl_resp.aw_ready;

  assign ctrl_req.w.data      = s_axi_ctrl_wdata_i;
  assign ctrl_req.w.strb      = s_axi_ctrl_wstrb_i;
  assign ctrl_req.w_valid     = s_axi_ctrl_wvalid_i;
  assign s_axi_ctrl_wready_o  = ctrl_resp.w_ready;

  assign s_axi_ctrl_bresp_o   = ctrl_resp.b.resp;
  assign s_axi_ctrl_bvalid_o  = ctrl_resp.b_valid;
  assign ctrl_req.b_ready     = s_axi_ctrl_bready_i;

  assign ctrl_req.ar.addr     = s_axi_ctrl_araddr_i;
  assign ctrl_req.ar.prot     = s_axi_ctrl_arprot_i;
  assign ctrl_req.ar_valid    = s_axi_ctrl_arvalid_i;
  assign s_axi_ctrl_arready_o = ctrl_resp.ar_ready;

  assign s_axi_ctrl_rdata_o   = ctrl_resp.r.data;
  assign s_axi_ctrl_rresp_o   = ctrl_resp.r.resp;
  assign s_axi_ctrl_rvalid_o  = ctrl_resp.r_valid;
  assign ctrl_req.r_ready     = s_axi_ctrl_rready_i;


  logic                  data_mem_req;
  logic                  data_mem_gnt;
  logic [ADDR_WIDTH-1:0] data_mem_addr;
  logic [DATA_WIDTH-1:0] data_mem_wdata;
  logic [STRB_WIDTH-1:0] data_mem_strb;
  logic                  data_mem_we;
  logic [DATA_WIDTH-1:0] data_mem_rdata;
  logic                  data_mem_rvalid;

  axi_to_mem #(
    .axi_req_t(data_axi_req_t),
    .axi_resp_t(data_axi_resp_t),
    .AddrWidth(ADDR_WIDTH),
    .DataWidth(DATA_WIDTH),
    .IdWidth(ID_WIDTH),
    .NumBanks(1),
    .BufDepth(2),
    .OutFifoDepth(2)
  ) u_data_axi_to_mem(
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .busy_o(),

    .axi_req_i(data_req),
    .axi_resp_o(data_resp),

    .mem_req_o(data_mem_req),
    .mem_gnt_i(data_mem_gnt),
    .mem_addr_o(data_mem_addr),
    .mem_wdata_o(data_mem_wdata),
    .mem_strb_o(data_mem_strb),
    .mem_atop_o(),
    .mem_we_o(data_mem_we),
    .mem_rdata_i(data_mem_rdata),
    .mem_rvalid_i(data_mem_rvalid)
  );

  typedef struct packed {
    int unsigned idx;
    addr_t       start_addr;
    addr_t       end_addr;
  } apb_rule_t;

  apb_rule_t apb_addr_map;
  assign apb_addr_map = '{
    idx:        32'h0,
    start_addr: 32'h0,
    end_addr:   32'hFFFF_FFFF
  };

  `APB_TYPEDEF_ALL(apb, addr_t, data_t, strb_t)

  apb_req_t  ctrl_apb_req;
  apb_resp_t ctrl_apb_resp;

  axi_lite_to_apb #(
    .NoApbSlaves(1),
    .NoRules(1),
    .AddrWidth(ADDR_WIDTH),
    .DataWidth(DATA_WIDTH),
    .PipelineRequest(1'b0),
    .PipelineResponse(1'b0),
    .axi_lite_req_t(ctrl_axi_lite_req_t),
    .axi_lite_resp_t(ctrl_axi_lite_resp_t),
    .apb_req_t(apb_req_t),
    .apb_resp_t(apb_resp_t),
    .rule_t(apb_rule_t)
  ) u_axi_lite_to_apb (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .axi_lite_req_i(ctrl_req),
    .axi_lite_resp_o(ctrl_resp),

    .apb_req_o(ctrl_apb_req),
    .apb_resp_i(ctrl_apb_resp),

    .addr_map_i(apb_addr_map)
  );

  top #(
    .N_STREAMS(N_STREAMS),
    .M_MACROS(M_MACROS),
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .W_WORKERS(W_WORKERS),
    .B_BANKS(B_BANKS),
    .MACRO_DEPTH(MACRO_DEPTH),
    .BANK_DEPTH(BANK_DEPTH),
    .STREAM_OFFSET_WIDTH(STREAM_OFFSET_WIDTH)
  ) u_top (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .penable_i(ctrl_apb_req.penable),
    .pwrite_i(ctrl_apb_req.pwrite),
    .paddr_i(ctrl_apb_req.paddr),
    .psel_i(ctrl_apb_req.psel),
    .pwdata_i(ctrl_apb_req.pwdata),
    .prdata_o(ctrl_apb_resp.prdata),
    .pready_o(ctrl_apb_resp.pready),
    .pslverr_o(ctrl_apb_resp.pslverr),

    .data_req_i(data_mem_req),
    .data_gnt_o(data_mem_gnt),
    .data_addr_i(data_mem_addr),
    .data_wdata_i(data_mem_wdata),
    .data_be_i(data_mem_strb),
    .data_we_i(data_mem_we),
    .data_r_rdata_o(data_mem_rdata),
    .data_r_valid_o(data_mem_rvalid),

    .job_dispatched_o(job_dispatched_o)
  );

endmodule
