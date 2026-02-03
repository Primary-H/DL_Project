`timescale 1ns / 1ps
`define CLK_FREQ 100000000   // 100MHz 时钟
`define BAUD_RATE 115200   

// 标准 UART 模块 (RX/TX) - 修复版
module UART_Driver #(parameter CLK_FREQ=100000000, parameter BAUD_RATE=115200) (
    input clk, rst_n,
    input rx_pin, output tx_pin,
    output reg [7:0] rx_data, output reg rx_done,
    input [7:0] tx_data, input tx_start, output tx_busy
);
    localparam B_CNT = CLK_FREQ / BAUD_RATE;
    
    reg [15:0] cnt_rx; // 专门给 RX 用
    reg [15:0] cnt_tx; // 专门给 TX 用
    
    reg [3:0] state_rx, bit_rx;
    reg [3:0] state_tx, bit_tx;
    reg rx_sync, rx_reg;
    reg [9:0] shift_tx;


    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rx_sync <= 1'b1; // 空闲状态为高电平
            rx_reg  <= 1'b1;
        end else begin
            rx_sync <= rx_pin; // 第一级同步
            rx_reg  <= rx_sync;// 第二级同步（实际使用的信号）
        end
    end
    // RX Logic
    // ---------------- RX Logic 修复版 ----------------
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin 
            state_rx <= 0;
            rx_done <= 0; 
            cnt_rx <= 0;
        end else begin
            rx_done <= 0; // 默认拉低
            case(state_rx)
                // 0: IDLE - 检测起始位下降沿
                0: begin
                    if(!rx_reg) begin 
                        state_rx <= 1;
                        cnt_rx <= 0; // 【修复1】从 0 开始计数，而不是 B_CNT/2
                    end
                end
                
                // 1: Start Bit - 等待起始位中间点 (只走半个周期)
                1: begin
                    if(cnt_rx < B_CNT/2 - 1) begin // 【修复2】只等半个位宽
                        cnt_rx <= cnt_rx + 1;
                    end else begin 
                        // 此时到达起始位正中间
                        if(!rx_reg) begin // (可选) 再次确认起始位是否因噪声误触发
                            cnt_rx <= 0; 
                            state_rx <= 2; 
                            bit_rx <= 0;
                        end else begin
                            state_rx <= 0; // 如果中间变高了，说明是噪声，回IDLE
                        end
                    end
                end
                
                // 2: Data Bits - 接收 8 位数据
                2: begin
                    if(cnt_rx < B_CNT - 1) begin
                        // 从"起始位中间"走到"D0中间"，耗时一个完整 B_CNT
                        cnt_rx <= cnt_rx + 1;
                    end else begin
                        cnt_rx <= 0;
                        // 【修复3】此时处于数据位正中间，采样最稳定
                        rx_data[bit_rx] <= rx_reg;
                        
                        if(bit_rx == 7) 
                            state_rx <= 4; // 去停止位
                        else 
                            bit_rx <= bit_rx + 1;
                    end
                end
    
                // 4: Stop Bit - 等待停止位 (同样走一个 B_CNT 到停止位中间)
                4: begin
                     if(cnt_rx < B_CNT - 1) 
                        cnt_rx <= cnt_rx + 1;
                     else begin
                        cnt_rx <= 0;
                        state_rx <= 3; 
                     end
                end
    
                // 3: Done
                3: begin 
                    rx_done <= 1;
                    state_rx <= 0; 
                end
            endcase
        end
    end

    // TX Logic (保持不变)
    assign tx_pin = (state_tx == 0) ? 1'b1 : shift_tx[0];
    
    assign tx_busy = (state_tx != 0) || tx_start;
    
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin 
            state_tx <= 0; 
            
            cnt_tx <= 0;
        end else begin
            case(state_tx)
                0: if(tx_start) begin
                    shift_tx <= {1'b1, tx_data, 1'b0};
                    state_tx <= 1; 
                    
                    cnt_tx <= 0; 
                    bit_tx <= 0;
                end
                1: if(cnt_tx < B_CNT) cnt_tx <= cnt_tx + 1; else begin
                    cnt_tx <= 0; 
                    shift_tx <= {1'b1, shift_tx[9:1]};
                    if(bit_tx == 9) begin state_tx <= 0;  end
                    else bit_tx <= bit_tx + 1;
                end
            endcase
        end
    end
endmodule