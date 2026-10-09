module phy_link #(
    parameter CLK_FREQ = 48_000_000,
    parameter MAX_SPEED = 2'b11
)(
    
    input clk,
    input por_rst_n,
    input connected,
    
    
    input dev_next_packet,
    input dev_tx_fifo_wr,
    input dev_rx_fifo_read,
    input dev_rx_read_done,
    input dev_accept_data,
    input dev_fifo_rst_in,
    input [7:0] dev_tx_fifo_in,
    input [3:0] dev_tx_pid,
    input [3:0] dev_rx_pid,
    output [1:0] dev_speed,
    output [1:0] dev_rx_status,
    output [7:0] dev_rx_fifo_out,
    output dev_tx_busy,
    output dev_tx_fifo_full,
    output dev_rst_n,
    output dev_data_pid_valid,
    
    
    input host_start_rst,
    input host_next_packet,
    input host_tx_fifo_wr,
    input host_rx_fifo_read,
    input host_rx_read_done,
    input host_fifo_rst_in,
    input host_accept_data,                            
    input [7:0] host_tx_fifo_in,
    input [3:0] host_tx_pid,
    input [3:0] host_rx_pid,
    output [1:0] host_speed,
    output [1:0] host_rx_status,
    output [7:0] host_rx_fifo_out,
    output host_reset_busy,
    output host_tx_busy,
    output host_tx_fifo_full,
    output host_data_pid_valid,
    
    output w_idle
);

    
    wire w_dp, w_dm;
    wire w_dev_tx_dp, w_dev_tx_dm, w_dev_en;
    wire w_host_tx_dp, w_host_tx_dm, w_host_en;

    device_phy_link #(
        .CLK_FREQ(CLK_FREQ),
        .MAX_SPEED(MAX_SPEED)
    ) u_device (
        .clk(clk),
        .por_rst_n(por_rst_n),
        .idle(w_idle),
        .connected(connected),
        .rx_dp(w_dp),
        .rx_dm(w_dm),
        .accept_data(dev_accept_data),
        .next_packet(dev_next_packet),
        .tx_fifo_wr(dev_tx_fifo_wr),
        .rx_fifo_read(dev_rx_fifo_read),
        .rx_read_done(dev_rx_read_done),
        .fifo_rst_in(dev_fifo_rst_in),
        .tx_fifo_in(dev_tx_fifo_in),
        .tx_pid(dev_tx_pid),
        .rx_pid(dev_rx_pid),
        .rx_status(dev_rx_status),
        .speed(dev_speed),
        .rx_fifo_out(dev_rx_fifo_out),
        .tx_dp(w_dev_tx_dp),
        .tx_dm(w_dev_tx_dm),
        .device_en(w_dev_en),
        .tx_busy(dev_tx_busy),
        .tx_fifo_full(dev_tx_fifo_full),
        .device_rst_n(dev_rst_n),
        .data_pid_valid(dev_data_pid_valid)
    );

    host_phy_link #(
        .CLK_FREQ(CLK_FREQ)
    ) u_host (
        .clk(clk),
        .por_rst_n(por_rst_n),
        .idle(w_idle),
        .connected(connected),
        .rx_dp(w_dp),
        .rx_dm(w_dm),
        .start_rst(host_start_rst),
        .next_packet(host_next_packet),
        .tx_fifo_wr(host_tx_fifo_wr),
        .rx_fifo_read(host_rx_fifo_read),
        .rx_read_done(host_rx_read_done),
        .fifo_rst_in(host_fifo_rst_in),
        .accept_data(host_accept_data),
        .tx_fifo_in(host_tx_fifo_in),
        .tx_pid(host_tx_pid),
        .rx_pid(host_rx_pid),
        .speed(host_speed),
        .rx_status(host_rx_status),
        .rx_fifo_out(host_rx_fifo_out),
        .tx_dp(w_host_tx_dp),
        .tx_dm(w_host_tx_dm),
        .host_en(w_host_en),
        .reset_busy(host_reset_busy),
        .tx_busy(host_tx_busy),
        .tx_fifo_full(host_tx_fifo_full),
        .data_pid_valid(host_data_pid_valid)
    );

    bus u_bus (
        .host_dp(w_host_tx_dp),
        .host_dm(w_host_tx_dm),
        .device_dp(w_dev_tx_dp),
        .device_dm(w_dev_tx_dm),
        .device_en(w_dev_en),
        .host_en(w_host_en),
        .connected(connected),
        .speed(dev_speed),
        .dp(w_dp),
        .dm(w_dm),
        .idle(w_idle)
    );

endmodule