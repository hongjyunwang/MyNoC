// 1 arbiter per output port
// single N-input, 1-grant arbiter. The allocator will instantiate five of these, one per output port. 
// Given N flits wanting to be sent out from n/s/e/w/local port, which flit should be queue up first?
// --> Each arbiter independently decides which input port wins that output port this cycle.

// Design notes:
//   - Grant is combinational given requests and current priority pointer
//   - Pointer update is registered — advances on the cycle after a grant
//   - If no requests are active, pointer holds and no grant is issued
//   - grant_o is one-hot: at most one bit set per cycle
//   - Double-rank priority: starting from ptr, scan forward; wrap around
 
import noc_pkg::*;
 
module rr_arb #(
    parameter int N = 5 // number of requesters — 5 for a full mesh router
)(
    input logic clk_i,
    input logic rst_i,

    input logic [N-1:0] req_i, // request vector, one bit per input port
    output logic [N-1:0] grant_o // one-hot grant output
);

    localparam PTR_W = $clog2(N);

    logic [PTR_W-1:0] ptr;
 
    // Combinational grant logic — double-rank priority scheme
    logic [N-1:0] grant_phase1;  // grant candidates from ptr onward
    logic [N-1:0] grant_phase2;  // grant candidates from 0 to ptr-1
    logic phase1_hit;
    logic [N-1:0] grant_comb;
    logic [N-1:0] grant_r;
 
    always_comb begin
        grant_phase1 = '0;
        grant_phase2 = '0;
 
        // Phase 1: ptr to N-1
        // Find the first set bit at or after ptr
        for (int i = 0; i < N; i++) begin
            if (i >= ptr) begin
                if (req_i[i] && (grant_phase1 == '0))
                    grant_phase1[i] = 1'b1;
            end
        end
 
        // Phase 2: 0 to ptr-1
        // Only used if phase 1 found nothing
        for (int i = 0; i < N; i++) begin
            if (i < ptr) begin
                if (req_i[i] && (grant_phase2 == '0))
                    grant_phase2[i] = 1'b1;
            end
        end

        // Phase 1 takes priority; fall back to phase 2 if no hit
        phase1_hit = (grant_phase1 != '0);
        // grant_o auto becomes zero when no request
        grant_comb = phase1_hit ? grant_phase1 : grant_phase2;
    end

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            ptr     <= '0;
            grant_r <= '0;
        end else begin
            grant_r <= grant_comb;
            if (grant_comb != '0) begin
                for (int i = 0; i < N; i++) begin
                    if (grant_comb[i]) begin
                        if (i == N-1)
                            ptr <= '0;
                        else
                            ptr <= PTR_W'(i + 1);
                    end
                end
            end
        end
    end

    assign grant_o = grant_r;
 
endmodule