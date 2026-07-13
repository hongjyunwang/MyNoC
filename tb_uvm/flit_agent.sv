`ifndef FLIT_AGENT_SV
`define FLIT_AGENT_SV

class flit_agent extends uvm_agent;
    `uvm_component_utils(flit_agent)

    flit_driver driver;
    flit_monitor monitor;
    flit_sequencer sequencer;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    // Create the children components: driver, monitor, and sequencer
    // Using the factory
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        driver = flit_driver::type_id::create("driver", this);
        monitor = flit_monitor::type_id::create("monitor", this);
        sequencer = flit_sequencer::type_id::create("sequencer", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        // connects the driver's seq_item_port to the sequencer's seq_item_export
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass

`endif