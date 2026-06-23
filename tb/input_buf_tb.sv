`timescale 1ns/1ps

module input_buf_tb;
    import noc_pkg::*;

    localparam int CLK_PERIOD = 10;

    logic clk;
    logic rst;

    // Generate clock
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    task automatic do_reset();
        rst = 1;
        repeat(2) @(posedge clk);
        #1; // slight skew so we're sampling after the edge
        rst = 0;
        @(posedge clk); #1;
    endtask

    // ================ DUT ================
    logic wr_en;
    flit_t flit_input;
    logic full;
    logic rd_en;
    flit_t flit_output;
    logic empty;

    input_buf #(
        .BUFFER_DEPTH(16)
    ) dut (
        .clk_i(clk),
        .rst_i(rst),

        // Write
        .wr_en_i(wr_en),
        .flit_i(flit_input),
        .full_o(full),

        // Read
        .rd_en_i(rd_en),
        .flit_o(flit_output),
        .empty_o(empty)
    );

    // ================ Tasks ================
    // Drive all inputs to idle values
    task automatic idle_inputs();
        wr_en = 1'b0;
        rd_en = 1'b0;
        flit_input = '0;
    endtask

    // Push
    task automatic push_entry(
        input flit_t flit
    );
        // Wait until FIFO has space
        while (full) begin
            @(posedge clk); #1;
        end

        // Drive write for one cycle
        wr_en = 1'b1;
        rd_en = 1'b0;
        flit_input = flit;

        @(posedge clk); #1;

        // Return to idle
        wr_en = 1'b0;
        flit_input = '0;
    endtask

    // Pop
    task automatic pop_entry(
        output flit_t flit
    );
        // Wait until FIFO has data
        while (empty) begin
            @(posedge clk); #1;
        end

        flit = flit_output;
        rd_en = 1'b1;
        wr_en = 1'b0;

        @(posedge clk); #1;

        // Return to idle
        rd_en = 1'b0;
    endtask

    // Push one flit and pop one flit in the same cycle
    task automatic push_pop_same_cycle(
        input flit_t push_flit,
        output flit_t pop_flit
    );
        // For simultaneous read/write, FIFO must already contain data
        while (empty || full) begin
            @(posedge clk); #1;
        end

        // Sample current output before read pointer advances
        pop_flit = flit_output;

        wr_en = 1'b1;
        rd_en = 1'b1;
        flit_input = push_flit;

        @(posedge clk); #1;

        wr_en = 1'b0;
        rd_en = 1'b0;
        flit_input = '0;
    endtask

    // Check current empty/full flags
    task automatic check_flags(
        input logic exp_empty,
        input logic exp_full
    );
        if (empty !== exp_empty) begin
            $error("EMPTY mismatch: expected %0b, got %0b at time %0t", exp_empty, empty, $time);
        end

        if (full !== exp_full) begin
            $error("FULL mismatch: expected %0b, got %0b at time %0t", exp_full, full, $time);
        end
    endtask

    // Pop and compare against expected value
    task automatic expect_pop(
        input flit_t expected_flit
    );
        flit_t got_flit;
        pop_entry(got_flit);
        if (got_flit !== expected_flit) begin
            $error("FIFO ordering mismatch: expected 0x%0h, got 0x%0h at time %0t", expected_flit, got_flit, $time);
        end
    endtask

    // ================ Main Test Sequence ================

    int test_num;
    flit_t popped;

    initial begin
        $dumpfile("input_buf_tb.vcd");
        $dumpvars(0, input_buf_tb);

        idle_inputs();
        do_reset();

        // ============================================================
        // TEST 1: Basic push and pop
        // ============================================================
        test_num = 1;
        $display("\n=== TEST %0d: Basic push and pop ===", test_num);

        check_flags(1'b1, 1'b0); // empty=1, full=0 after reset

        push_entry(64'h0000_0000_0000_00A0);

        check_flags(1'b0, 1'b0); // empty=0, full=0 after one push

        expect_pop(64'h0000_0000_0000_00A0);

        check_flags(1'b1, 1'b0); // empty=1, full=0 after pop

        $display("T%0d PASS", test_num);

        do_reset();

        // ============================================================
        // TEST 2: FIFO Ordering
        // ============================================================
        test_num = 2;
        $display("\n=== TEST %0d: FIFO ordering ===", test_num);

        push_entry(64'h1111);
        push_entry(64'h2222);
        push_entry(64'h3333);
        push_entry(64'h4444);

        expect_pop(64'h1111);
        expect_pop(64'h2222);
        expect_pop(64'h3333);
        expect_pop(64'h4444);

        check_flags(1'b1, 1'b0);

        $display("T%0d PASS", test_num);

        do_reset();

        // ============================================================
        // TEST 3: Full flag and back-pressure
        // ============================================================
        test_num = 3;
        $display("\n=== TEST %0d: Full flag and back-pressure ===", test_num);

        for (int i = 0; i < 16; i++) begin
            push_entry(64'h1000 + i);
        end

        check_flags(1'b0, 1'b1); // empty=0, full=1

        // Try to write while full. This should NOT change FIFO contents.
        wr_en = 1'b1;
        rd_en = 1'b0;
        flit_input = 64'hDEAD_BEEF_DEAD_BEEF;

        @(posedge clk); #1;

        wr_en = 1'b0;
        flit_input = '0;

        check_flags(1'b0, 1'b1);

        // Original 16 entries should still come out in order.
        for (int i = 0; i < 16; i++) begin
            expect_pop(64'h1000 + i);
        end

        check_flags(1'b1, 1'b0);

        $display("T%0d PASS", test_num);

        do_reset();

        // ============================================================
        // TEST 4: Simultaneous read/write
        // ============================================================
        test_num = 4;
        $display("\n=== TEST %0d: Simultaneous read/write ===", test_num);

        push_entry(64'hAAAA);
        push_entry(64'hBBBB);

        push_pop_same_cycle(64'hCCCC, popped);

        assert (popped === 64'hAAAA)
            else $fatal(1, "T%0d: simultaneous RW popped wrong value. got=0x%0h exp=0x%0h",
                        test_num, popped, 64'hAAAA);

        expect_pop(64'hBBBB);
        expect_pop(64'hCCCC);

        check_flags(1'b1, 1'b0);

        $display("T%0d PASS", test_num);

        do_reset();

        // ============================================================
        // TEST 5: Wraparound
        // ============================================================
        test_num = 5;
        $display("\n=== TEST %0d: Wraparound ===", test_num);

        // Fill FIFO
        for (int i = 0; i < 16; i++) begin
            push_entry(64'h2000 + i);
        end

        check_flags(1'b0, 1'b1);

        // Pop half
        for (int i = 0; i < 8; i++) begin
            expect_pop(64'h2000 + i);
        end

        check_flags(1'b0, 1'b0);

        // Push 8 more, forcing write pointer to wrap
        for (int i = 0; i < 8; i++) begin
            push_entry(64'h3000 + i);
        end

        check_flags(1'b0, 1'b1);

        // Pop remaining old entries
        for (int i = 8; i < 16; i++) begin
            expect_pop(64'h2000 + i);
        end

        // Pop wrapped new entries
        for (int i = 0; i < 8; i++) begin
            expect_pop(64'h3000 + i);
        end

        check_flags(1'b1, 1'b0);

        $display("T%0d PASS", test_num);

        $display("\nAll FIFO tests passed!");
        $finish;
    end

endmodule
