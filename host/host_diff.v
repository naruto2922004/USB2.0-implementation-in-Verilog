// 00: not decided
// 01: low speed
// 10: full speed
// 11: high speed

// 00 = K
// 01 = J
// 10 = SE0
// 11 = Idle(don't do anything)

// nrzi_serial_valid:
// Asserted by the upstream TX engine only when a packet is ready
// and the PHY reports LINE_IDLE (bus available).
module host_diff #(
    parameter CLK_FREQ = 48_000_000
)(
    input clk, por_rst_n, nrzi_serial_valid, packet_done, idle, connected, // packet_done will be 1 bufferend from nrzi encoder
    // tx
    input[1:0] tx_line_state,
    output reg tx_dp, tx_dm,
    output reg host_en,
    // rx
    input rx_dp, rx_dm,
    output reg [1:0] rx_line_state,
    // reset
    input start_rst,
    output reset_busy,
    output reg [1:0] speed

);
    localparam ATTACH_DEBOUNCE     = (CLK_FREQ / 1000) * 2;    
    localparam RESET_MIN           = (CLK_FREQ / 100);          
    localparam DEVICE_CHIRP_MAX    = (CLK_FREQ / 1000) * 7;     
    localparam DEVICE_CHIRP_LENGTH = (CLK_FREQ / 1000);    
    localparam HOST_CHIRP_LENGTH   = (CLK_FREQ / 1000000) * 50; 
    localparam RECOVERY_TAIL       = RESET_MIN - ((CLK_FREQ / 1000000) * 200);

    // localparam ATTACH_DEBOUNCE = 5;
    // localparam RESET_MIN  = 20;
    // localparam DEVICE_CHIRP_MAX  = 10;
    // localparam DEVICE_CHIRP_LENGTH  = 1;
    // localparam HOST_CHIRP_LENGTH  = 1;
    // localparam RECOVERY_TAIL = 19;


    reg [31:0] counter;
    reg [19:0] temp_counter;
    reg [19:0] disconnect_counter;
    reg [1:0] state, temp_state;
    reg rst_dp, rst_dm;
    reg data_dp, data_dm;

    assign reset_busy = (state != 2'b11);

    always @(posedge clk or negedge por_rst_n) begin
        if (!por_rst_n || start_rst || !connected) begin
            counter <= 32'd0;
            temp_counter <= 20'd0;
            state <= 2'b00;
            temp_state <= 2'b00;
            speed <= 2'b00;
            host_en <= 1'b0;
            rst_dm <= 1'b0;
            rst_dp <= 1'b0;
        end
        else begin
            case (state)
                2'b00: begin
                    counter <= 32'd0;
                    temp_state <= ((rx_dp && !rx_dm)||(!rx_dp && !rx_dm))? 2'b01 :(!rx_dp && rx_dm)? 2'b10 : 2'b00;
                    if (temp_state == 2'b01) begin
                        if(temp_counter >= ATTACH_DEBOUNCE)begin
                            speed <= 2'b10;
                            state <= 2'b01;
                            temp_state <= 2'b00;
                            temp_counter <= 20'd0;
                        end
                        else if((rx_dp && !rx_dm)||(!rx_dp && !rx_dm))
                            temp_counter <= temp_counter + 1'b1;
                        else
                            temp_counter <= 20'd0;
                        
                    end
                    else if (temp_state == 2'b10) begin
                        if(temp_counter >= ATTACH_DEBOUNCE)begin
                            speed <= 2'b01;
                            state <= 2'b10;
                            temp_state <= 2'b00;
                            temp_counter <= 20'd0;
                        end
                        else if(!rx_dp && rx_dm)
                            temp_counter <= temp_counter + 1'b1;
                        else
                            temp_counter <= 20'd0;
                    end
                end
                2'b01: begin
                    if (counter >= RESET_MIN)begin
                        state <= 2'b11;
                        temp_state <= 2'b00;
                        host_en <= 1'b0;
                    end
                    else begin
                        counter <= counter + 1'b1;
                        if(counter >= RECOVERY_TAIL && temp_state != 2'b11)begin
                            temp_state <= 2'b11;
                            host_en <= 1'b1;
                            rst_dm <= 1'b0;
                            rst_dp <= 1'b0;
                        end
                            
                        else if(temp_state == 2'b00)begin
                            host_en <= 1'b1;
                            rst_dm <= 1'b0;
                            rst_dp <= 1'b0;
                            if(counter >= DEVICE_CHIRP_MAX)
                                temp_state <= 2'b11;
                            else if (temp_counter >= DEVICE_CHIRP_LENGTH) begin
                                temp_state <= 2'b01;
                                speed <= 2'b11;
                                temp_counter <= 20'd0;
                            end
                            else if(!rx_dp && rx_dm)
                                temp_counter <= temp_counter + 1'b1;
                            else
                                temp_counter <= 20'd0;
                        end
                        else if (temp_state == 2'b01) begin
                            host_en <= 1'b1;
                            rst_dp <= 1'b0;
                            rst_dm <= 1'b1;
                            if(temp_counter >= HOST_CHIRP_LENGTH)begin
                                temp_state <= 2'b10;
                                temp_counter <= 20'd0;
                            end
                            else
                                temp_counter <= temp_counter + 1'b1;
                        end
                        else if (temp_state == 2'b10) begin
                            host_en <= 1'b1;
                            rst_dp <= 1'b1;
                            rst_dm <= 1'b0;
                            if(temp_counter >= HOST_CHIRP_LENGTH)begin
                                temp_state <= 2'b01;
                                temp_counter <= 20'd0;
                            end
                            else
                                temp_counter <= temp_counter + 1'b1;
                        end
                    end  
                        
                end
                2'b10: begin
                    host_en <= 1'b1;
                    rst_dm <= 1'b0;
                    rst_dp <= 1'b0;
                    if (counter >= RESET_MIN)begin
                        state <= 2'b11;
                        host_en <= 1'b0;
                        temp_state <= 2'b00;
                    end
                    else
                        counter <= counter +1'b1;
                end
                2'b11: begin
                    if (temp_state == 2'b00 && nrzi_serial_valid) begin
                        host_en <= 1'b1;
                        temp_state <= 2'b01;
                    end
                    else if(temp_state == 2'b01 && packet_done)begin
                        host_en <= 1'b0;
                        temp_state <= 2'b00;
                    end
                end
                default: state <= 2'b00; 
            endcase
        end
    end

    always @(*) begin
        
        if(idle)begin
            rx_line_state = 2'b11; 
            {data_dp, data_dm} = 2'b00;
        end
        else if (state == 2'b11 ) begin
            if(!host_en)begin
                {data_dp, data_dm} = 2'b00;
                case ({rx_dp, rx_dm})
                    2'b10: rx_line_state = speed[1] ? 2'b01 : 2'b00; // J
                    2'b01: rx_line_state = speed[1] ? 2'b00 : 2'b01; // K
                    2'b00: rx_line_state = 2'b10; // SE0
                    default: rx_line_state = 2'b11; // SE1 (never driven)
                endcase
            end
            else begin
                rx_line_state = 2'b11;
                case (tx_line_state)
                    2'b00: {data_dp, data_dm} = speed[1] ? 2'b01 : 2'b10; // K
                    2'b01: {data_dp, data_dm} = speed[1] ? 2'b10 : 2'b01; // J
                    2'b10: {data_dp, data_dm} = 2'b00; // SE0
                    default: {data_dp, data_dm} = 2'b11; // SE1 (never driven)
                endcase
            end
        end
        else begin
            {data_dp, data_dm} = 2'b00;
            rx_line_state = 2'b11;
        end

        tx_dp = (state == 2'b11)? data_dp: rst_dp;
        tx_dm = (state == 2'b11)? data_dm: rst_dm;
        
    end
    

endmodule