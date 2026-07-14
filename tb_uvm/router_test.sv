`ifndef ROUTER_TEST_SV
`define ROUTER_TEST_SV

class router_test extends uvm_test;
    `uvm_component_utils(router_test)

    router_env env;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = router_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        flit_sequence seq;

        phase.raise_objection(this);

        seq = flit_sequence::type_id::create("seq");
        assert(seq.randomize());
        seq.start(env.agent.sequencer);

        phase.drop_objection(this);
    endtask

endclass

`endif