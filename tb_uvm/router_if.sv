`ifndef ROUTER_IF_SV
`define ROUTER_IF_SV

import noc_pkg::*;

// virtual interface
interface router_if(input logic clk, input logic rst_n);
    // input side — driver drives valid+flit, observes ready
    flit_t flit_in;
    logic flit_in_valid;
    logic flit_in_ready;

    // output side — monitor observes
    flit_t flit_out;
    logic flit_out_valid;

    // credit
    logic credit_in;
    logic credit_out;
endinterface

`endif
