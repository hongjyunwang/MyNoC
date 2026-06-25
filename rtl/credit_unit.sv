// Keeps track of the credit for each output port

module credit_unit
    import noc_pkg::*;
#(
    parameter int BUFFER_DEPTH = 16
)(
    input logic clk_i,
    input logic rst_i,

    input logic credit_decr_i, // signal to decrease credit
    input logic credit_incr_i, // signal to increase credit

    output logic has_credit_o, // signals whether there is credit to use
    output logic [$clog2(BUFFER_DEPTH):0] count_o // outputs current credit count
);

    localparam int CTR_W = $clog2(BUFFER_DEPTH) + 1;

    logic [CTR_W-1:0] count_r;

    always_ff @(posedge clk_i or posedge rst_i) begin
        if (rst_i) begin
            count_r <= CTR_W'(BUFFER_DEPTH);
        end else begin
            unique case ({credit_incr_i, credit_decr_i})
                2'b00: count_r <= count_r; // no change
                2'b01: count_r <= count_r - 1'b1;
                2'b10: count_r <= count_r + 1'b1;
                2'b11: count_r <= count_r; // no change
            endcase
        end
    end

    assign has_credit_o = (count_r > '0);
    assign count_o = count_r;

    // synthesis translate_off
    always_ff @(posedge clk_i) begin
        if (!rst_i) begin
            if (credit_decr_i && !credit_incr_i && count_r == '0)
                $fatal(1, "credit_unit: underflow");
            if (credit_incr_i && !credit_decr_i && count_r == CTR_W'(BUFFER_DEPTH))
                $fatal(1, "credit_unit: overflow — BUFFER_DEPTH=%0d", BUFFER_DEPTH);
        end
    end
    // synthesis translate_on

endmodule