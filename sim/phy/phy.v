module phy (
    input clk,
    input rst_n,
    input high_speed,
    input transfering,
    input [7:0] tx_data,
    input [1:0] speed,
    output [7:0] rx_data,
    output rx_byte_valid,
    output rx_packet_done,
    output tx_packet_done,
    output tx_buffer_loaded,
    inout dp,
    inout dm
);

    tx_sim u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .transfering(transfering),
        .data(tx_data),
        .speed(speed),
        .packet_done(tx_packet_done),
        .buffer_loaded(tx_buffer_loaded),
        .dp(dp),
        .dm(dm)
    );

    rx_sim u_rx (
        .clk(clk),
        .rst_n(rst_n),
        .dp(dp),
        .dm(dm),
        .high_speed(high_speed),
        .data(rx_data),
        .byte_valid(rx_byte_valid),
        .packet_done(rx_packet_done)
    );

endmodule
