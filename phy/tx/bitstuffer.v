module bitstuffer (
    input wire clk, rst_n, data_in, serial_valid_in,
    output reg data_out, serial_valid_out,
    output stall_upstream
);
    
    reg [2:0] one_count;

    always @(posedge clk or negedge rst_n) begin
    
        if (!rst_n) begin
            one_count <= 3'b000;
            data_out <= 1'b1;
            serial_valid_out <= 1'b0;
        end 
        else begin 
            serial_valid_out <= serial_valid_in;
            if(serial_valid_in)begin
                if(one_count == 3'b110) begin
                    one_count <= 3'b000;
                    data_out <= 1'b0;
                end
                else if (data_in == 1'b1) begin
                    one_count <= one_count + 1'b1;
                    data_out <= 1'b1;
                end
                else begin
                    one_count <= 3'b000;
                    data_out <= 1'b0;
                end
            end
            else if (one_count == 3'b110) begin
                one_count <= 3'b000;
                data_out <= 1'b0;
                serial_valid_out <= 1'b1;
            end
        end
    end
    assign stall_upstream = (one_count == 3'b110);
endmodule
