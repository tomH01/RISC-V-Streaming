module buffer_pool #(
  parameter int M_MACROS       = 16,
  parameter int NUM_READ_PORTS = 1,
  parameter int DATA_WIDTH     = 32,
  parameter int ADDR_WIDTH     = 32,
  parameter int MACRO_DEPTH    = 256,

  localparam int MACRO_PTR_WIDTH = $clog2(M_MACROS)
)(
  input logic clk_i,
  input logic rst_ni,


  // Ingress IF
  input logic  [M_MACROS-1:0]   ingr_done_i,
  input logic  [M_MACROS-1:0]   ingr_req_i,
  input logic  [ADDR_WIDTH-1:0] ingr_addr_i  [M_MACROS],
  input logic  [DATA_WIDTH-1:0] ingr_wdata_i [M_MACROS],
  input logic  [3:0]            ingr_be_i    [M_MACROS],
  output logic [M_MACROS-1:0]   ingr_gnt_o,

  // Egress IF
  input logic  [M_MACROS-1:0]        egr_release_i,
  input logic  [NUM_READ_PORTS-1:0]  egr_req_i,
  input logic  [ADDR_WIDTH-1:0]      egr_addr_i         [NUM_READ_PORTS],
  input logic  [MACRO_PTR_WIDTH-1:0] egr_macro_select_i [NUM_READ_PORTS],
  output logic [NUM_READ_PORTS-1:0]  egr_gnt_o,
  output logic [DATA_WIDTH-1:0]      egr_r_rdata_o [NUM_READ_PORTS],
  output logic [NUM_READ_PORTS-1:0]  egr_r_valid_o
);
  logic [M_MACROS-1:0]   mux_req;
  logic [ADDR_WIDTH-1:0] mux_addr [M_MACROS];

  logic [3:0]            macro_be      [M_MACROS]; 
  logic [M_MACROS-1:0]   macro_gnt;
  logic [DATA_WIDTH-1:0] macro_r_rdata [M_MACROS];
  logic [M_MACROS-1:0]   macro_r_valid;

  logic [M_MACROS-1:0]   demux_gnt;

  logic [M_MACROS-1:0]        macro_owner_q;
  logic [MACRO_PTR_WIDTH-1:0] egr_macro_select_q [NUM_READ_PORTS];
  logic [NUM_READ_PORTS-1:0]  egr_req_q;

  logic [NUM_READ_PORTS-1:0]  macro_win_mask [M_MACROS];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      macro_owner_q      <= '0;
      egr_macro_select_q <= '{default: '0};
      egr_req_q          <= '0;
    end else begin
      macro_owner_q <= (macro_owner_q | ingr_done_i) & ~egr_release_i;

      for (int p = 0; p < NUM_READ_PORTS; p++) begin
        if (egr_req_i[p] && egr_gnt_o[p]) begin
          egr_macro_select_q[p] <= egr_macro_select_i[p];
        end

        egr_req_q[p] <= egr_req_i[p] && egr_gnt_o[p];
      end
    end
  end

  always_comb begin   
    for (int p = 0; p < NUM_READ_PORTS; p++) begin
      egr_gnt_o[p]     = macro_gnt[egr_macro_select_i[p]] && 
                         (macro_owner_q[egr_macro_select_i[p]] == 1'b1) && 
                         macro_win_mask[egr_macro_select_i[p]][p];
      egr_r_rdata_o[p] = egr_req_q[p] ? macro_r_rdata[egr_macro_select_q[p]] : '0;
      egr_r_valid_o[p] = macro_r_valid[egr_macro_select_q[p]] && egr_req_q[p];
    end
  end

  generate
    for (genvar i = 0; i < M_MACROS; i++) begin : gen_buffer_array
      always_comb begin
        mux_req[i]        = 1'b0;
        mux_addr[i]       = '0;
        macro_be[i]       = 4'b1111;
        macro_win_mask[i] = '0;

        if (macro_owner_q[i] == 1'b0) begin
          // Ingress - WRITE
          mux_req[i]  = ingr_req_i[i];
          mux_addr[i] = ingr_addr_i[i];
          macro_be[i] = ingr_be_i[i];
          
        end else begin
          // Egress - READ
          for (int p = 0; p < NUM_READ_PORTS; p++) begin
            if (egr_macro_select_i[p] == i && egr_req_i[p]) begin
              mux_req[i]  = 1'b1;
              mux_addr[i] = egr_addr_i[p];
              macro_win_mask[i][p] = 1'b1;
              break;
            end
          end
        end
      end

      assign demux_gnt[i]  = (macro_owner_q[i] == 1'b0) ? macro_gnt[i] : 1'b0;
      assign ingr_gnt_o[i] = demux_gnt[i]; 

      buffer_sram_macro u_macro (
        .clk_i(clk_i),
        .rst_ni(rst_ni),

        .req(mux_req[i]),
        .add(mux_addr[i]),

        .gnt(macro_gnt[i]),

        .wen(macro_owner_q[i]),
        .be(macro_be[i]),
        
        .wdata(ingr_wdata_i[i]),

        .r_rdata(macro_r_rdata[i]),
        .r_valid(macro_r_valid[i])    
      );
    end 
  endgenerate
endmodule
