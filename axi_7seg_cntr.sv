module axi_7seg_cntr #(
    parameter int unsigned NDISP = 8, // Number of 7-segment displays [2...8]
    parameter bit unsigned MODE_DISP  = 1, // 1 => active-low digit enable (Nexys A7 common-anode)
    parameter bit unsigned MODE_SEG   = 0, // 0 => active-low segments (Nexys A7 common-anode)
    parameter int unsigned CLK_FREQ_HZ = 100_000_000,
    parameter int unsigned DIGIT_REFRESH_HZ = 1000,
    parameter int unsigned ADDR_WIDTH = 3,
    parameter int unsigned DATA_WIDTH = 32
) (
    input  logic                     clk,
    input  logic                     nrst,

    // AXI4-Lite SLAVE
    input  logic [ADDR_WIDTH-1:0]    awaddr,
    input  logic [2:0]               awprot,
    input  logic                     awvalid,
    output logic                     awready,

    input  logic [DATA_WIDTH-1:0]    wdata,
    input  logic [DATA_WIDTH/8-1:0]  wstrb,
    input  logic                     wvalid,
    output logic                     wready,

    output logic [1:0]               bresp,
    output logic                     bvalid,
    input  logic                     bready,

    input  logic [ADDR_WIDTH-1:0]    araddr,
    input  logic [2:0]               arprot,
    input  logic                     arvalid,
    output logic                     arready,

    output logic [DATA_WIDTH-1:0]    rdata,
    output logic [1:0]               rresp,
    output logic                     rvalid,
    input  logic                     rready,

    // 7-segment display outputs
    output logic [NDISP-1:0]         seg,
    output logic [6:0]               ABDCEFG,
    output logic                     DP
);

    // Internal register array
    logic [ADDR_WIDTH-1:0]    araddr_reg;
    logic [ADDR_WIDTH-1:0]    awaddr_reg;
    logic [DATA_WIDTH-1:0]    wdata_reg;

    // Display signals
    logic [NDISP-1:0]           display_enable;
    logic [3:0]                 data_displays[NDISP-1:0];
    logic                       data_dp[NDISP-1:0];
    logic [$clog2(NDISP)-1:0]   digit_display;
    logic [3:0]                 digit_displayed;
    localparam int unsigned REFRESH_TICKS =
        ((CLK_FREQ_HZ / (NDISP * DIGIT_REFRESH_HZ)) > 0) ? (CLK_FREQ_HZ / (NDISP * DIGIT_REFRESH_HZ)) : 1;
    localparam int unsigned REFRESH_COUNTER_MAX = REFRESH_TICKS - 1;
    localparam int unsigned REFRESH_COUNTER_WIDTH =
        (REFRESH_TICKS > 1) ? $clog2(REFRESH_TICKS) : 1;
    logic [REFRESH_COUNTER_WIDTH-1:0] refresh_counter;
    logic                       end_of_count;

    localparam ADDR_SEG  = 0;
    localparam ADDR_DP   = 4;

    typedef enum logic {
        IDLE_READ,
        READ_DATA
    } state_read;
    state_read state_r;

    // READ CHANNEL
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            arready     <= 0;
            araddr_reg  <= 0;
            rdata       <= 0;
            rresp       <= 0;
            rvalid      <= 0;
            state_r     <= IDLE_READ;
        end else begin
            case (state_r)
                IDLE_READ: begin
                    arready     <= 1;
                    if (arvalid && arready) begin
                        araddr_reg  <= araddr;
                        state_r     <= READ_DATA;
                        arready <= 0;
                    end
                end

                READ_DATA: begin
                    rvalid  <= 1;
                    rresp   <= 0;
                    rdata   <= 0;
                    if (araddr_reg == ADDR_SEG) begin
                        for (int i = 0; i < NDISP; i++) begin
                            rdata[(i*4)+:4] <= data_displays[i];
                        end
                    end else if (araddr_reg == ADDR_DP) begin
                        for (int i = 0; i < NDISP; i++) begin
                            rdata[i] <= data_dp[i];
                        end
                    end
                    if (rready && rvalid) begin
                        rvalid  <= 0;
                        state_r <= IDLE_READ;
                    end
                end

                default: begin
                    state_r <= IDLE_READ;
                end
            endcase
        end
    end


    typedef enum logic [1:0] {
        IDLE_WRITE,
        HAVE_AW,
        HAVE_W,
        RESP
    } state_write;
    state_write state_w;


    // WRITE CHANNEL
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            awready     <= 0;
            wready      <= 0;
            bvalid      <= 0;
            bresp       <= 0;
            awaddr_reg  <= 0;
            wdata_reg   <= 0;
            state_w     <= IDLE_WRITE;
            data_displays   <= '{default: '0};
            data_dp        <= '{default: '0};
        end else begin
            case (state_w)
                IDLE_WRITE: begin
                    awready <= 1;
                    wready  <= 1;
                    if ((wvalid && wready) && (awvalid && awready)) begin
                        wdata_reg   <= wdata;
                        awaddr_reg  <= awaddr;
                        wready      <= 0;
                        awready     <= 0;
                        state_w     <= RESP;
                    end else if (awvalid && awready) begin
                        awaddr_reg  <= awaddr;
                        awready     <= 0;
                        state_w     <= HAVE_AW;
                    end else if (wvalid && wready) begin
                        wdata_reg   <= wdata;
                        wready      <= 0;
                        state_w     <= HAVE_W;
                    end

                end

                HAVE_AW: begin
                    wready  <= 1;
                    if (wvalid && wready) begin
                        wdata_reg   <= wdata;
                        wready      <= 0;
                        state_w     <= RESP;
                    end
                end

                HAVE_W: begin
                    awready <= 1;
                    if (awvalid && awready) begin
                        awaddr_reg  <= awaddr;
                        awready     <= 0;
                        state_w     <= RESP;
                    end
                end

                RESP: begin
                    if (awaddr_reg == ADDR_SEG) begin
                        for (int i = 0; i < NDISP; i++) begin
                            data_displays[i] <= wdata_reg[(i*4)+:4];
                        end
                    end else if (awaddr_reg == ADDR_DP) begin
                        for (int i = 0; i < NDISP; i++) begin
                            data_dp[i] <= wdata_reg[i];
                        end
                    end

                    bvalid  <= 1;
                    bresp   <= 0;
                    if (bready && bvalid) begin
                        bvalid  <= 0;
                        state_w <= IDLE_WRITE;
                    end
                end

                default: begin
                    state_w <= IDLE_WRITE;
                end
            endcase
        end
    end

    // 7-segment display control
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            refresh_counter <= '0;
        end else if (end_of_count) begin
            refresh_counter <= '0;
        end else begin
            refresh_counter <= refresh_counter + 1;
        end
    end
    assign end_of_count = (refresh_counter == REFRESH_COUNTER_MAX);

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            digit_display <= 0;
        end else if (end_of_count) begin
            if (digit_display == NDISP - 1) begin
                digit_display <= 0;
            end else begin
                digit_display <= digit_display + 1;
            end
        end
    end

    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            display_enable <= {NDISP{1'b0}};
            display_enable[0] <= 1'b1;
        end else if (end_of_count) begin
            display_enable <= {display_enable[NDISP-2:0], display_enable[NDISP-1]};
        end
    end

    // Assign outputs to 7-segment displays
    always_comb begin
        digit_displayed = data_displays[digit_display];
        seg = {NDISP{MODE_DISP}} ^ display_enable;
        DP = MODE_SEG ^ data_dp[digit_display];
        case (digit_displayed)
            4'h0: ABDCEFG = {7{MODE_SEG}} ^ 7'b0000001;
            4'h1: ABDCEFG = {7{MODE_SEG}} ^ 7'b1001111;
            4'h2: ABDCEFG = {7{MODE_SEG}} ^ 7'b0010010;
            4'h3: ABDCEFG = {7{MODE_SEG}} ^ 7'b0000110;
            4'h4: ABDCEFG = {7{MODE_SEG}} ^ 7'b1001100;
            4'h5: ABDCEFG = {7{MODE_SEG}} ^ 7'b0100100;
            4'h6: ABDCEFG = {7{MODE_SEG}} ^ 7'b0100000;
            4'h7: ABDCEFG = {7{MODE_SEG}} ^ 7'b0001111;
            4'h8: ABDCEFG = {7{MODE_SEG}} ^ 7'b0000000;
            4'h9: ABDCEFG = {7{MODE_SEG}} ^ 7'b0000100;
            4'hA: ABDCEFG = {7{MODE_SEG}} ^ 7'b0001000;
            4'hB: ABDCEFG = {7{MODE_SEG}} ^ 7'b1100000;
            4'hC: ABDCEFG = {7{MODE_SEG}} ^ 7'b0110001;
            4'hD: ABDCEFG = {7{MODE_SEG}} ^ 7'b1000010;
            4'hE: ABDCEFG = {7{MODE_SEG}} ^ 7'b0110000;
            4'hF: ABDCEFG = {7{MODE_SEG}} ^ 7'b0111000;
            default: ABDCEFG = 7'b0000000;
        endcase
    end
    
endmodule
