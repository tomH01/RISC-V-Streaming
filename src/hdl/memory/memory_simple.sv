// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`define L2_BANK_SIZE 512
`define MACRO_SIZE_PRI0 256
`define NB_L2_PRI0_MACROS 2

`define SYNOPSYS_MACRO_PRI0 sadclssd4LOW1p256x32m16b1w1c0p1d0l0rm3sdrw01_wrapper

// Private bank 0
`define SOC_MEM_MAP_PRIVATE_BANK0_START_ADDR 32'h1C00_0000
`define SOC_MEM_MAP_PRIVATE_BANK0_END_ADDR   32'h1C01_0000

module memory_simple #() (
    input logic clk_i,
    input logic rst_ni,
    // ################################
    // Bus Interface - REQUEST CHANNEL
    input logic          req,
    input logic [31:0]   add,
    input logic          wen,
    input logic [31:0]   wdata,
    input logic [3:0]    be,
    output logic          gnt,
    // ################################
    // Bus Interface - RESPONSE CHANNEL
    output logic         r_opc,
    output logic [31:0]  r_rdata,
    output logic         r_valid
);
  localparam int unsigned MEM_ADDR_WIDTH = $clog2(`L2_BANK_SIZE);
  localparam int unsigned BANK_SIZE_PRI0 = `NB_L2_PRI0_MACROS * `MACRO_SIZE_PRI0;

  generate
    if (BANK_SIZE_PRI0 > `L2_BANK_SIZE) begin
      $error("PRI0 total bank sizes larger than address space");
    end
  endgenerate

  //Derived parameters
  localparam int unsigned PRI0_MEM_ADDR_WIDTH = $clog2(BANK_SIZE_PRI0);

  // PRIVATE BANK0
  //Perform TCDM handshaking for constant 1 cycle latency
  assign gnt   = req;
  assign r_opc = 1'b0;
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      r_valid <= 1'b0;
    end else begin
      r_valid <= req;
    end
  end
  //Remove Address offset
  logic [31:0] pri0_address;
  assign pri0_address = add - `SOC_MEM_MAP_PRIVATE_BANK0_START_ADDR;

  logic [31:0] q[`NB_L2_PRI0_MACROS];
  logic [31:0] BE_BW_BANK;
  assign BE_BW_BANK = {
      {8{be[3]}},
      {8{be[2]}},
      {8{be[1]}},
      {8{be[0]}}
  };
  logic [$clog2(`NB_L2_PRI0_MACROS)-1:0] mem_sel;
  logic [$clog2(`NB_L2_PRI0_MACROS)-1:0] mem_sel_delayed;
  assign mem_sel = pri0_address[(PRI0_MEM_ADDR_WIDTH+2-1):(PRI0_MEM_ADDR_WIDTH+2-1)-$clog2(`NB_L2_PRI0_MACROS)+1];
  assign r_rdata = q[mem_sel_delayed];
  always_ff @(posedge clk_i or negedge rst_ni) begin
      if (~rst_ni) begin
      mem_sel_delayed <= '0;
      end else begin
      mem_sel_delayed <= mem_sel;
      end
  end
  for (genvar ii = 0; ii < `NB_L2_PRI0_MACROS; ++ii) begin : gen_pri0_banks
      `SYNOPSYS_MACRO_PRI0 bank_sram_pri0_i (
          .Q  (q[ii]),
          .ADR(pri0_address[(PRI0_MEM_ADDR_WIDTH+2-1)-$clog2(`NB_L2_PRI0_MACROS):2]),
          .D  (wdata),
          .WEM(BE_BW_BANK),
          .WE (~wen),
          .ME (req && mem_sel == ii),
          .CLK(clk_i),
          .LS('0),
          .DS('0),
          .SD('0)
      );
  end

endmodule
