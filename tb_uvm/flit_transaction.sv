// Data object that flows through your entire UVM environment
// one single class for all flit types

`ifndef FLIT_TRANSACTION_SV
`define FLIT_TRANSACTION_SV

class flit_transaction extends uvm_sequence_item;
    `uvm_object_utils_begin(flit_transaction)
        `uvm_field_enum(flit_type_t, flit_type, UVM_ALL_ON)
        `uvm_field_int(dst_x, UVM_ALL_ON)
        `uvm_field_int(dst_y, UVM_ALL_ON)
        `uvm_field_int(src_x, UVM_ALL_ON)
        `uvm_field_int(src_y, UVM_ALL_ON)
        `uvm_field_int(vc_id, UVM_ALL_ON)
        `uvm_field_int(pkt_id, UVM_ALL_ON)
        `uvm_field_int(payload, UVM_ALL_ON)
    `uvm_object_utils_end

    // sequence controls these — not rand
    flit_type_t flit_type;
    logic [X_COORD_W-1:0] dst_x;
    logic [Y_COORD_W-1:0] dst_y;
    logic [X_COORD_W-1:0] src_x;
    logic [Y_COORD_W-1:0] src_y;
    logic [VC_ID_W-1:0] vc_id;
    logic [PACKET_ID_W-1:0] pkt_id;

    // varies per flit — rand
    rand logic [HEAD_PAYLOAD_W-1:0] payload;

    // constructor
    function new(string name = "flit_transaction");
        super.new(name);
    endfunction

endclass

`endif