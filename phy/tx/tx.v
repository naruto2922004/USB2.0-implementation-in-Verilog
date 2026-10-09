



module tx (
    input clk, rst_n, transfering,
    input [7:0] data,
    input [1:0] speed,
    output reg packet_done,        
    output wire buffer_loaded,     
    output wire nrzi_serial_valid, 
    output wire [1:0] line_state   
);

    reg bitstuffer_buff;
    wire done_buff;                
    wire serial_valid, serializer_out;
    wire bitstuffer_out, serializer_halt, high_speed;

    assign high_speed = (speed == 2'b11);

    serializer inst5 (
        .clk(clk),
        .rst_n(rst_n),
        .data_valid(transfering),
        .halt(serializer_halt),
        .high_speed(high_speed),
        .data_byte(data),
        .serial_out(serializer_out),
        .buffer_loaded(buffer_loaded),
        .serial_valid(serial_valid)
    );

    bitstuffer inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(serializer_out),
        .serial_valid_in(serial_valid),
        .data_out(bitstuffer_out),
        .serial_valid_out(nrzi_serial_valid),
        .stall_upstream(serializer_halt)
    );

    nrzi_encoder inst4 (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(bitstuffer_buff),
        .serial_valid(nrzi_serial_valid),
        .speed(speed),
        .packet_done(done_buff),
        .line_state(line_state)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bitstuffer_buff <= 1'b0;
            packet_done     <= 1'b0;
        end
        else begin
            bitstuffer_buff <= bitstuffer_out;
            packet_done     <= done_buff;
        end
    end

endmodule