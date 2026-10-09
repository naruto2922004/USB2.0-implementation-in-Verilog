module link (
    input wire clk,
    input wire rst_n,
    
    input wire next_packet,
    input wire [3:0] tx_pid,
    input wire tx_fifo_empty,    
    input wire [7:0] tx_fifo_in, 
    output wire tx_fifo_read, 
    output wire tx_busy,
    
    input wire high_speed,
    input wire [1:0] speed,
    
    input wire rx_fifo_read,
    input wire rx_read_done,
    output wire [7:0] rx_fifo_out,
    output wire [3:0] rx_pid,
    output wire [1:0] rx_status
);

    
    wire tx_transfering;
    wire [7:0] tx_data_phy;
    wire tx_buffer_loaded;
    wire tx_packet_done;
    
    wire [7:0] rx_data_phy;
    wire rx_byte_valid;
    wire rx_packet_done;
    
    wire dp;
    wire dm;


    tx_link tx_link_inst (
        .clk(clk),
        .rst_n(rst_n),
        .next_packet(next_packet),
        .fifo_empty(tx_fifo_empty),
        .packet_done(tx_packet_done),
        .buffer_loaded(tx_buffer_loaded),
        .pid(tx_pid),
        .fifo_in(tx_fifo_in),
        .transfering(tx_transfering),
        .busy(tx_busy),
        .fifo_read(tx_fifo_read),
        .data_phy(tx_data_phy)
    );

    phy phy_inst (
        .clk(clk),
        .rst_n(rst_n),
        .high_speed(high_speed),
        .transfering(tx_transfering),
        .tx_data(tx_data_phy),
        .speed(speed),
        .rx_data(rx_data_phy),
        .rx_byte_valid(rx_byte_valid),
        .rx_packet_done(rx_packet_done),
        .tx_packet_done(tx_packet_done),
        .tx_buffer_loaded(tx_buffer_loaded),
        .dp(dp),
        .dm(dm)
    );

    rx_link rx_link_inst (
        .clk(clk),
        .rst_n(rst_n),
        .byte_valid(rx_byte_valid),    
        .phy_done(rx_packet_done),     
        .fifo_read(rx_fifo_read),      
        .read_done(rx_read_done),
        .phy_data(rx_data_phy),
        .fifo_out(rx_fifo_out),
        .pid(rx_pid),
        .status(rx_status)
    );

endmodule