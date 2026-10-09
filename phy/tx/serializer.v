module serializer (
    input clk, rst_n, data_valid, halt, high_speed,
    input [7:0] data_byte,
    output reg serial_out, buffer_loaded, serial_valid
);
    reg [4:0] sync_count;
    reg [3:0] data_count;
    reg [7:0] buffer;
    reg [1:0] state;
    
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            serial_out    <= 1'b0;
            sync_count    <= 5'd0;
            data_count    <= 4'd0;
            buffer_loaded <= 1'b0;
            serial_valid  <= 1'b0;
            buffer        <= 8'd0;
            state         <= 2'b00;
        end 
        else begin
            case (state)
                2'b00: begin 
                    serial_out    <= 1'b0;
                    sync_count    <= 5'd0;
                    data_count    <= 4'd0;
                    buffer_loaded <= 1'b0;
                    serial_valid  <= 1'b0;
                    buffer        <= 8'd0;
                    if (data_valid)
                        state <= 2'b01;
                end

                2'b01: begin 
                    if (!halt) begin
                        serial_valid <= 1'b1;
                        if (sync_count == (high_speed ? 5'd31 : 5'd7)) begin
                            state      <= 2'b10;
                            serial_out <= 1'b1;
                            sync_count <= 5'd0;
                            data_count <= 4'd0;
                        end
                        else begin
                            serial_out <= 1'b0;
                            sync_count <= sync_count + 1'b1;
                        end
                    end
                end

                2'b10: begin 
                    if (!halt) begin
                        serial_valid <= 1'b1;
                        if (data_count == 4'd0) begin
                            serial_out    <= data_byte[0];
                            buffer        <= {1'b0, data_byte[7:1]};
                            data_count    <= 4'd1;
                            buffer_loaded <= 1'b1;
                        end
                        else if (data_count <= 4'd6) begin
                            buffer_loaded <= 1'b0;
                            serial_out    <= buffer[0];
                            buffer        <= {1'b0, buffer[7:1]};
                            data_count    <= data_count + 1'b1;
                        end
                        else if (data_count == 4'd7) begin
                            buffer_loaded <= 1'b0;
                            serial_out    <= buffer[0];
                            buffer        <= {1'b0, buffer[7:1]};
                            data_count    <= 4'd8;
                        end
                        else if (data_count == 4'd8) begin
                            if (data_valid) begin
                                serial_out    <= data_byte[0];
                                buffer        <= {1'b0, data_byte[7:1]};
                                data_count    <= 4'd1;
                                buffer_loaded <= 1'b1;
                            end
                            else begin
                                buffer_loaded <= 1'b0;
                                serial_out    <= 1'b0;
                                serial_valid  <= 1'b0;
                                state         <= 2'b00;
                                data_count    <= 4'd0;
                            end
                        end
                    end
                end

                default: state <= 2'b00;
            endcase
        end
    end

endmodule
