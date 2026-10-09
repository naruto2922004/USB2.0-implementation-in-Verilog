
module sync_detect (
    input wire clk, rst_n, data_in, high_speed, idle,
    input [1:0] line_state,
    output sync_detected, packet_done
);
    
    reg [4:0] counter;
    reg [2:0] ps, ns;
    reg sync_buff;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n || idle) begin
            counter <= 5'b0;
            ps      <= 3'b000;
            sync_buff <= 1'b0;
        end
        else begin
            ps <= ns;
            if(ps == 3'b010)
                sync_buff <= 1'b1;
            else if(ps == 3'b011)
                sync_buff <= 1'b0;

            if (ps == 3'b000)
                counter <= (!data_in) ? counter + 1'b1 : 5'b0;
            else
                counter <= 5'b0;
        end
    end   

    always @(*) begin
        if(line_state == 2'b11)
            ns = 3'd0;
        else begin
            case (ps)
                3'b000:  ns = (high_speed && counter >= 5'd31 && !data_in) ? 3'b001 : 
                            (!high_speed && counter >= 5'd7 && !data_in) ? 3'b001 : 3'b000;
                3'b001:  ns = (data_in) ? 3'b010 : 3'b000;
                3'b010:  ns = (line_state == 2'b10) ? 3'b011 : 3'b010; 
                3'b011:  ns = (line_state == 2'b10) ? 3'b101 : 3'b100;
                3'b100:  ns = (line_state == 2'b10) ? 3'b011 : 3'b100; 
                3'b101:  ns = (line_state == 2'b01) ? 3'b110 :(line_state == 2'b10) ? 3'b101 : 3'b100;
                3'b110:  ns = 3'b000;
                default: ns = 3'b000;
            endcase
        end
    end

    assign sync_detected = (ps == 3'b010) || (ps == 3'b011) || (ps == 3'b100) || (ps == 3'b101);
    assign packet_done = (ps == 3'b110);

endmodule
