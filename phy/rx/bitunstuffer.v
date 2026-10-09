module bitunstuffer (
    input wire clk, rst_n, idle, data_in,
    output reg data_out, 
    output reg stall_downstream
);
    
    reg [2:0] one_count;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || idle) begin
            one_count <= 3'b000;
            data_out <= 1'b1;
            stall_downstream <= 1'b0;
        end else begin
            data_out <= data_in;
            if(stall_downstream)
                stall_downstream <= 1'b0;
            if(one_count == 3'b110) begin
                one_count <= 3'b000;
                stall_downstream <= 1'b1;
            end
            else if (data_in == 1'b1)
                one_count <= one_count + 1'b1;
            else
                one_count <= 3'b000;
        end
    end

endmodule
