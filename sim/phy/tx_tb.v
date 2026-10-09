`timescale 1ns/1ps

module tx_tb;


    reg clk;
    reg rst_n;

    reg transfering;
    reg [7:0] data;
    reg [1:0] speed;


    wire packet_done;
    wire buffer_loaded;
    wire dp;
    wire dm;

    tx_sim dut (
        .clk(clk),
        .rst_n(rst_n),
        .transfering(transfering),
        .data(data),
        .speed(speed),
        .packet_done(packet_done),
        .buffer_loaded(buffer_loaded),
        .dp(dp),
        .dm(dm)
    );

    initial
        clk = 1'b0;

    always
        #10 clk = ~clk;

    initial begin

        rst_n       = 0;
        transfering = 0;
        data        = 8'h00;
        speed       = 2'b01; 

        repeat(3)
            @(posedge clk);

        rst_n = 1;

        @(posedge clk);

        transfering = 1;
        data = 8'h12; 

        while (!buffer_loaded)
            @(posedge clk);

        @(posedge clk);
        data = 8'h34; 

        while (!buffer_loaded)
            @(posedge clk);

        @(posedge clk);
        data = 8'h56; 

        while (!buffer_loaded)
            @(posedge clk);

        @(posedge clk);
        transfering = 0;
        data = 8'h00;

        while (!packet_done)
            @(posedge clk);

        repeat(5)
            @(posedge clk);

        
        
        @(posedge clk);

        transfering = 1;
        data = 8'h12; 

        while (!buffer_loaded)
            @(posedge clk);

        @(posedge clk);
        data = 8'h34; 

        while (!buffer_loaded)
            @(posedge clk);

        @(posedge clk);
        data = 8'h56; 

        while (!buffer_loaded)
            @(posedge clk);

        @(posedge clk);
        transfering = 0;
        data = 8'h00;

        while (!packet_done)
            @(posedge clk);

        repeat(5)
            @(posedge clk);

        $stop;
    end

endmodule