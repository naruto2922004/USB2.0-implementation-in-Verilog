`timescale 1ns/1ps

module phy_tb;

    
    reg clk;
    reg rst_n;
    reg high_speed;
    reg transfering;
    reg [7:0] tx_data;
    reg [1:0] speed;

    
    wire [7:0] rx_data;
    wire rx_byte_valid;
    wire rx_packet_done;
    wire tx_packet_done;
    wire tx_buffer_loaded;

    
    wire dp;
    wire dm;

    
    phy dut (
        .clk(clk),
        .rst_n(rst_n),
        .high_speed(high_speed),
        .transfering(transfering),
        .tx_data(tx_data),
        .speed(speed),
        .rx_data(rx_data),
        .rx_byte_valid(rx_byte_valid),
        .rx_packet_done(rx_packet_done),
        .tx_packet_done(tx_packet_done),
        .tx_buffer_loaded(tx_buffer_loaded),
        .dp(dp),
        .dm(dm)
    );

    
    initial clk = 1'b0;
    always #10 clk = ~clk;

    
    initial begin
        rst_n       = 0;
        high_speed  = 1;
        transfering = 0;
        tx_data     = 8'h00;
        speed       = 2'b11; 

        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        
        transfering = 1;
        tx_data = 8'h12;

        while (!tx_buffer_loaded) @(posedge clk);
        @(posedge clk);
        tx_data = 8'hfb;

        while (!tx_buffer_loaded) @(posedge clk);
        @(posedge clk);
        tx_data = 8'h5e;

        while (!tx_buffer_loaded) @(posedge clk);
        @(posedge clk);
        transfering = 0;
        tx_data = 8'h00;

        while (!tx_packet_done) @(posedge clk);
        repeat(5) @(posedge clk);

        
        @(posedge clk);
        transfering = 1;
        tx_data = 8'hff;

        while (!tx_buffer_loaded) @(posedge clk);
        @(posedge clk);
        tx_data = 8'h34;

        while (!tx_buffer_loaded) @(posedge clk);
        @(posedge clk);
        tx_data = 8'h96;

        while (!tx_buffer_loaded) @(posedge clk);
        @(posedge clk);
        transfering = 0;
        tx_data = 8'h00;

        while (!tx_packet_done) @(posedge clk);
        repeat(5) @(posedge clk);
        
        $stop;
    end

endmodule