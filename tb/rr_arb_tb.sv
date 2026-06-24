// tb_rr_arb.sv
// Directed self-checking testbench for rr_arb.sv
//
// Verification goals:
//   1. Basic grant      — single requester always wins
//   2. Priority         — with multiple requesters, ptr determines winner
//   3. Pointer advance  — ptr moves to winner+1 after each grant
//   4. Fairness         — all requesters eventually get granted (no starvation)
//   5. No phantom grant — all-zero request produces all-zero grant
//   6. Wraparound       — pointer wraps correctly from N-1 back to 0
//   7. One-hot          — grant is always one-hot or all-zero

`timescale 1ns/1ps
import noc_pkg::*;

module tb_rr_arb;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam int N = 5;
    localparam int PTR_W = $clog2(N);
    localparam int CLK_PERIOD = 10;

    // -------------------------------------------------------------------------
    // DUT signals
    // -------------------------------------------------------------------------
    logic clk;
    logic rst;
    logic [N-1:0] req;
    logic [N-1:0] grant;

    // -------------------------------------------------------------------------
    // Test counters
    // -------------------------------------------------------------------------
    int total_pass = 0;
    int total_fail = 0;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    rr_arb #(.N(N)) dut (
        .clk_i(clk),
        .rst_i(rst),
        .req_i(req),
        .grant_o(grant)
    );

    // -------------------------------------------------------------------------
    // Clock generation
    // -------------------------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // -------------------------------------------------------------------------
    // Helper tasks
    // -------------------------------------------------------------------------

    // Apply reset for 2 cycles
    task do_reset();
        req = '0;
        rst = 1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        @(posedge clk); #1;
        rst = 0;
        @(posedge clk); #1;
    endtask

    // Check one-hot or all-zero property on grant
    task check_one_hot(input logic [N-1:0] g, input string test_name);
        int bit_count;
        bit_count = 0;
        for (int i = 0; i < N; i++) bit_count += g[i];
        if (bit_count > 1) begin
            $error("[FAIL] %s: grant=%05b has %0d bits set — not one-hot", test_name, g, bit_count);
            total_fail++;
        end else begin
            total_pass++;
        end
    endtask

    // Check that a specific port was granted
    task check_grant(
        input logic [N-1:0] g,
        input int expected_port,
        input string test_name
    );
        if (g !== (N'(1) << expected_port)) begin
            $error("[FAIL] %s: grant=%05b, expected port %0d (=%05b)",
                   test_name, g, expected_port, (N'(1) << expected_port));
            total_fail++;
        end else begin
            $display("[PASS] %s: port %0d granted correctly", test_name, expected_port);
            total_pass++;
        end
    endtask

    // Check that grant is all-zero
    task check_no_grant(input logic [N-1:0] g, input string test_name);
        if (g !== '0) begin
            $error("[FAIL] %s: expected no grant but got grant=%05b", test_name, g);
            total_fail++;
        end else begin
            $display("[PASS] %s: no grant issued correctly", test_name);
            total_pass++;
        end
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        $display("========================================");
        $display("rr_arb testbench start");
        $display("========================================");

        // Initialize all signals before clock runs
        rst = 1;
        req = '0;
        repeat(4) @(posedge clk);
        rst = 0;
        @(posedge clk); #1;

        // -----------------------------------------------------------------
        // Test 1: No requests — grant must be all-zero
        // -----------------------------------------------------------------
        do_reset();
        req = 5'b00000;
        @(posedge clk); #1;
        check_no_grant(grant, "T1: no requests");
        check_one_hot(grant, "T1: one-hot check");

        // -----------------------------------------------------------------
        // Test 2: Single requester — must always win regardless of ptr
        // After reset ptr=0. Request only port 3.
        // -----------------------------------------------------------------
        do_reset();
        req = 5'b01000; // only port 3
        @(posedge clk); #1;
        check_grant(grant, 3, "T2: single requester port 3");
        check_one_hot(grant, "T2: one-hot check");

        // -----------------------------------------------------------------
        // Test 3: All requesters — ptr=0 after reset, so port 0 wins first
        // Then pointer advances: port 1 wins next, then 2, 3, 4, wrap to 0
        // This verifies fairness and pointer advance in one sweep
        // -----------------------------------------------------------------
        do_reset();
        req = 5'b11111; // all five requesting
        
        for (int expected = 0; expected < N; expected++) begin
            @(posedge clk); #1;
            check_grant(grant, expected, $sformatf("T3: fairness sweep port %0d", expected));
            check_one_hot(grant, $sformatf("T3: one-hot port %0d", expected));
        end

        // After full sweep, pointer wraps back to 0 — port 0 wins again
        @(posedge clk); #1;
        check_grant(grant, 0, "T3: wraparound back to port 0");

        // -----------------------------------------------------------------
        // Test 4: Pointer wraparound from N-1
        // Force ptr to point at port 4 (last), then request all.
        // Port 4 should win first, then wrap to port 0.
        // We get ptr to 4 by doing 4 grants from all-ones with ptr starting at 0.
        // -----------------------------------------------------------------
        do_reset();
        req = 5'b11111;

        // Advance ptr to 4 by consuming 4 grants
        repeat(4) @(posedge clk);
        #1;
        // Now ptr should be at 4 — port 4 wins this cycle
        @(posedge clk); #1;
        check_grant(grant, 4, "T4: ptr at 4, port 4 wins");

        // Next cycle ptr wraps to 0
        @(posedge clk); #1;
        check_grant(grant, 0, "T4: ptr wrapped to 0");

        // -----------------------------------------------------------------
        // Test 5: Requester at lower index than ptr — ptr skips and wraps
        // Reset, advance ptr to 3 by consuming 3 grants.
        // Then only request port 1 (below ptr).
        // Port 1 should win via phase 2 (wrap-around scan).
        // -----------------------------------------------------------------
        do_reset();
        req = 5'b11111;
        repeat(3) @(posedge clk); // advance ptr to 3
        #1;

        req = 5'b00010; // only port 1, which is below ptr=3
        @(posedge clk); #1;
        check_grant(grant, 1, "T5: wrap-around scan grants port below ptr");
        check_one_hot(grant, "T5: one-hot check");

        // -----------------------------------------------------------------
        // Test 6: Grant held across back-to-back requests from same port
        // Port 2 requests for 3 consecutive cycles.
        // It should win cycle 1, then lose priority to port 3+,
        // but since only port 2 is requesting it wins all three.
        // -----------------------------------------------------------------
        do_reset();
        req = 5'b00100; // only port 2
        repeat(3) begin
            @(posedge clk); #1;
            check_grant(grant, 2, "T6: sole requester wins repeatedly");
        end

        // -----------------------------------------------------------------
        // Test 7: Request de-assertion mid-sequence
        // All request, port 0 wins. Then port 0 de-asserts.
        // Next winner should be port 1.
        // -----------------------------------------------------------------
        do_reset();
        req = 5'b11111;
        @(posedge clk); #1;
        check_grant(grant, 0, "T7: port 0 wins first");

        req = 5'b11110; // port 0 de-asserts
        @(posedge clk); #1;
        check_grant(grant, 1, "T7: port 1 wins after port 0 de-asserts");

        // -----------------------------------------------------------------
        // Test 8: No starvation — each port gets exactly one grant per round
        // Run 20 cycles with all requesters active, count grants per port.
        // Each port should receive exactly 4 grants (20 cycles / 5 ports).
        // -----------------------------------------------------------------
        do_reset();
        req = 5'b11111;
        begin
            int grant_count [N];
            for (int i = 0; i < N; i++) grant_count[i] = 0;

            repeat(20) begin
                @(posedge clk); #1;
                for (int i = 0; i < N; i++)
                    if (grant[i]) grant_count[i]++;
            end

            for (int i = 0; i < N; i++) begin
                if (grant_count[i] !== 4) begin
                    $error("[FAIL] T8: port %0d received %0d grants, expected 4", i, grant_count[i]);
                    total_fail++;
                end else begin
                    $display("[PASS] T8: port %0d received %0d grants", i, grant_count[i]);
                    total_pass++;
                end
            end
        end

        // -----------------------------------------------------------------
        // Report
        // -----------------------------------------------------------------
        #10;
        $display("========================================");
        $display("rr_arb testbench complete");
        $display("PASS: %0d  FAIL: %0d  TOTAL: %0d",
                 total_pass, total_fail, total_pass + total_fail);
        if (total_fail == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILURES DETECTED — review $error messages above");
        $display("========================================");
        $finish;
    end

    // -------------------------------------------------------------------------
    // Waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_rr_arb.vcd");
        $dumpvars(0, tb_rr_arb);
    end

endmodule
