`timescale 1ns/1ps

module phy_link_tb;

    localparam CLK_FREQ   = 48_000_000;
    localparam MAX_SPEED  = 2'b11;
    localparam CLK_PERIOD = 2; 

    
    reg clk;
    reg por_rst_n;
    reg connected;


    reg        dev_next_packet;
    reg        dev_tx_fifo_wr;
    reg        dev_rx_fifo_read;
    reg        dev_rx_read_done;
    reg [7:0]  dev_tx_fifo_in;
    reg [3:0]  dev_tx_pid;
    reg [3:0]  dev_rx_pid;
    wire [1:0] dev_rx_status;
    wire [7:0] dev_rx_fifo_out;
    wire       dev_tx_busy;
    wire       dev_tx_fifo_full;
    wire       dev_rst_n;

    reg        host_start_rst;
    reg        host_next_packet;
    reg        host_tx_fifo_wr;
    reg        host_rx_fifo_read;
    reg        host_rx_read_done;
    reg [7:0]  host_tx_fifo_in;
    reg [3:0]  host_tx_pid;
    reg [3:0]  host_rx_pid;
    wire [1:0] host_rx_status;
    wire [7:0] host_rx_fifo_out;
    wire       host_reset_busy;
    wire       host_tx_busy;
    wire       host_tx_fifo_full;

    reg [7:0] host_payload [0:7];
    reg [7:0] dev_payload  [0:7];
    integer   i;


    reg [8*24-1:0] tb_phase; 
    reg [8*24-1:0] tb_stage; 


    phy_link #(
        .CLK_FREQ (CLK_FREQ),
        .MAX_SPEED(MAX_SPEED)
    ) dut (
        .clk               (clk),
        .por_rst_n         (por_rst_n),
        .connected         (connected),

        .dev_next_packet   (dev_next_packet),
        .dev_tx_fifo_wr    (dev_tx_fifo_wr),
        .dev_rx_fifo_read  (dev_rx_fifo_read),
        .dev_rx_read_done  (dev_rx_read_done),
        .dev_tx_fifo_in    (dev_tx_fifo_in),
        .dev_tx_pid        (dev_tx_pid),
        .dev_rx_pid        (dev_rx_pid),
        .dev_rx_status     (dev_rx_status),
        .dev_rx_fifo_out   (dev_rx_fifo_out),
        .dev_tx_busy       (dev_tx_busy),
        .dev_tx_fifo_full  (dev_tx_fifo_full),
        .dev_rst_n         (dev_rst_n),

        .host_start_rst    (host_start_rst),
        .host_next_packet  (host_next_packet),
        .host_tx_fifo_wr   (host_tx_fifo_wr),
        .host_rx_fifo_read (host_rx_fifo_read),
        .host_rx_read_done (host_rx_read_done),
        .host_tx_fifo_in   (host_tx_fifo_in),
        .host_tx_pid       (host_tx_pid),
        .host_rx_pid       (host_rx_pid),
        .host_rx_status    (host_rx_status),
        .host_rx_fifo_out  (host_rx_fifo_out),
        .host_reset_busy   (host_reset_busy),
        .host_tx_busy      (host_tx_busy),
        .host_tx_fifo_full (host_tx_fifo_full)
    );


    initial clk = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;


    task wait_dev_rst_n_posedge;
        begin
            tb_stage = "WAIT_DEV_RST_POSEDGE";
            @(posedge dev_rst_n);
        end
    endtask


    task wait_dev_rst_n_reconnect;
        begin
            tb_stage = "WAIT_DEV_RST_NEGEDGE";
            if (dev_rst_n == 1'b1) begin
                @(negedge dev_rst_n);
            end
            tb_stage = "WAIT_DEV_RST_POSEDGE";
            @(posedge dev_rst_n);
        end
    endtask


    task host_to_device_transfer;
        input [3:0] pid;
        integer idx;
        begin

            tb_stage = "H2D_LOAD_TX_FIFO";
            @(posedge clk);
            host_tx_fifo_wr <= 1'b1;
            for (idx = 0; idx < 8; idx = idx + 1) begin
                host_tx_fifo_in <= host_payload[idx];
                @(posedge clk);
            end
            host_tx_fifo_wr <= 1'b0;


            tb_stage = "H2D_START_TX";
            host_tx_pid      <= pid;
            host_next_packet <= 1'b1;
            @(posedge clk);
            host_next_packet <= 1'b0;

            tb_stage = "H2D_WAIT_TX_BUSY_ASSERT";
            @(posedge clk);
            while (host_tx_busy == 1'b0) begin
                @(posedge clk);
            end
            tb_stage = "H2D_WAIT_TX_BUSY_DEASSERT";
            while (host_tx_busy == 1'b1) begin
                @(posedge clk);
            end

            tb_stage = "H2D_WAIT_RX_STATUS";
            @(posedge clk);
            while (dev_rx_status == 2'b00) begin
                @(posedge clk);
            end

            if (dev_rx_status == 2'b01) begin
                tb_stage = "H2D_READ_RX_FIFO";
                dev_rx_fifo_read <= 1'b1;
                while (dev_rx_status == 2'b01) begin
                    @(posedge clk);
                end
                dev_rx_fifo_read <= 1'b0;
                @(posedge clk);
            end

            tb_stage = "H2D_RX_READ_DONE_PULSE";
            dev_rx_read_done <= 1'b1;
            @(posedge clk);
            dev_rx_read_done <= 1'b0;

            tb_stage = "H2D_COMPLETE";
        end
    endtask


    task device_to_host_transfer;
        input [3:0] pid;
        integer idx;
        begin
            
            tb_stage = "D2H_LOAD_TX_FIFO";
            @(posedge clk);
            dev_tx_fifo_wr <= 1'b1;
            for (idx = 0; idx < 8; idx = idx + 1) begin
                dev_tx_fifo_in <= dev_payload[idx];
                @(posedge clk);
            end
            dev_tx_fifo_wr <= 1'b0;


            tb_stage = "D2H_START_TX";
            dev_tx_pid      <= pid;
            dev_next_packet <= 1'b1;
            @(posedge clk);
            dev_next_packet <= 1'b0;


            tb_stage = "D2H_WAIT_TX_BUSY_ASSERT";
            @(posedge clk);
            while (dev_tx_busy == 1'b0) begin
                @(posedge clk);
            end
            tb_stage = "D2H_WAIT_TX_BUSY_DEASSERT";
            while (dev_tx_busy == 1'b1) begin
                @(posedge clk);
            end


            tb_stage = "D2H_WAIT_RX_STATUS";
            @(posedge clk);
            while (host_rx_status == 2'b00) begin
                @(posedge clk);
            end

            if (host_rx_status == 2'b01) begin
                tb_stage = "D2H_READ_RX_FIFO";
                host_rx_fifo_read <= 1'b1;
                while (host_rx_status == 2'b01) begin
                    @(posedge clk);
                end
                host_rx_fifo_read <= 1'b0;
                @(posedge clk);
            end

            tb_stage = "D2H_RX_READ_DONE_PULSE";
            host_rx_read_done <= 1'b1;
            @(posedge clk);
            host_rx_read_done <= 1'b0;

            tb_stage = "D2H_COMPLETE";
        end
    endtask


    initial begin
        tb_phase = "INIT";
        tb_stage = "SIGNAL_INIT";

        por_rst_n         = 1'b0;
        connected         = 1'b0;

        dev_next_packet   = 1'b0;
        dev_tx_fifo_wr    = 1'b0;
        dev_rx_fifo_read  = 1'b0;
        dev_rx_read_done  = 1'b0;
        dev_tx_fifo_in    = 8'h00;
        dev_tx_pid        = 4'h0;
        dev_rx_pid        = 4'h0;

        host_start_rst    = 1'b0;
        host_next_packet  = 1'b0;
        host_tx_fifo_wr   = 1'b0;
        host_rx_fifo_read = 1'b0;
        host_rx_read_done = 1'b0;
        host_tx_fifo_in   = 8'h00;
        host_tx_pid       = 4'h0;
        host_rx_pid       = 4'h0;


        for (i = 0; i < 8; i = i + 1) begin
            host_payload[i] = i + 8'h10;
            dev_payload[i]  = i + 8'h80;
        end

        tb_phase = "POR_RESET";
        tb_stage = "ASSERT_POR_RST";
        repeat (10) @(posedge clk);
        por_rst_n = 1'b1;
        tb_stage = "POR_RST_RELEASED";
        repeat (5) @(posedge clk);


        tb_phase = "INITIAL_CONNECT";
        tb_stage = "ASSERT_CONNECTED";
        connected = 1'b1;
        wait_dev_rst_n_posedge;
        tb_stage = "CONNECT_RESET_DONE";


        tb_phase = "HOST_RESET";
        tb_stage = "PULSE_HOST_START_RST";
        @(posedge clk);
        host_start_rst = 1'b1;
        @(posedge clk);
        host_start_rst = 1'b0;
        wait_dev_rst_n_posedge;
        tb_stage = "HOST_RESET_DONE";

        tb_phase = "INITIAL_H2D";
        host_to_device_transfer(4'h3);

        tb_phase = "INITIAL_D2H";
        device_to_host_transfer(4'hB);

        tb_phase = "DISCONNECT";
        tb_stage = "DEASSERT_CONNECTED";
        connected = 1'b0;
        repeat (10) @(posedge clk);

        tb_phase = "RECONNECT";
        tb_stage = "ASSERT_CONNECTED";
        connected = 1'b1;
        wait_dev_rst_n_reconnect;
        tb_stage = "RECONNECT_RESET_DONE";

        tb_phase = "RECONNECT_H2D";
        host_to_device_transfer(4'h3);

        tb_phase = "RECONNECT_D2H";
        device_to_host_transfer(4'hB);

        tb_phase = "DONE";
        tb_stage = "TEST_COMPLETE";
        repeat (20) @(posedge clk);
        $finish;
    end

endmodule