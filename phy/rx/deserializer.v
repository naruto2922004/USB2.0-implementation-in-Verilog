// After byte_valid is asserted, the next byte deserialization 
//happens in the exact next cycle if sync_detect is asserted.
// byte_valid is asserted till the next byte is ready.
module deserializer (
    input wire clk, rst_n, serial_in, sync_detect, halt,
    output reg [7:0] data_out,
    output reg byte_valid
);

    reg [2:0] bit_count;
    reg s, buff;
    always @(posedge clk or negedge rst_n) begin
        
        if(byte_valid)
            byte_valid <= 1'b0;  
        if (!rst_n || !sync_detect) begin
            byte_valid <= 1'b0;
            bit_count <= 3'd0;
            s <= 1'b0;
            data_out <= 8'd0;
            if(!rst_n)
                buff <= 1'b0;
        end
        else if (!(halt && serial_in == 1'b0) && sync_detect) begin
                if (!s) begin
                    data_out[7] <= serial_in;
                    bit_count <= 3'b0;
                    s <= 1'b1;
                end
                else if (s) begin
                    data_out <= {serial_in, data_out[7:1]};
                    bit_count <= bit_count + 1'b1;
                    if (bit_count >= 3'b110)begin
                        s <= 1'b0; 
                        byte_valid <= 1'b1;
                    end 
                end 
        end
    end
    //assign byte_valid = (bit_count == 3'b111) && !halt;
    
endmodule
