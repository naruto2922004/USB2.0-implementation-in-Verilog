// status:
// no packet =     2'b00
// packet valid =  2'b01
// FIFO empty =    2'b10
// packet corupt = 2'b11
module rx_link (
    input clk, rst_n, byte_valid, phy_done, fifo_read, read_done, accept_data, fifo_rst_in,
    input [7:0] phy_data,
    output [7:0] fifo_out,
    output reg [3:0] pid,
    output [1:0] status,
    output reg data_pid_valid
);
    reg [1:0] state, temp_state, temp_status;
    reg [7:0] crc_in, fifo_in, buff1, buff2;
    wire [4:0] crc5_rx;
    wire [15:0] crc16_rx;
    reg [2:0] bit_count;
    reg crc5_rst_n, crc16_rst_n, fifo_wr, crc_valid, crc_halt; 
    wire full, empty, fifo_rst_n;
    assign status = (temp_status == 2'b01 && empty)? 2'b10 : temp_status;
    assign fifo_rst_n = !(!rst_n || !fifo_rst_in);
    
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

    sync_fifo #(
        .DEPTH(1024),
        .WIDTH(8),
        .PTR_WIDTH(10)
    ) u_sync_fifo (
        .clk(clk),
        .rst_n(fifo_rst_n),
        .wr_en(fifo_wr),
        .rd_en(fifo_read),
        .din(fifo_in),
        .full(full),
        .empty(empty),
        .dout(fifo_out)
    );

    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            state <= 2'b00;
            temp_state <= 2'b00;
            temp_status <= 2'b00;
            pid <= 4'd0;
            crc_in <= 8'h00;
            fifo_in <= 8'h00;
            crc5_rst_n <= 1'b0;
            crc16_rst_n <= 1'b0;
            crc_valid <= 1'b0;
            crc_halt <= 1'b0;
            bit_count <= 3'd0;
            data_pid_valid <= 1'b0;
        end
        else begin
            case(state)
                2'b00: begin
                    if(temp_state == 2'b00)begin
                        crc_in <= 8'h00;
                        fifo_in <= 8'h00;
                        crc5_rst_n <= 1'b0;
                        crc16_rst_n <= 1'b0;
                        fifo_wr <= 1'b0;
                        crc_valid <= 1'b0;
                        crc_halt <= 1'b0;
                    end
                    if((temp_state == 2'b01) && phy_done) // pid error buffer
                        temp_state <= 2'b10;
                    else if(temp_state == 2'b10)begin // error state
                        if(read_done)begin
                            temp_state <= 2'b00;
                            temp_status <= 2'b00;
                            bit_count <= 3'd0;
                            pid <= 4'd0;
                        end
                        else
                            temp_status <= 2'b11; 
                    end
                    else if(temp_state == 2'b11)begin // packet ready state
                        if(read_done)begin
                            temp_state <= 2'b00;
                            temp_status <= 2'b00;
                            bit_count <= 3'd0;
                            pid <= 4'd0;
                        end
                        else
                            temp_status <= 2'b01;
                    end

                    if (data_pid_valid) begin
                        if(bit_count == 3'd7)begin
                            pid <= 4'd0;
                            data_pid_valid <= 1'b0;
                            state <= 2'b00;
                            temp_state <= 2'b00;
                        end
                        else if (accept_data) begin
                            state <= 2'b11;
                            temp_state <= 2'b00;
                            data_pid_valid <= 1'b0;
                            bit_count <= 3'd0;
                        end
                        else
                            bit_count <= bit_count + 1'b1;
                    end
                    else if(byte_valid && (temp_state == 2'b00))begin
                        pid <= phy_data[3:0];
                        if(phy_data[7:4] == ~phy_data[3:0])begin
                            temp_state <= 2'b00;
                            if (phy_data[1:0] == 2'b10)// handshake
                                state <= 2'b01;
                            else if ((phy_data[1:0] == 2'b01) || (phy_data[3:0] == 4'b0100)) // token
                                state <= 2'b10;
                            else if (phy_data[1:0] == 2'b11) // data
                                data_pid_valid <= 1'b1;
                        end
                        else if(phy_data[7:4] != ~phy_data[3:0])begin
                            temp_state <= 2'b01;
                            state <= 2'b00;
                        end

                    end
                end
                2'b01: begin
                    if((temp_state == 2'b00) && phy_done)
                        temp_state <= 2'b01;
                    else if(temp_state == 2'b01)begin
                        if(read_done)begin
                            temp_state <= 2'b00;
                            state <= 2'b00;
                            temp_status <= 2'b00;
                            pid <= 4'd0;
                        end
                        else
                            temp_status <= 2'b01;
                    end
                end
                2'b10: begin
                    if((temp_state == 2'b00) && byte_valid)begin
                        buff2 <= phy_data;
                        temp_state <= 2'b01;        
                    end
                    else if(temp_state == 2'b01)begin
                        if(crc_valid)
                            crc_valid <= 1'b0;
                        if(fifo_wr)
                            fifo_wr <= 1'b0;
                        if(byte_valid)begin
                            crc5_rst_n <= 1'b1;
                            crc_valid <= 1'b1;
                            crc_in <= buff2;
                            fifo_wr <= 1'b1;
                            fifo_in <= buff2;
                            buff2 <= phy_data;
                        end
                        if(phy_done)
                            temp_state <= 2'b10;
                    end
                    else if(temp_state == 2'b10)begin
                        if(crc_valid || fifo_wr)begin
                            crc_valid <= 1'b0;
                            fifo_wr <= 1'b0;
                            bit_count <= bit_count + 1'b1;
                        end
                        else if(bit_count < 3'd5)
                            bit_count <= bit_count + 1'b1;
                        else if(bit_count == 3'd5)begin
                            crc_valid <= 1'b1;
                            crc_in <= buff2;
                            fifo_wr <= 1'b1;
                            fifo_in <= {5'd0, buff2[2:0]};
                        end
                        else if(bit_count > 3'd5)begin
                            bit_count <= bit_count + 1'b1;
                            if(bit_count == 3'd7)begin
                                temp_state <= 2'b11;
                                crc_halt <= 1'b1;
                            end
                        end
                    end
                    else if(temp_state == 2'b11)begin
                        state <= 2'b00;
                        if(crc5_rx == buff2[7:3])
                            temp_state <= 2'b11;
                        else
                            temp_state <= 2'b10;
                    end
                end
                2'b11: begin
                    if((temp_state == 2'b00) && byte_valid)begin
                        buff1 <= phy_data;
                        temp_state <= 2'b01;        
                    end
                    else if(temp_state == 2'b01 && byte_valid)begin
                        buff1 <= phy_data;
                        buff2 <= buff1;
                        temp_state <= 2'b10;
                    end
                    else if(temp_state == 2'b10)begin
                        if(crc_valid && !byte_valid)
                            crc_valid <= 1'b0;
                        if(fifo_wr)
                            fifo_wr <= 1'b0;
                        if(byte_valid)begin
                            crc16_rst_n <= 1'b1;
                            crc_valid <= 1'b1;
                            crc_in <= buff2;
                            fifo_wr <= 1'b1;
                            fifo_in <= buff2;
                            buff2 <= buff1;
                            buff1 <= phy_data;
                        end
                        if(phy_done)
                            temp_state <= 2'b11;
                    end
                    else if(temp_state == 2'b11)begin
                        if(bit_count < 3'd6)
                            bit_count <= bit_count +1'b1;
                        if(bit_count == 3'd6)begin
                            state <= 2'b00;
                            if((buff2 == crc16_rx[15:8]) && (buff1 == crc16_rx[7:0]))
                                temp_state <= 2'b11;
                            else
                                temp_state <= 2'b10;
                        end 
                    end
                end
            endcase
        end 
    end

endmodule