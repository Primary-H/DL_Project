`timescale 1ns / 1ps

module Matrix_FSM(
    input clk, rst_n,
    // UART
    input [7:0] rx_data, input rx_done,
    output reg [7:0] tx_data, output reg tx_start, input tx_busy,
    
    // Inputs
    input [7:0] sw,
    input btn,          // Confirm Button
    input btn_info,     // Info Button
    input [7:0] rand_in,
    output reg [7:0] led,

    // 7-segment tube
    output [4:0] number,
    output is_active,
    
    // ALU
    output reg alu_start,
    input alu_done,
    output reg [2:0] alu_opcode,
    output reg [2:0] op_idx_a, op_idx_b,
    output reg [15:0] scalar_val,
    
    // ?????????A???????????????ALU???????????
    output [2:0] mat_row_a,

    // Memory Interface
    output reg mem_we, output reg mem_wr_done,
    output reg mem_clr_out,
    output reg [2:0] dim_m, dim_n,
    output reg [2:0] wr_r, wr_c,
    output reg [15:0] w_data,
    
    // Query Interface
    output reg [2:0] q_m, q_n,
    input [2:0] q_count_in,
    output reg [2:0] rd_idx,
    output reg [2:0] rd_r, rd_c,
    input [15:0] r_data_in,

    input [15:0] total_cnt_in,
    
    output reg helper_start,
    input helper_done,
    
    output [2:0] current_op_out
);
    // =========================================================
    // 1. ???????????????
    // =========================================================
    localparam S_IDLE        = 0;
    localparam S_GET_DIM     = 1;
    localparam S_GET_COUNT   = 2;
    localparam S_INPUT_DATA  = 3;
    localparam S_GEN_DATA    = 4;
    localparam S_GET_CD      = 5; 
    localparam S_FILL_ZEROS  = 10;
    localparam S_ERROR       = 99;

    // =========================================================
    // 2. ?????????????
    // =========================================================
    localparam S_CALC           = 20;
    localparam S_PRINT_PREPARE  = 21; 
    localparam S_PRINT_BODY     = 22;

    // =========================================================
    // 3. ?§Ò??????
    // =========================================================
    localparam S_LIST_SCAN_INIT = 30;
    localparam S_LIST_CHECK_CNT = 31;
    localparam S_LIST_HEAD_M    = 32;
    localparam S_LIST_HEAD_X    = 33;
    localparam S_LIST_HEAD_N    = 34;
    localparam S_LIST_HEAD_TAG  = 35;
    localparam S_LIST_HEAD_ID   = 36;
    localparam S_LIST_HEAD_NL   = 37;
    localparam S_LIST_READ_WAIT = 40;
    localparam S_LIST_DATA_TX   = 41;
    localparam S_LIST_DATA_SPC  = 42;
    localparam S_LIST_ROW_NL    = 43;
    localparam S_LIST_NEXT_DIM  = 45;
    localparam S_WAIT_RELEASE   = 46;
    localparam S_TX_WAIT        = 47;
    localparam S_TX_HOLD_1      = 48;
    localparam S_TX_HOLD_2      = 49;

    // =========================================================
    // 4. ??????????????
    // =========================================================
    localparam S_SELECT_OP       = 50;
    localparam S_SUMM_SEND_TOTAL = 51;
    localparam S_SUMM_INIT       = 52;
    localparam S_SUMM_CHECK      = 53;
    localparam S_SUMM_SEND_STR   = 54;
    localparam S_SUMM_NEXT       = 55;

    // =========================================================
    // 5. ??????????
    // =========================================================
    localparam S_FLOW_GET_M      = 60; 
    localparam S_FLOW_GET_N      = 61; 
    localparam S_FLOW_LIST_START = 62; 
    localparam S_FLOW_LIST_WAIT  = 63; 
    localparam S_FLOW_SELECT_ID  = 64; 
    localparam S_FLOW_ECHO_PREP  = 65; 
    localparam S_FLOW_ECHO_BODY  = 66; 
    localparam S_FLOW_GET_SCALAR = 67; 
    localparam S_FLOW_NEXT_STEP  = 68; 

    localparam S_CHECK_VALIDITY = 70; 
    localparam S_GET_CD_VAL     = 71; 

    // =========================================================
    // 6. ???????????
    // =========================================================
    localparam S_RAND_PRE_NL         = 79; // [????] ?????????§Ù?
    localparam S_RAND_INIT           = 80; 
    localparam S_RAND_SEARCH_A       = 81; 
    localparam S_RAND_CHECK_A        = 82; 
    localparam S_RAND_PRE_CHECK_MULT = 83; 
    localparam S_RAND_PICK_A         = 84; 
    localparam S_RAND_SEARCH_B       = 85; 
    localparam S_RAND_CHECK_B        = 86; 
    localparam S_RAND_PICK_B         = 87; 
    localparam S_RAND_GEN_SCALAR     = 88; 
    localparam S_RAND_PRINT_NEXT     = 89; 
    localparam S_RAND_WAIT_CONFIRM   = 90; 

    reg [6:0] state, next_state; 
    reg [7:0] op_mode;          
    reg [2:0] filter_m, filter_n, filter_p; 
    reg [2:0] param_count;      
    reg [2:0] current_scan_m, current_scan_n; 
    reg [4:0] countdown_sec = 10; 

    reg btn_prev, btn_info_prev;
    reg [2:0] gen_cnt_target, gen_cnt_done;
    reg [2:0] scan_m, scan_n, scan_k;

    reg [3:0] tx_step;      
    reg [3:0] sub_state;    
    reg [2:0] filter_phase; 
    reg [2:0] param_cnt;
    reg [6:0] return_state;
    reg op_step;
    reg pending_check;
    
    // ???????
    reg is_neg;             
    reg [15:0] abs_val;     
    reg [3:0]  digit_100;
    reg [3:0]  digit_10;    
    reg [3:0]  digit_1;     
    reg has_printed_high;   

    // ???????§µ????¨¹????
    reg [25:0] timer_cnt;
    reg [4:0]  curr_sec;        
    reg [4:0]  cfg_sec;
    reg        err_mode;
    
    // ????§µ??????????
    reg [2:0] dim_a_m, dim_a_n;
    reg [2:0] dim_b_m, dim_b_n;

    // --- ??????????????? ---
    reg is_random_mode;            // ?????????
    reg [2:0] rand_start_m, rand_start_n; // ??????????
    reg [2:0] latched_q_count;     // ??????????????
    reg [2:0] search_p;            // ??????B??????????????
    reg       rand_a_valid;        // ???? ??????????

    wire send_str_done = (state == S_SUMM_SEND_STR && tx_step == 6 && !tx_busy);
    
    assign current_op_out = op_mode;
    assign mat_row_a = filter_m; 
    assign number = curr_sec;
    
    wire is_valid_calc = 
        (op_mode == "1" && dim_a_m == dim_b_m && dim_a_n == dim_b_n) || // ???
        (op_mode == "2" && dim_a_n == dim_b_m) ||                       // ???
        (op_mode == "3") ||                                             // ????
        (op_mode == "4");                                               // ???

    // --------------------------------------------------------
    // Process 1: Sequential State Register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) state <= S_IDLE;
        else       state <= next_state;
    end

    // --------------------------------------------------------
    // Process 2: Combinational Next State Logic
    // --------------------------------------------------------
    always @* begin
        next_state = state;

        if (err_mode == 1'b1 && curr_sec == 0) begin
            next_state = S_IDLE;
        end 
        else begin
            case(state)
                S_IDLE: begin
                    if (sw[7] && btn && !btn_prev) next_state = S_IDLE;
                    else if (btn_info && !btn_info_prev) next_state = S_LIST_SCAN_INIT;
                    else if (rx_done) begin
                        if (rx_data == 8'h0D || rx_data == 8'h0A || rx_data == 8'h20 || rx_data == 8'h00) begin
                            next_state = S_IDLE;
                        end
                        else if (rx_data == "c") next_state = S_SELECT_OP;
                        else if (rx_data >= "1" && rx_data <= "5") next_state = S_GET_DIM;
                        else if (rx_data == "d") next_state = S_GET_CD_VAL;
                        else next_state = S_ERROR;
                    end 
                end

                S_GET_DIM: begin
                    if(rx_done) begin
                        if(rx_data >= "1" && rx_data <= "5") begin
                            if(sw[0]) next_state = S_GET_COUNT;
                            else      next_state = S_INPUT_DATA;
                        end else next_state = S_ERROR;
                    end
                end

                S_GET_COUNT: begin
                    if(rx_done) begin
                        if(rx_data >= "1" && rx_data <= "2") next_state = S_GEN_DATA;
                        else                                 next_state = S_ERROR;
                    end
                end

                S_INPUT_DATA: begin
                    if (btn && !btn_prev) next_state = S_FILL_ZEROS;
                    else if(rx_done) begin
                        if(rx_data >= "0" && rx_data <= "9") begin
                            if(wr_c == dim_n - 1 && wr_r == dim_m - 1) next_state = S_IDLE;
                        end
                    end
                end

                S_GET_CD_VAL: begin
                    if(rx_done) next_state = S_IDLE;
                    else        next_state = S_GET_CD_VAL;
                end

                // ?????????? - ??????????
                S_FLOW_NEXT_STEP: begin
                    if (op_mode == "4") next_state = S_CALC;
                    else if (op_mode == "1" || op_mode == "2") begin
                        if (op_step == 0) next_state = S_FLOW_GET_M; 
                        else              next_state = S_CHECK_VALIDITY;
                    end
                    else if (op_mode == "3") begin 
                        if (op_step == 0) next_state = S_FLOW_GET_SCALAR;
                        else              next_state = S_CALC;
                    end
                    else next_state = S_IDLE;
                end

                S_CHECK_VALIDITY: begin
                    if (is_valid_calc) next_state = S_CALC;
                    else               next_state = S_FLOW_GET_M;
                end
                
                S_FILL_ZEROS: begin
                    if(wr_r == dim_m - 1 && wr_c == dim_n - 1) next_state = S_IDLE;
                    else next_state = S_FILL_ZEROS;
                end
                
                S_TX_HOLD_1: next_state = S_IDLE;
                
                S_GEN_DATA: begin
                    if(wr_c == dim_n - 1 && wr_r == dim_m - 1) begin
                        if(gen_cnt_done + 1 >= gen_cnt_target) next_state = S_IDLE;
                    end
                end

                S_ERROR: begin
                    if(btn && !btn_prev) next_state = S_IDLE;
                end

                // --- ?§Ò?/???? ---
                S_LIST_SCAN_INIT: next_state = S_LIST_CHECK_CNT;
                S_LIST_CHECK_CNT: next_state = S_LIST_HEAD_M;
                S_LIST_HEAD_M: begin
                    if(q_count_in == 0 || scan_k >= q_count_in) next_state = S_LIST_NEXT_DIM;
                    else if(!tx_busy) next_state = S_TX_WAIT; 
                end
                S_LIST_HEAD_X:    if(!tx_busy) next_state = S_TX_WAIT;
                S_LIST_HEAD_N:    if(!tx_busy) next_state = S_TX_WAIT;
                S_LIST_HEAD_TAG:  if(!tx_busy) next_state = S_TX_WAIT;
                S_LIST_HEAD_ID:   if(!tx_busy) next_state = S_TX_WAIT;
                S_LIST_HEAD_NL:   if(!tx_busy) next_state = S_TX_WAIT;
                S_LIST_READ_WAIT: next_state = S_LIST_DATA_TX;
                S_LIST_DATA_TX:   if(!tx_busy) next_state = S_TX_WAIT;
                S_LIST_DATA_SPC:  if(!tx_busy) next_state = S_TX_WAIT;
                S_LIST_ROW_NL:    if(!tx_busy) next_state = S_TX_WAIT;
                S_TX_WAIT: begin
                    if(!tx_busy) next_state = return_state;
                    else         next_state = S_TX_WAIT;
                end
                S_LIST_NEXT_DIM: begin
                    if(scan_n == 5) begin
                        if(scan_m == 5) next_state = S_WAIT_RELEASE;
                        else            next_state = S_LIST_CHECK_CNT;
                    end else            next_state = S_LIST_CHECK_CNT;
                end
                S_WAIT_RELEASE: begin
                    if(!btn_info) next_state = S_IDLE;
                end

                // --- ??????????? ---
                S_CALC:          if(alu_done) next_state = S_PRINT_PREPARE;
                S_PRINT_PREPARE: next_state = S_PRINT_BODY;
                S_PRINT_BODY:    
                    if(!tx_busy && !tx_start && sub_state == 8) next_state = S_IDLE;
                    else next_state = S_PRINT_BODY;

                // --- ???????????? ---
                S_SELECT_OP: begin
                    if (rx_done) next_state = S_SUMM_SEND_TOTAL;
                end
                S_SUMM_SEND_TOTAL: begin
                    if (tx_step == 2 && !tx_busy && !tx_start) next_state = S_SUMM_INIT;
                    else next_state = S_SUMM_SEND_TOTAL;
                end
                S_SUMM_INIT:     next_state = S_SUMM_CHECK;
                S_SUMM_CHECK: begin
                    if (q_count_in > 0) next_state = S_SUMM_SEND_STR;
                    else                next_state = S_SUMM_NEXT;
                end
                S_SUMM_SEND_STR: if (send_str_done) next_state = S_SUMM_NEXT;
                S_SUMM_NEXT: begin
                    if (scan_n == 5 && scan_m == 5) next_state = S_FLOW_GET_M;
                    else next_state = S_SUMM_CHECK;
                end

                // --- ?????????????????? ---
                S_FLOW_GET_M: begin
                    if (rx_done) begin
                        if (rx_data >= "1" && rx_data <= "5") next_state = S_FLOW_GET_N;
                        // ?????????????????§µ?????????? INIT
                        else if (rx_data == "r" || rx_data == "R") next_state = S_RAND_PRE_NL; 
                        else next_state = S_FLOW_GET_M;
                    end else next_state = S_FLOW_GET_M;
                end

                S_FLOW_GET_N: begin
                    if (rx_done && rx_data >= "1" && rx_data <= "5") next_state = S_FLOW_LIST_START;
                    else next_state = S_FLOW_GET_N;
                end
                S_FLOW_LIST_START: next_state = S_FLOW_LIST_WAIT;
                S_FLOW_LIST_WAIT:  if (helper_done) next_state = S_FLOW_SELECT_ID; else next_state = S_FLOW_LIST_WAIT;
                S_FLOW_SELECT_ID: begin
                    if (btn && !btn_prev) begin 
                        if (pending_check) next_state = S_FLOW_ECHO_PREP;
                        else               next_state = S_FLOW_SELECT_ID;
                    end else next_state = S_FLOW_SELECT_ID;
                end
                S_FLOW_ECHO_PREP: next_state = S_FLOW_ECHO_BODY;
                
                // ????????? (????)
                S_FLOW_ECHO_BODY: begin
                    if (!tx_busy && !tx_start && sub_state == 8) begin
                        if (is_random_mode) next_state = S_RAND_PRINT_NEXT;
                        else                next_state = S_FLOW_NEXT_STEP;
                    end else next_state = S_FLOW_ECHO_BODY;
                end

                S_FLOW_GET_SCALAR: begin
                    if (btn && !btn_prev) next_state = S_FLOW_NEXT_STEP; 
                    else                  next_state = S_FLOW_GET_SCALAR;
                end

                // =========================================================
                // ?????????????
                // =========================================================
                // ?????????????????§Ù?
                S_RAND_PRE_NL: begin
                    if (!tx_busy && !tx_start) next_state = S_RAND_INIT;
                    else next_state = S_RAND_PRE_NL;
                end

                S_RAND_INIT:     next_state = S_RAND_SEARCH_A;
                S_RAND_SEARCH_A: next_state = S_RAND_CHECK_A;
                
                S_RAND_CHECK_A: begin
                    if (q_count_in > 0) begin
                        if (op_mode == "2") next_state = S_RAND_PRE_CHECK_MULT;
                        else                next_state = S_RAND_PICK_A;
                    end else begin
                        // A ??????????????? A
                        if (scan_m == rand_start_m && scan_n == rand_start_n && rand_a_valid) 
                             next_state = S_IDLE; // Loop full circle -> Exit
                        else next_state = S_RAND_SEARCH_A;
                    end
                end

                // ???????????????????? B (A_col == B_row)
                S_RAND_PRE_CHECK_MULT: begin
                    if (q_count_in > 0) begin
                        next_state = S_RAND_PICK_A; // ??? A ??????
                    end else begin
                        if (search_p >= 5) begin
                             // ??????? A ????? B???????? A????????? A
                             if (scan_m == rand_start_m && scan_n == rand_start_n && rand_a_valid)
                                 next_state = S_IDLE;
                             else
                                 next_state = S_RAND_SEARCH_A;
                        end else begin
                             next_state = S_RAND_PRE_CHECK_MULT; // ???????????
                        end
                    end
                end

                S_RAND_PICK_A: next_state = S_FLOW_ECHO_PREP; // ???? A

                S_RAND_PRINT_NEXT: begin
                    if (op_mode == "4") next_state = S_RAND_WAIT_CONFIRM; 
                    else if (op_step == 0) begin
                        // ??????? A?????? B
                        if (op_mode == "3") next_state = S_RAND_GEN_SCALAR;
                        else                next_state = S_RAND_SEARCH_B;
                    end else begin
                        // ??????? B??????
                        next_state = S_RAND_WAIT_CONFIRM;
                    end
                end

                S_RAND_SEARCH_B: next_state = S_RAND_CHECK_B;
                
                S_RAND_CHECK_B: begin
                    if (q_count_in > 0) next_state = S_RAND_PICK_B;
                    else begin
                        // ?????? PRE_CHECK ?????????????????????
                        if (search_p >= 5) next_state = S_IDLE; 
                        else next_state = S_RAND_SEARCH_B; 
                    end
                end
                
                S_RAND_PICK_B: next_state = S_FLOW_ECHO_PREP; 

                S_RAND_GEN_SCALAR: begin
                    if (!tx_busy && !tx_start && tx_step == 2) next_state = S_RAND_PRINT_NEXT;
                    else next_state = S_RAND_GEN_SCALAR;
                end

                S_RAND_WAIT_CONFIRM: begin
                    if (btn && !btn_prev) next_state = S_CALC;
                    else next_state = S_RAND_WAIT_CONFIRM;
                end

            endcase
        end
    end

    // --------------------------------------------------------
    // Process 3: Sequential Output/Datapath Logic
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            led <= 8'hAA; 
            mem_we <= 0; mem_wr_done <= 0; mem_clr_out <= 0;
            tx_start <= 0; alu_start <= 0;
            btn_prev <= 0; btn_info_prev <= 0;
            dim_m <= 0; dim_n <= 0;
            wr_r <= 0; wr_c <= 0;
            gen_cnt_target <= 0;
            countdown_sec <= 10;
            helper_start <= 0;
            op_mode <= 0;
            timer_cnt <= 0;
            curr_sec <= 0;
            cfg_sec <= 10;      
            err_mode <= 0;
            dim_a_m <= 0; dim_a_n <= 0;
            dim_b_m <= 0; dim_b_n <= 0;
            
            scan_m <= 1; scan_n <= 1;
            param_cnt <= 0;
            tx_step <= 0;
            sub_state <= 0;
            filter_phase <= 0;
            op_step <= 0;
            pending_check <= 0;

            q_m <= 1; q_n <= 1;
            rd_idx <= 1; rd_r <= 0; rd_c <= 0;
            alu_opcode <= 0; scalar_val <= 0;
            op_idx_a <= 0; op_idx_b <= 0;
            filter_m <= 0; filter_n <= 0; filter_p <= 0;
            
            is_random_mode <= 0;
            rand_start_m <= 1; rand_start_n <= 1;
            latched_q_count <= 0;
            search_p <= 1;
            rand_a_valid <= 0;
        end else begin
            // 1. ????????
            if (err_mode && state != S_CHECK_VALIDITY) begin
                if (timer_cnt >= 50000000) begin 
                    timer_cnt <= 0;
                    if (curr_sec > 0) curr_sec <= curr_sec - 1;
                end else timer_cnt <= timer_cnt + 1;
            end else timer_cnt <= 0;

            // 2. ???????????
            mem_we <= 0; mem_wr_done <= 0; mem_clr_out <= 0;
            tx_start <= 0;
            btn_prev <= btn; btn_info_prev <= btn_info;
            
            case(state)
                S_IDLE: begin
                    err_mode <= 0;
                    alu_start <= 0;
                    op_mode <= 0;
                    is_random_mode <= 0; 
                    led <= 8'h01;
                    if (sw[7] && btn && !btn_prev) begin
                        mem_clr_out <= 1; led <= 8'h00; 
                    end
                    else if(btn_info && !btn_info_prev) led <= 8'hF0;
                    else if(rx_done) begin
                        if(rx_data >= "1" && rx_data <= "5") begin
                            dim_m <= rx_data - "0"; led <= 8'h02; 
                        end
                    end
                end

                S_GET_CD_VAL: begin
                    led <= 8'hDD;
                    if(rx_done) begin
                        if(rx_data >= "5" && rx_data <= "9") cfg_sec <= rx_data - "0";
                        else if(rx_data >= "a" && rx_data <= "f") cfg_sec <= (rx_data - "a") + 10;
                        else if(rx_data >= "A" && rx_data <= "F") cfg_sec <= (rx_data - "A") + 10;
                    end
                end

                S_FLOW_NEXT_STEP: begin
                    if (op_mode == "4") err_mode <= 0;
                    else if (op_mode == "1" || op_mode == "2") begin
                        if (op_step == 0) begin
                            op_step <= 1; scan_m <= 1; scan_n <= 1;
                        end
                    end
                    else if (op_mode == "3") begin
                        if (op_step == 0) op_step <= 1;
                        else              err_mode <= 0;
                    end
                end

                S_CHECK_VALIDITY: begin
                    if (is_valid_calc) begin
                        err_mode <= 0; led <= 8'hF0;
                    end else begin
                        err_mode <= 1; curr_sec <= cfg_sec; led <= 8'hFF;
                        op_step <= 0; scan_m <= 1; scan_n <= 1;
                    end
                end

                S_GET_DIM: begin
                    led <= 8'h02;
                    if(rx_done) begin
                        if(rx_data >= "1" && rx_data <= "5") begin
                            dim_n <= rx_data - "0"; wr_r <= 0; wr_c <= 0; led <= 8'h04;
                        end
                    end
                end

                S_GET_COUNT: begin
                    led <= 8'h04;
                    if(rx_done) begin
                        if(rx_data >= "1" && rx_data <= "2") begin
                            gen_cnt_target <= rx_data - "0"; gen_cnt_done <= 0;
                        end
                    end
                end

               S_INPUT_DATA: begin
                    led <= 8'h08;
                    if (mem_we) begin 
                         if(wr_c == dim_n - 1) begin
                            wr_c <= 0;
                            if(wr_r != dim_m - 1) wr_r <= wr_r + 1; 
                        end else wr_c <= wr_c + 1;
                        mem_we <= 0;
                    end
                    if(rx_done) begin
                        if(rx_data >= "0" && rx_data <= "9") begin
                            mem_we <= 1; w_data <= rx_data - "0"; 
                            if(wr_c == dim_n - 1 && wr_r == dim_m - 1) begin
                                mem_wr_done <= 1; led <= 8'hFF;
                            end
                        end
                    end
                end
                
                S_FILL_ZEROS: begin
                    mem_we <= 1; w_data <= 0; 
                    if(wr_c == dim_n - 1) begin
                        wr_c <= 0;
                        if(wr_r == dim_m - 1) begin
                            mem_wr_done <= 1; led <= 8'hFF; wr_r <= 0;
                        end else wr_r <= wr_r + 1;
                    end else wr_c <= wr_c + 1;
                end

                S_GEN_DATA: begin
                    mem_we <= 1; w_data <= rand_in % 10;
                    if(wr_c == dim_n - 1) begin
                        wr_c <= 0;
                        if(wr_r == dim_m - 1) begin
                            mem_wr_done <= 1; wr_r <= 0;
                            if(gen_cnt_done + 1 >= gen_cnt_target) led <= 8'hFF;
                            else gen_cnt_done <= gen_cnt_done + 1;
                        end else wr_r <= wr_r + 1;
                    end else wr_c <= wr_c + 1;
                end

                S_ERROR: led <= 8'h0F;

                // --- ?§Ò??????? ---
                S_LIST_SCAN_INIT: begin scan_m <= 1; scan_n <= 1; end
                S_LIST_CHECK_CNT: begin q_m <= scan_m; q_n <= scan_n; scan_k <= 0; end
                S_LIST_HEAD_M: begin
                    if((q_count_in != 0 && scan_k < q_count_in) && !tx_busy) begin 
                         tx_data <= scan_m + "0"; tx_start <= 1; return_state <= S_LIST_HEAD_X;
                    end
                end
                S_LIST_HEAD_X: begin 
                    if(!tx_busy) begin tx_data <= "*"; tx_start <= 1; return_state <= S_LIST_HEAD_N; end 
                end
                S_LIST_HEAD_N: begin 
                    if(!tx_busy) begin tx_data <= scan_n + "0"; tx_start <= 1; return_state <= S_LIST_HEAD_TAG; end 
                end
                S_LIST_HEAD_TAG: begin 
                    if(!tx_busy) begin tx_data <= "&"; tx_start <= 1; return_state <= S_LIST_HEAD_ID; end 
                end
                S_LIST_HEAD_ID: begin 
                    if(!tx_busy) begin tx_data <= scan_k + "0"; tx_start <= 1; return_state <= S_LIST_HEAD_NL; end 
                end
                S_LIST_HEAD_NL: begin 
                    if(!tx_busy) begin 
                        tx_data <= 8'h0A; tx_start <= 1; 
                        rd_idx <= scan_k + 1; rd_r <= 0; rd_c <= 0;
                        dim_m <= scan_m; dim_n <= scan_n;
                        return_state <= S_LIST_READ_WAIT;
                    end 
                end
                S_LIST_DATA_TX: begin
                    if(!tx_busy) begin 
                        tx_data <= r_data_in + "0"; tx_start <= 1; return_state <= S_LIST_DATA_SPC;
                    end
                end
                S_LIST_DATA_SPC: begin
                    if(!tx_busy) begin
                        tx_data <= " "; tx_start <= 1;
                        if(rd_c != scan_n - 1) begin
                             rd_c <= rd_c + 1; return_state <= S_LIST_READ_WAIT;
                        end else return_state <= S_LIST_ROW_NL;
                    end
                end
                S_LIST_ROW_NL: begin
                    if(!tx_busy) begin
                        tx_data <= 8'h0A; tx_start <= 1; rd_c <= 0;
                        if(rd_r == scan_m - 1) begin 
                            rd_r <= 0; scan_k <= scan_k + 1; return_state <= S_LIST_HEAD_M;
                        end else begin 
                            rd_r <= rd_r + 1; return_state <= S_LIST_READ_WAIT;
                        end
                    end
                end
                S_LIST_NEXT_DIM: begin
                    if(scan_n == 5) begin
                        scan_n <= 1;
                        if(scan_m != 5) scan_m <= scan_m + 1;
                    end else scan_n <= scan_n + 1;
                end
                S_WAIT_RELEASE: if(!btn_info) led <= 8'h01;

               S_CALC: begin
                    led <= 8'hC0;
                    if(alu_done) alu_start <= 0; else alu_start <= 1; 
                end
                
                S_PRINT_PREPARE: begin
                    led <= 8'hC1; alu_start <= 0; 
                    rd_idx <= 0; sub_state <= 0; rd_r <= 0; rd_c <= 0;
                    if(op_mode == "4") begin 
                        q_m <= filter_n; q_n <= filter_m;
                        dim_m <= filter_n; dim_n <= filter_m; 
                    end 
                    else if(op_mode == "2") begin 
                        q_m <= filter_m; q_n <= filter_p; 
                        dim_m <= filter_m; dim_n <= filter_p; 
                    end 
                    else begin 
                        q_m <= filter_m; q_n <= filter_n;
                        dim_m <= filter_m; dim_n <= filter_n;
                    end
                end

                S_PRINT_BODY, S_FLOW_ECHO_BODY: begin 
                    led <= 8'hC3;
                    if(!tx_busy && !tx_start) begin
                        case(sub_state)
                            0: begin 
                                if (r_data_in[15]) begin is_neg<=1; abs_val<=~r_data_in+1; end 
                                else begin is_neg<=0; abs_val<=r_data_in; end
                                sub_state <= 1;
                            end
                            1: begin
                                digit_100 <= abs_val / 100;
                                digit_10  <= (abs_val % 100) / 10;
                                digit_1   <= abs_val % 10;
                                has_printed_high <= 0; 
                                sub_state <= 2;
                            end
                            2: begin
                                if (is_neg) begin
                                    tx_data <= "-"; tx_start <= 1; is_neg <= 0; 
                                    sub_state <= 3;
                                end else sub_state <= 3;
                            end
                            3: begin
                                if (digit_100 > 0) begin
                                    tx_data <= digit_100 + "0"; tx_start <= 1;
                                    has_printed_high <= 1; sub_state <= 4;
                                end else sub_state <= 4;
                            end
                            4: begin
                                if (digit_10 > 0 || has_printed_high) begin
                                    tx_data <= digit_10 + "0"; tx_start <= 1; sub_state <= 5;
                                end else sub_state <= 5;
                            end
                            5: begin
                                tx_data <= digit_1 + "0"; tx_start <= 1; sub_state <= 6;
                            end
                            6: begin
                                if(rd_c == q_n-1) tx_data <= 8'h0A;
                                else              tx_data <= " ";
                                tx_start <= 1; sub_state <= 7;
                            end
                            7: begin
                                if(rd_c == q_n-1) begin
                                    if(rd_r == q_m-1) sub_state <= 8;
                                    else begin rd_r <= rd_r + 1; rd_c <= 0; sub_state <= 0; end
                                end else begin rd_c <= rd_c + 1; sub_state <= 0; end
                            end
                        endcase
                    end
                end

                S_SELECT_OP: begin
                    led <= 8'hF1;
                    is_random_mode <= 0; 
                    if(rx_done) begin 
                        op_mode <= rx_data; tx_step <= 0; 
                        case(rx_data) "1": alu_opcode <= 1; "2": alu_opcode <= 2; 
                                      "3": alu_opcode <= 3; "4": alu_opcode <= 4;
                                      default: alu_opcode <= 7; endcase 
                    end 
                end

                S_SUMM_SEND_TOTAL: begin 
                    if(!tx_busy && !tx_start) begin
                        case(tx_step)
                            0: begin
                                if (total_cnt_in >= 10) begin
                                    tx_data <= (total_cnt_in / 10) + "0"; tx_start <= 1; tx_step <= 1;
                                end else begin
                                    tx_data <= total_cnt_in + "0"; tx_start <= 1; tx_step <= 2;
                                end
                            end
                            1: begin
                                tx_data <= (total_cnt_in % 10) + "0"; tx_start <= 1; tx_step <= 2;
                            end
                            2: begin
                                tx_data <= " "; tx_start <= 1;
                            end
                        endcase
                    end
                end

                S_SUMM_INIT: begin
                    scan_m <= 1; scan_n <= 1; q_m <= 1; q_n <= 1; tx_step <= 0;
                end
                S_SUMM_CHECK: tx_step <= 0; 
                S_SUMM_SEND_STR: begin
                    if(!tx_busy && !tx_start) begin
                        case(tx_step)
                            0: begin tx_data <= scan_m + "0"; tx_start <= 1; tx_step <= 1; end
                            1: begin tx_data <= "*"; tx_start <= 1; tx_step <= 2; end
                            2: begin tx_data <= scan_n + "0"; tx_start <= 1; tx_step <= 3; end
                            3: begin tx_data <= "*"; tx_start <= 1; tx_step <= 4; end
                            4: begin tx_data <= q_count_in + "0"; tx_start <= 1; tx_step <= 5; end
                            5: begin tx_data <= " "; tx_start <= 1; tx_step <= 6; end
                        endcase
                    end
                end

                S_SUMM_NEXT: begin
                if(scan_n == 5) begin
                    if(scan_m == 5) begin
                        scan_m <= 1; scan_n <= 1; op_step <= 0; 
                    end else begin
                        scan_n <= 1; q_n <= 1; scan_m <= scan_m + 1; q_m <= scan_m + 1;
                    end
                end else begin
                    scan_n <= scan_n + 1; q_n <= scan_n + 1;
                end
            end

            // ----------------------------------------------------
            // ????????
            // ----------------------------------------------------
            S_FLOW_GET_M: begin
                led <= 8'h11;
                if (rx_done && rx_data >= "1" && rx_data <= "5") scan_m <= rx_data - "0";
            end

            S_FLOW_GET_N: begin
                led <= 8'h12;
                if (rx_done && rx_data >= "1" && rx_data <= "5") scan_n <= rx_data - "0";
            end

            S_FLOW_LIST_START: begin
                helper_start <= 1; q_m <= scan_m; q_n <= scan_n; 
                dim_m <= scan_m; dim_n <= scan_n;
                if(op_step == 0) begin 
                    filter_m <= scan_m; filter_n <= scan_n; 
                    dim_a_m <= scan_m; dim_a_n <= scan_n;
                end else begin
                    if(op_mode == "2") filter_p <= scan_n;
                    dim_b_m <= scan_m; dim_b_n <= scan_n;
                end
            end

            S_FLOW_LIST_WAIT: begin
                pending_check <= 0;
                if (helper_done) helper_start <= 0; else helper_start <= 1;
            end

            S_FLOW_SELECT_ID: begin
                led <= 8'h14;
                if (rx_done && rx_data >= "0" && rx_data <= "9") begin
                    if ((rx_data - "0") < q_count_in) begin
                        pending_check <= 1;
                        if (op_step == 0) op_idx_a <= (rx_data - "0") + 1;
                        else              op_idx_b <= (rx_data - "0") + 1;
                    end
                end
            end

            S_FLOW_ECHO_PREP: begin
                sub_state <= 0; rd_r <= 0; rd_c <= 0;
                if (op_step == 0) rd_idx <= op_idx_a; else rd_idx <= op_idx_b;
                // ??????????????? scan_m/scan_n
                // ??????????????? B ?????????? scan_m/n ???????? B ?????
                q_m <= scan_m; q_n <= scan_n; dim_m <= scan_m; dim_n <= scan_n;
            end
            
            S_FLOW_GET_SCALAR: begin
                led <= 8'h18;
                if (rx_done && rx_data >= "0" && rx_data <= "9") scalar_val <= rx_data - "0";
                else if (!rx_done) scalar_val <= {12'b0, sw[3:0]};
            end

            // =========================================================
            // ???????????????? (Data Path)
            // =========================================================
            // ?????????????????§Ù?????????????
            S_RAND_PRE_NL: begin
                if (!tx_busy && !tx_start) begin
                    tx_data <= 8'h0A; tx_start <= 1;
                end
            end

            S_RAND_INIT: begin
                is_random_mode <= 1;
                op_step <= 0;
                scan_m <= (rand_in[2:0] % 5) + 1;
                scan_n <= (rand_in[5:3] % 5) + 1;
                rand_start_m <= (rand_in[2:0] % 5) + 1;
                rand_start_n <= (rand_in[5:3] % 5) + 1;
                rand_a_valid <= 0; 
            end

            S_RAND_SEARCH_A: begin
                q_m <= scan_m; q_n <= scan_n;
            end

            S_RAND_CHECK_A: begin
                if (q_count_in > 0) begin
                    latched_q_count <= q_count_in; 
                    
                    if (op_mode == "2") begin
                         // ??????????B???????
                         search_p <= (rand_in % 5) + 1; // ?????? B ??????????????
                         q_m <= scan_n; 
                         q_n <= (rand_in % 5) + 1;      
                    end 
                end else begin
                    // A ??????????????? A
                    if (scan_n == 5) begin
                        scan_n <= 1;
                        if (scan_m == 5) scan_m <= 1; else scan_m <= scan_m + 1;
                    end else scan_n <= scan_n + 1;
                    
                    if (scan_n == rand_start_n && scan_m == rand_start_m) rand_a_valid <= 1;
                    
                    // ???????????? q_m/q_n
                    if (scan_n == 5) begin
                         q_n <= 1;
                         if (scan_m == 5) q_m <= 1; else q_m <= scan_m + 1;
                    end else begin
                         q_n <= scan_n + 1;
                         q_m <= scan_m; 
                    end
                end
            end

            S_RAND_PRE_CHECK_MULT: begin
                // ?????????? (scan_n, search_p) ???????
                if (q_count_in == 0) begin
                    if (search_p < 5) begin
                         search_p <= search_p + 1;
                         q_m <= scan_n;      
                         q_n <= search_p + 1; 
                    end else begin
                        // ????????B??????A????????????A??¦Ë??
                        if (scan_n == 5) begin
                            scan_n <= 1;
                            if (scan_m == 5) scan_m <= 1; else scan_m <= scan_m + 1;
                        end else scan_n <= scan_n + 1;

                        if (scan_n == rand_start_n && scan_m == rand_start_m) rand_a_valid <= 1;
                    end
                end
            end

            S_RAND_PICK_A: begin
                dim_m <= scan_m; dim_n <= scan_n;
                op_idx_a <= (rand_in % latched_q_count) + 1;
                filter_m <= scan_m; filter_n <= scan_n;
                dim_a_m <= scan_m; dim_a_n <= scan_n;
            end

            S_RAND_PRINT_NEXT: begin
                if (op_mode != "4" && op_step == 0) begin
                    op_step <= 1; 
                    if (op_mode == "3") begin
                        scalar_val <= rand_in % 10;
                        tx_step <= 1; 
                    end 
                end 
            end

            S_RAND_SEARCH_B: begin
                // ??????? B
                if (op_mode == "2") begin
                    // ?????B_row = A_col (?? dim_a_n)
                    q_m <= dim_a_n; 
                    if (search_p > 5) search_p <= 1; 
                    q_n <= search_p;
                end 
                else if (op_mode == "1") begin
                    // ?????B ??????
                    q_m <= dim_a_m; q_n <= dim_a_n;
                end
            end

            S_RAND_CHECK_B: begin
                if (q_count_in > 0) begin
                    latched_q_count <= q_count_in;
                end else begin
                    // ??§Ô??????????????
                    search_p <= search_p + 1;
                    q_m <= dim_a_n; q_n <= search_p + 1; 
                end
            end

            S_RAND_PICK_B: begin
                op_idx_b <= (rand_in % latched_q_count) + 1;
                dim_b_m <= q_m; dim_b_n <= q_n;
                if (op_mode == "2") filter_p <= q_n;
                
                // ??????????????? scan_m/scan_n ? B ?????
                // ???????? ECHO_PREP ??????????????? B ????????????????? A ?????
                scan_m <= q_m; 
                scan_n <= q_n;
            end

            S_RAND_GEN_SCALAR: begin
                if (tx_step == 0) begin
                    tx_step <= 1;
                end else if (tx_step == 1) begin
                    if (!tx_busy) begin
                        tx_data <= scalar_val + "0"; tx_start <= 1;
                        tx_step <= 2;
                    end
                end else if (tx_step == 2) begin
                     if (!tx_busy) begin
                        tx_data <= 8'h0A; tx_start <= 1; 
                     end
                end
            end
            
            S_RAND_WAIT_CONFIRM: begin
                 led <= 8'h55; 
                 // ??????? ALU ????
                 if (op_mode == "2") begin
                     dim_m <= filter_n;        // ??????? n
                     dim_n <= filter_p;        // ???????? p
                     scalar_val <= {13'b0, filter_m}; // ????scalar_val?????????? m
                 end
            end

            endcase
        end
    end
    
    assign is_active = err_mode;
endmodule