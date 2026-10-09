module rx_sim(
    input clk, rst_n, dp, dm, high_speed,
    output [7:0] data,
    output byte_valid, packet_done
);  
    wire full_speed, nrzi_out, bitunstuffer_out, sync_detected, halt, SE0_detected;
    wire [1:0] line_state;
    assign SE0_detected = !dp && !dm;
    reg SE0_buff;

    diff_rx_sampler u_diff_rx_sampler (
        .clk(clk),
        .rst_n(rst_n),
        .dp(dp),
        .dm(dm),
        .full_speed(full_speed),
        .line_state(line_state)
    );

    nrzi_decoder u_nrzi_decoder (
        .clk(clk),
        .rst_n(rst_n),
        .line_state(line_state),
        .full_speed(full_speed),
        .data_out(nrzi_out)
    );

    eop_detect u_eop_detect (
        .clk(clk),
        .rst_n(rst_n),
        .line_state(line_state),
        .full_speed(full_speed),
        .eop_detected(packet_done)
    );

    bitunstuffer u_bitunstuffer (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(nrzi_out),
        .full_speed(full_speed),
        .data_out(bitunstuffer_out),
        .stall_downstream(halt)
    );

    sync_detect u_sync_detect (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(bitunstuffer_out),
        .high_speed(high_speed),
        .SE0_detected(SE0_buff),
        .sync_detected(sync_detected)
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

    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            SE0_buff <= 1'b0;
        else
            SE0_buff <= SE0_detected;
    end

endmodule
