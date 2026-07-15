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


module l2_sram_macro #(
  parameter     MACRO_TYPE = "SYNOPSYS",
  parameter int B_BANKS    = 4,

  localparam int BANK_PTR_WIDTH  = (B_BANKS > 1) ? $clog2(B_BANKS) : 1,
  localparam int BANK_ADDR_WIDTH = $clog2(`MACRO_SIZE_PRI0)
)(
    input logic clk_i,
    input logic rst_ni,

    // Bus Interface - REQUEST CHANNEL
    input  logic [B_BANKS-1:0] req_i,
    input  logic [31:0]        addr_i  [B_BANKS],
    input  logic [B_BANKS-1:0] wen_i,
    input  logic [31:0]        wdata_i [B_BANKS],
    input  logic [3:0]         be_i    [B_BANKS],
    output logic [B_BANKS-1:0] gnt_o,

    // Bus Interface - RESPONSE CHANNEL
    output logic [31:0]        r_rdata_o [B_BANKS],
    output logic [B_BANKS-1:0] r_valid_o
);

  logic [31:0] BE_BW_BANK [B_BANKS];

  generate
    for (genvar i = 0; i < B_BANKS; i++) begin : gen_parallel_banks
      // TCDM handshaking for constant 1 cycle latency
      assign gnt_o[i] = req_i[i];

      always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin 
          r_valid_o[i] <= 1'b0;
        end else begin
          r_valid_o[i] <= req_i[i] && wen_i[i];
        end
      end

      logic [BANK_ADDR_WIDTH-1:0] internal_bank_addr;

      if (B_BANKS > 1) begin : gen_multi_addr_slice
        assign internal_bank_addr = addr_i[i][BANK_PTR_WIDTH+BANK_ADDR_WIDTH+2-1:2+BANK_PTR_WIDTH];
      end else begin : gen_single_addr_slice
        assign internal_bank_addr = addr_i[i][BANK_ADDR_WIDTH+2-1:2];
      end

      assign BE_BW_BANK[i] = {
        {8{be_i[i][3]}},
        {8{be_i[i][2]}},
        {8{be_i[i][1]}},
        {8{be_i[i][0]}}
      };

      if (MACRO_TYPE == "SYNOPSYS") begin : gen_asic_bank
        `SYNOPSYS_MACRO_PRI0 bank_sram_pri0_i (
            .Q  (r_rdata_o[i]),
            .ADR(internal_bank_addr),
            .D  (wdata_i[i]),
            .WEM(BE_BW_BANK[i]),
            .WE (~wen_i[i]),
            .ME (req_i[i]),
            .CLK(clk_i),
            .LS(1'b0),
            .DS(1'b0),
            .SD(1'b0)
        );
      end else begin : gen_rtl_bank
        tc_sram #(
          .NumWords(`MACRO_SIZE_PRI0),
          .WordWidth(32),
          .NumPorts(1)
        ) u_bank (
          .clk_i(clk_i),
          .rst_ni(rst_ni),
          .req_i(req_i[i]),
          .we_i(~wen_i[i]),
          .addr_i(internal_bank_addr),
          .wdata_i(wdata_i[i]),
          .be_i(be_i[i]),
          .rdata_o(r_rdata_o[i])
        );
      end

    end
  endgenerate

endmodule
