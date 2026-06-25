`timescale 1ns/1ps

// credit_unit_tb.sv
// Compile: iverilog -g2012 -o credit_unit_tb noc_pkg.sv credit_unit.sv credit_unit_tb.sv
// Run:     vvp credit_unit_tb

import noc_pkg::*;

module credit_unit_tb;

    localparam int BUFFER_DEPTH = 8;
    localparam int CTR_W = $clog2(BUFFER_DEPTH) + 1;
    localparam int CLK_HALF = 5;

    logic clk_i;
    logic rst_i;
    logic credit_decr_i;
    logic credit_incr_i;
    logic has_credit_o;
    logic [CTR_W-1:0] count_o;

    credit_unit #(.BUFFER_DEPTH(BUFFER_DEPTH)) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .credit_decr_i(credit_decr_i),
        .credit_incr_i(credit_incr_i),
        .has_credit_o(has_credit_o),
        .count_o(count_o)
    );

    initial clk_i = 0;
    always #CLK_HALF clk_i = ~clk_i;

    int tests_run = 0;
    int tests_passed = 0;

    task automatic apply_reset();
        rst_i = 1;
        credit_decr_i = 0;
        credit_incr_i = 0;
        @(posedge clk_i); #1;
        @(posedge clk_i); #1;
        rst_i = 0;
        @(posedge clk_i); #1;
    endtask

    task automatic check(input string name, input logic cond);
        tests_run++;
        if (cond) begin
            tests_passed++;
            $display("  PASS  %s", name);
        end else begin
            $display("  FAIL  %s  (count=%0d)", name, count_o);
        end
    endtask

    // --------------------------------------------------------
    // TEST 1 — Reset initializes counter to BUFFER_DEPTH
    // --------------------------------------------------------
    task automatic test_reset();
        $display("\n[TEST 1] Reset initializes to BUFFER_DEPTH");
        apply_reset();
        check("reset: count == BUFFER_DEPTH", count_o == CTR_W'(BUFFER_DEPTH));
        check("reset: has_credit high",       has_credit_o == 1'b1);
    endtask

    // --------------------------------------------------------
    // TEST 2 — Decrement: drain counter one flit at a time
    // --------------------------------------------------------
    task automatic test_decrement();
        $display("\n[TEST 2] Decrement — drain to zero");
        apply_reset();
        for (int i = BUFFER_DEPTH; i > 0; i--) begin
            credit_decr_i = 1;
            @(posedge clk_i); #1;
            credit_decr_i = 0;
            check($sformatf("decr: count==%0d", i-1), count_o == CTR_W'(i-1));
        end
        check("decr: has_credit low at zero", has_credit_o == 1'b0);
    endtask

    // --------------------------------------------------------
    // TEST 3 — Increment: refill from zero back to BUFFER_DEPTH
    // --------------------------------------------------------
    task automatic test_increment();
        $display("\n[TEST 3] Increment — refill from zero");
        apply_reset();
        // Drain first
        for (int i = 0; i < BUFFER_DEPTH; i++) begin
            credit_decr_i = 1; @(posedge clk_i); #1; credit_decr_i = 0;
        end
        check("incr setup: count at zero", count_o == '0);
        // Refill
        for (int i = 0; i < BUFFER_DEPTH; i++) begin
            credit_incr_i = 1;
            @(posedge clk_i); #1;
            credit_incr_i = 0;
            check($sformatf("incr: count==%0d", i+1), count_o == CTR_W'(i+1));
        end
        check("incr: has_credit high at full", has_credit_o == 1'b1);
    endtask

    // --------------------------------------------------------
    // TEST 4 — Simultaneous incr+decr is a net no-op
    // --------------------------------------------------------
    task automatic test_simultaneous();
        $display("\n[TEST 4] Simultaneous incr+decr — net no-op");
        apply_reset();
        // Drain to a mid-point first
        for (int i = 0; i < 4; i++) begin
            credit_decr_i = 1; @(posedge clk_i); #1; credit_decr_i = 0;
        end
        check("simul setup: count==4", count_o == CTR_W'(4));

        // Now assert both simultaneously for 3 cycles — count must not change
        for (int cy = 0; cy < 3; cy++) begin
            credit_decr_i = 1;
            credit_incr_i = 1;
            @(posedge clk_i); #1;
            credit_decr_i = 0;
            credit_incr_i = 0;
            check($sformatf("simul cy%0d: count still 4", cy), count_o == CTR_W'(4));
        end
    endtask

    // --------------------------------------------------------
    // TEST 5 — has_credit deasserts exactly at zero
    // --------------------------------------------------------
    task automatic test_has_credit_boundary();
        $display("\n[TEST 5] has_credit boundary at zero");
        apply_reset();
        for (int i = BUFFER_DEPTH; i > 1; i--) begin
            credit_decr_i = 1; @(posedge clk_i); #1; credit_decr_i = 0;
        end
        check("boundary: has_credit high at count==1", has_credit_o == 1'b1);
        credit_decr_i = 1; @(posedge clk_i); #1; credit_decr_i = 0;
        check("boundary: has_credit low at count==0",  has_credit_o == 1'b0);
        check("boundary: count==0",                    count_o == '0);
        // One credit back — should re-assert
        credit_incr_i = 1; @(posedge clk_i); #1; credit_incr_i = 0;
        check("boundary: has_credit high again at 1",  has_credit_o == 1'b1);
    endtask

    // --------------------------------------------------------
    // TEST 6 — Idle cycles do not change counter
    // --------------------------------------------------------
    task automatic test_idle();
        $display("\n[TEST 6] Idle — counter holds");
        apply_reset();
        for (int i = 0; i < 3; i++) begin
            credit_decr_i = 1; @(posedge clk_i); #1; credit_decr_i = 0;
        end
        check("idle setup: count==5", count_o == CTR_W'(BUFFER_DEPTH - 3));
        for (int cy = 0; cy < 5; cy++) begin
            @(posedge clk_i); #1;
            check($sformatf("idle cy%0d: count unchanged", cy),
                  count_o == CTR_W'(BUFFER_DEPTH - 3));
        end
    endtask

    initial begin
        $dumpfile("credit_unit_tb.vcd");
        $dumpvars(0, credit_unit_tb);

        test_reset();
        test_decrement();
        test_increment();
        test_simultaneous();
        test_has_credit_boundary();
        test_idle();

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