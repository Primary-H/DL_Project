`timescale 1ns / 1ps

module Seven_Seg_Driver(
    input [2:0] op_mode,   // 运算模式
    input enable,          // 使能
    input rst_n,           // 复位信号，低有效
    output reg [7:0] an    // 位选
);
    
    always @* begin
        if (enable) begin
            case(op_mode)
                // 'A'
                3'd1: an = 8'b11101110; 
                // 'c'
                3'd2: an = 8'b10011100; 
                // 'S'
                3'd3: an = 8'b10110110; 
                // 't'
                3'd4: an = 8'b00011110; 
                //'F'
                3'd5: an = 8'b10001110; 
                default: an = 8'h00; // 全灭    
            endcase
        end else begin
            an = 0; 
        end
    end
endmodule