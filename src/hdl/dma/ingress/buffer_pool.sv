module buffer_pool #(
  parameter int M_MACROS      = 16,
  parameter int NB_READ_PORTS = 1,
  parameter int DATA_WIDTH    = 32,
  parameter int MACRO_DEPTH   = 256
)(
  input logic clk_i,
  input logic rst_ni,

  input logic [M_MACROS-1:0] macro_owner,

  // ###############
  // Ingress Channel
  input logic [M_MACROS-1:0]                 in_req,
  input logic [M_MACROS-1:0][31:0]           in_add,
  input logic [M_MACROS-1:0][DATA_WIDTH-1:0] in_wdata,
  input logic [M_MACROS-1:0][3:0]            in_be,
  output logic [M_MACROS-1:0]                in_gnt,

  // ##############
  // Egress Channel
  input logic [NB_READ_PORTS-1:0]                       out_req
  input logic [NB_READ_PORTS-1:0][31:0]                 out_add,
  input logic [NB_READ_PORTS-1:0][$clog(M_MACROS)-1:0]  out_macro_select,

  output logic [NB_READ_PORTS-1:0]                      out_gnt,
  output logic [NB_READ_PORTS-1:0]                      out_r_opc,
  output logic [NB_READ_PORTS-1:0][DATA_WIDTH-1:0]      out_r_rdata,
  output logic [NB_READ_PORTS-1:0]                      out_r_valid
)

  logic [M_MACROS-1:0]        mux_req;
  logic [M_MACROS-1:0][31:0]  mux_add;

  logic [M_MACROS-1:0][3:0]             macro_be; 
  logic [M_MACROS-1:0]                  macro_gnt;
  logic [M_MACROS-1:0]                  macro_r_opc,
  logic [M_MACROS-1:0][DATA_WIDTH-1:0]  macro_r_rdata,
  logic [M_MACROS-1:0]                  macro_r_valid

  logic [M_MACROS-1:0]        demux_gnt;

  logic [NB_READ_PORTS-1:0][$clog(M_MACROS)-1:0]  out_macro_select_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      out_macro_select_q <= '0;
    end else begin
      for (int p = 0; p < NB_READ_PORTS; p++) begin
        if (out_req[p] && out_gnt[p]) begin
          out_macro_select_q <= out_macro_select;
        end
      end
    end
  end

  always_comb begin
    for (int p = 0; p < NB_READ_PORTS; p++) begin
      out_gnt[p]      = macro_gnt[out_macro_select[p]];
      out_r_opc[p]    = macro_r_opc[out_macro_select_q[p]];
      out_r_rdata[p]  = macro_r_rdata[out_macro_select_q[p]];
      out_r_valid[p]  = macro_r_valid[out_macro_select_q[p]];
    end
  end

  generate
    always_comb begin
      mux_req[i]  = 1'b0;
      mux_add[i]  = '0;
      macro_be[i] = 4'b1111;

      if (macro_owner[i] == 1'b0) begin
        // Ingress - WRITE
        mux_req[i] = in_req[i];
        mux_add[i] = in_add[i];
        macro_be[i] = in_be[i];
      end else begin
        // Egress - READ
        for (int p = 0; p < NB_READ_PORTS; p++) begin
          if (out_macro_select[p] == i) begin
            mux_req[i] = out_req[p];
            mux_add[i] = out_add[p];
          end
        end
      end
    end

    assign demux_gnt[i] = (macro_owner[i] == 1'b0) ? macro_gnt[i] : 1'b0;
    assign in_gnt[i]    = demux_gnt[i]; 

    for (genvar i = 0; i < M_MACROS; i++) begin : gen_buffer_array
      sram_macro u_macro (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .req(mux_req[i]),
        .add(mux_add[i]),

        .gnt(macro_gnt[i])

        .wen(~macro_owner[i]),
        .be(macro_be[i]),
        
        .wdata(in_wdata[i]),

        .r_opc(macro_r_opc[i]),
        .r_rdata(macro_r_rdata[i]),
        .r_valid(macro_r_valid[i])    
      );
    end 
  endgenerate
endmodule