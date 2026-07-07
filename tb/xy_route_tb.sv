// tb_xy_route.sv
// Exhaustive directed self-checking testbench for xy_route.sv
// Tests all 256 (dst_x, dst_y) combinations across all 16 router positions
// in a 4x4 mesh via a generate block.
//
// Verification goals:
//   1. Correctness    — port_sel matches expected XY routing decision
//   2. Exclusivity    — exactly one bit of port_sel is set per valid input
//   3. XY ordering    — X dimension resolved before Y (structural check via oracle)
//   4. Local delivery — dst == my coordinates always produces PORT_LOCAL

`timescale 1ns/1ps
import noc_pkg::*;

module tb_xy_route;

    localparam int MESH_X = MESH_DIM_X; // 4
    localparam int MESH_Y = MESH_DIM_Y; // 4
    localparam int CW_X = X_COORD_W; // $clog2(4) = 2
    localparam int CW_Y = Y_COORD_W;

    localparam int PORT_N = 4;
    localparam int PORT_S = 3;
    localparam int PORT_E = 2;
    localparam int PORT_W = 1;
    localparam int PORT_LOCAL = 0;

    // -------------------------------------------------------------------------
    // Global test counters (shared across all generate instances)
    // -------------------------------------------------------------------------
    int total_pass = 0;
    int total_fail = 0;

    // -------------------------------------------------------------------------
    // Expected routing results
    // Mirrors the XY routing logic in xy_route.sv exactly.
    // -------------------------------------------------------------------------
    function automatic logic [4:0] expected_port(
        input int mx, input int my, // router coord
        input int dx, input int dy // destination coord
    );
        logic [4:0] p;
        p = 5'b0;
        if (dx > mx) p[PORT_E] = 1'b1;
        else if (dx < mx) p[PORT_W] = 1'b1;
        else if (dy > my) p[PORT_S] = 1'b1;
        else if (dy < my) p[PORT_N] = 1'b1;
        else p[PORT_LOCAL] = 1'b1;
        return p;
    endfunction

    // -------------------------------------------------------------------------
    // Shared checker task
    // Called from every generate instance after applying stimulus.
    // Checks correctness, exclusivity, and XY ordering simultaneously.
    // -------------------------------------------------------------------------
    task automatic check(
        input int mx,
        input int my,
        input int dx,
        input int dy,
        input logic [4:0] actual
    );
        logic [4:0] exp;
        int bit_count;

        // calculate correct value
        exp = expected_port(mx, my, dx, dy);

        // --- Correctness check ---
        if (actual !== exp) begin
            $error("[FAIL] Router(%0d,%0d) dst(%0d,%0d): got port_sel=%05b, expected=%05b",
                   mx, my, dx, dy, actual, exp);
            total_fail++;
        end else begin
            total_pass++;
        end

        // --- Exclusivity check: exactly one bit must be set ---
        bit_count = 0;
        for (int i = 0; i < 5; i++) bit_count += actual[i];
        if (bit_count !== 1) begin
            $error("[FAIL] Exclusivity violated: Router(%0d,%0d) dst(%0d,%0d) port_sel=%05b has %0d bits set",
                   mx, my, dx, dy, actual, bit_count);
            total_fail++;
        end

        // --- XY ordering check ---
        // Y routing only activates when dst_x == my_x — the core of the deadlock freedom argument.
        if ((dx != mx) && (actual[PORT_N] || actual[PORT_S])) begin
            $error("[FAIL] XY order violated: Router(%0d,%0d) dst(%0d,%0d) routed N/S before X resolved",
                   mx, my, dx, dy);
            total_fail++;
        end

        // --- Local delivery check ---
        // When coordinates match exactly, Local must be selected.
        if ((dx == mx) && (dy == my) && !actual[PORT_LOCAL]) begin
            $error("[FAIL] Local delivery missed: Router(%0d,%0d) dst(%0d,%0d) port_sel=%05b",
                   mx, my, dx, dy, actual);
            total_fail++;
        end

    endtask

    // -------------------------------------------------------------------------
    // Generate block — instantiates one DUT per router position
    // Each instance drives all (dst_x, dst_y) combinations and calls check().
    //
    // Tradeoff: 16 parallel instances vs. a single reconfigurable instance.
    // Parallel instantiation reflects real synthesis — each router is unique
    // silicon with different parameter values. It also lets Verilator check
    // each parameter combination independently during lint.
    // -------------------------------------------------------------------------
    genvar gx, gy;
    generate
        for (gx = 0; gx < MESH_X; gx++) begin : gen_x
            for (gy = 0; gy < MESH_Y; gy++) begin : gen_y

                // Per-instance stimulus signals
                logic [CW_X-1:0] dst_x;
                logic [CW_Y-1:0] dst_y;
                logic [4:0] port_sel;

                // DUT instantiation — MY_X and MY_Y baked in per instance
                xy_route #(
                    .MY_X(gx),
                    .MY_Y(gy)
                ) dut (
                    .dst_x(dst_x),
                    .dst_y(dst_y),
                    .port_sel(port_sel)
                );

                // Per-instance stimulus process
                // Exhaustively sweeps all dst combinations, then calls checker
                initial begin
                    // Small stagger so waveform is readable per-instance
                    #(gx * MESH_Y + gy);

                    for (int dx = 0; dx < MESH_X; dx++) begin
                        for (int dy = 0; dy < MESH_Y; dy++) begin
                            dst_x = CW_X'(dx);
                            dst_y = CW_Y'(dy);
                            #1; // one time unit for combinational logic to settle
                            check(gx, gy, dx, dy, port_sel);
                        end
                    end
                end

            end : gen_y
        end : gen_x
    endgenerate

    // -------------------------------------------------------------------------
    // Termination — wait for all instances to finish, then report
    //
    // The wait time must exceed the longest possible instance runtime.
    // Each instance runs MESH_X * MESH_Y * 1ns = 16ns of stimulus,
    // plus its stagger offset (max 15ns). 64ns gives comfortable margin.
    // -------------------------------------------------------------------------
    initial begin
        #200;
        $display("========================================");
        $display("xy_route testbench complete");
        $display("PASS: %0d  FAIL: %0d  TOTAL: %0d",
                 total_pass, total_fail, total_pass + total_fail);
        if (total_fail == 0)
            $display("ALL TESTS PASSED");
        else
            $display("FAILURES DETECTED — review $error messages above");
        $display("========================================");
        $finish;
    end

    initial begin
        $dumpfile("tb_xy_route.vcd");
        $dumpvars(0, tb_xy_route);
    end

endmodule
