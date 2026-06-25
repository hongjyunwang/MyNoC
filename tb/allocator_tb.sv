`timescale 1ns/1ps

// ============================================================
// allocator_tb.sv — Directed self-checking testbench
// Tests: mutual exclusion, fairness/pointer rotation,
//        perfect matching, edge cases (no-req, single-req,
//        request drop mid-sequence, idle pointer persistence)
// Compile: iverilog -g2012 -o allocator_tb noc_pkg.sv rr_arb.sv allocator.sv allocator_tb.sv
// Run:     vvp allocator_tb
// ============================================================

import noc_pkg::*;

module allocator_tb;

    // --------------------------------------------------------
    // Parameters
    // --------------------------------------------------------
    localparam int N = 5;
    localparam int CLK_HALF = 5; // 10ns period

    // --------------------------------------------------------
    // DUT signals
    // --------------------------------------------------------
    logic clk_i;
    logic rst_i;
    logic [N-1:0] req [N];   // req[input][output]
    logic [N-1:0] grant [N];   // grant[input][output]

    // --------------------------------------------------------
    // DUT instantiation
    // --------------------------------------------------------
    allocator #(.N(N)) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .req(req),
        .grant(grant)
    );

    // --------------------------------------------------------
    // Clock generation
    // --------------------------------------------------------
    initial clk_i = 0;
    always #CLK_HALF clk_i = ~clk_i;

    // --------------------------------------------------------
    // Test tracking
    // --------------------------------------------------------
    int tests_run = 0;
    int tests_passed = 0;

    // --------------------------------------------------------
    // Tasks & functions
    // --------------------------------------------------------

    // Clear all requests
    task automatic clear_req();
        for (int i = 0; i < N; i++)
            req[i] = '0;
    endtask

    // Apply reset
    task automatic apply_reset();
        rst_i = 1;
        clear_req();
        @(posedge clk_i); #1;
        @(posedge clk_i); #1;
        rst_i = 0;
        @(posedge clk_i); #1;
    endtask

    // Check mutual exclusion: no output port granted to >1 input,
    // no input port granted >1 output
    function automatic logic check_mutex();
        logic [N-1:0] out_grant_count;
        logic [N-1:0] in_grant_count;
        out_grant_count = '0;
        in_grant_count  = '0;
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                if (grant[i][j]) begin
                    out_grant_count[j]++;
                    in_grant_count[i]++;
                end
            end
        end
        for (int k = 0; k < N; k++) begin
            if (out_grant_count[k] > 1) return 0; // output k double-granted
            if (in_grant_count[k]  > 1) return 0; // input k got two outputs
        end
        return 1;
    endfunction

    // Check grant only goes to a requesting port
    function automatic logic check_grant_implies_req();
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                if (grant[i][j] && !req[i][j]) return 0;
        return 1;
    endfunction

    // Count how many grants are active this cycle
    function automatic int count_grants();
        int cnt = 0;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                if (grant[i][j]) cnt++;
        return cnt;
    endfunction

    // Helper: assert a named condition and update counters
    task automatic check(input string name, input logic cond);
        tests_run++;
        if (cond) begin
            tests_passed++;
            $display("  PASS  %s", name);
        end else begin
            $display("  FAIL  %s", name);
        end
    endtask

    // --------------------------------------------------------
    // ========================================================
    //  TEST 1 — No requests: grant matrix must be all-zero
    // ========================================================
    // Tradeoff note: arbiter should not advance pointer on
    // an idle cycle — pointer persistence verified in Test 5.
    // --------------------------------------------------------
    task automatic test_no_requests();
        $display("\n[TEST 1] No requests — grant must be all-zero");
        apply_reset();
        clear_req();
        @(posedge clk_i); #1;
        check("no_req: grant all zero", count_grants() == 0);
        check("no_req: mutex", check_mutex());
    endtask

    // --------------------------------------------------------
    // ========================================================
    //  TEST 2 — Single requester per output port
    //  Each input i exclusively requests output i.
    //  All N grants should fire simultaneously — perfect match.
    // ========================================================
    // Tradeoff note: separable round-robin achieves maximum
    // throughput under zero-contention traffic; the throughput
    // deficit only appears when multiple inputs compete for the
    // same output (hotspot). This test confirms the zero-
    // contention baseline.
    // --------------------------------------------------------
    task automatic test_single_requester_per_output();
        $display("\n[TEST 2] Single requester per output — all N grants expected");
        apply_reset();
        clear_req();
        for (int i = 0; i < N; i++)
            req[i][i] = 1'b1; // input i wants output i exclusively
        @(posedge clk_i); #1;
        check("single_req: grant count == N", count_grants() == N);
        check("single_req: mutex",            check_mutex());
        check("single_req: grant=>req",       check_grant_implies_req());
        // Verify each input i was granted output i
        for (int i = 0; i < N; i++)
            check($sformatf("single_req: grant[%0d][%0d]", i, i), grant[i][i] == 1'b1);
        clear_req();
    endtask

    // --------------------------------------------------------
    // ========================================================
    //  TEST 3 — All-to-one contention (hotspot)
    //  All N inputs request output port 0 simultaneously.
    //  Only one grant should fire per cycle.
    //  Over N cycles, every input must be granted exactly once
    //  (fairness / pointer rotation).
    // ========================================================
    // Tradeoff note: this is the canonical hotspot stress test.
    // Throughput is 1/N of theoretical maximum — the measurable
    // deficit vs iSLIP documented in the project spec. The
    // rotation check proves starvation-freedom.
    // --------------------------------------------------------
    task automatic test_hotspot_fairness();
        logic [N-1:0] granted_inputs;
        int           grant_count;
        int           winner;
        $display("\n[TEST 3] Hotspot: all inputs → output 0, verify rotation over %0d cycles", N);
        apply_reset();
        granted_inputs = '0;
        grant_count    = 0;

        for (int cycle = 0; cycle < N; cycle++) begin
            clear_req();
            for (int i = 0; i < N; i++)
                req[i][0] = 1'b1; // every input wants output 0
            @(posedge clk_i); #1;

            check($sformatf("hotspot cy%0d: mutex", cycle), check_mutex());
            check($sformatf("hotspot cy%0d: grant=>req", cycle), check_grant_implies_req());
            check($sformatf("hotspot cy%0d: exactly 1 grant", cycle), count_grants() == 1);

            // Record which input was granted
            for (int i = 0; i < N; i++) begin
                if (grant[i][0]) begin
                    check($sformatf("hotspot cy%0d: input %0d not previously granted", cycle, i),
                          !granted_inputs[i]);
                    granted_inputs[i] = 1'b1;
                    grant_count++;
                end
            end
        end
        check("hotspot: all N inputs granted exactly once", grant_count == N);
        check("hotspot: all inputs covered", granted_inputs == {N{1'b1}});
        clear_req();
    endtask

    // --------------------------------------------------------
    // ========================================================
    //  TEST 4 — Mutual exclusion under random-ish contention
    //  Multiple inputs request overlapping output sets.
    //  No output should be granted to two inputs; no input
    //  should receive two grants.
    // ========================================================
    // Tradeoff note: mutual exclusion is the primary safety
    // property — a formal proof target in Phase 4. This
    // directed check gives early confidence before formal runs.
    // --------------------------------------------------------
    task automatic test_mutex_overlapping();
        $display("\n[TEST 4] Mutex under overlapping requests");
        apply_reset();

        // Pattern: inputs 0,1,2 all want output 2
        //          inputs 3,4   want output 4
        //          input  0     also wants output 1 (only requester)
        clear_req();
        req[0][2] = 1; req[0][1] = 1;
        req[1][2] = 1;
        req[2][2] = 1;
        req[3][4] = 1;
        req[4][4] = 1;
        @(posedge clk_i); #1;
        check("overlap: mutex", check_mutex());
        check("overlap: grant=>req", check_grant_implies_req());
        // output 1 has only one requester — must be granted
        check("overlap: uncontested output 1 granted", grant[0][1] == 1'b1);

        // Run several more cycles to verify mutex holds across pointer states
        for (int cy = 0; cy < 4; cy++) begin
            @(posedge clk_i); #1;
            check($sformatf("overlap cy%0d: mutex",      cy+1), check_mutex());
            check($sformatf("overlap cy%0d: grant=>req", cy+1), check_grant_implies_req());
        end
        clear_req();
    endtask

    // --------------------------------------------------------
    // ========================================================
    //  TEST 5 — Pointer persistence across idle cycles
    //  Grant input 0 for output 0, then go idle for 3 cycles,
    //  then re-present all requesters. The pointer should have
    //  NOT advanced during idle cycles, so input 1 should be
    //  next (not input 0 again).
    // ========================================================
    // Tradeoff note: if the pointer advanced on idle cycles it
    // would produce unfair skew — inputs that happen to request
    // during a quiet period would be deprioritized on return.
    // --------------------------------------------------------
    task automatic test_pointer_persistence();
        int first_winner;
        int second_winner;
        $display("\n[TEST 5] Pointer persistence across idle cycles");
        apply_reset();

        // Cycle 0: all inputs request output 0, record winner
        clear_req();
        for (int i = 0; i < N; i++) req[i][0] = 1'b1;
        @(posedge clk_i); #1;
        first_winner = -1;
        for (int i = 0; i < N; i++)
            if (grant[i][0]) first_winner = i;
        check("persist: first grant issued", first_winner != -1);

        // Cycles 1-3: idle — no requests
        for (int cy = 0; cy < 3; cy++) begin
            clear_req();
            @(posedge clk_i); #1;
            check($sformatf("persist idle cy%0d: no grants", cy), count_grants() == 0);
        end

        // Cycle 4: all inputs request output 0 again
        // Expected winner = (first_winner + 1) % N
        for (int i = 0; i < N; i++) req[i][0] = 1'b1;
        @(posedge clk_i); #1;
        second_winner = -1;
        for (int i = 0; i < N; i++)
            if (grant[i][0]) second_winner = i;
        check("persist: second grant issued", second_winner != -1);
        check("persist: pointer advanced by exactly 1",
              second_winner == (first_winner + 1) % N);
        clear_req();
    endtask

    // --------------------------------------------------------
    // ========================================================
    //  TEST 6 — Request drop mid-sequence
    //  Start with all inputs requesting output 0.
    //  After the first grant, one input drops its request.
    //  Verify the remaining inputs are still served fairly
    //  and no grant goes to the dropped requester.
    // ========================================================
    // Tradeoff note: the arbiter must handle sparse request
    // vectors cleanly — the pointer skips non-requesting inputs
    // rather than stalling, which is the correct behavior for
    // a work-conserving allocator.
    // --------------------------------------------------------
    task automatic test_request_drop();
        int first_winner;
        $display("\n[TEST 6] Request drop mid-sequence");
        apply_reset();

        // All request output 0
        clear_req();
        for (int i = 0; i < N; i++) req[i][0] = 1'b1;
        @(posedge clk_i); #1;
        first_winner = -1;
        for (int i = 0; i < N; i++)
            if (grant[i][0]) first_winner = i;
        check("drop: initial grant issued", first_winner != -1);

        // Drop input 'first_winner' — it got what it needed
        req[first_winner][0] = 1'b0;

        // Run remaining N-1 cycles, verify dropped input never re-granted
        for (int cy = 0; cy < N-1; cy++) begin
            @(posedge clk_i); #1;
            check($sformatf("drop cy%0d: mutex",      cy), check_mutex());
            check($sformatf("drop cy%0d: grant=>req", cy), check_grant_implies_req());
            check($sformatf("drop cy%0d: dropped input not re-granted", cy),
                  grant[first_winner][0] == 1'b0);
        end
        clear_req();
    endtask

    // --------------------------------------------------------
    // ========================================================
    //  TEST 7 — Perfect matching (permutation traffic)
    //  Input i requests output (i+1)%N — a rotation permutation.
    //  No two inputs want the same output, so all N grants
    //  should fire simultaneously every cycle.
    // ========================================================
    // Tradeoff note: separable round-robin achieves 100%
    // throughput under permutation traffic because there is no
    // contention — each output arbiter sees exactly one request.
    // This confirms the allocator is not introducing artificial
    // bottlenecks in the zero-contention case.
    // --------------------------------------------------------
    task automatic test_perfect_matching();
        $display("\n[TEST 7] Perfect matching — rotation permutation traffic");
        apply_reset();
        clear_req();
        for (int i = 0; i < N; i++)
            req[i][(i+1)%N] = 1'b1;
        @(posedge clk_i); #1;
        check("permutation: grant count == N", count_grants() == N);
        check("permutation: mutex",            check_mutex());
        check("permutation: grant=>req",       check_grant_implies_req());
        for (int i = 0; i < N; i++)
            check($sformatf("permutation: grant[%0d][%0d]", i, (i+1)%N),
                  grant[i][(i+1)%N] == 1'b1);
        clear_req();
    endtask

    // --------------------------------------------------------
    // ========================================================
    //  TEST 8 — Post-reset state
    //  Immediately after reset with all requests asserted,
    //  input 0 should win (pointer initializes to 0).
    // ========================================================
    // Tradeoff note: reset behavior must be deterministic.
    // The credit counter reset interaction (Phase 1 credit_unit)
    // depends on the arbiter being in a known state at reset
    // deassert — an incorrect reset state here propagates as
    // a subtle bug into the full router pipeline.
    // --------------------------------------------------------
    task automatic test_post_reset_state();
        $display("\n[TEST 8] Post-reset: pointer starts at 0, input 0 wins output 0");
        apply_reset();
        clear_req();
        for (int i = 0; i < N; i++) req[i][0] = 1'b1;
        @(posedge clk_i); #1;
        check("reset: grant[0][0] asserted first", grant[0][0] == 1'b1);
        check("reset: mutex",                      check_mutex());
        clear_req();
    endtask

    // --------------------------------------------------------
    // Main test sequence
    // --------------------------------------------------------
    initial begin
        $dumpfile("allocator_tb.vcd");
        $dumpvars(0, allocator_tb);

        test_no_requests();
        test_single_requester_per_output();
        test_hotspot_fairness();
        test_mutex_overlapping();
        test_pointer_persistence();
        test_request_drop();
        test_perfect_matching();
        test_post_reset_state();

        $display("\n========================================");
        $display("Results: %0d / %0d tests passed", tests_passed, tests_run);
        $display("========================================\n");

        if (tests_passed == tests_run)
            $display("ALL TESTS PASSED");
        else
            $display("FAILURES DETECTED — see FAIL lines above");

        $finish;
    end

endmodule