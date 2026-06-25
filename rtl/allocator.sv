// instantiates five rr_arb instances, one per output port
// wires up the request and grant signals between them and the input ports.
// Just a wrapper around the round robin arbiters

// Given x input ports want each of the n/s/e/w/local output ports, grant one for each output port

// Design notes:
//   - Separable allocation: each output port arbitrates independently
//   - This can produce suboptimal global matching under hotspot traffic
//   - The throughput deficit vs iSLIP is measurable and explainable
//   - One grant per output port per cycle — mutual exclusion guaranteed
//   - An input port can only win one output port per cycle in practice
//     because it only has one head flit with one destination

import noc_pkg::*;

module allocator #(
    parameter int N = 5  // number of ports — 5 for a full mesh router
)(
    input logic clk_i,
    input logic rst_i,

    // Request matrix: req[input_port][output_port]
    // req[i][j] = 1 means input port i has a head flit wanting output port j
    input logic [N-1:0] req [N],

    // Grant matrix: grant[input_port][output_port]
    // grant[i][j] = 1 means input port i wins output port j this cycle
    output logic [N-1:0] grant [N]
);

    logic [N-1:0] req_per_out [N]; // req_per_out[output_port][input_port]
    logic [N-1:0] grant_per_out [N]; // grant_per_out[output_port][input_port]

    // Transpose: slice columns out of the request matrix
    // transposed vector is fed into round robin arbiter
    always_comb begin
        for (int j = 0; j < N; j++) begin // for each output port
            for (int i = 0; i < N; i++) begin  // for each input port
                req_per_out[j][i] = req[i][j];
            end
        end
    end

    // Instantiate round robin arbiters
    genvar j;
    generate
        // iterate through output ports
        for (j = 0; j < N; j++) begin : gen_arb
            rr_arb #(.N(N)) arb(
                .clk_i(clk_i),
                .rst_i(rst_i),
                .req_i(req_per_out[j]), // req_i tells which input ports want this output port
                .grant_o(grant_per_out[j]) // grant_o tells which input port got this output port
            );
        end
    endgenerate

    // Transpose grant back into grant[input][output] form
    // grant[i][j] = grant_per_out[j][i]
    always_comb begin
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                grant[i][j] = grant_per_out[j][i];
            end
        end
    end

endmodule
