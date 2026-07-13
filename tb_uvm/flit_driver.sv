`ifndef FLIT_DRIVER_SV
`define FLIT_DRIVER_SV

import noc_pkg::*;

class flit_driver extends uvm_driver #(flit_transaction);
    `uvm_component_utils(flit_driver)

    // instantiate virtual interface
    virtual router_if vif;

    // constructor
    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // Build phase
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if(!uvm_config_db#(virtual router_if)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "virtual interface not set for flit_driver")
    endfunction

    // Run phase
    task run_phase(uvm_phase phase);
        // initialize driver outputs (idle inputs into the DUT)
        vif.flit_in = '0;
        vif.flit_in_valid = 1'b0;
        wait(vif.rst_n === 1'b1); // wait for reset to fininsh

        forever begin
            flit_transaction t; 
            seq_item_port.get_next_item(t); // t will point to the next flit_transaction provided by the sequencer.
            drive_flit(t);
            // Note that the driver does not catch the inputted packet. It just inputs it into the router
            seq_item_port.item_done();
        end
    endtask

    // This task takes one transaction and drives it onto the router's pin-level interface.
    task drive_flit(flit_transaction t);
        flit_t word;
        word = pack_flit(t);

        // drive DUT wires at negative clock edge
        @(negedge vif.clk);
        vif.flit_in = word;
        vif.flit_in_valid = 1'b1;
        
        // Hold the flit input until the DUT accepts it (handshake)
        do @(negedge vif.clk); while(vif.flit_in_ready !== 1'b1);

        vif.flit_in_valid = 1'b0;
        vif.flit_in = '0;
    endtask

    // This function converts a transaction object into a packed flit_t.
    // think of it as taking a UVM transaction object into a flit that the DUT understands
    function flit_t pack_flit(flit_transaction t);
        // constructs DUT understands
        head_flit_t h;
        data_flit_t d;

        // Map transaction fields to wires for DUT
        if(t.flit_type == HEAD || t.flit_type == HEAD_TAIL) begin
            h.flit_type = t.flit_type;
            h.dst_x = t.dst_x;
            h.dst_y = t.dst_y;
            h.src_x = t.src_x;
            h.src_y = t.src_y;
            h.vc_id = t.vc_id;
            h.pkt_id = t.pkt_id;
            h.payload = t.payload[HEAD_PAYLOAD_W-1:0];
            return flit_t'(h);
        end
        else begin
            d.flit_type = t.flit_type;
            d.vc_id = t.vc_id;
            d.payload = t.payload;
            return flit_t'(d);
        end
    endfunction

endclass

`endif