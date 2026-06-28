`timescale 1ns/1ps

// router_tb.sv
// Directed self-checking testbench for router.sv
// Router under test: MY_X=1, MY_Y=1 — center of a 4x4 mesh
//
// Compile:
//   iverilog -g2012 -o router_tb \
//     noc_pkg.sv xy_route.sv rr_arb.sv allocator.sv \
//     input_buf.sv credit_unit.sv router.sv router_tb.sv
// Run: vvp router_tb

import noc_pkg::*;

module router_tb;

    localparam int MY_X = 1;
    localparam int MY_Y = 1;
    localparam int BUFFER_DEPTH = 4;
    localparam int N = 5;
    localparam int CLK_HALF = 5;

    localparam int PORT_LOCAL = 0;
    localparam int PORT_W = 1;
    localparam int PORT_E = 2;
    localparam int PORT_S = 3;
    localparam int PORT_N = 4;

    logic  clk_i;
    logic  rst_i;
    flit_t flit_in_i [N];
    logic  flit_in_valid_i [N];
    logic  flit_in_ready_o [N];
    flit_t flit_out_o [N];
    logic  flit_out_valid_o [N];
    logic  credit_in_i [N];
    logic  credit_out_o [N];

    int unsigned DST_X [5];
    int unsigned DST_Y [5];
    int          EXP_P [5];
    string       LABEL [5];
    flit_type_t  exp_types [4];

    router #(
        .MY_X(MY_X),
        .MY_Y(MY_Y),
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .N(N)
    ) dut (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .flit_in_i(flit_in_i),
        .flit_in_valid_i(flit_in_valid_i),
        .flit_in_ready_o(flit_in_ready_o),
        .flit_out_o(flit_out_o),
        .flit_out_valid_o(flit_out_valid_o),
        .credit_in_i(credit_in_i),
        .credit_out_o(credit_out_o)
    );

    initial clk_i = 0;
    always #CLK_HALF clk_i = ~clk_i;

    int tests_run = 0;
    int tests_passed = 0;

    task automatic check(input string name, input logic cond);
        tests_run++;
        if (cond) begin
            tests_passed++;
            $display("  PASS  %s", name);
        end else begin
            $display("  FAIL  %s", name);
        end
    endtask

    task automatic idle_inputs();
        for (int i = 0; i < N; i++) begin
            flit_in_i[i] = '0;
            flit_in_valid_i[i] = 1'b0;
            credit_in_i[i] = 1'b0;
        end
    endtask

    task automatic fill_credits(input int j);
        for (int c = 0; c < BUFFER_DEPTH; c++) begin
            credit_in_i[j] = 1'b1;
            @(posedge clk_i); #1;
            credit_in_i[j] = 1'b0;
        end
    endtask

    task automatic apply_reset();
        rst_i = 1;
        idle_inputs();
        #1;
        @(posedge clk_i); #1;
        @(posedge clk_i); #1;
        rst_i = 0;
        @(posedge clk_i); #1;
    endtask

    function automatic flit_t make_head_tail(
        input logic [X_COORD_W-1:0] dst_x,
        input logic [Y_COORD_W-1:0] dst_y,
        input logic [PACKET_ID_W-1:0] pkt_id
    );
        head_flit_t hf;
        hf = '0;
        hf.flit_type = HEAD_TAIL;
        hf.dst_x = dst_x;
        hf.dst_y = dst_y;
        hf.src_x = X_COORD_W'(MY_X);
        hf.src_y = Y_COORD_W'(MY_Y);
        hf.pkt_id = pkt_id;
        return flit_t'(hf);
    endfunction

    function automatic flit_t make_head(
        input logic [X_COORD_W-1:0] dst_x,
        input logic [Y_COORD_W-1:0] dst_y,
        input logic [PACKET_ID_W-1:0] pkt_id
    );
        head_flit_t hf;
        hf = '0;
        hf.flit_type = HEAD;
        hf.dst_x = dst_x;
        hf.dst_y = dst_y;
        hf.src_x = X_COORD_W'(MY_X);
        hf.src_y = Y_COORD_W'(MY_Y);
        hf.pkt_id = pkt_id;
        return flit_t'(hf);
    endfunction

    function automatic flit_t make_body(input logic [DATA_PAYLOAD_W-1:0] payload);
        data_flit_t df;
        df = '0;
        df.flit_type = BODY;
        df.payload = payload;
        return flit_t'(df);
    endfunction

    function automatic flit_t make_tail(input logic [DATA_PAYLOAD_W-1:0] payload);
        data_flit_t df;
        df = '0;
        df.flit_type = TAIL;
        df.payload = payload;
        return flit_t'(df);
    endfunction

    task automatic inject_flit(input int p, input flit_t f);
        flit_in_i[p] = f;
        flit_in_valid_i[p] = 1'b1;
        @(posedge clk_i); #1;
        while (!flit_in_ready_o[p]) begin
            @(posedge clk_i); #1;
        end
        flit_in_valid_i[p] = 1'b0;
        flit_in_i[p] = '0;
    endtask

    task automatic wait_for_output(
        input  int    j,
        input  int    max_cycles,
        output logic  seen,
        output flit_t captured
    );
        seen = 1'b0;
        captured = '0;
        // check immediately before any clock advance
        if (flit_out_valid_o[j]) begin
            seen = 1'b1;
            captured = flit_out_o[j];
            credit_in_i[j] = 1'b1;
            @(posedge clk_i); #1;
            credit_in_i[j] = 1'b0;
            return;
        end
        for (int cy = 0; cy < max_cycles; cy++) begin
            @(posedge clk_i); #1;
            if (flit_out_valid_o[j]) begin
                seen = 1'b1;
                captured = flit_out_o[j];
                credit_in_i[j] = 1'b1;
                @(posedge clk_i); #1;
                credit_in_i[j] = 1'b0;
                return;
            end
        end
    endtask

    // ----------------------------------------------------------------
    // TEST 1 — HEAD_TAIL to LOCAL port
    // Single-flit packet must not enter ST_ALLOCATED.
    // ----------------------------------------------------------------
    task automatic test_head_tail_local();
        logic  seen;
        flit_t cap;
        $display("\n[TEST 1] HEAD_TAIL -> LOCAL port");
        apply_reset();
        // fill_credits(PORT_LOCAL);
        inject_flit(PORT_N, make_head_tail(X_COORD_W'(MY_X), Y_COORD_W'(MY_Y), 4'h1));
        wait_for_output(PORT_LOCAL, 20, seen, cap);
        check("ht_local: flit received", seen);
        check("ht_local: flit_type==HEAD_TAIL",
              seen && flit_type_t'(cap[FLIT_WIDTH-1 -: 2]) == HEAD_TAIL);
    endtask

    // ----------------------------------------------------------------
    // TEST 2 — HEAD_TAIL to all five output ports
    // Router at (1,1): E=(2,1) W=(0,1) S=(1,2) N=(1,0)
    // ----------------------------------------------------------------
    task automatic test_all_ports();
        logic  seen;
        flit_t cap;
        // int unsigned DST_X [5];
        // int unsigned DST_Y [5];
        // int EXP_P [5];
        // string LABEL [5];
        DST_X[0] = MY_X; DST_X[1] = 2;    DST_X[2] = 0;    DST_X[3] = MY_X; DST_X[4] = MY_X;
        DST_Y[0] = MY_Y; DST_Y[1] = MY_Y; DST_Y[2] = MY_Y; DST_Y[3] = 2;    DST_Y[4] = 0;
        EXP_P[0] = PORT_LOCAL; EXP_P[1] = PORT_E; EXP_P[2] = PORT_W; EXP_P[3] = PORT_S; EXP_P[4] = PORT_N;
        LABEL[0] = "LOCAL"; LABEL[1] = "EAST"; LABEL[2] = "WEST"; LABEL[3] = "SOUTH"; LABEL[4] = "NORTH";

        $display("\n[TEST 2] HEAD_TAIL to all five output ports");
        for (int t = 0; t < 5; t++) begin
            apply_reset();
            // fill_credits(EXP_P[t]);
            inject_flit(PORT_N,
                make_head_tail(X_COORD_W'(DST_X[t]), Y_COORD_W'(DST_Y[t]), 4'h2));
            wait_for_output(EXP_P[t], 20, seen, cap);
            check($sformatf("all_ports: %s received", LABEL[t]), seen);
            check($sformatf("all_ports: %s type==HEAD_TAIL", LABEL[t]),
                  seen && flit_type_t'(cap[FLIT_WIDTH-1 -: 2]) == HEAD_TAIL);
        end
    endtask

    // ----------------------------------------------------------------
    // TEST 3 — Multi-flit: HEAD + BODY + BODY + TAIL
    // Wormhole state machine must hold route without re-arbitrating.
    // ----------------------------------------------------------------
    task automatic test_multiflit_packet();
        logic  seen;
        flit_t cap;
        int    exp_port;
        $display("\n[TEST 3] Multi-flit packet HEAD+BODY+BODY+TAIL");
        apply_reset();
        exp_port = PORT_E;

        // Inject HEAD first, wait for it to appear, then inject body/tail
        inject_flit(PORT_N, make_head(X_COORD_W'(2), Y_COORD_W'(MY_Y), 4'h3));
        wait_for_output(exp_port, 20, seen, cap);
        $display("flit 0: seen=%0b cap=%h type_bits=%02b", seen, cap, cap[FLIT_WIDTH-1 -: 2]);
        check("multiflit: flit 0 received", seen);
        check("multiflit: flit 0 type correct",
            seen && flit_type_t'(cap[FLIT_WIDTH-1 -: 2]) == HEAD);

        // Now inject body/tail one at a time and observe each
        inject_flit(PORT_N, make_body(DATA_PAYLOAD_W'(32'hDEAD_0001)));
        wait_for_output(exp_port, 20, seen, cap);
        $display("flit 1: seen=%0b cap=%h type_bits=%02b", seen, cap, cap[FLIT_WIDTH-1 -: 2]);
        check("multiflit: flit 1 received", seen);
        check("multiflit: flit 1 type correct",
            seen && flit_type_t'(cap[FLIT_WIDTH-1 -: 2]) == BODY);

        inject_flit(PORT_N, make_body(DATA_PAYLOAD_W'(32'hDEAD_0002)));
        wait_for_output(exp_port, 20, seen, cap);
        $display("flit 2: seen=%0b cap=%h type_bits=%02b", seen, cap, cap[FLIT_WIDTH-1 -: 2]);
        check("multiflit: flit 2 received", seen);
        check("multiflit: flit 2 type correct",
            seen && flit_type_t'(cap[FLIT_WIDTH-1 -: 2]) == BODY);

        inject_flit(PORT_N, make_tail(DATA_PAYLOAD_W'(32'hDEAD_0003)));
        wait_for_output(exp_port, 20, seen, cap);
        $display("flit 3: seen=%0b cap=%h type_bits=%02b", seen, cap, cap[FLIT_WIDTH-1 -: 2]);
        check("multiflit: flit 3 received", seen);
        check("multiflit: flit 3 type correct",
            seen && flit_type_t'(cap[FLIT_WIDTH-1 -: 2]) == TAIL);
    endtask

    // ----------------------------------------------------------------
    // TEST 4 — Back-to-back packets on same input port
    // ST_IDLE must restore after tail so second packet can allocate.
    // ----------------------------------------------------------------
    task automatic test_back_to_back();
        logic  seen;
        flit_t cap;
        $display("\n[TEST 4] Back-to-back packets on same input port");
        apply_reset();
        // fill_credits(PORT_E);

        inject_flit(PORT_N, make_head_tail(X_COORD_W'(2), Y_COORD_W'(MY_Y), 4'h4));
        wait_for_output(PORT_E, 20, seen, cap);
        check("b2b: first packet received", seen);

        inject_flit(PORT_N, make_head_tail(X_COORD_W'(2), Y_COORD_W'(MY_Y), 4'h5));
        credit_in_i[PORT_E] = 1'b1; @(posedge clk_i); #1; credit_in_i[PORT_E] = 1'b0;
        wait_for_output(PORT_E, 20, seen, cap);
        check("b2b: second packet received", seen);
        begin
            head_flit_t hf_check;
            hf_check = head_flit_t'(cap);
            check("b2b: second pkt_id correct", seen && hf_check.pkt_id == 4'h5);
        end
    endtask

    // ----------------------------------------------------------------
    // TEST 5 — Credit stall and resume
    // No flit must leave when credit counter is zero.
    // ----------------------------------------------------------------
    task automatic test_credit_stall();
        logic  seen;
        flit_t cap;
        int    stall_cycles;
        $display("\n[TEST 5] Credit stall and resume on PORT_E");
        apply_reset();

        // Drain all 4 credits by sending 4 flits without returning credits
        for (int i = 0; i < BUFFER_DEPTH; i++) begin
            inject_flit(PORT_N, make_head_tail(X_COORD_W'(2), Y_COORD_W'(MY_Y), 4'h0));
            // wait for it to exit but do NOT pulse credit_in_i
            for (int cy = 0; cy < 10; cy++) begin
                if (flit_out_valid_o[PORT_E]) break;
                @(posedge clk_i); #1;
            end
            @(posedge clk_i); #1;
        end

        // Credit counter now at 0 — inject one more flit
        inject_flit(PORT_N, make_head_tail(X_COORD_W'(2), Y_COORD_W'(MY_Y), 4'h6));

        // Verify no output for 10 cycles
        stall_cycles = 0;
        for (int cy = 0; cy < 10; cy++) begin
            if (flit_out_valid_o[PORT_E]) stall_cycles = -1;
            @(posedge clk_i); #1;
        end
        check("stall: no flit sent with zero credits", stall_cycles == 0);

        // Return one credit — router should now send
        credit_in_i[PORT_E] = 1'b1;
        @(posedge clk_i); #1;
        credit_in_i[PORT_E] = 1'b0;
        wait_for_output(PORT_E, 20, seen, cap);
        check("stall: flit sent after credit restored", seen);
    endtask

    // ----------------------------------------------------------------
    // TEST 6 — Parallel forward: two input ports, two output ports
    // Separable allocator must not serialize zero-contention traffic.
    // ----------------------------------------------------------------
    task automatic test_parallel_forward();
        logic  seen_e, seen_s;
        flit_t cap_e, cap_s;
        $display("\n[TEST 6] Parallel forward — two ports, two outputs");
        apply_reset();
        // fill_credits(PORT_E);
        // fill_credits(PORT_S);

        flit_in_i[PORT_N] = make_head_tail(X_COORD_W'(2), Y_COORD_W'(MY_Y), 4'h7);
        flit_in_i[PORT_W] = make_head_tail(X_COORD_W'(MY_X), Y_COORD_W'(2), 4'h8);
        flit_in_valid_i[PORT_N] = 1'b1;
        flit_in_valid_i[PORT_W] = 1'b1;
        @(posedge clk_i); #1;
        flit_in_valid_i[PORT_N] = 1'b0;
        flit_in_valid_i[PORT_W] = 1'b0;

        seen_e = 0; seen_s = 0;
        for (int cy = 0; cy < 20; cy++) begin
            if (flit_out_valid_o[PORT_E] && !seen_e) begin
                seen_e = 1; cap_e = flit_out_o[PORT_E];
            end
            if (flit_out_valid_o[PORT_S] && !seen_s) begin
                seen_s = 1; cap_s = flit_out_o[PORT_S];
            end
            if (seen_e) begin credit_in_i[PORT_E] = 1; end
            if (seen_s) begin credit_in_i[PORT_S] = 1; end
            @(posedge clk_i); #1;
            credit_in_i[PORT_E] = 0;
            credit_in_i[PORT_S] = 0;
            if (seen_e && seen_s) break;
        end
        check("parallel: PORT_E received", seen_e);
        check("parallel: PORT_S received", seen_s);

        begin
            head_flit_t hf_e, hf_s;
            hf_e = head_flit_t'(cap_e);
            hf_s = head_flit_t'(cap_s);
            check("parallel: PORT_E pkt_id==7", seen_e && hf_e.pkt_id == 4'h7);
            check("parallel: PORT_S pkt_id==8", seen_s && hf_s.pkt_id == 4'h8);
        end
    endtask

    initial begin
        rst_i = 1;  // assert reset immediately at t=0
        idle_inputs();
        $dumpfile("router_tb.vcd");
        $dumpvars(0, router_tb);

        test_head_tail_local();
        test_all_ports();
        test_multiflit_packet();
        test_back_to_back();
        test_credit_stall();
        test_parallel_forward();

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