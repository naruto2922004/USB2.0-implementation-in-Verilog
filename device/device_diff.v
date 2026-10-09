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
module device_diff #(
    parameter CLK_FREQ = 48_000_000,
    parameter MAX_SPEED = 2'b11
)(
    input clk, por_rst_n, nrzi_serial_valid, packet_done, idle, connected, // packet_done will be 1 bufferend from nrzi encoder
    // tx
    input[1:0] tx_line_state,
    output reg tx_dp, tx_dm,
    output reg device_en,
    // rx
    input rx_dp, rx_dm,
    output reg [1:0] rx_line_state,
    // reset
    output reg device_reset_n,
    output reg [1:0] speed

);
    localparam RESET_DEBOUNCE        = ((CLK_FREQ / 1000000) * 5) / 2; 
    localparam DEVICE_CHIRP_LENGTH   = (CLK_FREQ / 1000);         
    localparam HOST_CHIRP_MAX_LENGTH = (CLK_FREQ / 1000000) * 60;   
    localparam HOST_CHIRP_DELAY      = (CLK_FREQ / 1000000) * 100;     



    reg [19:0] counter;
    reg [1:0] state, temp_state, temp_counter;
    reg rst_dp, rst_dm;
    reg data_dp, data_dm;

    always @(posedge clk or negedge por_rst_n) begin
        if (!por_rst_n || !connected) begin
            counter <= 20'd0;
            temp_counter <= 2'b00;
            state <= 2'b00;
            temp_state <= 2'b00;
            speed <= (MAX_SPEED == 2'b11)? 2'b10: MAX_SPEED;
            device_en <= 1'b0;
            device_reset_n <= 1'b0;
            rst_dm <= 1'b0;
            rst_dp <= 1'b0;     
        end
        else begin
            case (state)
                2'b00: begin
                    if (!idle && !device_en)begin
                        if (counter < RESET_DEBOUNCE)begin
                            if(!rx_dp && !rx_dm)
                                counter <= counter + 1'b1;
                            else
                                counter <= 20'd0;
                        end
                        else begin
                            state <= (MAX_SPEED == 2'b11)? 2'b01: 2'b10;
                            counter <= 20'd0;
                            temp_state <= 2'b00;
                            temp_counter <= 2'b00;
                            device_reset_n <= 1'b0;
                        end
                    end
                end
                2'b01: begin
                    if (temp_state == 2'b00) begin
                        if (counter < DEVICE_CHIRP_LENGTH) begin
                            device_en <= 1'b1;
                            {rst_dp, rst_dm} <= 2'b01;
                            counter <= counter + 1'b1;
                        end
                        else begin
                            device_en <= 1'b0;
                            {rst_dp, rst_dm} <= 2'b00;
                            counter <= 20'd0;
                            temp_counter <= 2'b00;
                            temp_state <= 2'b01;
                        end
                     end
                    else if (temp_state == 2'b01) begin
                        if(temp_counter == 2'b11)begin
                            state <= 2'b10;
                            temp_state <= 2'b00;
                            counter <= 20'd0;
                            temp_counter <= 2'b00;
                            speed <= 2'b11;
                        end
                        else if(temp_counter == 2'b00)begin
                            if(counter > HOST_CHIRP_DELAY)begin
                                state <= 2'b10;
                                temp_state <= 2'b00;
                                counter <= 20'd0;
                                temp_counter <= 2'b00;
                            end
                            else begin
                                if({rx_dp, rx_dm} == 2'b01)begin
                                    counter <= 20'd0;
                                    temp_state <= 2'b10;
                                end
                                else
                                    counter <= counter + 1'b1;
                            end
                        end
                        else begin
                            if(counter >= HOST_CHIRP_MAX_LENGTH)begin
                                state <= 2'b10;
                                temp_state <= 2'b00;
                                counter <= 20'd0;
                                temp_counter <= 2'b00;
                            end
                            else begin
                                if({rx_dp, rx_dm} == 2'b01)begin
                                    counter <= 20'd0;
                                    temp_state <= 2'b10;
                                end
                                else
                                    counter <= counter + 1'b1;
                            end
                        end
                    end
                    else if(temp_state == 2'b10)begin
                        if(counter >= HOST_CHIRP_MAX_LENGTH)begin
                            state <= 2'b10;
                            temp_state <= 2'b00;
                            counter <= 20'd0;
                            temp_counter <= 2'b00;
                        end
                        else begin
                            if({rx_dp, rx_dm} == 2'b10)begin
                                counter <= 20'd0;
                                temp_state <= 2'b01;
                                temp_counter <= temp_counter + 1'b1;
                            end
                            else
                                counter <= counter + 1'b1;
                        end
                    end
                end
                2'b10: begin
                    device_en <= 1'b0;
                    if (idle)begin
                        state <= 2'b11;
                        temp_state <= 2'b00;
                        device_reset_n <= 1'b1;
                        counter <= 20'd0;
                    end

                end
                2'b11: begin
                    if (!idle && !device_en)begin
                        if (counter < RESET_DEBOUNCE)begin
                            if(!rx_dp && !rx_dm)
                                counter <= counter + 1'b1;
                            else
                                counter <= 20'd0;
                        end
                        else begin
                            state <= (MAX_SPEED == 2'b11)? 2'b01: 2'b10;
                            speed <= (MAX_SPEED == 2'b11)? 2'b10: MAX_SPEED;
                            counter <= 20'd0;
                            temp_state <= 2'b00;
                            temp_counter <= 2'b00;
                            device_reset_n <= 1'b0;
                            device_en <= 1'b0;
                        end
                    end
                    if (temp_state == 2'b00 && nrzi_serial_valid) begin
                        device_en <= 1'b1;
                        temp_state <= 2'b01;
                    end
                    else if(temp_state == 2'b01 && packet_done)begin
                        device_en <= 1'b0;
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
            if(!device_en)begin
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