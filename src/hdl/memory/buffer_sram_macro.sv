// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`ifndef TARGET_FPGA
  `define SYNOPSYS_MACRO_PRI0 sadclssd4LOW1p256x32m16b1w1c0p1d0l0rm3sdrw01_wrapper
`endif

// Private bank 0

module buffer_sram_macro #(
  parameter     MACRO_TYPE = "SYNOPSYS",
  parameter int MACRO_DEPTH = 256,

  localparam int MACRO_ADDR_WIDTH = $clog2(MACRO_DEPTH)
)(
    input logic clk_i,
    input logic rst_ni,
    // ################################
    // Bus Interface - REQUEST CHANNEL
    input logic          req_i,
    input logic [31:0]   addr_i,
    input logic          wen_i,
    input logic [31:0]   wdata_i,
    input logic [3:0]    be_i,
    output logic         gnt_o,
    // ################################
    // Bus Interface - RESPONSE CHANNEL
    output logic [31:0]  r_rdata_o,
    output logic         r_valid_o
);

  // TCDM handshaking for constant 1 cycle latency
  assign gnt_o   = req_i;

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      r_valid_o <= 1'b0;
    end else begin
      r_valid_o <= req_i;
    end
  end

  logic [31:0] pri0_address;
  assign pri0_address = addr_i;

  logic [31:0] BE_BW_BANK;
  assign BE_BW_BANK = {
      {8{be_i[3]}},
      {8{be_i[2]}},
      {8{be_i[1]}},
      {8{be_i[0]}}
  };

  `ifndef TARGET_FPGA  
    if (MACRO_TYPE == "SYNOPSYS") begin : gen_asic_bank
    `SYNOPSYS_MACRO_PRI0 bank_sram_pri0_i (
        .Q  (r_rdata_o),
        .ADR(pri0_address[MACRO_ADDR_WIDTH+2-1:2]),
        .D  (wdata_i),
        .WEM(BE_BW_BANK),
        .WE (~wen_i),
        .ME (req_i),
        .CLK(clk_i),
        .LS(1'b0),
        .DS(1'b0),
        .SD(1'b0)
    );
    end else begin : gen_rtl_bank
      tc_sram #(
        .NumWords(MACRO_DEPTH),
        .DataWidth(32),
        .NumPorts(1)
      ) u_bank (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .req_i(req_i),
        .we_i(~wen_i),
        .addr_i(pri0_address[MACRO_ADDR_WIDTH+2-1:2]),
        .wdata_i(wdata_i),
        .be_i(be_i),
        .rdata_o(r_rdata_o)
      );
    end
  `else
    xpm_memory_spram #(
      .ADDR_WIDTH_A(MACRO_ADDR_WIDTH),
      .AUTO_SLEEP_TIME(0),
      .BYTE_WRITE_WIDTH_A(8),
      .CASCADE_HEIGHT(0),
      .READ_DATA_WIDTH_A(32),
      .READ_LATENCY_A(1),
      .MEMORY_SIZE(MACRO_DEPTH*32),
      .MEMORY_PRIMITIVE("block"),
      .WRITE_DATA_WIDTH_A(32),
      .WRITE_MODE_A("read_first")
    ) u_xpm_ram (
        .clka(clk_i),
        .rsta(~rst_ni),
        .ena(req_i),
        .wea(be_i & {4{~wen_i}}),
        .addra(pri0_address[MACRO_ADDR_WIDTH+2-1:2]),
        .dina(wdata_i),
        .douta(r_rdata_o),
        .sbiterra(),
        .dbiterra(),
        .sleep(1'b0),
        .injectsbiterra(1'b0),
        .injectdbiterra(1'b0),
        .regcea(1'b1)
    );
  `endif

endmodule
