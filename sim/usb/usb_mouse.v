module usb_mouse #(
    parameter CLK_FREQ = 48_000_000,
    parameter MAX_SPEED = 2'b11
)(
    
    input wire clk,
    input wire por_rst_n,
    input wire connected,

    
    input  wire sw_request_valid,
    input  wire [63:0] sw_request,
    input  wire [6:0] sw_vacant_address,
    output wire sw_address_ack,
    input  wire sw_transfer_start,
    input  wire [3:0] sw_endpoint,
    input  wire [1:0] sw_transfer_type,
    input  wire sw_direction,
    input  wire [7:0] sw_interval,
    output wire [3:0] sw_status,
    output wire sw_rx_valid,
    output wire [2:0] sw_rx_type,
    output wire sw_rx_fifo_empty,
    input  wire sw_rx_fifo_read,
    input  wire sw_rx_read_done,
    output wire [7:0] sw_rx_fifo_out,

    
    input  wire [63:0] ep1_in,
    input  wire ep1_valid,
    output wire ep1_sent
);


    
    
    wire idle;
    wire fifo_rst_n;
    wire host_start_rst;
    wire host_next_packet;
    wire host_tx_fifo_wr;
    wire host_rx_fifo_read;
    wire host_rx_read_done;
    wire [7:0] host_tx_fifo_in;
    wire [3:0] host_tx_pid;
    wire [3:0] host_rx_pid;
    wire [1:0] host_rx_status;
    wire [7:0] host_rx_fifo_out;
    wire host_reset_busy;
    wire host_tx_busy;
    wire host_tx_fifo_full;
    wire host_rx_data_pid_valid;
    wire host_rx_accept_data;           

    
    wire dev_next_packet;
    wire dev_tx_fifo_wr;
    wire dev_rx_fifo_read;
    wire dev_rx_read_done;
    wire [7:0] dev_tx_fifo_in;
    wire [3:0] dev_tx_pid;
    wire [3:0] dev_rx_pid;
    wire [1:0] dev_rx_status, dev_speed, host_speed;
    wire [7:0] dev_rx_fifo_out;
    wire dev_tx_busy;
    wire dev_tx_fifo_full;
    wire dev_fifo_rst_n;
    wire dev_rst_n;
    wire device_rx_data_pid_valid;
    wire device_rx_accept_data;
    


    
    phy_link #(
        .CLK_FREQ(CLK_FREQ),
        .MAX_SPEED(MAX_SPEED)
    ) u_phy_link (
        .clk               (clk),
        .por_rst_n         (por_rst_n),
        .connected         (connected),
        
        
        .dev_next_packet   (dev_next_packet),
        .dev_tx_fifo_wr    (dev_tx_fifo_wr),
        .dev_rx_fifo_read  (dev_rx_fifo_read),
        .dev_rx_read_done  (dev_rx_read_done),
        .dev_accept_data   (device_rx_accept_data),
        .dev_fifo_rst_in   (dev_fifo_rst_n),
        .dev_tx_fifo_in    (dev_tx_fifo_in),
        .dev_tx_pid        (dev_tx_pid),
        .dev_rx_pid        (dev_rx_pid),
        .dev_speed         (dev_speed),
        .dev_rx_status     (dev_rx_status),
        .dev_rx_fifo_out   (dev_rx_fifo_out),
        .dev_tx_busy       (dev_tx_busy),
        .dev_tx_fifo_full  (dev_tx_fifo_full),
        .dev_rst_n         (dev_rst_n),
        .dev_data_pid_valid(device_rx_data_pid_valid),
        
        
        .host_start_rst    (host_start_rst),
        .host_next_packet  (host_next_packet),
        .host_tx_fifo_wr   (host_tx_fifo_wr),
        .host_rx_fifo_read (host_rx_fifo_read),
        .host_rx_read_done (host_rx_read_done),
        .host_fifo_rst_in  (fifo_rst_n),
        .host_accept_data  (host_rx_accept_data),
        .host_tx_fifo_in   (host_tx_fifo_in),
        .host_tx_pid       (host_tx_pid),
        .host_rx_pid       (host_rx_pid),
        .host_speed        (host_speed),
        .host_rx_status    (host_rx_status),
        .host_rx_fifo_out  (host_rx_fifo_out),
        .host_reset_busy   (host_reset_busy),
        .host_tx_busy      (host_tx_busy),
        .host_tx_fifo_full (host_tx_fifo_full),
        .host_data_pid_valid(host_rx_data_pid_valid),
        .w_idle            (idle)
    );

    
    host_protocol #(
        .CLK_FREQ(CLK_FREQ)
    ) u_host_protocol (
        .clk                    (clk),
        .por_rst_n              (por_rst_n),
        .connected              (connected),
        .idle                   (idle),
        .speed                  (host_speed),
        
        
        .host_reset_busy        (host_reset_busy),
        .host_tx_busy           (host_tx_busy),
        .host_tx_fifo_full      (host_tx_fifo_full),
        .host_rx_data_pid_valid (host_rx_data_pid_valid),
        .host_rx_status         (host_rx_status),
        .host_rx_fifo_out       (host_rx_fifo_out),
        .host_rx_pid            (host_rx_pid),
        .host_sw_rx_fifo_read   (host_rx_fifo_read),
        .host_sw_rx_read_done   (host_rx_read_done),
        .host_rx_accept_data    (host_rx_accept_data),
        .fifo_rst_n             (fifo_rst_n),
        .host_start_rst         (host_start_rst),
        .host_tx_next_packet    (host_next_packet),
        .host_tx_fifo_wr        (host_tx_fifo_wr),
        .host_tx_fifo_in        (host_tx_fifo_in),
        .host_tx_pid            (host_tx_pid),
        
        
        .sw_status              (sw_status),
        .sw_request_valid       (sw_request_valid),
        .sw_request             (sw_request),
        .sw_vacant_address      (sw_vacant_address),
        .sw_address_ack         (sw_address_ack),
        .sw_transfer_start      (sw_transfer_start),
        .sw_endpoint            (sw_endpoint),
        .sw_transfer_type       (sw_transfer_type),
        .sw_direction           (sw_direction),
        .sw_interval            (sw_interval),
        .sw_rx_valid            (sw_rx_valid),
        .sw_rx_type             (sw_rx_type),
        .sw_rx_fifo_empty       (sw_rx_fifo_empty),
        .sw_rx_fifo_read        (sw_rx_fifo_read),
        .sw_rx_read_done        (sw_rx_read_done),
        .sw_rx_fifo_out         (sw_rx_fifo_out),
        .sw_reset               (1'b0)
    );

    
    mouse_protocol #(
        .CLK_FREQ(CLK_FREQ)
    ) u_keyboard_protocol (
        .clk                      (clk),
        .rst_n                    (dev_rst_n), 
        .connected                (connected),
        .idle                     (idle),
        .speed                    (dev_speed),
        
        
        .device_tx_busy           (dev_tx_busy),
        .device_tx_fifo_full      (dev_tx_fifo_full),
        .device_rx_data_pid_valid (device_rx_data_pid_valid),
        .device_rx_status         (dev_rx_status),
        .device_rx_fifo_out       (dev_rx_fifo_out),
        .device_rx_pid            (dev_rx_pid),
        .device_rx_fifo_read      (dev_rx_fifo_read),
        .device_fifo_rst_n        (dev_fifo_rst_n),
        
        .device_rx_read_done      (dev_rx_read_done),
        .device_rx_accept_data    (device_rx_accept_data),
        .device_tx_next_packet    (dev_next_packet),
        .device_tx_fifo_wr        (dev_tx_fifo_wr),
        .device_tx_fifo_in        (dev_tx_fifo_in),
        .device_tx_pid            (dev_tx_pid),
        
        
        .ep1_in                   (ep1_in),
        .ep1_valid                (ep1_valid),
        .ep1_sent                 (ep1_sent)
    );

endmodule