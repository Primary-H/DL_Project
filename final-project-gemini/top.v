`timescale 1ns / 1ps

module Matrix_Calc_Top(
    input           sys_clk,    // 100MHz ????
    input           rst_n,      
    input           uart_rx,
    output          uart_tx,
    input   [7:0]   sw,
    input           btn_c,      // Confirm
    input           btn_s1,     // Info
    output  [7:0]   led,
    output  [1:0]   tub_sel,
    output  [7:0]   seg_out,
    output          show_mode,
    output  [7:0]   an
);

    // =========================================================
    // 1. ???????????
    // =========================================================
    wire clk_50m;
    
    // ?????????????? MMCM/PLL
    Clock_Divider u_clk_div (
        .clk_in (sys_clk),
        .rst_n  (rst_n),
        .clk_out(clk_50m)
    );

    // =========================================================
    // 2. ?????????
    // =========================================================
    wire [7:0] rx_data, tx_data, rand_val;
    wire rx_done, tx_start, tx_busy;
    
    // FSM ???
    wire fsm_alu_start, alu_done;
    wire [2:0] fsm_alu_opcode, fsm_op_idx_a, fsm_op_idx_b;
    wire [15:0] fsm_scalar_val;
    wire [2:0] fsm_mat_row_a;
    wire fsm_mem_we, fsm_wr_done;
    wire fsm_mem_clr;
    wire [2:0] fsm_dim_m, fsm_dim_n, fsm_wr_r, fsm_wr_c, fsm_q_m, fsm_q_n;
    wire [2:0] fsm_rd_idx, fsm_rd_r, fsm_rd_c;
    wire [15:0] fsm_w_data;
    wire [7:0] fsm_tx_data;
    wire fsm_tx_start;
    wire helper_start, helper_done; 
    
    // ALU ???
    wire alu_res_we, alu_wr_done;
    wire [2:0] alu_dim_m, alu_dim_n, alu_wr_r, alu_wr_c;
    wire [2:0] alu_rd_m, alu_rd_n, alu_rd_idx, alu_rd_r, alu_rd_c;
    wire [15:0] alu_w_data;
    wire [15:0] alu_scalar_in;
    wire storage_wr_sel;
    wire alu_access_en = fsm_alu_start; 
    assign alu_scalar_in = (fsm_alu_opcode == 3'd2) ? {13'b0, fsm_mat_row_a} : fsm_scalar_val;
    assign storage_wr_sel = alu_access_en ? 1'b0 : 1'b1;

    // Helper ???
    wire [7:0] hlp_tx_data;
    wire hlp_tx_start;
    wire [2:0] hlp_rd_m, hlp_rd_n, hlp_rd_idx, hlp_rd_r, hlp_rd_c;
    
    // Memory ???????
    wire [2:0] mem_q_count;
    wire [15:0] mem_rd_data;
    wire [15:0] w_total_cnt;
    wire [2:0] cfg_max_x = 3'd3;

    // ??????
    wire [4:0] number;
    wire is_active;
    wire [2:0] current_op_out; 

    // =========================================================
    // 3. ?????????? (Arbitration Logic)
    // =========================================================
    
    // 3.1 Memory ????? (ALU ????)
    wire real_we, real_wr_done;
    wire [2:0] real_wr_m, real_wr_n, real_wr_r, real_wr_c;
    wire [15:0] real_w_data;
    wire [15:0] mem_rd_data;
    
    assign real_we       = alu_access_en ? alu_res_we    : fsm_mem_we;
    assign real_wr_done  = alu_access_en ? alu_wr_done   : fsm_wr_done;
    assign real_wr_m     = alu_access_en ? alu_dim_m     : fsm_dim_m;
    assign real_wr_n     = alu_access_en ? alu_dim_n     : fsm_dim_n;
    assign real_wr_r     = alu_access_en ? alu_wr_r      : fsm_wr_r;
    assign real_wr_c     = alu_access_en ? alu_wr_c      : fsm_wr_c;
    assign real_w_data   = alu_access_en ? alu_w_data    : fsm_w_data;

    // 3.2 Memory ????? (?????: ALU > Helper > FSM)
    wire hlp_active = helper_start; // FSM ???? start ?????? Helper ???
    
    // ????? MUX
    wire [2:0] real_rd_m     = fsm_alu_start ? alu_rd_m   : (hlp_active ? hlp_rd_m   : fsm_dim_m);
    wire [2:0] real_rd_n     = fsm_alu_start ? alu_rd_n   : (hlp_active ? hlp_rd_n   : fsm_dim_n);
    wire [2:0] real_rd_idx   = fsm_alu_start ? alu_rd_idx : (hlp_active ? hlp_rd_idx : fsm_rd_idx);
    wire [2:0] real_rd_r     = fsm_alu_start ? alu_rd_r   : (hlp_active ? hlp_rd_r   : fsm_rd_r);
    wire [2:0] real_rd_c     = fsm_alu_start ? alu_rd_c   : (hlp_active ? hlp_rd_c   : fsm_rd_c);

    // 3.3 UART ??????? (Helper > FSM)
    assign tx_data  = hlp_active ? hlp_tx_data  : fsm_tx_data;
    assign tx_start = hlp_active ? hlp_tx_start : fsm_tx_start;

    // =========================================================
    // 4. ????????
    // =========================================================

    UART_Driver #(.CLK_FREQ(50000000), .BAUD_RATE(115200)) u_uart (
        .clk(clk_50m),
        .rst_n(rst_n),
        .rx_pin(uart_rx), .tx_pin(uart_tx),
        .rx_data(rx_data), .rx_done(rx_done),
        .tx_data(tx_data), .tx_start(tx_start), .tx_busy(tx_busy)
    );

    LFSR_Generator u_lfsr (
        .clk(clk_50m),
        .rst_n(rst_n), .rand_out(rand_val)
    );

    Matrix_Storage_Controller #(.MAX_X(3)) u_mem_ctrl (
        .clk(clk_50m),
        .rst_n(rst_n),
        .clr_signal(fsm_mem_clr), 
        .cfg_max_x(cfg_max_x),
        .total_cnt_out(w_total_cnt),
        .q_m(fsm_q_m), .q_n(fsm_q_n), .q_count(mem_q_count),
        .wr_en(real_we), .wr_matrix_done(real_wr_done),
        .wr_sel(storage_wr_sel),
        .wr_m(real_wr_m), .wr_n(real_wr_n),
        .wr_row(real_wr_r), .wr_col(real_wr_c),
        .wr_data(real_w_data),
        .rd_m(real_rd_m), .rd_n(real_rd_n),
        .rd_idx(real_rd_idx),
        .rd_row(real_rd_r), .rd_col(real_rd_c),
        .rd_data(mem_rd_data)
    );

    Matrix_FSM u_fsm (
        .clk(clk_50m),
        .rst_n(rst_n),
        // UART
        .rx_data(rx_data), .rx_done(rx_done),
        .tx_data(fsm_tx_data), .tx_start(fsm_tx_start), .tx_busy(tx_busy),
        // UI
        .sw(sw), .btn(btn_c), .btn_info(btn_s1), .rand_in(rand_val),
        .led(led),
        .number(number),
        .is_active(is_active),
        // ALU Control
        .alu_start(fsm_alu_start), .alu_done(alu_done),
        .alu_opcode(fsm_alu_opcode),
        .op_idx_a(fsm_op_idx_a), .op_idx_b(fsm_op_idx_b),
        .scalar_val(fsm_scalar_val),
        .mat_row_a(fsm_mat_row_a),
        // Memory Control
        .mem_we(fsm_mem_we), .mem_wr_done(fsm_wr_done),
        .mem_clr_out(fsm_mem_clr), 
        .dim_m(fsm_dim_m), .dim_n(fsm_dim_n),
        .wr_r(fsm_wr_r), .wr_c(fsm_wr_c),
        .w_data(fsm_w_data),
        // Query / Read
        .q_m(fsm_q_m), .q_n(fsm_q_n), .q_count_in(mem_q_count),
        .rd_idx(fsm_rd_idx), .rd_r(fsm_rd_r), .rd_c(fsm_rd_c), 
        .r_data_in(mem_rd_data),
        .total_cnt_in(w_total_cnt),
        // Helper Control
        .helper_start(helper_start),
        .helper_done(helper_done),
        .current_op_out(current_op_out)
    );

    Matrix_Tx_Helper u_helper (
        .clk(clk_50m),
        .rst_n(rst_n),
        .start(helper_start),
        .done(helper_done),
        // Target dims
        .target_m(fsm_q_m), 
        .target_n(fsm_q_n),
        // Storage Read Interface
        .rd_m(hlp_rd_m), .rd_n(hlp_rd_n),
        .rd_idx(hlp_rd_idx),
        .rd_row(hlp_rd_r), .rd_col(hlp_rd_c),
        .r_data(mem_rd_data),
        .q_count(mem_q_count),
        // UART Interface
        .tx_data(hlp_tx_data),
        .tx_start(hlp_tx_start),
        .tx_busy(tx_busy)
    );

    Matrix_ALU u_alu (
        .clk(clk_50m),
        .rst_n(rst_n),
        .start(fsm_alu_start), .done(alu_done), .opcode(fsm_alu_opcode),
        .dim_m(fsm_dim_m), .dim_n(fsm_dim_n), 
        .src_idx_A(fsm_op_idx_a), .src_idx_B(fsm_op_idx_b),
        .scalar_val(alu_scalar_in), // ??? Mux ?????????
        .rd_m(alu_rd_m), .rd_n(alu_rd_n), .rd_idx(alu_rd_idx),
        .rd_row(alu_rd_r), .rd_col(alu_rd_c), .r_data(mem_rd_data),
        .res_we(alu_res_we), .res_wr_done(alu_wr_done),
        .wr_row(alu_wr_r), .wr_col(alu_wr_c), .w_data(alu_w_data),
        .res_dim_m(alu_dim_m), .res_dim_n(alu_dim_n)
    );

    // =========================================================
    // 5. ???????????? (????????)
    // =========================================================

    // 5.1 ???????? (DN0 ??): ????????????
    // ????????????????????????????????????(?????seg_decoder???)
    // ????????????????????????active???????
    seg_decoder u_seg_decoder (
        .clk(clk_50m),
        .rst_n(rst_n),
        .is_active(is_active),
        .tub_sel(tub_sel),
        .number(number),
        .seg_out(seg_out)
    );

    // 5.2 ???????? (DN1 ??): ????????????
    // ?????????????????(is_active=0) ?? ?????0 ????
    assign show_mode = (current_op_out != 0);
    
    Seven_Seg_Driver u_seg_driver_left (
        .op_mode(current_op_out),
        .rst_n(rst_n),
        .enable(show_mode),        
        .an(an)           
    );

endmodule