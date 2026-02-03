`timescale 1ns / 1ps
`define CLK_FREQ 100000000   
`define BAUD_RATE 115200      

module LFSR_Generator(
    input clk,
    input rst_n,
    output [7:0] rand_out
);
    reg [7:0] lfsr_reg;
    // x^8 + x^6 + x^5 + x^4 + 1
    wire feedback = lfsr_reg[7] ^ lfsr_reg[5] ^ lfsr_reg[4] ^ lfsr_reg[3];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            lfsr_reg <= 8'hAA; 
        else
            lfsr_reg <= {lfsr_reg[6:0], feedback};
    end
    assign rand_out = lfsr_reg;
endmodule