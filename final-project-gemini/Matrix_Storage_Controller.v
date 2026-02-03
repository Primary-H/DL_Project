`timescale 1ns / 1ps

module Matrix_Storage_Controller #(
    // [Parameter] MAX_X: Total slots per matrix type.
    // Slot 0 is reserved for ALU results (Calculation Buffer).
    // Slots 1 to (MAX_X-1) are for User Storage.
    parameter MAX_X = 3,       
    parameter DATA_WIDTH = 16
)(
    input clk,
    input rst_n,
    input clr_signal,

    // --- Configuration & Status ---
    input [2:0] cfg_max_x,     // Configurable limit (Total slots: Buffer + User Storage)
    input [2:0] q_m, q_n,      // Query dimensions
    output [2:0] q_count,      // Output: How many matrices stored for this dimension
    output reg [15:0] total_cnt_out, // Global count of all stored matrices

    // --- Write Interface ---
    input wr_en,
    input wr_matrix_done,      // Pulse when a full matrix write is complete
    // [Write Select]: 0 = ALU Result (writes to Slot 0), 1 = User Input (writes to Slot 1+)
    input wr_sel,              
    input [2:0] wr_m, wr_n,
    input [2:0] wr_row, wr_col,
    input signed [DATA_WIDTH-1:0] wr_data,

    // --- Read Interface ---
    input [2:0] rd_m, rd_n,
    input [2:0] rd_idx,        // Read Index: 0 = ALU Result, 1+ = Stored Matrices
    input [2:0] rd_row, rd_col,
    output signed [DATA_WIDTH-1:0] rd_data  
);

    // Total Memory Depth: 25 Matrix types * MAX_X Slots per type * 25 Elements max
    localparam TOTAL_DEPTH = 25 * MAX_X * 25;
    reg signed [DATA_WIDTH-1:0] mem_array [0:TOTAL_DEPTH-1];

    // Metadata Registers
    reg [2:0] matrix_cnt [1:5][1:5]; // Count of valid matrices for each MxN dimension
    reg [2:0] write_ptr  [1:5][1:5]; // Circular pointer for overwriting old matrices
    
    integer i, j;

    // [Initialization]
    initial begin
        for(i=1; i<=5; i=i+1) begin
            for(j=1; j<=5; j=j+1) begin
                matrix_cnt[i][j] = 0;
                write_ptr[i][j]  = 1; // Start User writes at Slot 1 (Slot 0 is reserved)
            end
        end
        total_cnt_out = 0;
    end

    // =========================================================
    // 1. Address Calculation Logic
    // =========================================================
    
    // --- Write Address Calculation ---
    // Map (m,n) dimensions to a linear block index (0 to 24)
    wire [15:0] wr_type_idx = (wr_m - 3'd1) * 3'd5 + (wr_n - 3'd1);
    // Base address for this Matrix Type
    wire [15:0] wr_slot_base = wr_type_idx * (MAX_X * 25);
    
    // [Slot Offset]
    reg [15:0] wr_instance_base;
    always @* begin
        // If wr_sel=0 (ALU), force write to Slot 0
        if (wr_sel == 1'b0) wr_instance_base = 0; 
        // If wr_sel=1 (User), write to current circular pointer slot
        else                wr_instance_base = write_ptr[wr_m][wr_n] * 25;
    end

    // Final Write Address: Base + Slot + Element Offset
    wire [15:0] wr_addr = wr_slot_base + wr_instance_base + (wr_row * 3'd5) + wr_col;

    // --- Read Address Calculation ---
    wire [15:0] rd_type_idx = (rd_m - 3'd1) * 3'd5 + (rd_n - 3'd1);
    wire [15:0] rd_slot_base = rd_type_idx * (MAX_X * 25);
    wire [15:0] rd_instance_base = rd_idx * 25; // rd_idx selects specific matrix (0, 1, 2...)
    wire [15:0] rd_addr = rd_slot_base + rd_instance_base + (rd_row * 3'd5) + rd_col;

    // =========================================================
    // 2. Storage & Pointer Logic
    // =========================================================
    always @(posedge clk) begin
        if (clr_signal) begin
            for(i=1; i<=5; i=i+1) begin
                for(j=1; j<=5; j=j+1) begin
                    matrix_cnt[i][j] <= 0;
                    write_ptr[i][j]  <= 1; // Reset pointer to Slot 1
                end
            end
            total_cnt_out <= 0;
        end
        else begin
            // --- Write Data ---
            if (wr_en) begin
                mem_array[wr_addr] <= wr_data;
            end

            // --- Update Metadata on Matrix Completion ---
            if (wr_matrix_done) begin
                
                if (wr_sel == 1'b1) begin
                    // [User Input Mode] Update pointers for storage
                    
                    // Circular Buffer Logic:
                    // If pointer reaches limit (cfg_max_x - 1), wrap back to 1.
                    // Example: if cfg_max_x=3, slots are 0(ALU), 1, 2. Wrap 2 -> 1.
                    if (write_ptr[wr_m][wr_n] >= cfg_max_x - 1)
                        write_ptr[wr_m][wr_n] <= 1; 
                    else
                        write_ptr[wr_m][wr_n] <= write_ptr[wr_m][wr_n] + 1;

                    // Increment valid count if storage isn't full yet
                    if (matrix_cnt[wr_m][wr_n] < cfg_max_x - 1) begin
                        matrix_cnt[wr_m][wr_n] <= matrix_cnt[wr_m][wr_n] + 1; 
                        total_cnt_out <= total_cnt_out + 1;                   
                    end
                end 
                else begin
                    // [ALU Mode]
                    // Do NOT update user pointers/counters.
                    // ALU results always overwrite Slot 0 for that dimension.
                end
            end
        end
    end

    // --- Read Output ---
    assign rd_data = mem_array[rd_addr];
    
    // Output current count for queried dimension (used by FSM to list matrices)
    assign q_count = matrix_cnt[q_m][q_n];

endmodule