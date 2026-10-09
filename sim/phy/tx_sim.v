



module tx_sim (
    input clk, rst_n, transfering,
    input [7:0] data,
    input [1:0] speed,
    output reg packet_done,
    output buffer_loaded, dp, dm
);
    reg buff;
    wire serial_valid, serializer_out, bitstuffer_valid;
    wire bitstuffer_out, serializer_halt;
    wire [1:0] differential_in;

     serializer inst5(
        .clk(clk),
        .rst_n(rst_n),
        .data_valid(transfering),
        .halt(serializer_halt),
        .high_speed(speed[1]),
        .data_byte(data),
        .serial_out(serializer_out),
        .buffer_loaded(buffer_loaded),
        .serial_valid(serial_valid)
    );

    bitstuffer inst(
        .clk(clk),
        .rst_n(rst_n),
        .data_in(serializer_out),
        .serial_valid_in(serial_valid),
        .data_out(bitstuffer_out),
        .serial_valid_out(bitstuffer_valid),
        .stall_upstream(serializer_halt)
    );

    nrzi_encoder inst4(
        .clk(clk),
        .rst_n(rst_n),
        .data_in(buff),
        .serial_valid(bitstuffer_valid),
        .packet_done(packet_done),
        .line_state(differential_in)
    );

   
    diff_tx_driver inst2(
        .line_state(differential_in),
        .full_speed(speed[0]),
        .dp(dp),
        .dm(dm)
    );
    
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            buff <= 1'b0;
        else
            buff <= bitstuffer_out;
    end



endmodule
