// Reset initializes the previous line state to the USB idle (J) state.
module nrzi_decoder (
    input wire clk, rst_n,
    input [1:0] line_state,
    output reg data_out
);
    reg [1:0] prev_line_state;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)begin
            prev_line_state <= 2'b11;
            data_out <= 1'b1;
        end
        else begin
            prev_line_state <= line_state;
            if (prev_line_state != line_state)
                data_out <= 1'b0;  
            else
                data_out <= 1'b1;
        end
    end
endmodule
