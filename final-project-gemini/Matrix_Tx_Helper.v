`timescale 1ns / 1ps

module Matrix_Tx_Helper(
    input clk,
    input rst_n,

    // --- ���ƽӿ� ---
    input start,                // �����ź� (����)
    output reg done,            // ����ź�? (����)
    input [2:0] target_m,       // Ҫ��ӡ�ľ�������
    input [2:0] target_n,       // Ҫ��ӡ�ľ�������

    // --- �洢�������ӿ� (Storage Interface) ---
    // ��Щ�źŽ�ͨ�� MUX ���ӵ� Storage Controller
    output reg [2:0] rd_m, rd_n,
    output reg [2:0] rd_idx,
    output reg [2:0] rd_row, rd_col,
    input [15:0] r_data,        // ���ص�����
    input [2:0] q_count,        // ��ά���¾����������?

    // --- UART �ӿ� ---
    output reg [7:0] tx_data,
    output reg tx_start,
    input tx_busy
);

    // ״̬����
    localparam S_IDLE        = 0;
    localparam S_INIT        = 1; // ��ʼ��ά��
    localparam S_CHECK_IDX   = 2; // ����Ƿ��ӡ�����о���
    localparam S_SEND_ID     = 3; // ���;��� ID (0, 1...)
    localparam S_SEND_NL_1   = 4; // ID��Ļ���?
    localparam S_READ_DATA   = 5; // ׼����ȡ����
    localparam S_SEND_VAL    = 6; // ��������ֵ
    localparam S_Check_SEP   = 7; // �жϷ��Ϳո��ǻ���
    localparam S_SEND_SEP    = 8; // ִ�з��ͷָ���
    localparam S_NEXT_ELEM   = 9; // �ƶ�����һ��Ԫ��
    localparam S_TX_WAIT     = 10; // ͨ�õȴ����ڿ���״̬
    localparam S_DONE        = 11;

    reg [3:0] state, next_state;
    reg [3:0] return_state; // �ӳ��򷵻ص�ַ�Ĵ���

    // ʱ���߼���״̬��ת
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) state <= S_IDLE;
        else       state <= next_state;
    end

    // ����߼���״̬��?
    always @* begin
        next_state = state;
        case(state)
            S_IDLE: begin
                if(start) next_state = S_INIT;
            end

            S_INIT: next_state = S_CHECK_IDX;

            S_CHECK_IDX: begin
                // �����ǰ����? >= ������˵����ӡ���?
                if(rd_idx > q_count) next_state = S_DONE;
                else                  next_state = S_SEND_ID;
            end

            S_SEND_ID: begin
                if(!tx_busy) next_state = S_TX_WAIT;
            end

            S_SEND_NL_1: begin
                if(!tx_busy) next_state = S_TX_WAIT;
            end

            S_READ_DATA: next_state = S_SEND_VAL; // ���� Storage �����ӳٻ򼫿죬��һ�����ݼ���

            S_SEND_VAL: begin
                if(!tx_busy) next_state = S_TX_WAIT;
            end

            S_Check_SEP: next_state = S_SEND_SEP;

            S_SEND_SEP: begin
                if(!tx_busy) next_state = S_TX_WAIT;
            end

           S_NEXT_ELEM: begin
                // ���������жϵ�ǰ�Ƿ��Ǿ�������һ�С����һ��?
                if(rd_col == rd_n - 1 && rd_row == rd_m - 1) 
                    next_state = S_CHECK_IDX; // ����һ������Ľ�β��ȥ����Ƿ�����һ��
                else
                    next_state = S_READ_DATA; // ��û���굱ǰ���󣬼�������һ����
            end

            S_TX_WAIT: begin
                // �ȴ�������ɣ�����? return_state
                if(!tx_busy && !tx_start) next_state = return_state;
            end

            S_DONE: next_state = S_IDLE;
            
            default: next_state = S_IDLE;
        endcase
    end

    // ����߼�?
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            rd_m <= 0; rd_n <= 0; rd_idx <= 1;
            rd_row <= 0; rd_col <= 0;
            tx_start <= 0; done <= 0; tx_data <= 0;
            return_state <= S_IDLE;
        end else begin
            // Ĭ���ź�
            tx_start <= 0;
            done <= 0;

            case(state)
                S_IDLE: begin
                    
                end

                S_INIT: begin
                    rd_m <= target_m;
                    rd_n <= target_n;
                    rd_idx <= 1;
                    rd_row <= 0;
                    rd_col <= 0;
                end

                S_SEND_ID: begin
                    if(!tx_busy && !tx_start) begin
                        tx_data <= rd_idx - 1 + "0"; // ���ƣ�����ID < 10
                        tx_start <= 1;
                        return_state <= S_SEND_NL_1; // ���� ID ȥ������
                    end
                end

                S_SEND_NL_1: begin
                    if(!tx_busy && !tx_start) begin
                        tx_data <= 8'h0A; // \n
                        tx_start <= 1;
                        rd_row <= 0; rd_col <= 0; // ׼������һ������
                        return_state <= S_READ_DATA;
                    end
                end

                // S_READ_DATA: ���ﲻ��Ҫ��������ַ�� INIT �� NEXT_ELEM ��׼����

                S_SEND_VAL: begin
                    if(!tx_busy && !tx_start) begin
                        tx_data <= r_data + "0"; // ���ƣ��������� < 10
                        tx_start <= 1;
                        return_state <= S_Check_SEP;
                    end
                end

                // �����Ƿ��ո��Ƿ�����
                S_Check_SEP: begin
                    // ���߼��жϣ���������
                end

                S_SEND_SEP: begin
                    if(!tx_busy && !tx_start) begin
                        tx_start <= 1;
                        return_state <= S_NEXT_ELEM; // ����ָ���ȥ��һ��Ԫ��?

                        if(rd_col == rd_n - 1) begin
                            // ��β��������
                            tx_data <= 8'h0A;
                        end else begin
                            // ���ڣ����ո�
                            tx_data <= " ";
                        end
                    end
                end

                S_NEXT_ELEM: begin
                    // ���������߼�
                    if(rd_col == rd_n - 1) begin
                        rd_col <= 0;
                        if(rd_row == rd_m - 1) begin
                            rd_row <= 0;
                            rd_idx <= rd_idx + 1; // ���������ָ����һ��?
                        end else begin
                            rd_row <= rd_row + 1;
                        end
                    end else begin
                        rd_col <= rd_col + 1;
                    end
                end

                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule