// ICAP Example with proper UART for Arty A7 (100MHz)
// This version uses a small FIFO to handle timing differences

module top (
    input  wire clk,        // 100MHz on Arty A7
    input  wire rst_n,      // Reset button (BTN0)
    output reg  uart_tx
);

    // Function to convert character to ASCII
    function [7:0] asc;
        input [7:0] ch;
        begin
            asc = ch;
        end
    endfunction

    // Hex to ASCII lookup table
    wire [7:0] htoa_c [0:15];
    assign htoa_c[0]  = 8'h30; // '0'
    assign htoa_c[1]  = 8'h31; // '1'
    assign htoa_c[2]  = 8'h32; // '2'
    assign htoa_c[3]  = 8'h33; // '3'
    assign htoa_c[4]  = 8'h34; // '4'
    assign htoa_c[5]  = 8'h35; // '5'
    assign htoa_c[6]  = 8'h36; // '6'
    assign htoa_c[7]  = 8'h37; // '7'
    assign htoa_c[8]  = 8'h38; // '8'
    assign htoa_c[9]  = 8'h39; // '9'
    assign htoa_c[10] = 8'h41; // 'A'
    assign htoa_c[11] = 8'h42; // 'B'
    assign htoa_c[12] = 8'h43; // 'C'
    assign htoa_c[13] = 8'h44; // 'D'
    assign htoa_c[14] = 8'h45; // 'E'
    assign htoa_c[15] = 8'h46; // 'F'

    // Function to convert nibble to hex ASCII
    function [7:0] htoa_f;
        input [3:0] hex;
        begin
            htoa_f = htoa_c[hex];
        end
    endfunction

    // Function to reverse bit order in 32-bit word
    function [31:0] rev_f;
        input [31:0] v;
        integer i, j;
        begin
            for (i = 0; i < 32; i = i + 1) begin
                j = (7 - (i % 8)) + (i / 8) * 8;
                rev_f[j] = v[i];
            end
        end
    endfunction

    //--------------------------------------------------------------------
    // ICAP Signals
    //--------------------------------------------------------------------
    reg  [31:0] I = 32'h00000000;
    wire [31:0] O;
    wire        CLK;
    reg         CSIB = 1'b0;
    reg         RDWRB = 1'b0;

    //--------------------------------------------------------------------
    // FRAME_ECC Signals
    //--------------------------------------------------------------------
    wire [25:0] FAR;
    wire [12:0] SYNDROME;
    wire [6:0]  SYNWORD;
    wire [4:0]  SYNBIT;
    wire        CRCERROR;
    wire        ECCERROR;
    wire        ECCERRORSINGLE;
    wire        SYNDROMEVALID;

    //--------------------------------------------------------------------
    // UART/Output Signals
    //--------------------------------------------------------------------
    reg  [127:0] result;
    reg  [7:0]   cout = 8'h00;
    reg          cout_en = 1'b0;
    reg          cout_clk;
    
    reg  [33:0]  icap = 34'h3FFFFFFFF;
    reg          icap_en = 1'b0;
    reg          icap_clk;
    
    reg          isep_en = 1'b0;
    reg          clk_sel = 1'b0;

    //--------------------------------------------------------------------
    // ICAP Sequence Parameters
    //--------------------------------------------------------------------
    parameter OFF_WRITE = 1024;
    parameter OFF_WDATA = OFF_WRITE + 14;
    parameter OFF_F0FLT = OFF_WDATA + 5;
    parameter OFF_F1FLT = OFF_WDATA + 101 + 7;
    parameter OFF_WDSYN = OFF_WDATA + 303;
    parameter OFF_WDONE = OFF_WDSYN + 7;
    
    parameter OFF_RBACK = 2048;
    parameter OFF_RDATA = OFF_RBACK + 11;
    parameter OFF_RDSYN = OFF_RDATA + 404;
    parameter OFF_RDONE = OFF_RDSYN + 7;
    
    parameter OFF_FIXUP = 3072;
    parameter OFF_FDATA = OFF_FIXUP + 10;
    parameter OFF_FDSYN = OFF_FDATA + 202;
    parameter OFF_FDONE = OFF_FDSYN + 7;
    
    parameter OFF_VDONE = OFF_RDONE + 2048;

    //--------------------------------------------------------------------
    // ICAP Interface
    //--------------------------------------------------------------------
    ICAPE2 #(
        .DEVICE_ID(32'h0362D093),
        .ICAP_WIDTH("X32")
    ) ICAP_inst (
        .I(I),
        .CLK(CLK),
        .CSIB(CSIB),
        .RDWRB(RDWRB),
        .O(O)
    );

    BUFGMUX BUFGMUX_inst (
        .I0(icap_clk),
        .I1(clk),
        .O(CLK),
        .S(clk_sel)
    );

    always @(*) begin
        CSIB = icap[33];
        RDWRB = icap[32];
        I = rev_f(icap[31:0]);
    end

    //--------------------------------------------------------------------
    // FRAME_ECC Instance
    //--------------------------------------------------------------------
    FRAME_ECCE2 #(
        .FRAME_RBT_IN_FILENAME("frame.rbt"),
        .FARSRC("EFAR")
    ) FRAME_ECC_inst (
        .FAR(FAR),
        .SYNDROME(SYNDROME),
        .SYNWORD(SYNWORD),
        .SYNBIT(SYNBIT),
        .CRCERROR(CRCERROR),
        .ECCERROR(ECCERROR),
        .ECCERRORSINGLE(ECCERRORSINGLE),
        .SYNDROMEVALID(SYNDROMEVALID)
    );

    //--------------------------------------------------------------------
    // ICAP Procedure
    //--------------------------------------------------------------------
    reg [12:0] cnt_v = 13'd0;
    
    always @(posedge icap_clk) begin
        // Default values
        icap <= 34'h3FFFFFFFF;
        icap_en <= 1'b1;
        isep_en <= 1'b0;

        case (cnt_v)
            // Separator points
            OFF_WRITE-1, OFF_WDONE, OFF_RDONE, OFF_FDONE, OFF_VDONE: begin
                isep_en <= 1'b1;
                icap_en <= 1'b0;
            end

            // SEQ_WRITE sequence
            OFF_WRITE+0:  icap <= {2'b00, 32'hAA995566};
            OFF_WRITE+1:  icap <= {2'b00, 32'h20000000};
            OFF_WRITE+2:  icap <= {2'b00, 32'h30008001};
            OFF_WRITE+3:  icap <= {2'b00, 32'h00000007};
            OFF_WRITE+4:  icap <= {2'b00, 32'h20000000};
            OFF_WRITE+5:  icap <= {2'b00, 32'h20000000};
            OFF_WRITE+6:  icap <= {2'b00, 32'h30018001};
            OFF_WRITE+7:  icap <= {2'b00, 32'h0362D093};
            OFF_WRITE+8:  icap <= {2'b00, 32'h30008001};
            OFF_WRITE+9:  icap <= {2'b00, 32'h00000001};
            OFF_WRITE+10: icap <= {2'b00, 32'h20000000};
            OFF_WRITE+11: icap <= {2'b00, 32'h30002001};
            OFF_WRITE+12: icap <= {2'b00, 32'h0002051A};
            OFF_WRITE+13: icap <= {2'b00, 32'h3000412F};

            OFF_F0FLT: icap <= {2'b00, 32'h00001000};
            OFF_F1FLT: icap <= {2'b00, 32'h00000200};

            OFF_WDSYN+0: icap <= {2'b00, 32'h30008001};
            OFF_WDSYN+1: icap <= {2'b00, 32'h0000000D};
            OFF_WDSYN+2: icap <= {2'b00, 32'h20000000};
            OFF_WDSYN+3: icap <= {2'b00, 32'h20000000};
            OFF_WDSYN+4: icap <= {2'b00, 32'h20000000};
            OFF_WDSYN+5: icap <= {2'b11, 32'h20000000};
            OFF_WDSYN+6: icap <= {2'b11, 32'hFFFFFFFF};

            OFF_RBACK+0,  OFF_RBACK+2048+0:  icap <= {2'b00, 32'hAA995566};
            OFF_RBACK+1,  OFF_RBACK+2048+1:  icap <= {2'b00, 32'h20000000};
            OFF_RBACK+2,  OFF_RBACK+2048+2:  icap <= {2'b00, 32'h20000000};
            OFF_RBACK+3,  OFF_RBACK+2048+3:  icap <= {2'b00, 32'h20000000};
            OFF_RBACK+4,  OFF_RBACK+2048+4:  icap <= {2'b00, 32'h30008001};
            OFF_RBACK+5,  OFF_RBACK+2048+5:  icap <= {2'b00, 32'h00000004};
            OFF_RBACK+6,  OFF_RBACK+2048+6:  icap <= {2'b00, 32'h20000000};
            OFF_RBACK+7,  OFF_RBACK+2048+7:  icap <= {2'b00, 32'h30002001};
            OFF_RBACK+8,  OFF_RBACK+2048+8:  icap <= {2'b00, 32'h0002051A};
            OFF_RBACK+9,  OFF_RBACK+2048+9:  icap <= {2'b00, 32'h28006194};
            OFF_RBACK+10, OFF_RBACK+2048+10: icap <= {2'b11, 32'h20000000};

            OFF_RDSYN+0, OFF_RDSYN+2048+0: icap <= {2'b00, 32'h30008001};
            OFF_RDSYN+1, OFF_RDSYN+2048+1: icap <= {2'b00, 32'h0000000D};
            OFF_RDSYN+2, OFF_RDSYN+2048+2: icap <= {2'b00, 32'h20000000};
            OFF_RDSYN+3, OFF_RDSYN+2048+3: icap <= {2'b00, 32'h20000000};
            OFF_RDSYN+4, OFF_RDSYN+2048+4: icap <= {2'b00, 32'h20000000};
            OFF_RDSYN+5, OFF_RDSYN+2048+5: icap <= {2'b11, 32'h20000000};
            OFF_RDSYN+6, OFF_RDSYN+2048+6: icap <= {2'b11, 32'hFFFFFFFF};

            OFF_FIXUP+0: icap <= {2'b00, 32'hAA995566};
            OFF_FIXUP+1: icap <= {2'b00, 32'h20000000};
            OFF_FIXUP+2: icap <= {2'b00, 32'h30018001};
            OFF_FIXUP+3: icap <= {2'b00, 32'h0362D093};
            OFF_FIXUP+4: icap <= {2'b00, 32'h30008001};
            OFF_FIXUP+5: icap <= {2'b00, 32'h00000001};
            OFF_FIXUP+6: icap <= {2'b00, 32'h20000000};
            OFF_FIXUP+7: icap <= {2'b00, 32'h30002001};
            OFF_FIXUP+8: icap <= {2'b00, 32'h0002051A};
            OFF_FIXUP+9: icap <= {2'b00, 32'h300040CA};

            OFF_FDSYN+0: icap <= {2'b00, 32'h30008001};
            OFF_FDSYN+1: icap <= {2'b00, 32'h0000000D};
            OFF_FDSYN+2: icap <= {2'b00, 32'h20000000};
            OFF_FDSYN+3: icap <= {2'b00, 32'h20000000};
            OFF_FDSYN+4: icap <= {2'b00, 32'h20000000};
            OFF_FDSYN+5: icap <= {2'b11, 32'h20000000};
            OFF_FDSYN+6: icap <= {2'b11, 32'hFFFFFFFF};

            default: begin
                if ((cnt_v >= OFF_WDATA && cnt_v < OFF_F0FLT) ||
                    (cnt_v > OFF_F0FLT && cnt_v < OFF_F1FLT) ||
                    (cnt_v > OFF_F1FLT && cnt_v < OFF_WDSYN)) begin
                    icap <= {2'b00, 32'h00000000};
                end
                else if ((cnt_v >= OFF_RDATA && cnt_v < OFF_RDSYN) ||
                         (cnt_v >= OFF_RDATA+2048 && cnt_v < OFF_RDSYN+2048)) begin
                    icap <= {2'b01, 32'h20000000};
                end
                else if (cnt_v >= OFF_FDATA && cnt_v < OFF_FDSYN) begin
                    icap <= {2'b00, 32'h00000000};
                end
                else begin
                    icap_en <= 1'b0;
                end
            end
        endcase

        if (cnt_v < 8191)
            cnt_v <= cnt_v + 1;
    end

    //--------------------------------------------------------------------
    // Output Procedure with FIFO
    //--------------------------------------------------------------------
    reg [5:0] cout_cnt_v = 6'd0;
    reg [6:0] idx_v;
    reg [3:0] sep_v = 4'd0;
    
    // Small FIFO for UART
    reg [7:0] uart_fifo [0:63];
    reg [5:0] fifo_wr_ptr = 0;
    reg [5:0] fifo_rd_ptr = 0;
    wire fifo_empty = (fifo_wr_ptr == fifo_rd_ptr);
    wire fifo_full = ((fifo_wr_ptr + 1) == fifo_rd_ptr);
    
    // Clock divider for cout_clk - run at ~10kHz
    reg [13:0] cout_clk_div = 0;
    always @(posedge clk) begin
        if (cout_clk_div == 9999) begin
            cout_clk_div <= 0;
            cout_clk <= 1'b1;
        end else begin
            cout_clk_div <= cout_clk_div + 1;
            cout_clk <= 1'b0;
        end
    end
    
    // Output procedure - writes to FIFO
    always @(posedge cout_clk) begin
        cout_en <= 1'b1;

        if (icap_en == 1'b1) begin
            case (cout_cnt_v)
                0,1,2,3,4,5,6,7,9,10,11,12,13,14,15,16,
                18,19,20,21,22,23,24,25,27,28,29,30,31,32,33,34: begin
                    idx_v = (31 - cout_cnt_v + cout_cnt_v/9) * 4;
                    cout <= htoa_f(result[idx_v +: 4]);
                end
                8, 17, 26: cout <= 8'h2E;  // '.'
                35: cout <= 8'h0A;  // LF
                36: cout <= 8'h0D;  // CR
                default: begin
                    cout <= 8'h00;
                    cout_en <= 1'b0;
                end
            endcase
        end
        else if (isep_en == 1'b1) begin
            case (cout_cnt_v)
                0, 1, 4, 6: cout <= 8'h20;  // ' '
                2, 3, 7, 8: cout <= 8'h2D;  // '-'
                5: begin
                    cout <= htoa_c[sep_v];
                    sep_v <= sep_v + 1;
                end
                35: cout <= 8'h0A;  // LF
                36: cout <= 8'h0D;  // CR
                default: begin
                    cout <= 8'h00;
                    cout_en <= 1'b0;
                end
            endcase
        end
        else begin
            cout_en <= 1'b0;
        end

        // Write to FIFO if enabled and not full
        if (cout_en && !fifo_full) begin
            uart_fifo[fifo_wr_ptr] <= cout;
            fifo_wr_ptr <= fifo_wr_ptr + 1;
        end

        if (cout_cnt_v == 39) begin
            result <= {rev_f(I), rev_f(O), 
                      CSIB, RDWRB, 2'b00, 2'b00, FAR,
                      3'b000, SYNDROME, SYNWORD, SYNBIT,
                      CRCERROR, ECCERRORSINGLE, ECCERROR, SYNDROMEVALID};
            
            icap_clk <= 1'b1;
            cout_cnt_v <= 0;
        end
        else if (cout_cnt_v == 19) begin
            icap_clk <= 1'b0;
            cout_cnt_v <= cout_cnt_v + 1;
        end
        else begin
            cout_cnt_v <= cout_cnt_v + 1;
        end
    end

    //--------------------------------------------------------------------
    // UART Transmitter - 115200 baud at 100MHz
    //--------------------------------------------------------------------
    reg [9:0] uart_baud_cnt = 0;
    reg [3:0] uart_bit_cnt = 0;
    reg [1:0] uart_state = 0;
    reg [7:0] uart_data;
    
    localparam UART_IDLE = 2'b00;
    localparam UART_START = 2'b01;
    localparam UART_DATA = 2'b10;
    localparam UART_STOP = 2'b11;
    localparam BAUD_PERIOD = 868;  // 100MHz / 115200
    
    always @(posedge clk) begin
        case (uart_state)
            UART_IDLE: begin
                uart_tx <= 1'b1;
                if (!fifo_empty) begin
                    uart_data <= uart_fifo[fifo_rd_ptr];
                    fifo_rd_ptr <= fifo_rd_ptr + 1;
                    uart_state <= UART_START;
                    uart_baud_cnt <= 0;
                end
            end
            
            UART_START: begin
                uart_tx <= 1'b0;
                if (uart_baud_cnt == BAUD_PERIOD - 1) begin
                    uart_state <= UART_DATA;
                    uart_baud_cnt <= 0;
                    uart_bit_cnt <= 0;
                end else begin
                    uart_baud_cnt <= uart_baud_cnt + 1;
                end
            end
            
            UART_DATA: begin
                uart_tx <= uart_data[uart_bit_cnt];
                if (uart_baud_cnt == BAUD_PERIOD - 1) begin
                    uart_baud_cnt <= 0;
                    if (uart_bit_cnt == 7) begin
                        uart_state <= UART_STOP;
                    end else begin
                        uart_bit_cnt <= uart_bit_cnt + 1;
                    end
                end else begin
                    uart_baud_cnt <= uart_baud_cnt + 1;
                end
            end
            
            UART_STOP: begin
                uart_tx <= 1'b1;
                if (uart_baud_cnt == BAUD_PERIOD - 1) begin
                    uart_state <= UART_IDLE;
                end else begin
                    uart_baud_cnt <= uart_baud_cnt + 1;
                end
            end
        endcase
    end

endmodule