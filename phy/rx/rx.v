module rx(
    input clk, rst_n, idle,
    input [1:0] line_state, speed,
    output [7:0] data,
    output byte_valid, packet_done
);  
    wire high_speed, nrzi_out, bitunstuffer_out, sync_detected, halt;

    assign high_speed = (speed == 2'b11);

    nrzi_decoder u_nrzi_decoder (
        .clk(clk),
        .rst_n(rst_n),
        .line_state(line_state),
        .data_out(nrzi_out)
    );

    bitunstuffer u_bitunstuffer (
        .clk(clk),
        .rst_n(rst_n),
        .idle(idle),
        .data_in(nrzi_out),
        .data_out(bitunstuffer_out),
        .stall_downstream(halt)
    );

    sync_detect u_sync_detect (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(bitunstuffer_out),
        .high_speed(high_speed),
        .idle(idle),
        .line_state(line_state),
        .sync_detected(sync_detected),
        .packet_done(packet_done)
    );

    deserializer u_deserializer (
        .clk(clk),
        .rst_n(rst_n),
        .serial_in(bitunstuffer_out),
        .sync_detect(sync_detected),
        .halt(halt),
        .data_out(data),
        .byte_valid(byte_valid)
    );


endmodule
