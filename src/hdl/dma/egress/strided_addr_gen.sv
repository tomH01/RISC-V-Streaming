module strided_addr_gen #(
  parameter int ADDR_WIDTH   = 32,
  parameter int STRIDE_WIDTH = 14,
  parameter int COUNT_WIDTH  = 10,
  parameter int NUM_AXES     = 4,

  localparam int AXIS_CFG_WIDTH = STRIDE_WIDTH + COUNT_WIDTH,
  localparam int PAYLOAD_WIDTH  = NUM_AXES * AXIS_CFG_WIDTH
)(
  input logic clk_i, 
  input logic rst_ni,

  input logic                     job_start_i,
  input logic                     req_i,
  input logic [ADDR_WIDTH-1:0]    base_addr_i,
  input logic [PAYLOAD_WIDTH-1:0] payload_i, 

  output logic [ADDR_WIDTH-1:0] addr_o
);

  typedef struct packed {
    logic [STRIDE_WIDTH-1:0] stride;
    logic [COUNT_WIDTH-1:0]  count;
  } axis_cfg_t;

  axis_cfg_t axis [NUM_AXES];
  genvar i;
  generate
    for (i = 0; i < NUM_AXES; i++) begin : gen_unpack_payload
      assign axis[i] = payload_i[i * AXIS_CFG_WIDTH +: AXIS_CFG_WIDTH];
    end
  endgenerate

  (* use_dsp = "no" *) logic [ADDR_WIDTH-1:0] jump  [NUM_AXES];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      jump  <= '{default: '0};
    end else begin
      if (job_start_i) begin
        for (int i = 0; i < NUM_AXES; i++) begin
          jump[i] <= ADDR_WIDTH'(axis[i].stride) * ADDR_WIDTH'(axis[i].count - 1);
        end
      end
    end
  end

  logic job_start_d;
  always_ff @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni)
    job_start_d <= 1'b0;
  else
    job_start_d <= job_start_i;
  end

  logic signed [ADDR_WIDTH-1:0] delta [NUM_AXES];
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      delta <= '{default:'0};
    end else if (job_start_d) begin
      logic [ADDR_WIDTH-1:0] jump_acc;
      jump_acc = '0;

      for (int i = 0; i < NUM_AXES; i++) begin
        delta[i] <= ADDR_WIDTH'(axis[i].stride) - jump_acc;
        jump_acc = jump_acc + jump[i];
      end
    end
  end

  logic [COUNT_WIDTH-1:0] cnt_q [NUM_AXES];
  logic                   wrap  [NUM_AXES];

  always_comb begin
    wrap[0] = (cnt_q[0] == axis[0].count - 1);
    for (int i = 1; i < NUM_AXES; i++) begin
      wrap[i] = wrap[i-1] && (cnt_q[i] == axis[i].count - 1);
    end
  end

  logic signed [ADDR_WIDTH-1:0] selected_delta;

  always_comb begin
    selected_delta = delta[0];

    for (int i = 0; i < NUM_AXES - 1; i++) begin
      if (wrap[i]) begin
        selected_delta = delta[i+1];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      addr_o <= '0;
      cnt_q  <= '{default: '0};

    end else begin
      if (job_start_i) begin
        addr_o <= base_addr_i;
        cnt_q  <= '{default: '0};
      end else if (req_i) begin
        if (wrap[NUM_AXES-1]) begin 
          addr_o <= base_addr_i;
        end else begin
          addr_o   <= addr_o + selected_delta;
        end 

        cnt_q[0] <= wrap[0] ? '0 : cnt_q[0] + 1;
        for (int i = 1; i < NUM_AXES; i++) begin
          if (wrap[i-1]) begin
            cnt_q[i] <= wrap[i] ? '0 : cnt_q[i] + 1;
          end
        end
      end
    end
  end

endmodule
