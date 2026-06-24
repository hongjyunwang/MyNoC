// Routing computation unit
// Given a destination coordinate, which output port direction should this packet go?
// purely combinational
// xy_route.sv
// Purely combinational XY dimension-ordered routing unit

module xy_route 
    import noc_pkg::*;
#(
    parameter int MY_X = 0, // this router's X coordinate
    parameter int MY_Y = 0 // this router's Y coordinate
)(
    input logic [X_COORD_W-1:0] dst_x, // destination X from head flit
    input logic [Y_COORD_W-1:0] dst_y, // destination Y from head flit

    output logic [4:0] port_sel // one-hot: [N, S, E, W, Local]
);

// Port index constants — use these everywhere, never raw bit positions.
// Changing the mapping here propagates automatically to all downstream logic.
localparam int PORT_N = 4; // North (bit 4)
localparam int PORT_S = 3; // South 
localparam int PORT_E = 2; // East 
localparam int PORT_W = 1; // West 
localparam int PORT_LOCAL = 0; // Local

always_comb begin
    // Default: no port selected.
    // Body and tail flits do not invoke this module's output —
    // the router top level holds the route established by the head flit.
    // Defaulting to zero makes undriven cases visible in simulation
    // rather than propagating X.
    port_sel = 5'b0;

    // X dimension first — resolve horizontal distance before vertical.
    // This is the XY routing rule. Violating this order breaks the
    // deadlock freedom proof: if you allow Y-first under any condition,
    // cyclic channel dependencies become possible.

    if (dst_x > MY_X) begin
        // move East
        port_sel[PORT_E] = 1'b1;

    end else if (dst_x < MY_X) begin
        // move West
        port_sel[PORT_W] = 1'b1;

    end else begin
        // Only enter Y routing once X is fully resolved

        if (dst_y > MY_Y) begin
            // South
            port_sel[PORT_S] = 1'b1;

        end else if (dst_y < MY_Y) begin
            // North
            port_sel[PORT_N] = 1'b1;

        end else begin
            // Local
            port_sel[PORT_LOCAL] = 1'b1;

        end
    end
end

// Elaboration-time sanity checks.
// These fire during compilation, not simulation — they catch
// misconfigured instantiations before you waste simulation time.
initial begin
    assert (MY_X < MESH_DIM_X)
        else $fatal(1, "xy_route: MY_X=%0d out of range for MESH_DIM_X=%0d", MY_X, MESH_DIM_X);
    assert (MY_Y < MESH_DIM_Y)
        else $fatal(1, "xy_route: MY_Y=%0d out of range for MESH_DIM_Y=%0d", MY_Y, MESH_DIM_Y);
end

endmodule