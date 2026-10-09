`timescale 1ns/1ps
module link_tb;

    reg clk;
    reg rst_n;
    
    reg next_packet;
    reg [3:0] tx_pid;
    reg tx_fifo_empty;
    reg [7:0] tx_fifo_in;
    wire tx_fifo_read;
    wire tx_busy;
    
    reg high_speed;
    reg [1:0] speed;
    
    reg rx_fifo_read;
    reg rx_read_done;
    wire [7:0] rx_fifo_out;
    wire [3:0] rx_pid;
    wire [1:0] rx_status;

    reg [7:0] mem [0:2];
    reg [1:0] read_ptr;

    link dut (
        .clk(clk),
        .rst_n(rst_n),
        .next_packet(next_packet),
        .tx_pid(tx_pid),
        .tx_fifo_empty(tx_fifo_empty),
        .tx_fifo_in(tx_fifo_in),
        .tx_fifo_read(tx_fifo_read),
        .tx_busy(tx_busy),
        .high_speed(high_speed),
        .speed(speed),
        .rx_fifo_read(rx_fifo_read),
        .rx_read_done(rx_read_done),
        .rx_fifo_out(rx_fifo_out),
        .rx_pid(rx_pid),
        .rx_status(rx_status)
    );

    always #5 clk = ~clk;

    initial begin
        clk = 0;
        rst_n = 0;
        next_packet = 0;
        tx_pid = 4'd0;
        tx_fifo_empty = 0;
        tx_fifo_in = 8'd0;
        high_speed = 1'b0;
        speed = 2'b01;
        rx_fifo_read = 0;
        rx_read_done = 0;
        
        mem[0] = 8'h00;
        mem[1] = 8'h00;
        mem[2] = 8'h00;
        read_ptr = 2'd0;

        repeat(3) @(posedge clk);
        rst_n = 1;

        @(posedge clk);
        tx_pid = 4'b0010; 
        next_packet = 1;
        
        @(posedge clk);
        next_packet = 0;
    end



always @(posedge clk) begin

    if (!rst_n) begin
        tx_fifo_in    <= 8'd0;
        tx_fifo_empty <= 1'b0;
        read_ptr      <= 2'd0;
    end
    else begin
        if (tx_fifo_read) begin
            tx_fifo_in <= mem[read_ptr];

            if (read_ptr == 2'd0) begin
                tx_fifo_empty <= 1'b1;
            end
            else begin
                read_ptr <= read_ptr + 1'b1;
            end
        end
    end
end

always @(posedge clk) begin
    if (!rst_n) begin
        rx_fifo_read <= 1'b0;
        rx_read_done <= 1'b0;
    end
    else begin

        
        rx_read_done <= 1'b0;

        case (rx_status)

            2'b01: begin
                rx_fifo_read <= 1'b1;
            end

            2'b10: begin
                if (rx_fifo_read)
                    rx_fifo_read <= 1'b0;

                rx_read_done <= 1'b1;
            end

            2'b11: begin
                rx_fifo_read <= 1'b0;
                rx_read_done <= 1'b1;
            end

            default: begin
                rx_fifo_read <= 1'b0;
            end

        endcase
    end
end

endmodule