// router.sv
// Wormhole-switched mesh NoC router — single VC, 5-port
//
// Pipeline: Decode (cy N) → Allocate (cy N+1) → Forward (cy N+1)
//   Cycle N: head flit at FIFO head, xy_route computes port_sel,
//              allocator sees request
//   Cycle N+1: registered grant appears, ANDed with has_credit,
//              FIFO popped, crossbar driven, credit decremented
//
// Per-port state machine (wormhole):
//   IDLE — no active packet, eligible to request allocation
//   ALLOCATED — head flit won grant, holding route for body/tail flits
//   Back to IDLE on tail flit or HEAD_TAIL flit forward

module router
    import noc_pkg::*;
#(
    parameter int MY_X = 0,
    parameter int MY_Y = 0,
    parameter int BUFFER_DEPTH = 16,
    parameter int N = 5 // number of ports
)(
    input logic clk_i,
    input logic rst_i,

    // Upstream
    input flit_t flit_in_i [N], // the actual flit data arriving on each of the N input ports. 
    input logic flit_in_valid_i [N], // signaling there is an incoming flit at the port
    output logic flit_in_ready_o [N], // telling upstream router it is ready to take a new flit

    // Downstream
    output flit_t flit_out_o [N], // flit to be sent out
    output logic flit_out_valid_o [N], // signal that a flit is being sent out

    // Credit interface
    input logic credit_in_i [N], // one for each output port
    output logic credit_out_o [N] // one for each input port
);

    // ----------------------------------------------------------------
    // Port index constants — match xy_route.sv
    // ----------------------------------------------------------------
    localparam int PORT_N = 4;
    localparam int PORT_S = 3;
    localparam int PORT_E = 2;
    localparam int PORT_W = 1;
    localparam int PORT_LOCAL = 0;

    // ----------------------------------------------------------------
    // Per input port state machine
    // ----------------------------------------------------------------
    typedef enum logic [1:0] {
        ST_IDLE = 2'b00,
        ST_ALLOCATED = 2'b01
    } port_state_t;

    port_state_t state_r [N];

    // Held output port (one-hot) for body/tail flits
    // This is holding the grant for a complete packet
    // Basically keeps the mapping between a granted input output path for the packet to go through
    logic [N-1:0] held_route_r [N]; // held_route_r[input_port][output_port]

    // ----------------------------------------------------------------
    // Input buffers (input_buf.sv)
    // ----------------------------------------------------------------
    flit_t flit_buf_out [N];
    logic buf_empty [N];
    logic buf_full [N];
    logic buf_rd_en [N];
    genvar p;
    generate
        // one FIFO per input port
        for (p = 0; p < N; p++) begin : gen_input_buf
            input_buf #(.BUFFER_DEPTH(BUFFER_DEPTH)) ibuf (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .wr_en_i(flit_in_valid_i[p] && !buf_full[p]),
                .flit_i(flit_in_i[p]),
                .full_o(buf_full[p]),
                .rd_en_i(buf_rd_en[p]), // signal to pop
                .flit_o(flit_buf_out[p]),
                .empty_o(buf_empty[p])
            );
        end
    endgenerate

    // tracks whether each input port has space (not full)
    generate
        for (p = 0; p < N; p++) begin : gen_ready
            assign flit_in_ready_o[p] = !buf_full[p];
        end
    endgenerate

    // ----------------------------------------------------------------
    // XY routing (xy_route.sv)
    // Combinational: port_sel[i] valid same cycle head flit is at buf head
    // ----------------------------------------------------------------
    logic [4:0] port_sel [N];

    generate
        // iterate through input ports
        for (p = 0; p < N; p++) begin : gen_route
            // Cast raw flit bits to head_flit_t to extract dst fields
            head_flit_t hf;
            assign hf = head_flit_t'(flit_buf_out[p]); //read from fifo

            xy_route #(.MY_X(MY_X), .MY_Y(MY_Y)) xyr (
                .dst_x(hf.dst_x),
                .dst_y(hf.dst_y),
                .port_sel(port_sel[p])
            );
        end
    endgenerate

    // ----------------------------------------------------------------
    // Allocator request matrix (allocator.sv)
    // req[i][j] = 1: input port i wants output port j
    // grant[i][j] = 1: input port i is granted to output port j
    // Only assert in IDLE state with a head/head-tail flit ready
    // ----------------------------------------------------------------
    logic [N-1:0] req [N];
    logic [N-1:0] grant[N];

    // Build the req input into the allocator
    always_comb begin
        // iterate through input ports
        for (int i = 0; i < N; i++) begin
            if (state_r[i] == ST_IDLE && !buf_empty[i]) begin
                head_flit_t hf;
                hf = head_flit_t'(flit_buf_out[i]);
                // Only request if this is a head or head-tail flit
                if (hf.flit_type == HEAD || hf.flit_type == HEAD_TAIL)
                    req[i] = port_sel[i]; // assign output port to the current input port
                else
                    req[i] = '0;
            end else begin
                req[i] = '0;
            end
        end
    end

    allocator #(.N(N)) alloc (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req(req),
        .grant(grant)
    );

    // ----------------------------------------------------------------
    // Credit units — one per output port
    // ----------------------------------------------------------------
    logic has_credit [N];

    generate
        // iterate through output port
        for (p = 0; p < N; p++) begin : gen_credit
            // decrement when a flit is forwarded out of output port p
            // increment when downstream returns a credit on this port
            logic decr;
            assign decr = flit_out_valid_o[p];

            credit_unit #(.BUFFER_DEPTH(BUFFER_DEPTH)) cu (
                .clk_i(clk_i),
                .rst_i(rst_i),
                .credit_decr_i(decr), // receives from downstream
                .credit_incr_i(credit_in_i[p]), // receives from downstream
                .has_credit_o (has_credit[p]),
                .count_o()  // unconnected — used by formal only
            );
        end
    endgenerate

    // ----------------------------------------------------------------
    // Forward decision
    // do_forward[i][j] = grant[i][j] AND has_credit[j]
    // A flit moves only when the allocator granted it AND the downstream buffer has room.
    // ***Note that do_forward is only high for any freshly allocated path
    // ----------------------------------------------------------------
    logic [N-1:0] do_forward [N];
    always_comb begin
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                do_forward[i][j] = grant[i][j] && has_credit[j];
    end

    // ----------------------------------------------------------------
    // FIFO read enable and credit return
    // buf_rd_en[i]: pop input port i's FIFO this cycle
    // credit_out_o[i]: tell upstream a slot freed on input port i
    // ----------------------------------------------------------------
    always_comb begin
        // iterate through input ports
        for (int i = 0; i < N; i++) begin
            buf_rd_en[i] = 1'b0;
            credit_out_o[i] = 1'b0;

            if (state_r[i] == ST_ALLOCATED) begin
                // Body/tail: forward on held route if credit available
                for (int j = 0; j < N; j++) begin
                    // if the output is holding the route, output has credit, has more to send, and not a fresh grant path
                    if (held_route_r[i][j] && has_credit[j] && !buf_empty[i] && !do_forward[i][j]) begin
                        buf_rd_en[i] = 1'b1; // signal to pop from fifo
                        credit_out_o[i] = 1'b1; // update credit (increase)
                    end
                end
            end else begin
                // Head/head-tail: forward only on a fresh grant
                for (int j = 0; j < N; j++) begin
                    if (do_forward[i][j]) begin
                        buf_rd_en[i] = 1'b1;
                        credit_out_o[i] = 1'b1;
                    end
                end
            end
        end
    end

    // ----------------------------------------------------------------
    // State machine and held route update
    // ----------------------------------------------------------------
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            for (int i = 0; i < N; i++) begin
                state_r[i] <= ST_IDLE;
                held_route_r[i]  <= '0;
            end
        end else begin
            // iterate through input ports
            for (int i = 0; i < N; i++) begin
                case (state_r[i])
                    ST_IDLE: begin
                        // Check if a grant fired this cycle
                        // iterate through output ports
                        for (int j = 0; j < N; j++) begin            
                            // if input port i was granted output port j
                            if (do_forward[i][j]) begin
                                head_flit_t hf;
                                hf = head_flit_t'(flit_buf_out[i]);
                                if (hf.flit_type == HEAD) begin
                                    // Multi-flit packet — hold route
                                    state_r[i] <= ST_ALLOCATED;
                                    held_route_r[i] <= grant[i];
                                end
                                // HEAD_TAIL: single flit, stay IDLE

                                if (hf.flit_type == HEAD) begin
                                    state_r[i] <= ST_ALLOCATED;
                                    held_route_r[i] <= grant[i];
                                    $display("t=%0t port %0d -> ST_ALLOCATED held=%05b", $time, i, grant[i]);
                                end
                            end
                        end
                    end

                    // Body
                    ST_ALLOCATED: begin
                        if (buf_rd_en[i] && !buf_empty[i]) begin
                            flit_type_t ft;
                            ft = flit_type_t'(flit_buf_out[i][FLIT_WIDTH-1 -: 2]);
                            if (ft == TAIL || ft == HEAD_TAIL) begin
                                state_r[i] <= ST_IDLE;
                                held_route_r[i] <= '0;
                            end
                        end
                    end

                    default: state_r[i] <= ST_IDLE;
                endcase
            end
        end
    end

    // ----------------------------------------------------------------
    // Crossbar — one mux per output port
    // flit_out_o[j] driven by whichever input port won output j
    // ----------------------------------------------------------------
    always_comb begin
        for (int j = 0; j < N; j++) begin
            flit_out_o[j] = '0;
            flit_out_valid_o[j] = 1'b0;
            for (int i = 0; i < N; i++) begin
                // Head/head-tail: fresh grant
                if (do_forward[i][j]) begin
                    flit_out_o[j] = flit_buf_out[i];
                    flit_out_valid_o[j] = 1'b1;
                end
                // Body/tail: held route
                if (state_r[i] == ST_ALLOCATED &&
                    held_route_r[i][j] &&
                    has_credit[j] &&
                    !buf_empty[i] &&
                    !do_forward[i][j]) begin
                    flit_out_o[j] = flit_buf_out[i];
                    flit_out_valid_o[j] = 1'b1;

                    if (state_r[i] == ST_ALLOCATED &&
                        held_route_r[i][j] &&
                        has_credit[j] &&
                        !buf_empty[i]) begin
                        $display("t=%0t body/tail: input %0d -> output %0d flit=%h", $time, i, j, flit_buf_out[i]);
                        flit_out_o[j] = flit_buf_out[i];
                        flit_out_valid_o[j] = 1'b1;
                    end
                end
            end
        end
    end

endmodule