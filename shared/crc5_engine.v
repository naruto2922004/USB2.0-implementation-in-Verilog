module crc5_engine (
    input rst_n, clk, data_valid, halt,
    input [7:0] data_in,
    output [4:0] rx_out
);
    reg [4:0] rx;
    reg [7:0] buffer;
    reg [2:0] bit_count;

    assign rx_out = ~rx;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            rx <= 5'b11111;
        else if(!halt)begin
            if(data_valid)begin
                buffer <= {1'b0, data_in[7:1]};
                bit_count <= 3'd0;
                
                if(data_in[0] ^ rx[0])
                    rx <= {1'b0, rx[4:1]} ^ 5'b10100;
                else
                    rx <= {1'b0, rx[4:1]};
            end
            else if(bit_count != 3'b111)begin
                buffer <= {1'b0, buffer[7:1]};
                bit_count <= bit_count + 1'b1;
                
                if(buffer[0] ^ rx[0])
                    rx <= {1'b0, rx[4:1]} ^ 5'b10100;
                else
                    rx <= {1'b0, rx[4:1]};
            end
        end
    end

endmodule