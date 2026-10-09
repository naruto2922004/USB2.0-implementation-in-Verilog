module host_phy_link #(
    parameter CLK_FREQ = 48_000_000
)(
    input clk, por_rst_n, idle, connected, rx_dp, rx_dm, start_rst, 
    input next_packet, tx_fifo_wr, rx_fifo_read, rx_read_done, fifo_rst_in, accept_data,
    input [7:0] tx_fifo_in,
    input [3:0] tx_pid, rx_pid,
    output [1:0] speed,
    output [1:0] rx_status,
    output [7:0] rx_fifo_out,
    output tx_dp, tx_dm, host_en, reset_busy, tx_busy, tx_fifo_full, data_pid_valid
);
    wire [7:0] data;
    wire rst_n, nrzi_serial_valid, tx_packet_done, rx_packet_done, fifo_rst_n;
    wire transfering, fifo_empty, buffer_loaded, fifo_read, byte_valid;
    wire [1:0] tx_line_state, rx_line_state;
    wire [7:0] tx_data, rx_data, fifo_out;

    assign fifo_rst_n = !(!por_rst_n || !fifo_rst_in);

    host_diff #(
        .CLK_FREQ(CLK_FREQ)
    ) u_host_diff (
        .clk(clk),
        .por_rst_n(por_rst_n),
        .nrzi_serial_valid(nrzi_serial_valid),
        .packet_done(tx_packet_done),
        .idle(idle),
        .connected(connected),
        .tx_line_state(tx_line_state),
        .tx_dp(tx_dp),
        .tx_dm(tx_dm),
        .host_en(host_en),
        .rx_dp(rx_dp),
        .rx_dm(rx_dm),
        .rx_line_state(rx_line_state),
        .start_rst(start_rst),
        .reset_busy(reset_busy),
        .speed(speed)
    );


    tx u_host_tx(
        .clk(clk),
        .rst_n(por_rst_n),
        .transfering(transfering),
        .data(data),
        .speed(speed),
        .packet_done(tx_packet_done),
        .buffer_loaded(buffer_loaded),
        .nrzi_serial_valid(nrzi_serial_valid),
        .line_state(tx_line_state)
    );

    rx u_host_rx(
        .clk(clk),
        .rst_n(por_rst_n),
        .idle(idle),
        .line_state(rx_line_state),
        .speed(speed),
        .data(rx_data),
        .byte_valid(byte_valid),
        .packet_done(rx_packet_done)
    );

    tx_link u_tx_link(
        .clk(clk),
        .rst_n(por_rst_n),
        .next_packet(next_packet),
        .fifo_empty(fifo_empty),
        .packet_done(tx_packet_done),
        .buffer_loaded(buffer_loaded),
        .pid(tx_pid),
        .fifo_out(fifo_out),
        .transfering(transfering),
        .busy(tx_busy),
        .fifo_read(fifo_read),
        .data_phy(data)
    );

    sync_fifo #(
        .DEPTH(1024),
        .WIDTH(8),
        .PTR_WIDTH(10)
    ) u_sync_fifo (
        .clk(clk),
        .rst_n(por_rst_n),
        .wr_en(tx_fifo_wr),
        .rd_en(fifo_read),
        .din(tx_fifo_in),
        .full(tx_fifo_full),
        .empty(fifo_empty),
        .dout(fifo_out)
    );

    rx_link u_rx_link(
        .clk(clk),
        .rst_n(por_rst_n),
        .byte_valid(byte_valid),
        .phy_done(rx_packet_done),
        .fifo_read(rx_fifo_read),
        .read_done(rx_read_done),
        .accept_data(accept_data),
        .fifo_rst_in(fifo_rst_n),
        .phy_data(rx_data),
        .fifo_out(rx_fifo_out),
        .pid(rx_pid),
        .status(rx_status),
        .data_pid_valid(data_pid_valid)
    );


endmodule