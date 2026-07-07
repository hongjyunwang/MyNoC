`timescale 1ns/1ps

module hello_uvm_tb;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // hello_test is a kind of uvm_test
    class hello_test extends uvm_test;
        // Register hello_test with the UVM factory so UVM can create it by name
        `uvm_component_utils(hello_test)

        // Constructor
        function new(string name = "hello_test", uvm_component parent = null);
            super.new(name, parent); // constructor of the parent class
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this); // start time consuming activity, do not end run_phase

            `uvm_info("HELLO", "UVM is running", UVM_LOW)

            #10;

            phase.drop_objection(this); // end time consuming activity, can end run_phase
        endtask
    endclass

    initial begin
        // run test by name because we registered it
        run_test("hello_test");
    end
endmodule
