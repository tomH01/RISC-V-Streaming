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
  `define SYNOPSYS_MACRO_128   sadclssd4LOW1p128x32m16b1w1c0p1d0l0rm3sdrw01_wrapper
  `define SYNOPSYS_MACRO_256   sadclssd4LOW1p256x32m16b1w1c0p1d0l0rm3sdrw01_wrapper
  `define SYNOPSYS_MACRO_512   sadclssd4LOW1p512x32m16b2w1c0p1d0l0rm3sdrw01_wrapper
  `define SYNOPSYS_MACRO_1024  sadclssd4LOW1p1024x32m16b2w1c0p1d0l0rm3sdrw01_wrapper
  `define SYNOPSYS_MACRO_2048  sadclssd4LOW1p2048x32m16b2w1c0p1d0l0rm3sdrw01_wrapper
  `define SYNOPSYS_MACRO_4096  sadclssd4LOW1p4096x32m16b2w1c0p1d0l0rm3sdrw01_wrapper
  `define SYNOPSYS_MACRO_8192  sadclssd4LOW1p8192x32m16b2w1c0p1d0l0rm3sdrw01_wrapper
  `define SYNOPSYS_MACRO_16384 sadclssd4LOW1p16384x32m16b4w1c0p1d0l0rm3sdrw01_wrapper
  `define SYNOPSYS_MACRO_32768 sadclssd4LOW1p32768x32m16b8w1c0p1d0l0rm3sdrw01_wrapper

  `define INSTANTIATE_L2_SYNOPSYS_SRAM(MACRO_NAME) \
    MACRO_NAME bank_sram_pri0_i ( \
        .Q  (r_rdata_o[i]), \
        .ADR(internal_bank_addr), \
        .D  (wdata_i[i]), \
        .WEM(BE_BW_BANK[i]), \
        .WE (~wen_i[i]), \
        .ME (req_i[i]), \
        .CLK(clk_i), \
        .LS (1'b0), \
        .DS (1'b0), \
        .SD (1'b0) \
    )
`endif

module l2_sram_macro #(
  parameter     MACRO_TYPE = "SYNOPSYS",
  parameter int B_BANKS    = 4,
  parameter int BANK_DEPTH = 32768,

  localparam int BANK_PTR_WIDTH  = (B_BANKS > 1) ? $clog2(B_BANKS) : 1,
  localparam int BANK_ADDR_WIDTH = $clog2(BANK_DEPTH)
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
      assign internal_bank_addr = addr_i[i][BANK_ADDR_WIDTH+2-1:2];

      assign BE_BW_BANK[i] = {
        {8{be_i[i][3]}},
        {8{be_i[i][2]}},
        {8{be_i[i][1]}},
        {8{be_i[i][0]}}
      };

      `ifndef TARGET_FPGA
        if (MACRO_TYPE == "SYNOPSYS") begin : gen_asic_bank
          case (BANK_DEPTH)
            128:   `INSTANTIATE_L2_SYNOPSYS_SRAM(`SYNOPSYS_MACRO_128);
            256:   `INSTANTIATE_L2_SYNOPSYS_SRAM(`SYNOPSYS_MACRO_256);
            512:   `INSTANTIATE_L2_SYNOPSYS_SRAM(`SYNOPSYS_MACRO_512);
            1024:  `INSTANTIATE_L2_SYNOPSYS_SRAM(`SYNOPSYS_MACRO_1024);
            2048:  `INSTANTIATE_L2_SYNOPSYS_SRAM(`SYNOPSYS_MACRO_2048);
            4096:  `INSTANTIATE_L2_SYNOPSYS_SRAM(`SYNOPSYS_MACRO_4096);
            8192:  `INSTANTIATE_L2_SYNOPSYS_SRAM(`SYNOPSYS_MACRO_8192);
            16384: `INSTANTIATE_L2_SYNOPSYS_SRAM(`SYNOPSYS_MACRO_16384);
            32768: `INSTANTIATE_L2_SYNOPSYS_SRAM(`SYNOPSYS_MACRO_32768);
            default: ;
          endcase
        end else begin : gen_rtl_bank
          tc_sram #(
            .NumWords(BANK_DEPTH),
            .DataWidth(32),
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
      `else
        xpm_memory_spram #(
        .ADDR_WIDTH_A(BANK_ADDR_WIDTH),
        .AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(8),
        .CASCADE_HEIGHT(0),
        .READ_DATA_WIDTH_A(32),
        .READ_LATENCY_A(1),
        .MEMORY_SIZE(BANK_DEPTH*32),
        .MEMORY_PRIMITIVE("block"),
        .WRITE_DATA_WIDTH_A(32),
        .WRITE_MODE_A("read_first")
      ) u_xpm_ram (
          .clka(clk_i),
          .rsta(~rst_ni),
          .ena(req_i[i]),
          .wea(be_i[i] & {4{~wen_i[i]}}),
          .addra(internal_bank_addr),
          .dina(wdata_i[i]),
          .douta(r_rdata_o[i]),
          .sleep(1'b0),
          .sbiterra(),
          .dbiterra(),
          .injectsbiterra(1'b0),
          .injectdbiterra(1'b0),
          .regcea(1'b1)
        );
      `endif
    end
  endgenerate

endmodule
