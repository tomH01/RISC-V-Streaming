module axi3_to_apb3_bridge #(
  parameter int unsigned ADDR_WIDTH = 32,
  parameter int unsigned DATA_WIDTH = 32,
  parameter int unsigned ID_WIDTH   = 4
)(
  input logic                  clk_i,
  input logic                  rst_ni,

  // AXI3 Subordinate IF
  input  logic                  awvalid_i,
  output logic                  awready_o,
  input  logic [ADDR_WIDTH-1:0] awaddr_i,
  input  logic [ID_WIDTH-1:0]   awid_i,
  input  logic [3:0]            awlen_i,
  input  logic [2:0]            awsize_i,
  input  logic [1:0]            awburst_i,

  input  logic                  wvalid_i,
  output logic                  wready_o, 
  input  logic [DATA_WIDTH-1:0] wdata_i,
  input  logic [ID_WIDTH-1:0]   wid_i,
  input  logic                  wlast_i,

  output logic                  bvalid_o,
  input  logic                  bready_i,
  output logic [1:0]            bresp_o,
  output logic [ID_WIDTH-1:0]   bid_o,

  input  logic                  arvalid_i,
  output logic                  arready_o,
  input  logic [ADDR_WIDTH-1:0] araddr_i,
  input  logic [ID_WIDTH-1:0]   arid_i,
  input  logic [3:0]            arlen_i,
  input  logic [2:0]            arsize_i,
  input  logic [1:0]            arburst_i,

  output logic                  rvalid_o,
  input  logic                  rready_i,
  output logic [DATA_WIDTH-1:0] rdata_o,
  output logic [1:0]            rresp_o,
  output logic [ID_WIDTH-1:0]   rid_o,
  output logic                  rlast_o,

  // APB Manager IF
  output logic                  penable_o,
  output logic                  pwrite_o,
  output logic [ADDR_WIDTH-1:0] paddr_o,
  output logic                  psel_o,
  output logic [DATA_WIDTH-1:0] pwdata_o,
  input  logic [DATA_WIDTH-1:0] prdata_i,
  input  logic                  pready_i,
  input  logic                  pslverr_i
);

  localparam logic [1:0] AXI_RESP_OKAY   = 2'b00;
  localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

  typedef enum logic [2:0] {
    IDLE,
    APB_SETUP,
    APB_ENABLE,
    DRAIN_W_BURST,
    WRITE_RESPONSE,
    READ_RESPONSE
  } state_e;

  state_e state_q, state_d;

  logic is_write_q, is_write_d;

  logic [ID_WIDTH-1:0] bid_q, rid_q;

  logic                  awdone_q;
  logic                  wdone_q;
  logic                  ardone_q;
  logic [ADDR_WIDTH-1:0] addr_q;
  logic [DATA_WIDTH-1:0] wdata_q;
  logic [DATA_WIDTH-1:0] rdata_q;

  logic                  burst_err_q;
  logic [3:0]            beat_cnt_q;
  logic [3:0]            len_q;
  logic                  apb_err_q;

  always_comb begin
    state_d     = state_q;
    is_write_d  = is_write_q;

    penable_o   = 1'b0;
    pwrite_o    = 1'b0;
    psel_o      = 1'b0;

    bvalid_o    = 1'b0;
    bresp_o     = AXI_RESP_OKAY;

    rvalid_o    = 1'b0;
    rresp_o     = AXI_RESP_OKAY;
    rlast_o     = 1'b0;

    awready_o   = 1'b0;
    arready_o   = 1'b0;
    wready_o    = 1'b0;

    case (state_q)
      IDLE: begin
        if (awdone_q || awvalid_i) begin
          awready_o  = !awdone_q;
          wready_o   = !wdone_q;
          is_write_d = 1'b1;

          if ((awdone_q || awvalid_i) && (wdone_q || wvalid_i)) begin
            if (burst_err_q || (awvalid_i && awlen_i != 4'b0)) begin
              state_d = DRAIN_W_BURST;
            end else begin
              state_d = APB_SETUP;
            end
          end
        end else if (ardone_q || arvalid_i) begin
          arready_o  = !ardone_q;
          is_write_d = 1'b0;

          if (ardone_q || arvalid_i) begin
            if (burst_err_q || (arvalid_i && arlen_i != 4'b0)) begin
              state_d = READ_RESPONSE;
            end else begin
              state_d = APB_SETUP;
            end
          end
        end else begin
          awready_o = 1'b1;
          arready_o = 1'b1;
          wready_o  = 1'b1;
        end
      end

      APB_SETUP: begin
        psel_o   = 1'b1;
        pwrite_o = is_write_q;
        state_d  = APB_ENABLE;
      end

      APB_ENABLE: begin
        psel_o    = 1'b1;
        penable_o = 1'b1;
        pwrite_o  = is_write_q;

        if (pready_i) begin
          state_d = is_write_q ? WRITE_RESPONSE : READ_RESPONSE;
        end
      end

      DRAIN_W_BURST: begin
        wready_o = 1'b1;
        if (wvalid_i && wlast_i) begin
          state_d = WRITE_RESPONSE;
        end
      end

      WRITE_RESPONSE: begin
        bvalid_o = 1'b1;
        bresp_o  = (burst_err_q || apb_err_q) ? AXI_RESP_SLVERR : AXI_RESP_OKAY;

        if (bready_i) begin
          state_d = IDLE;
        end
      end

      READ_RESPONSE: begin
        rvalid_o = 1'b1;
        rresp_o  = (burst_err_q || apb_err_q) ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
        rlast_o  = (beat_cnt_q == len_q);

        if (rready_i) begin
          if (beat_cnt_q == len_q) begin
            state_d = IDLE;
          end
        end
      end

      default: state_d = IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q     <= IDLE;
      is_write_q  <= 1'b0;
      awdone_q    <= 1'b0;
      wdone_q     <= 1'b0;
      ardone_q    <= 1'b0;
      burst_err_q <= 1'b0;
      apb_err_q   <= 1'b0;
      beat_cnt_q  <= '0;
      len_q       <= '0;
      addr_q      <= '0;
      wdata_q     <= '0;
      rdata_q     <= '0;
      bid_q       <= '0;
      rid_q       <= '0;
    end else begin
      state_q    <= state_d;
      is_write_q <= is_write_d;

      if (awvalid_i && awready_o) begin
        awdone_q    <= 1'b1;
        addr_q      <= awaddr_i;
        bid_q       <= awid_i;
        if (awlen_i != 4'b0) burst_err_q <= 1'b1;
      end

      if (wvalid_i && wready_o) begin
        wdone_q <= 1'b1;
        wdata_q <= wdata_i;
      end

      if (arvalid_i && arready_o) begin
        ardone_q    <= 1'b1;
        addr_q      <= araddr_i;
        rid_q       <= arid_i;
        len_q       <= arlen_i;
        if (arlen_i != 4'b0) burst_err_q <= 1'b1;
      end

      if (state_q == APB_ENABLE && pready_i) begin
        apb_err_q <= pslverr_i;
        if (!is_write_q) begin
          rdata_q <= prdata_i;
        end
      end

      if (state_q == READ_RESPONSE && rvalid_o && rready_i) begin
        if (beat_cnt_q != len_q) begin
          beat_cnt_q <= beat_cnt_q + 1'b1;
        end
      end

      if ((state_q == WRITE_RESPONSE && bvalid_o && bready_i) ||
          (state_q == READ_RESPONSE  && rvalid_o && rready_i && beat_cnt_q == len_q)) begin
        awdone_q    <= 1'b0;
        wdone_q     <= 1'b0;
        ardone_q    <= 1'b0;
        burst_err_q <= 1'b0;
        apb_err_q   <= 1'b0;
        beat_cnt_q  <= '0;
        len_q       <= '0;
      end
    end
  end

  assign paddr_o  = addr_q;
  assign pwdata_o = wdata_q;
  assign rdata_o  = rdata_q;
  assign bid_o    = bid_q;
  assign rid_o    = rid_q;

endmodule
