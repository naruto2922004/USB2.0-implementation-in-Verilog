module diff_rx_sampler (
    input clk, rst_n, dp, dm,
    output reg full_speed,
    output reg [1:0] line_state
);
    always@(posedge clk or negedge rst_n)begin
        if(!rst_n)
            full_speed <= (dp && !dm);
    end

    always@(* ) begin
        case ({dp, dm})
            2'b10: line_state = full_speed ? 2'b01 : 2'b00; // J
            2'b01: line_state = full_speed ? 2'b00 : 2'b01; // K
            2'b00: line_state = 2'b10; // SE0
            default: line_state = 2'b11; // SE1 (never driven)
        endcase
    end

endmodule
