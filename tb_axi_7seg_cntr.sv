`include "axi_lite_template/agent_axi_lite.sv"

module tb_axi_7seg_cntr;

    const integer t_clk   = 10;    // Clock period 100MHz

    // Test mismatch: NDISP != DATA_WIDTH
    localparam NDISP            = 8;
    localparam bit MODE_DISP    = 1; // 0: common anode, 1: common cathode
    localparam bit MODE_SEG     = 1; // 0: common anode, 1: common cathode
    localparam ADDR_WIDTH       = 5;
    localparam DATA_WIDTH       = 32;

    localparam ADDR_SEG  = 0;
    localparam ADDR_DP   = 4;

    logic [NDISP-1:0]         seg;
    logic [6:0]               ABDCEFG;
    logic                     DP;

    axi_if #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) axi_if();

    axi_lite_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) master;


    axi_7seg_cntr #(
        .NDISP(NDISP),
        .MODE_DISP(MODE_DISP),
        .MODE_SEG(MODE_SEG),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) dut (
        .clk        (axi_if.clk),
        .nrst       (axi_if.nrst),

        // AXI4-Lite SLAVE
        .awaddr     (axi_if.awaddr),
        .awprot     (axi_if.awprot),
        .awvalid    (axi_if.awvalid),
        .awready    (axi_if.awready),

        .wdata      (axi_if.wdata),
        .wstrb      (axi_if.wstrb),
        .wvalid     (axi_if.wvalid),
        .wready     (axi_if.wready),

        .bresp      (axi_if.bresp),
        .bvalid     (axi_if.bvalid),
        .bready     (axi_if.bready),

        .araddr     (axi_if.araddr),
        .arprot     (axi_if.arprot),
        .arvalid    (axi_if.arvalid),
        .arready    (axi_if.arready),

        .rdata      (axi_if.rdata),
        .rresp      (axi_if.rresp),
        .rvalid     (axi_if.rvalid),
        .rready     (axi_if.rready),

        // 7-segment display outputs
        .seg        (seg),
        .ABDCEFG    (ABDCEFG),
        .DP         (DP)
    );


    // Clock generation 
    initial begin
        axi_if.clk = 0;
        forever #(t_clk/2) axi_if.clk = ~axi_if.clk;
    end

    // Reset generation and initialization
    initial begin
        axi_if.nrst = 0;
        master = new(axi_if);
        master.reset_if();
        #100 @(posedge axi_if.clk);
        axi_if.nrst = 1;
        @(posedge axi_if.clk);
    end

    initial begin
        logic [DATA_WIDTH-1:0] read_data;
        @(posedge axi_if.nrst);
        @(posedge axi_if.clk);

        // Write to all displays
        master.write(32'h12345678, ADDR_SEG, 4'b1111);
        master.write(8'b10101010, ADDR_DP, 4'b1111);


        // Read back and check
        master.read(read_data, ADDR_SEG);
        if (read_data !== 32'h12345678) begin
            $error("Mismatch in SEG readback: expected 0x12345678, got 0x%h", read_data);
        end
        master.read(read_data, ADDR_DP);
        if (read_data !== 8'b10101010) begin
            $error("Mismatch in DP readback: expected 0b10101010, got 0b%b", read_data);
        end

        $display("All tests passed.");
        #1000000000;
    end

endmodule