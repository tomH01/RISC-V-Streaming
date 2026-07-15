module meta #(
  parameter int N_STREAMS     = 4,
  parameter int DATA_WIDTH    = 32,
  parameter int ADDR_WIDTH    = 32,
  parameter int W_WORKERS     = 2,
  parameter int B_BANKS       = 2,
  parameter int BANK_DEPTH    = 16384,

  localparam int STREAM_PTR_WIDTH = (N_STREAMS > 1) ? $clog2(N_STREAMS) : 1,
  localparam int DATA_WIDTH_BYTES = DATA_WIDTH / 8,
  localparam int SRAM_SIZE_B      = B_BANKS * BANK_DEPTH * DATA_WIDTH_BYTES,
  localparam int SRAM_PTR_WIDTH   = $clog2(SRAM_SIZE_B)
)(
  input logic clk_i,
  input logic rst_ni,

  // Control IF
  // TODO: BASE ADDR SRAM

  // Subordinate IF
  input  logic                        meta_req_i,
  input  logic [ADDR_WIDTH-1:0]       meta_addr_i,
  output logic                        meta_gnt_o,
  input  logic                        meta_wen_i ,
  input  logic [DATA_WIDTH-1:0]       meta_wdata_i,
  input  logic [DATA_WIDTH_BYTES-1:0] meta_be_i,

  output logic [DATA_WIDTH-1:0] meta_r_rdata_o,
  output logic                  meta_r_valid_o,

  // L2 Allocator IF
  output logic                  fifo_ready_o,
  input  logic                  fifo_valid_i,
  input  logic [DATA_WIDTH-1:0] fifo_data_i,
  output logic [DATA_WIDTH-1:0] cpu_done_ptr_o,

  // Worker IF
  input logic [W_WORKERS-1:0]        ptr_valid_i,
  input logic [STREAM_PTR_WIDTH-1:0] ptr_stream_id_i [W_WORKERS],
  input logic [ADDR_WIDTH-1:0]       ptr_i           [W_WORKERS]
);

  logic [DATA_WIDTH-1:0] cpu_done_ptr_q;
  logic [DATA_WIDTH-1:0] stream_ptrs_q [N_STREAMS];

  logic                  fifo_full;
  logic                  fifo_empty;
  logic                  fifo_push;  
  logic                  fifo_pop;
  logic [DATA_WIDTH-1:0] fifo_dout;

  logic [7:0] addr_offset;
  logic       is_stream_reg;
  logic       is_cpu_done_reg;
  logic       is_fifo_reg;
  int         decoded_stream_id;

  assign addr_offset       = meta_addr_i[7:0];
  assign is_stream_reg     = (addr_offset < 8'h80);
  assign is_cpu_done_reg   = (addr_offset == 8'h80);
  assign is_fifo_reg       = (addr_offset == 8'h84);
  assign decoded_stream_id = addr_offset[7:2];

  assign meta_gnt_o = (meta_req_i && is_fifo_reg && meta_wen_i) ? ~fifo_empty : 1'b1;

  assign fifo_pop     = meta_req_i && meta_gnt_o && is_fifo_reg && meta_wen_i && !fifo_empty;
  assign fifo_push    = fifo_valid_i && fifo_ready_o;
  
  assign fifo_ready_o   = ~fifo_full;
  assign cpu_done_ptr_o = cpu_done_ptr_q;

  // CPU IF
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cpu_done_ptr_q   <= '0;
      meta_r_valid_o <= 1'b0;
      meta_r_rdata_o <= '0;
    end else begin
      meta_r_valid_o <= 1'b0;

      // CPU Write
      if (meta_req_i && meta_gnt_o && !meta_wen_i) begin
        if (is_cpu_done_reg) begin
          cpu_done_ptr_q <= meta_wdata_i;
        end
      end

      // CPU Read
      if (meta_req_i && meta_gnt_o && meta_wen_i) begin
        meta_r_valid_o <= 1'b1;

        if (is_stream_reg && (decoded_stream_id < N_STREAMS)) begin
          meta_r_rdata_o <= stream_ptrs_q[decoded_stream_id];
        end else if (is_cpu_done_reg) begin
          meta_r_rdata_o <= cpu_done_ptr_q;
        end else if (is_fifo_reg) begin
          meta_r_rdata_o <= fifo_dout;          
        end else begin
          meta_r_rdata_o <= '0;
        end
      end
    end
  end

  // Worker IF
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      stream_ptrs_q       <= '{default: '0};
    end else begin
      for (int i = 0; i < N_STREAMS; i++) begin
        logic [DATA_WIDTH-1:0]     min_ptr;
        logic                      update_en;
        
        min_ptr   = '0;
        update_en = 1'b0;

        // Find min pointer per stream
        for (int w = 0; w < W_WORKERS; w++) begin
          if (ptr_valid_i[w] && (ptr_stream_id_i[w] == i)) begin
            if (!update_en) begin
              min_ptr   = ptr_i[w];
              update_en = 1'b1;
            end else begin
              logic [SRAM_PTR_WIDTH-1:0] diff;
              diff = ptr_i[w][SRAM_PTR_WIDTH-1:0] - min_ptr[SRAM_PTR_WIDTH-1:0];

              if (diff[SRAM_PTR_WIDTH-1] == 1'b1) begin
                min_ptr = ptr_i[w];
              end 
            end
          end
        end

        if (update_en) begin
          stream_ptrs_q[i] <= min_ptr;
        end
      end
    end
  end

  fwft_fifo #(
    .DATA_WIDTH(DATA_WIDTH),
    .DEPTH(16)
  ) u_fifo (
    .clk_i(clk_i),
    .rst_ni(rst_ni),

    .push_i(fifo_push),
    .data_i(fifo_data_i),
    .full_o(fifo_full),

    .pop_i(fifo_pop),
    .data_o(fifo_dout),
    .empty_o(fifo_empty)
  );

endmodule
