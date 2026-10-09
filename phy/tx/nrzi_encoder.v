module nrzi_encoder (
    input wire clk, rst_n, data_in, serial_valid,
    input [1:0] speed,
    output reg packet_done,
    output reg [1:0]line_state
);
    reg [1:0] state;
    reg [1:0] bit_count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || (state == 2'b00))begin
            line_state <= (speed == 2'b11)? 2'b00 : 2'b01;
            bit_count <= 2'd0;
            packet_done <= 1'b0;
            if(!rst_n)
                state <= 2'b00;
            else if(state == 2'b00 && serial_valid)
                state <= 2'b01;
        end
        else begin
            if (state == 2'b01) begin
                if (data_in == 1'b0)
                    line_state <= {1'b0, ~line_state[0]};
                state <= !serial_valid? 2'b10: 2'b01;  
            end
            else if(state == 2'b10)begin
                if (bit_count != 2'd3)begin
                    line_state <= 2'b10;
                    bit_count <= bit_count + 1'b1;
                end
                else begin
                    line_state <= 2'b01;
                    packet_done <= 1'b1;
                    state <= 2'b00;
                end
            end
        end
    end
endmodule
