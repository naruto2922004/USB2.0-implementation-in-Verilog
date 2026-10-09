
module bus (
    input host_dp, host_dm, device_dp, device_dm,
    input device_en, host_en, connected,
    input [1:0] speed, 
    output reg dp, dm, idle
);
    
    always @(*) begin
        if(!connected)begin
            idle = 1'b0;
            {dp,dm}= 2'b00;
        end
        else if(!device_en && !host_en)begin
            idle = 1'b1;
            case (speed)
                2'b01: {dp,dm} = 2'b01;
                2'b10: {dp,dm} = 2'b10;
                2'b11: {dp,dm} = 2'b00; 
                default: {dp,dm} = 2'b00;
            endcase
        end
        else if (device_en) begin
            idle = 1'b0;
            dp = device_dp;
            dm = device_dm;
        end
        else if (host_en) begin
            idle = 1'b0;
            dp = host_dp;
            dm = host_dm;
        end
        
    end

endmodule