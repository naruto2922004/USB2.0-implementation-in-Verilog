module eop_detect (
    input wire clk, rst_n,
    input wire [1:0] line_state,
    output wire eop_detected
);

    reg[1:0] ps;
    reg[1:0] ns;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            ps <= 2'b00;
        else
            ps <= ns;
    end

    always @(*) begin
        case (ps)
            2'b00: ns = (line_state == 2'b10) ? 2'b01 : 2'b00;
            2'b01: ns = (line_state == 2'b10) ? 2'b10 : 2'b00;
            2'b10: ns = (line_state == 2'b01) ? 2'b11 :(line_state == 2'b10) ? 2'b10 : 2'b00;
            2'b11: ns = 2'b00;
            default: ns = 2'b00;
        endcase
    end
    assign eop_detected = (ps == 2'b11);
endmodule
