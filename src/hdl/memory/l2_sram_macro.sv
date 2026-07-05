// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

`define MACRO_SIZE_PRI0 32768

`define SYNOPSYS_MACRO_PRI0 sadclssd4LOW1p32768x32m16b8w1c0p1d0l0rm3sdrw01_wrapper

// Private bank 0

module l2_sram_macro #() (
    input logic clk_i,
    input logic rst_ni,
    // ################################
    // Bus Interface - REQUEST CHANNEL
    input logic          req,
    input logic [31:0]   add,
    input logic          wen,
    input logic [31:0]   wdata,
    input logic [3:0]    be,
    output logic         gnt,
    // ################################
    // Bus Interface - RESPONSE CHANNEL
    output logic [31:0]  r_rdata,
    output logic         r_valid
);

  localparam int unsigned PRI0_MEM_ADDR_WIDTH = $clog2(`MACRO_SIZE_PRI0);

  // TCDM handshaking for constant 1 cycle latency
  assign gnt   = req;

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      r_valid <= 1'b0;
    end else begin
      r_valid <= req;
    end
  end

  logic [31:0] pri0_address;
  assign pri0_address = add;

  logic [31:0] BE_BW_BANK;
  assign BE_BW_BANK = {
      {8{be[3]}},
      {8{be[2]}},
      {8{be[1]}},
      {8{be[0]}}
  };

  `SYNOPSYS_MACRO_PRI0 bank_sram_pri0_i (
      .Q  (r_rdata),
      .ADR(pri0_address[PRI0_MEM_ADDR_WIDTH+2-1:2]),
      .D  (wdata),
      .WEM(BE_BW_BANK),
      .WE (~wen),
      .ME (req),
      .CLK(clk_i),
      .LS(1'b0),
      .DS(1'b0),
      .SD(1'b0)
  );

endmodule
