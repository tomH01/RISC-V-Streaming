module performance_monitor #(
  parameter int N_STREAMS = 4,
  parameter int W_WORKERS = 3,
  parameter int DATA_WIDTH = 32,
  parameter int ADDR_WIDTH = 32
)(
  input logic clk_i,
  input logic rst_ni,

  // APB Subordinate IF
  input logic                   penable_i,
  input logic                   pwrite_i,
  input logic  [ADDR_WIDTH-1:0] paddr_i,
  input logic                   psel_i,
  input logic  [DATA_WIDTH-1:0] pwdata_i,
  output logic [DATA_WIDTH-1:0] prdata_o,
  output logic                  pready_o,
  output logic                  pslverr_o,

  // DMA IF
  input  logic                 dma_enable_i,

  input  logic [N_STREAMS-1:0] ingr_stm_in_valid_i,
  input  logic [N_STREAMS-1:0] ingr_stm_in_ready_i,

  input  logic                 egr_job_req_valid_i,
  input  logic                 egr_job_req_ready_i,
  input  logic                 egr_meta_disp_valid_i,
  input  logic                 egr_meta_disp_ready_i,
  input  logic [W_WORKERS-1:0] egr_wkr_bp_req_i,
  input  logic [W_WORKERS-1:0] egr_wkr_bp_gnt_i,
  input  logic [W_WORKERS-1:0] egr_wkr_bus_valid_i,
  input  logic [W_WORKERS-1:0] egr_wkr_bus_ready_i,

  // CPU IF
  input  logic                 cpu_l2_valid_i,
  input  logic                 cpu_l2_ready_i,
  input  logic                 cpu_meta_req_i,
  input  logic                 cpu_meta_gnt_i
);

  logic                  dma_enable_q;
  logic [DATA_WIDTH-1:0] setup_cnt_q;
  logic [DATA_WIDTH-1:0] run_cnt_q;

  logic [DATA_WIDTH-1:0] ingr_stm_in_hs_cnt_q [N_STREAMS], 
                         ingr_stm_in_bp_cnt_q [N_STREAMS];
  logic [DATA_WIDTH-1:0] egr_job_req_hs_cnt_q, 
                         egr_job_req_bp_cnt_q;
  logic [DATA_WIDTH-1:0] egr_meta_disp_hs_cnt_q, 
                         egr_meta_disp_bp_cnt_q;
  logic [DATA_WIDTH-1:0] egr_wkr_bp_hs_cnt_q     [W_WORKERS],
                         egr_wkr_bp_bp_cnt_q     [W_WORKERS];
  logic [DATA_WIDTH-1:0] egr_wkr_bus_hs_cnt_q    [W_WORKERS],
                         egr_wkr_bus_bp_cnt_q    [W_WORKERS];

  logic [DATA_WIDTH-1:0] cpu_l2_hs_cnt_q,   cpu_l2_bp_cnt_q;
  logic [DATA_WIDTH-1:0] cpu_meta_hs_cnt_q, cpu_meta_bp_cnt_q;

  // Global Counters
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      dma_enable_q <= 1'b0;
      setup_cnt_q  <= '0;
      run_cnt_q    <= '0;
    end else begin
      if (!dma_enable_i && !dma_enable_q) begin
        setup_cnt_q <= setup_cnt_q + 1;
      end 
      if (dma_enable_i) begin
        dma_enable_q <= 1'b1;
        run_cnt_q    <= run_cnt_q + 1;
      end      
    end
  end

  // Ingress Counters
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
        ingr_stm_in_hs_cnt_q <= '{default: '0};
        ingr_stm_in_bp_cnt_q <= '{default: '0};
    end else if (dma_enable_i) begin
      for (int i = 0; i < N_STREAMS; i++) begin
        if (ingr_stm_in_valid_i[i] && ingr_stm_in_ready_i[i]) begin
          ingr_stm_in_hs_cnt_q[i] <= ingr_stm_in_hs_cnt_q[i] + 1;
        end else if (ingr_stm_in_valid_i[i] && !ingr_stm_in_ready_i[i]) begin
          ingr_stm_in_bp_cnt_q[i] <= ingr_stm_in_bp_cnt_q[i] + 1;
        end
      end
    end
  end

  // Egress Counters
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      egr_job_req_hs_cnt_q   <= '0;
      egr_job_req_bp_cnt_q   <= '0;
      egr_meta_disp_hs_cnt_q <= '0;
      egr_meta_disp_bp_cnt_q <= '0;
      egr_wkr_bp_hs_cnt_q    <= '{default: '0};
      egr_wkr_bp_bp_cnt_q    <= '{default: '0};
      egr_wkr_bus_hs_cnt_q   <= '{default: '0};
      egr_wkr_bus_bp_cnt_q   <= '{default: '0};
    end else if (dma_enable_i) begin
      if (egr_job_req_valid_i && egr_job_req_ready_i) begin
        egr_job_req_hs_cnt_q <= egr_job_req_hs_cnt_q + 1;
      end else if (egr_job_req_valid_i && !egr_job_req_ready_i) begin
        egr_job_req_bp_cnt_q <= egr_job_req_bp_cnt_q + 1;
      end

      if (egr_meta_disp_valid_i && egr_meta_disp_ready_i) begin
        egr_meta_disp_hs_cnt_q <= egr_meta_disp_hs_cnt_q + 1;
      end else if (egr_meta_disp_valid_i && !egr_meta_disp_ready_i) begin
        egr_meta_disp_bp_cnt_q <= egr_meta_disp_bp_cnt_q + 1;
      end

      for (int w = 0; w < W_WORKERS; w++) begin
        if (egr_wkr_bp_req_i[w] && egr_wkr_bp_gnt_i[w]) begin
          egr_wkr_bp_hs_cnt_q[w] <= egr_wkr_bp_hs_cnt_q[w] + 1;
        end else if (egr_wkr_bp_req_i[w] && !egr_wkr_bp_gnt_i[w]) begin
          egr_wkr_bp_bp_cnt_q[w] <= egr_wkr_bp_bp_cnt_q[w] + 1;
        end

        if (egr_wkr_bus_valid_i[w] && egr_wkr_bus_ready_i[w]) begin
          egr_wkr_bus_hs_cnt_q[w] <= egr_wkr_bus_hs_cnt_q[w] + 1;
        end else if (egr_wkr_bus_valid_i[w] && !egr_wkr_bus_ready_i[w]) begin
          egr_wkr_bus_bp_cnt_q[w] <= egr_wkr_bus_bp_cnt_q[w] + 1;
        end
      end
    end
  end

  // CPU Counters
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cpu_l2_hs_cnt_q   <= '0;
      cpu_l2_bp_cnt_q   <= '0;
      cpu_meta_hs_cnt_q <= '0;
      cpu_meta_bp_cnt_q <= '0;
    end else if (dma_enable_i) begin
      if (cpu_l2_valid_i && cpu_l2_ready_i) begin
        cpu_l2_hs_cnt_q <= cpu_l2_hs_cnt_q + 1;
      end else if (cpu_l2_valid_i && !cpu_l2_ready_i) begin
        cpu_l2_bp_cnt_q <= cpu_l2_bp_cnt_q + 1;
      end

      if (cpu_meta_req_i && cpu_meta_gnt_i) begin
        cpu_meta_hs_cnt_q <= cpu_meta_hs_cnt_q + 1;
      end else if (cpu_meta_req_i && !cpu_meta_gnt_i) begin
        cpu_meta_bp_cnt_q <= cpu_meta_bp_cnt_q + 1;
      end
    end
  end

  // APB Read-Out
  logic is_apb_space;
  assign is_apb_space = (paddr_i[27] == 1'b1);

  logic rd_en;
  assign pready_o  = is_apb_space & psel_i & penable_i;
  assign rd_en     = pready_o & !pwrite_i;
  assign pslverr_o = 1'b0;

  // 0x08004000 - 0x080040FF: Global, Fixed Egress & CPU Counters
  // 0x08004100 - 0x080041FF: Ingress Stream Counters (0x100 Offset)
  // 0x08004200 - 0x080042FF: Egress Worker Counters (0x200 Offset)
  logic is_perf_mon;
  assign is_perf_mon = (paddr_i[15:12] == 4'h4);

  logic [9:0] word_idx;
  assign word_idx = paddr_i[11:2];

  always_comb begin
    prdata_o = '0;

    if (rd_en && is_perf_mon) begin
      case (word_idx)
        10'h000: prdata_o = setup_cnt_q;
        10'h001: prdata_o = run_cnt_q;

        10'h002: prdata_o = egr_job_req_hs_cnt_q;
        10'h003: prdata_o = egr_job_req_bp_cnt_q;

        10'h004: prdata_o = egr_meta_disp_hs_cnt_q;
        10'h005: prdata_o = egr_meta_disp_bp_cnt_q;

        10'h006: prdata_o = cpu_l2_hs_cnt_q;
        10'h007: prdata_o = cpu_l2_bp_cnt_q;

        10'h008: prdata_o = cpu_meta_hs_cnt_q;
        10'h009: prdata_o = cpu_meta_bp_cnt_q;

        default: begin
          // Ingress Stream Counters
          for (int i = 0; i < N_STREAMS; i++) begin
            if (word_idx == (10'h040 + 2 * i)) begin
              prdata_o = ingr_stm_in_hs_cnt_q[i];
            end else if (word_idx == (10'h040 + 2 * i + 1)) begin
              prdata_o = ingr_stm_in_bp_cnt_q[i];
            end
          end

          // Egress Worker Counters
          for (int w = 0; w < W_WORKERS; w++) begin
            if (word_idx == (10'h080 + 4 * w)) begin
              prdata_o = egr_wkr_bp_hs_cnt_q[w];
            end else if (word_idx == (10'h080 + 4 * w + 1)) begin
              prdata_o = egr_wkr_bp_bp_cnt_q[w];
            end else if (word_idx == (10'h080 + 4 * w + 2)) begin
              prdata_o = egr_wkr_bus_hs_cnt_q[w];
            end else if (word_idx == (10'h080 + 4 * w + 3)) begin
              prdata_o = egr_wkr_bus_bp_cnt_q[w];
            end
          end
        end
      endcase
    end
  end

endmodule
