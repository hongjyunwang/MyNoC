module input_buf
    import noc_pkg::*;
#(
    parameter int BUFFER_DEPTH = 16
)(

    input logic clk_i,
    input logic rst_i,

    // Write
    input logic wr_en_i,
    input flit_t flit_i,
    output logic full_o,

    // Read
    input logic rd_en_i,
    output flit_t flit_o,
    output logic empty_o
);

    localparam PTR_W = $clog2(BUFFER_DEPTH);

    // FIFO storage
    flit_t flit_store [BUFFER_DEPTH];

    // Read/write pointer indices
    logic [PTR_W-1:0] wr_ptr;
    logic [PTR_W-1:0] rd_ptr;
    logic [PTR_W:0] count;

    // Combinational output drive
    assign flit_o = flit_store[rd_ptr];
    assign full_o = (count == (PTR_W+1)'(BUFFER_DEPTH));
    assign empty_o = (count == 0);

    // Gated read/write flags
    logic do_write, do_read;
    assign do_write = wr_en_i && !full_o;
    assign do_read  = rd_en_i && !empty_o;

    // Sequential write and pointer, count update
    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            count <= '0;
        end else begin
            // Write
            if (do_write) begin
                flit_store[wr_ptr] <= flit_i;
                if (wr_ptr == PTR_W'(BUFFER_DEPTH-1))
                    wr_ptr <= '0;
                else
                    wr_ptr <= wr_ptr + 1'b1;
            end

            // Read
            if (do_read) begin
                if (rd_ptr == PTR_W'(BUFFER_DEPTH-1))
                    rd_ptr <= '0;
                else
                    rd_ptr <= rd_ptr + 1'b1;
            end

            // Update occupancy count
            unique case ({do_write, do_read})
                2'b10: count <= count + 1'b1; // write only
                2'b01: count <= count - 1'b1; // read only
                2'b11: count <= count; // simultaneous read/write
                2'b00: count <= count; // no operation
            endcase

        end
    end

endmodule
