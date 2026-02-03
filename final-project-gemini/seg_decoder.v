module seg_decoder(
    input wire clk,
    input wire rst_n,
    input wire is_active,
    output reg [1:0] tub_sel,
    input [4:0] number, 
    output reg [7:0] seg_out
);
    // 1. 数位拆分 (Double Dabble 或者简单的除法/取模)
    // 15 / 10 = 1 (十位)
    // 15 % 10 = 5 (个位)
    wire [3:0] digit_ten;
    wire [3:0] digit_unit;
    assign digit_ten  = number / 10;
    assign digit_unit = number % 10;

    // 2. 扫描定时器
    // 我们需要大约 1kHz 的频率切换数码管，人眼才看不出闪烁
    // 假设 clk = 100MHz (10^8)，我们需要数 10^5 次
    reg [16:0] scan_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            scan_cnt <= 0;       // 复位清零
        else 
            scan_cnt <= scan_cnt + 1;
    end

    // 取计数器的高位作为扫描信号 (大约几百Hz)
    wire scan_tick = scan_cnt[16]; 

    // 3. 扫描逻辑 + 熄灭控制
    reg [3:0] current_digit; // 当前要显示的那个数字(0-9)

    always @(*) begin
        tub_sel = 2'b00; 
        current_digit = 4'd0;
        // --- 第一步：如果不激活，强制关闭位选 ---
        if (!is_active) begin
            tub_sel = 2'b00;       // 两个数码管都关掉
            current_digit = 4'd0;  // 数字无所谓
        end
        else begin
            case (scan_tick)
                1'b0: begin // 时隙 0：显示个位
                    tub_sel = 2'b01;       // 选中右边数码管 (假设 bit 0 是右)
                    current_digit = digit_unit;
                end
                1'b1: begin // 时隙 1：显示十位
                    tub_sel = 2'b10;       // 选中左边数码管
                    current_digit = digit_ten;
                end
            endcase
        end
    end

    // 4. 段码译码
    always @(*) begin
        if (!is_active) seg_out = 8'hFF; // 辅助熄灭
        else begin
            case (current_digit)
                4'd0: seg_out = 8'b1111_1100;  //"0" : abcdef_ _ 
                4'd1: seg_out = 8'b0110_0000; //"1":  _bc_ _ _ _ _ _
                4'd2: seg_out = 8'b1101_1010; //"2": ab_de_g_ 
                4'd3: seg_out = 8'b1111_0010; //"3":  abcd_ _ g _
                4'd4: seg_out = 8'b0110_0110; //"4": _bc _ _fg_
                4'd5: seg_out = 8'b1011_0110;  //"5": a_cd_fg_
                4'd6: seg_out = 8'b1011_1110; //"6": a_cdefg_
                4'd7: seg_out = 8'b1110_0000; //"7": abc_ _ _ _ _
                4'd8: seg_out = 8'b1111_1110; //"8": abcdefg_
                4'd9: seg_out = 8'b1110_0110; //"9": abc_ _ fg_
                default: seg_out = 8'b1001_1110;//"E": a_ _ defg_
            endcase
        end
    end

endmodule