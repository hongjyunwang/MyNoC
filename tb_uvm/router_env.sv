`ifndef ROUTER_ENV_SV
`define ROUTER_ENV_SV

class router_env extends uvm_env;
    `uvm_component_utils(router_env)

    flit_agent agent;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        // factory pattern to instantiate the agent
        super.build_phase(phase);
        agent = flit_agent::type_id::create("agent", this);
    endfunction

endclass

`endif