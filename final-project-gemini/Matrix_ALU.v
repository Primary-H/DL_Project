`timescale 1ns / 1ps

module Matrix_ALU(
    input clk,
    input rst_n,
    
    // --- Control Interface ---
    input start,
    output reg done,
    input [2:0] opcode,      // 1:Add, 2:Mult, 3:Scalar, 4:Transpose [cite: 105]
    
    // --- Operand Interface ---
    // For Add/Scalar/Transpose: dim_m, dim_n are dimensions of Matrix A (m x n).
    // For Matrix Mult A(m x n) * B(n x p): 
    //   - dim_m input holds 'n' (shared dimension)
    //   - dim_n input holds 'p' (cols of B)
    //   - scalar_val[2:0] holds 'm' (rows of A) [Reused port strategy]
    input [2:0] dim_m, dim_n,    
    input [2:0] src_idx_A,
    input [2:0] src_idx_B,
    input signed [15:0] scalar_val,

    // --- Storage Read Interface ---
    output reg [2:0] rd_m, rd_n,
    output reg [2:0] rd_idx,
    output reg [2:0] rd_row, rd_col,
    input signed [15:0] r_data,
    
    // --- Storage Write Interface (Writes to Result Slot 0) ---
    output reg res_we,
    output reg res_wr_done,
    output reg [2:0] wr_row, wr_col,
    output reg signed [15:0] w_data,
    
    // --- Result Dimensions Output ---
    output reg [2:0] res_dim_m, 
    output reg [2:0] res_dim_n
);

    // =========================================================
    // State Definition
    // =========================================================
    localparam S_IDLE      = 0;
    localparam S_PREPARE   = 1;  // Initialization state
    
    localparam S_TRANS_RD  = 10; // Transpose Read State
    localparam S_TRANS_WR  = 11; // Transpose Write State
    
    localparam S_ADD_RD_A  = 20; // Addition: Read A
    localparam S_ADD_RD_B  = 21; // Addition: Read B
    localparam S_ADD_WR    = 22; // Addition: Write Result
    
    localparam S_SCAL_RD   = 30; // Scalar Mult: Read A
    localparam S_SCAL_WR   = 31; // Scalar Mult: Write Result
    
    localparam S_MULT_RD_A = 40; // Matrix Mult: Read A[i][k]
    localparam S_MULT_RD_B = 41; // Matrix Mult: Read B[k][j]
    localparam S_MULT_ACC  = 42; // Matrix Mult: Accumulate Product
    localparam S_MULT_WR   = 43; // Matrix Mult: Write C[i][j]
    
    localparam S_DONE      = 99;

    reg [6:0] current_state, next_state;

    // =========================================================
    // Internal Registers
    // =========================================================
    // Loop counters
    reg [2:0] i, j, k; 
    // Data Buffers
    reg signed [15:0] val_A;
    reg signed [31:0] sum_acc; // 32-bit Accumulator to prevent overflow during MAC
    // Latched Dimensions
    reg [2:0] lat_m, lat_n, lat_p; 

    // =========================================================
    // Boundary Logic (Counters vs Dimensions)
    // =========================================================
    // Logic to detect end of loops based on latched dimensions
    wire end_i_A   = (i == lat_m - 1); // Row loop end
    wire end_j_A   = (j == lat_n - 1); // Col loop end (Standard)
    wire end_k     = (k == lat_n - 1); // Inner dimension loop end (k=0..n-1) for Mult
    wire end_j_B   = (j == lat_p - 1); // Col loop end (j=0..p-1) for Mult

    // =========================================================
    // Sequential Logic: State Register
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            current_state <= S_IDLE;
        else
            current_state <= next_state;
    end

    // =========================================================
    // Combinational Logic: Next State Decode
    // =========================================================
    always @(*) begin
        next_state = current_state; // Default hold

        case (current_state)
            S_IDLE: begin
                if (start) next_state = S_PREPARE;
            end

            S_PREPARE: begin
                // Branch to specific operation flow based on opcode [cite: 106]
                case (opcode)
                    3'd4: next_state = S_TRANS_RD; // Transpose
                    3'd1: next_state = S_ADD_RD_A; // Addition
                    3'd3: next_state = S_SCAL_RD;  // Scalar
                    3'd2: next_state = S_MULT_RD_A;// Multiply
                    default: next_state = S_DONE;
                endcase
            end

            // --- Transpose Flow ---
            // Simple Read-Write loop, swapping indices in datapath
            S_TRANS_RD: next_state = S_TRANS_WR;
            S_TRANS_WR: begin
                if (end_j_A && end_i_A) next_state = S_DONE;
                else                    next_state = S_TRANS_RD;
            end

            // --- Addition Flow ---
            // Read A -> Read B -> Write (A+B)
            S_ADD_RD_A: next_state = S_ADD_RD_B;
            S_ADD_RD_B: next_state = S_ADD_WR;
            S_ADD_WR: begin
                if (end_j_A && end_i_A) next_state = S_DONE;
                else                    next_state = S_ADD_RD_A;
            end

            // --- Scalar Flow ---
            // Read A -> Write (A*scalar)
            S_SCAL_RD: next_state = S_SCAL_WR;
            S_SCAL_WR: begin
                if (end_j_A && end_i_A) next_state = S_DONE;
                else                    next_state = S_SCAL_RD;
            end

            // --- Multiply Flow ---
            // Triple loop structure: Outer(i, j), Inner(k)
            S_MULT_RD_A: next_state = S_MULT_RD_B;
            S_MULT_RD_B: next_state = S_MULT_ACC;
            S_MULT_ACC: begin
                if (end_k) next_state = S_MULT_WR;    // Summation complete, write result
                else       next_state = S_MULT_RD_A;  // Continue summation with next k
            end
            S_MULT_WR: begin
                if (end_j_B && end_i_A) next_state = S_DONE;
                else                    next_state = S_MULT_RD_A; // Next element C[i][j]
            end

            S_DONE: next_state = S_IDLE;
            
            default: next_state = S_IDLE;
        endcase
    end

    // =========================================================
    // Sequential Logic: Datapath & Output Generation
    // =========================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset initialization
            done <= 0;
            res_we <= 0; res_wr_done <= 0;
            res_dim_m <= 0; res_dim_n <= 0;
            rd_m <= 0; rd_n <= 0; rd_idx <= 0; rd_row <= 0; rd_col <= 0;
            wr_row <= 0; wr_col <= 0; w_data <= 0;
            i <= 0; j <= 0; k <= 0;
            lat_m <= 0; lat_n <= 0; lat_p <= 0;
            val_A <= 0; sum_acc <= 0;
        end else begin
            // Default reset for pulsed signals
            res_we <= 0;
            res_wr_done <= 0;
            done <= 0;

            case (next_state) 
                // Optimization: Logic can be placed here to pre-fetch if needed
            endcase

            // Main Datapath Logic
            case (current_state)
                S_IDLE: begin
                    if (start) begin
                        lat_m <= dim_m;
                        lat_n <= dim_n;
                        i <= 0; j <= 0; k <= 0;
                    end
                end

                S_PREPARE: begin
                    // [Dimension Setup] 
                    case (opcode)
                        3'd4: begin // Transpose: Result dimensions are swapped
                            res_dim_m <= lat_n; res_dim_n <= lat_m;
                        end
                        3'd1: begin // Addition: Result dimensions same as input
                            res_dim_m <= lat_m; res_dim_n <= lat_n;
                        end
                        3'd3: begin // Scalar: Result dimensions same as input
                            res_dim_m <= lat_m; res_dim_n <= lat_n;
                        end
                        3'd2: begin // Multiply (Special Dimension Mapping)
                            // A(m x n) * B(n x p) -> C(m x p)
                            lat_p <= lat_n; // Input dim_n holds 'p'
                            lat_n <= lat_m; // Input dim_m holds 'n'
                            lat_m <= scalar_val[2:0]; // scalar_val re-purposed to hold 'm'
                            res_dim_m <= scalar_val[2:0]; res_dim_n <= dim_n;
                        end
                    endcase
                end

                // ================== Transpose Datapath ==================
                // Read A[i][j]
                S_TRANS_RD: begin
                    rd_m <= lat_m; rd_n <= lat_n; rd_idx <= src_idx_A;
                    rd_row <= i; rd_col <= j;
                end
                // Write A[i][j] to Result[j][i] (Swapping row/col) 
                S_TRANS_WR: begin
                    res_we <= 1;
                    wr_row <= j; wr_col <= i; // Swap logic
                    w_data <= r_data;
                    
                    // Loop Control (Iterate all elements)
                    if (end_j_A) begin
                        j <= 0;
                        if (end_i_A) begin
                            res_wr_done <= 1;
                        end else begin
                            i <= i + 1;
                        end
                    end else begin
                        j <= j + 1;
                    end
                end

                // ================== Addition Datapath ==================
                // Read A[i][j]
                S_ADD_RD_A: begin
                    rd_m <= lat_m; rd_n <= lat_n; rd_idx <= src_idx_A;
                    rd_row <= i; rd_col <= j;
                end
                // Read B[i][j] (Address setup similar to A)
                S_ADD_RD_B: begin
                    val_A <= r_data; // Store A
                    rd_idx <= src_idx_B; // Switch to Matrix B
                    // rd_row, rd_col remain same (i, j)
                end
                // Write (A + B) 
                S_ADD_WR: begin
                    res_we <= 1;
                    wr_row <= i; wr_col <= j;
                    w_data <= val_A + r_data; // Result = A + B

                    if (end_j_A) begin
                        j <= 0;
                        if (end_i_A) res_wr_done <= 1;
                        else i <= i + 1;
                    end else begin
                        j <= j + 1;
                    end
                end

                // ================== Scalar Datapath ==================
                S_SCAL_RD: begin
                    rd_m <= lat_m; rd_n <= lat_n; rd_idx <= src_idx_A;
                    rd_row <= i; rd_col <= j;
                end
                // Write (A[i][j] * scalar) 
                S_SCAL_WR: begin
                    res_we <= 1;
                    wr_row <= i; wr_col <= j;
                    w_data <= r_data * scalar_val;

                    if (end_j_A) begin
                        j <= 0;
                        if (end_i_A) res_wr_done <= 1;
                        else i <= i + 1;
                    end else begin
                        j <= j + 1;
                    end
                end

                // ================== Multiply Datapath ==================
                // Loop: i (0..m-1) -> j (0..p-1) -> k (0..n-1)
                // C[i][j] += A[i][k] * B[k][j] 
                S_MULT_RD_A: begin
                    if (k == 0) sum_acc <= 0; // Reset accumulator for new element C[i][j]
                    rd_m <= lat_m; rd_n <= lat_n; rd_idx <= src_idx_A;
                    rd_row <= i; rd_col <= k; // Read A[i][k]
                end
                S_MULT_RD_B: begin
                    val_A <= r_data;
                    rd_m <= lat_n; rd_n <= lat_p; rd_idx <= src_idx_B;
                    rd_row <= k; rd_col <= j; // Read B[k][j]
                end
                S_MULT_ACC: begin
                    sum_acc <= sum_acc + (val_A * r_data); // Multiply-Accumulate
                    
                    if (end_k) begin
                        k <= 0;
                        // Proceed to write result
                    end else begin
                        k <= k + 1;
                        // Loop back to read next k
                    end
                end
                S_MULT_WR: begin
                    res_we <= 1;
                    wr_row <= i; wr_col <= j;
                    w_data <= sum_acc[15:0]; // Truncate 32-bit acc to 16-bit output

                    if (end_j_B) begin
                        j <= 0;
                        if (end_i_A) res_wr_done <= 1;
                        else i <= i + 1;
                    end else begin
                        j <= j + 1;
                    end
                end

                S_DONE: begin
                    done <= 1;
                end
            endcase
        end
    end

endmodule