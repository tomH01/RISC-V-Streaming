`timescale 1ns / 1ps

module top_wrapper #(
    parameter N_STREAMS           = 4,
    parameter M_MACROS            = 32,
    parameter DATA_WIDTH          = 32,
    parameter ADDR_WIDTH          = 32,
    parameter W_WORKERS           = 4,
    parameter B_BANKS             = 4,
    parameter MACRO_DEPTH         = 256,
    parameter BANK_DEPTH          = 8192,
    parameter STREAM_OFFSET_WIDTH = 10,
    parameter ID_WIDTH            = 16,
    parameter USER_WIDTH          = 1
)(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 clk_i CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:s_axi_lite, ASSOCIATED_RESET rst_ni" *)
    input  wire clk_i,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 rst_ni RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire rst_ni,

    // ############################
    // AXI4 Subordinate IF (DATA)
    // ############################

    // Write Address Channel (AW)
    input  wire [ID_WIDTH-1:0]       s_axi_awid,
    input  wire [ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [7:0]                s_axi_awlen,
    input  wire [2:0]                s_axi_awsize,
    input  wire [1:0]                s_axi_awburst,
    input  wire                      s_axi_awlock,
    input  wire [3:0]                s_axi_awcache,
    input  wire [2:0]                s_axi_awprot,
    input  wire [3:0]                s_axi_awqos,
    input  wire [3:0]                s_axi_awregion,
    input  wire [USER_WIDTH-1:0]     s_axi_awuser,
    input  wire                      s_axi_awvalid,
    output wire                      s_axi_awready,

    // Write Data Channel (W)
    input  wire [DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                      s_axi_wlast,
    input  wire [USER_WIDTH-1:0]     s_axi_wuser,
    input  wire                      s_axi_wvalid,
    output wire                      s_axi_wready,

    // Write Response Channel (B)
    output wire [ID_WIDTH-1:0]       s_axi_bid,
    output wire [1:0]                s_axi_bresp,
    output wire [USER_WIDTH-1:0]     s_axi_buser,
    output wire                      s_axi_bvalid,
    input  wire                      s_axi_bready,

    // Read Address Channel (AR)
    input  wire [ID_WIDTH-1:0]       s_axi_arid,
    input  wire [ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [7:0]                s_axi_arlen,
    input  wire [2:0]                s_axi_arsize,
    input  wire [1:0]                s_axi_arburst,
    input  wire                      s_axi_arlock,
    input  wire [3:0]                s_axi_arcache,
    input  wire [2:0]                s_axi_arprot,
    input  wire [3:0]                s_axi_arqos,
    input  wire [3:0]                s_axi_arregion,
    input  wire [USER_WIDTH-1:0]     s_axi_aruser,
    input  wire                      s_axi_arvalid,
    output wire                      s_axi_arready,

    // Read Data Channel (R)
    output wire [ID_WIDTH-1:0]       s_axi_rid,
    output wire [DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                s_axi_rresp,
    output wire                      s_axi_rlast,
    output wire [USER_WIDTH-1:0]     s_axi_ruser,
    output wire                      s_axi_rvalid,
    input  wire                      s_axi_rready,


    // ############################
    // AXI4-Lite Subordinate IF (CTRL)
    // ############################

    // Write Address Channel (AW)
    input  wire [ADDR_WIDTH-1:0]     s_axi_lite_awaddr,
    input  wire [2:0]                s_axi_lite_awprot,
    input  wire                      s_axi_lite_awvalid,
    output wire                      s_axi_lite_awready,

    // Write Data Channel (W)
    input  wire [DATA_WIDTH-1:0]     s_axi_lite_wdata,
    input  wire [(DATA_WIDTH/8)-1:0] s_axi_lite_wstrb,
    input  wire                      s_axi_lite_wvalid,
    output wire                      s_axi_lite_wready,

    // Write Response Channel (B)
    output wire [1:0]                s_axi_lite_bresp,
    output wire                      s_axi_lite_bvalid,
    input  wire                      s_axi_lite_bready,

    // Read Address Channel (AR)
    input  wire [ADDR_WIDTH-1:0]     s_axi_lite_araddr,
    input  wire [2:0]                s_axi_lite_arprot,
    input  wire                      s_axi_lite_arvalid,
    output wire                      s_axi_lite_arready,

    // Read Data Channel (R)
    output wire [DATA_WIDTH-1:0]     s_axi_lite_rdata,
    output wire [1:0]                s_axi_lite_rresp,
    output wire                      s_axi_lite_rvalid,
    input  wire                      s_axi_lite_rready,


    // Job dispatched signal
    output wire                    job_dispatched_o
);

    top_axi_wrapper #(
        .N_STREAMS(N_STREAMS),
        .M_MACROS(M_MACROS),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .W_WORKERS(W_WORKERS),
        .B_BANKS(B_BANKS),
        .MACRO_DEPTH(MACRO_DEPTH),
        .BANK_DEPTH(BANK_DEPTH),
        .STREAM_OFFSET_WIDTH(STREAM_OFFSET_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .USER_WIDTH(USER_WIDTH)
    ) u_top_axi_wrapper (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .s_axi_data_awid_i(s_axi_awid),
        .s_axi_data_awaddr_i(s_axi_awaddr),
        .s_axi_data_awlen_i(s_axi_awlen),
        .s_axi_data_awsize_i(s_axi_awsize),
        .s_axi_data_awburst_i(s_axi_awburst),
        .s_axi_data_awlock_i(s_axi_awlock),
        .s_axi_data_awcache_i(s_axi_awcache),
        .s_axi_data_awprot_i(s_axi_awprot),
        .s_axi_data_awqos_i(s_axi_awqos),
        .s_axi_data_awregion_i(s_axi_awregion),
        .s_axi_data_awuser_i(s_axi_awuser),
        .s_axi_data_awvalid_i(s_axi_awvalid),
        .s_axi_data_awready_o(s_axi_awready),

        .s_axi_data_wdata_i(s_axi_wdata),
        .s_axi_data_wstrb_i(s_axi_wstrb),
        .s_axi_data_wlast_i(s_axi_wlast),
        .s_axi_data_wuser_i(s_axi_wuser),
        .s_axi_data_wvalid_i(s_axi_wvalid),
        .s_axi_data_wready_o(s_axi_wready),

        .s_axi_data_bid_o(s_axi_bid),
        .s_axi_data_bresp_o(s_axi_bresp),
        .s_axi_data_buser_o(s_axi_buser),
        .s_axi_data_bvalid_o(s_axi_bvalid),
        .s_axi_data_bready_i(s_axi_bready),

        .s_axi_data_arid_i(s_axi_arid),
        .s_axi_data_araddr_i(s_axi_araddr),
        .s_axi_data_arlen_i(s_axi_arlen),
        .s_axi_data_arsize_i(s_axi_arsize),
        .s_axi_data_arburst_i(s_axi_arburst),
        .s_axi_data_arlock_i(s_axi_arlock),
        .s_axi_data_arcache_i(s_axi_arcache),
        .s_axi_data_arprot_i(s_axi_arprot),
        .s_axi_data_arqos_i(s_axi_arqos),
        .s_axi_data_arregion_i(s_axi_arregion),
        .s_axi_data_aruser_i(s_axi_aruser),
        .s_axi_data_arvalid_i(s_axi_arvalid),
        .s_axi_data_arready_o(s_axi_arready),

        .s_axi_data_rid_o(s_axi_rid),
        .s_axi_data_rdata_o(s_axi_rdata),
        .s_axi_data_rresp_o(s_axi_rresp),
        .s_axi_data_rlast_o(s_axi_rlast),
        .s_axi_data_ruser_o(s_axi_ruser),
        .s_axi_data_rvalid_o(s_axi_rvalid),
        .s_axi_data_rready_i(s_axi_rready),


        .s_axi_ctrl_awaddr_i(s_axi_lite_awaddr),
        .s_axi_ctrl_awprot_i(s_axi_lite_awprot),
        .s_axi_ctrl_awvalid_i(s_axi_lite_awvalid),
        .s_axi_ctrl_awready_o(s_axi_lite_awready),

        .s_axi_ctrl_wdata_i(s_axi_lite_wdata),
        .s_axi_ctrl_wstrb_i(s_axi_lite_wstrb),
        .s_axi_ctrl_wvalid_i(s_axi_lite_wvalid),
        .s_axi_ctrl_wready_o(s_axi_lite_wready),

        .s_axi_ctrl_bresp_o(s_axi_lite_bresp),
        .s_axi_ctrl_bvalid_o(s_axi_lite_bvalid),
        .s_axi_ctrl_bready_i(s_axi_lite_bready),

        .s_axi_ctrl_araddr_i(s_axi_lite_araddr),
        .s_axi_ctrl_arprot_i(s_axi_lite_arprot),
        .s_axi_ctrl_arvalid_i(s_axi_lite_arvalid),
        .s_axi_ctrl_arready_o(s_axi_lite_arready),

        .s_axi_ctrl_rdata_o(s_axi_lite_rdata),
        .s_axi_ctrl_rresp_o(s_axi_lite_rresp),
        .s_axi_ctrl_rvalid_o(s_axi_lite_rvalid),    
        .s_axi_ctrl_rready_i(s_axi_lite_rready),

        .job_dispatched_o(job_dispatched_o)
    );

endmodule
