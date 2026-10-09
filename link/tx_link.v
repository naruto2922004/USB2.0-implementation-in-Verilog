//next_packet can only be asserted for one clock to abort on no data
// token: 2'b10
// data: 2'b11
module tx_link (
    input clk,
    input rst_n,
    input next_packet,
    input fifo_empty,
    input packet_done,
    input buffer_loaded,
    input [3:0] pid,
    input [7:0] fifo_out,
    output reg transfering,
    output busy,
    output reg fifo_read,
    output reg [7:0] data_phy
);

    reg [1:0] state;
    reg [2:0] temp_state; 
    reg [3:0] pid_buffer;
    reg [7:0] data_buffer, crc_in;
    wire [4:0] crc5_rx;
    wire [15:0] crc16_rx;
    reg [1:0] bit_count;
    reg crc5_rst_n, crc16_rst_n, crc_valid; 
    wire crc_halt; 
    assign crc_halt = (bit_count == 2'd2);
    assign busy = (state != 2'b00);

    crc5_engine crc5 (
        .rst_n(crc5_rst_n),
        .clk(clk),
        .data_valid(crc_valid),
        .halt(crc_halt),
        .data_in(crc_in),
        .rx_out(crc5_rx)
    );

    crc16_engine crc16 (
        .rst_n(crc16_rst_n),
        .clk(clk),
        .data_valid(crc_valid),
        .data_in(crc_in),
        .rx_out(crc16_rx)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            transfering <= 1'b0;
            fifo_read <= 1'b0;
            data_phy <= 8'd0;
            state <= 2'b00;
            temp_state <= 3'b000;
            crc5_rst_n <= 1'b0;
            crc16_rst_n <= 1'b0;
            bit_count <= 2'd0;
            crc_valid <= 1'b0;
        end 
        else begin
            case (state)
                2'b00: begin
                    transfering <= 1'b0;
                    fifo_read <= 1'b0;
                    data_phy <= 8'd0;
                    temp_state <= 3'b000;
                    crc5_rst_n <= 1'b0;
                    crc16_rst_n <= 1'b0;
                    bit_count <= 2'd0;
                    crc_valid <= 1'b0;
                    if (next_packet) begin
                        state <= 2'b01;
                        pid_buffer <= pid;
                        data_phy <= {~pid, pid};
                        transfering <= 1'b1;
                    end
                end

                2'b01: begin
                    if (pid_buffer[1:0] == 2'b10) begin // handshake
                        if (temp_state == 3'b000 && buffer_loaded) begin 
                            transfering <= 1'b0;
                            data_phy <= 8'd0;
                            temp_state <= 3'b001;
                        end 
                        else if (temp_state == 3'b001 && packet_done)
                            state <= 2'b00;
                    end 
                    else begin
                        if (temp_state == 3'b000) begin
                            if (!fifo_empty) begin
                                fifo_read <= 1'b1;
                                temp_state <= 3'b001;
                            end 
                            else if(pid_buffer[1:0] == 2'b11)begin
                                state <= 2'b11;
                                temp_state <= 3'b010;
                            end
                            else
                                state <= 2'b00;
                        end 
                        else if (temp_state == 3'b001) begin
                            fifo_read <= 1'b0;
                            temp_state <= 3'b010;
                        end 
                        else if (temp_state == 3'b010) begin
                            data_buffer <= fifo_out;
                            if ((pid_buffer[1:0] == 2'b01) || (pid_buffer == 4'b0100)) begin // token
                                state <= 2'b10;
                                crc5_rst_n <= 1'b1;
                            end 
                            else if (pid_buffer[1:0] == 2'b11) begin // data
                                state <= 2'b11;
                                crc16_rst_n <= 1'b1;
                            end 
                            else 
                                state <= 2'b00;
                            crc_valid <= 1'b1;
                            crc_in <= fifo_out;
                            temp_state <= 3'b000;
                        end
                    end
                end

                2'b10: begin
                    if (temp_state == 3'b000) begin
                        crc_valid <= 1'b0;
                        temp_state <= 3'b001;
                    end 
                    else if (fifo_empty) begin
                        if (buffer_loaded) begin
                            if (temp_state == 3'b001) begin
                                data_phy <= {crc5_rx, data_buffer[2:0]};
                                temp_state <= 3'b010;
                            end else if (temp_state == 3'b010) begin
                                transfering <= 1'b0;
                                data_phy <= 8'd0;
                                temp_state <= 3'b011;
                            end
                        end
                        else if((temp_state == 3'b011) && (packet_done))
                            state <= 2'b00;
                        
                        if (bit_count != 2'd2)
                            bit_count <= bit_count + 1'b1;
                    end 
                    else if ((temp_state == 3'b001) && buffer_loaded) begin
                        state <= 2'b01;
                        fifo_read <= 1'b1;
                        data_phy <= data_buffer;
                    end
                end

                2'b11: begin
                    if (temp_state == 3'b000) begin
                        crc_valid <= 1'b0;
                        temp_state <= 3'b001;
                    end 
                    else if (fifo_empty) begin
                        if (buffer_loaded) begin
                            if (temp_state == 3'b001) begin
                                data_phy <= data_buffer;
                                temp_state <= 3'b010;
                            end 
                            else if (temp_state == 3'b010) begin
                                data_phy <= crc16_rx[15:8]; 
                                temp_state <= 3'b011;      
                            end
                            else if(temp_state == 3'b011)begin
                                data_phy <= crc16_rx[7:0];
                                temp_state <= 3'b100;
                            end
                            else if(temp_state == 3'b100)begin
                                transfering <= 1'b0;
                                data_phy <= 8'd0;
                                temp_state <= 3'b101;
                            end
                        end
                        else if((temp_state == 3'b101)  && (packet_done))
                            state <= 2'b00;
                    end 
                    else if ((temp_state == 3'b001) && buffer_loaded) begin
                        state <= 2'b01;
                        fifo_read <= 1'b1;
                        data_phy <= data_buffer;
                    end
                end

                default: begin
                    state <= 2'b00;
                end
            endcase
        end
    end
endmodule
