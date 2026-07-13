`ifndef FLIT_MONITOR_SV
`define FLIT_MONITOR_SV

class flit_monitor extends uvm_monitor;
    `uvm_component_utils(flit_monitor)

    virtual router_if vif;
    uvm_analysis_port #(flit_transaction) ap; // broadcasted analysis port

    // constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual router_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for flit_monitor")
    endfunction

    task run_phase(uvm_phase phase);
        wait(vif.rst_n === 1'b1);
        forever begin
            // sample at positive edge
            @(posedge vif.clk);
            if(vif.flit_out_valid === 1'b1) begin
                flit_transaction t;
                t = unpack_flit(vif.flit_out);
                ap.write(t);
            end
        end
    endtask

    // Convert the signals received from the DUT to transaction objects for the UVM
    function flit_transaction unpack_flit(flit_t word);
        flit_transaction t;
        head_flit_t h;
        data_flit_t d;

        t = flit_transaction::type_id::create("t");

        // extract type from top 2 bits to decide layout
        if(word[63:62] == HEAD || word[63:62] == HEAD_TAIL) begin
            h = head_flit_t'(word);
            t.flit_type = h.flit_type;
            t.dst_x = h.dst_x;
            t.dst_y = h.dst_y;
            t.src_x = h.src_x;
            t.src_y = h.src_y;
            t.vc_id = h.vc_id;
            t.pkt_id = h.pkt_id;
            t.payload = h.payload;
        end
        else begin
            d = data_flit_t'(word);
            t.flit_type = d.flit_type;
            t.vc_id = d.vc_id;
            t.payload = d.payload[HEAD_PAYLOAD_W-1:0];
        end
        return t;
    endfunction

endclass

`endif