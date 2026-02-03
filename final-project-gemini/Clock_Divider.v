`timescale 1ns / 1ps

module Clock_Divider(
    input  clk_in,      // 输入 100MHz
    input  rst_n,
    output reg clk_out  // 输出 50MHz
);

    // 简单的二分频：每逢上升沿翻转一次
    // 注意：在实际工程中，建议使用 FPGA 的原语 (如 Xilinx BUFG) 来驱动 clk_out，
    // 但对于 50MHz 的低速设计，直接输出通常也能工作。
    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) 
            clk_out <= 1'b0;
        else 
            clk_out <= ~clk_out;
    end

endmodule