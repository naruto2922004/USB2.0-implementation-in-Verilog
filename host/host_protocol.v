
module host_protocol#(
    parameter CLK_FREQ = 48_000_000
 )(
    input clk, por_rst_n, connected, idle, 
    input [1:0] speed,
    
    //link layer
    input host_reset_busy, host_tx_busy, host_tx_fifo_full, host_rx_data_pid_valid,
    input [1:0] host_rx_status,
    input [7:0] host_rx_fifo_out,
    input [3:0] host_rx_pid,
    output host_sw_rx_fifo_read, 
    output reg host_sw_rx_read_done, host_rx_accept_data, fifo_rst_n,
    output reg host_start_rst, host_tx_next_packet, host_tx_fifo_wr,
    output reg [7:0] host_tx_fifo_in,
    output reg [3:0] host_tx_pid,
    // Status
    input sw_reset,
    output reg [3:0] sw_status,
    // Request
    input sw_request_valid,
    input [63:0] sw_request,

    input [6:0] sw_vacant_address,
    output reg sw_address_ack,

    input  wire sw_transfer_start,
    input wire [3:0] sw_endpoint,       // Endpoint number
    input wire [1:0] sw_transfer_type,  // Bulk/Interrupt/Isochronous
    input wire sw_direction,            // 0 = OUT, 1 = IN
    input wire [7:0] sw_interval,      

    // Receiving data description
    output reg sw_rx_valid,
    output reg [2:0] sw_rx_type,
    output sw_rx_fifo_empty,
    input sw_rx_fifo_read,
    input sw_rx_read_done,
    output [7:0] sw_rx_fifo_out

 ); 
   

    localparam HS_SOF_TIME = (CLK_FREQ / 8000);
    localparam FS_SOF_TIME = (CLK_FREQ / 1000);
    localparam HS_SOF_END_GAP = HS_SOF_TIME - ((CLK_FREQ / 1000000)*20); // 20us
    localparam FS_SOF_END_GAP = FS_SOF_TIME - ((CLK_FREQ / 1000000)*20); // 20us
    localparam RESPONSE_TIMEOUT = (CLK_FREQ / 1000000)*10; // 10us
    localparam [4:0] INTER_GAP = 5'd10;

    // Token PIDs
    localparam [3:0] PID_OUT   = 4'b0001;
    localparam [3:0] PID_IN    = 4'b1001;
    localparam [3:0] PID_SOF   = 4'b0101;
    localparam [3:0] PID_SETUP = 4'b1101;

    // Data PIDs
    localparam [3:0] PID_DATA0 = 4'b0011;
    localparam [3:0] PID_DATA1 = 4'b1011;
    localparam [3:0] PID_DATA2 = 4'b0111;
    localparam [3:0] PID_MDATA = 4'b1111;

    // Handshake PIDs
    localparam [3:0] PID_ACK   = 4'b0010;
    localparam [3:0] PID_NAK   = 4'b1010;
    localparam [3:0] PID_STALL = 4'b1110;
    localparam [3:0] PID_NYET  = 4'b0110;

    // Special PIDs
    localparam [3:0] PID_PING     = 4'b0100;

    //==============================================================
    // RX Data Type
    //==============================================================
    localparam [2:0] RX_NO_DATA       = 3'b000;
    localparam [2:0] RX_DEV_DESC      = 3'b001;
    localparam [2:0] RX_CONFIG_DESC   = 3'b010;
    localparam [2:0] RX_REQ_DATA      = 3'b011;
    localparam [2:0] RX_TRANSFER_DATA = 3'b100;


    //==============================================================
    // Protocol Status
    //==============================================================
    localparam [2:0] PROTO_DISCONNECTED    = 3'b000;
    localparam [2:0] PROTO_NOT_READY       = 3'b001;
    localparam [2:0] PROTO_CAN_TAKE_REQ    = 3'b010;
    localparam [2:0] PROTO_NOT_SUPPORTED   = 3'b011;
    localparam [2:0] PROTO_READY           = 3'b100;
    localparam [2:0] PROTO_EP_STALLED      = 3'b101;
    localparam [2:0] PROTO_CRIT_ERROR      = 3'b110;
    localparam [2:0] PROTO_ERROR           = 3'b111;

    // 0. USB Control Request: GET_DESCRIPTOR (Device, Length 8)
    localparam [63:0] GET_DESCRIPTOR_DEV_REQ = {
        8'h80, // bmRequestType : Device-to-Host, Standard, Device
        8'h06, // bRequest      : GET_DESCRIPTOR
        8'h00, // wValue (LSB)  : Descriptor Index 0
        8'h01, // wValue (MSB)  : Descriptor Type 1 (DEVICE)
        8'h00, // wIndex (LSB)  : Language ID / Index
        8'h00, // wIndex (MSB)  : Language ID / Index
        8'h08, // wLength (LSB) : Requesting 8 bytes
        8'h00  // wLength (MSB) : High byte of length
    };

    wire [63:0] REQ_SET_ADDRESS;

    assign REQ_SET_ADDRESS = {
    8'h00,                  // bmRequestType
    8'h05,                  // bRequest = SET_ADDRESS
    1'b0, sw_vacant_address,   // wValue LSB = 8 bits
    8'h00,                  // wValue MSB = 8 bits
    8'h00,                  // wIndex LSB
    8'h00,                  // wIndex MSB
    8'h00,                  // wLength LSB
    8'h00                   // wLength MSB
};

    // 2. USB Control Request: GET_DESCRIPTOR (Device, Length 18)
    localparam [63:0] REQ_GET_DEV_DESC_18 = {
        8'h80, // bmRequestType : Device-to-Host, Standard, Device
        8'h06, // bRequest      : GET_DESCRIPTOR
        8'h00, // wValue (LSB)  : Descriptor Index 0
        8'h01, // wValue (MSB)  : Descriptor Type 1 (DEVICE)
        8'h00, // wIndex (LSB)  : Language ID 0
        8'h00, // wIndex (MSB)  : Language ID 0
        8'h12, // wLength (LSB) : Requesting 18 bytes (0x12)
        8'h00  // wLength (MSB) : 
    };

    // 3. USB Control Request: GET_DESCRIPTOR (Configuration, Length 9)
    localparam [63:0] REQ_GET_CONF_DESC_9 = {
        8'h80, // bmRequestType : Device-to-Host, Standard, Device
        8'h06, // bRequest      : GET_DESCRIPTOR
        8'h00, // wValue (LSB)  : Descriptor Index 0
        8'h02, // wValue (MSB)  : Descriptor Type 2 (CONFIGURATION)
        8'h00, // wIndex (LSB)  : Language ID 0
        8'h00, // wIndex (MSB)  : Language ID 0
        8'h09, // wLength (LSB) : Requesting 9 bytes (Header only)
        8'h00  // wLength (MSB) : 
    };

    // 4. USB Control Request: GET_DESCRIPTOR (Configuration, Length 34)

    // // 5. USB Control Request: SET_CONFIGURATION (Config = 1)
    // localparam [63:0] REQ_SET_CONFIGURATION_1 = {
    //     8'h00, // bmRequestType : Host-to-Device, Standard, Device
    //     8'h09, // bRequest      : SET_CONFIGURATION
    //     8'h01, // wValue (LSB)  : Configuration Value 1
    //     8'h00, // wValue (MSB)  : 
    //     8'h00, // wIndex (LSB)  : 0
    //     8'h00, // wIndex (MSB)  : 0
    //     8'h00, // wLength (LSB) : 0 bytes (No data stage)
    //     8'h00  // wLength (MSB) : 
    // };

    // // 6. USB Control Request: GET_DESCRIPTOR (HID Report, Length 63)
    // localparam [63:0] REQ_GET_HID_REPORT_DESC = {
    //     8'h81, // bmRequestType : Device-to-Host, Standard, Interface
    //     8'h06, // bRequest      : GET_DESCRIPTOR
    //     8'h00, // wValue (LSB)  : Descriptor Index 0
    //     8'h22, // wValue (MSB)  : Descriptor Type 0x22 (HID REPORT)
    //     8'h00, // wIndex (LSB)  : Interface 0
    //     8'h00, // wIndex (MSB)  : Interface 0
    //     8'h3F, // wLength (LSB) : Requesting 63 bytes (0x3F)
    //     8'h00  // wLength (MSB) : 
    // };

    // // 7. USB HID Class Request: SET_IDLE (Duration = 0, Infinite)
    // localparam [63:0] REQ_HID_SET_IDLE = {
    //     8'h21, // bmRequestType : Host-to-Device, Class, Interface
    //     8'h0A, // bRequest      : SET_IDLE
    //     8'h00, // wValue (LSB)  : Report ID 0
    //     8'h00, // wValue (MSB)  : Duration 0 (Indefinite)
    //     8'h00, // wIndex (LSB)  : Interface 0
    //     8'h00, // wIndex (MSB)  : Interface 0
    //     8'h00, // wLength (LSB) : 0 bytes
    //     8'h00  // wLength (MSB) : 
    // };

    // // 8. USB HID Class Request: SET_PROTOCOL (Protocol = 1, Report)
    // localparam [63:0] REQ_HID_SET_PROTOCOL = {
    //     8'h21, // bmRequestType : Host-to-Device, Class, Interface
    //     8'h0B, // bRequest      : SET_PROTOCOL
    //     8'h01, // wValue (LSB)  : Protocol 1 (Report Protocol)
    //     8'h00, // wValue (MSB)  : 
    //     8'h00, // wIndex (LSB)  : Interface 0
    //     8'h00, // wIndex (MSB)  : Interface 0
    //     8'h00, // wLength (LSB) : 0 bytes
    //     8'h00  // wLength (MSB) : 
    // };

    reg [3:0] req_sel;  // 0 to 8: Selects which of the 9 USB requests to send
    reg [3:0] byte_idx; // 0 to 7: Selects the byte within the chosen request(MSB to LSB)
    
    reg  [63:0] active_req;
    wire [7:0]  tx_byte;
    reg host_rx_read, data_toggle;
    reg [3:0] state;
    reg [4:0] temp_state;
    reg [19:0] sof_count, response_time;
    reg [4:0] gen_counter;
    reg [7:0] max_packetlength;
    reg [1:0] retry;
    reg [10:0] frame_count;
    reg [9:0] byte_index;
    reg [15:0] config_len;
    reg error;
    reg [4:0] sw_endpoint_buff;
    reg [7:0] sw_interval_buff;
    reg [15:0] sw_interval_count;
    reg [6:0] address_buff;
    reg [2:0] sof_state;
    reg break;


    wire [15:0] hs_interval;

    always @(*) begin
        case (req_sel)
            4'd0: active_req = GET_DESCRIPTOR_DEV_REQ; 
            4'd1: active_req = REQ_SET_ADDRESS;      
            4'd2: active_req = REQ_GET_DEV_DESC_18;    
            4'd3: active_req = REQ_GET_CONF_DESC_9;    
            4'd4: active_req = {
                8'h80,                 // bmRequestType
                8'h06,                 // bRequest
                8'h00,                 // wValue LSB
                8'h02,                 // wValue MSB
                8'h00,                 // wIndex LSB
                8'h00,                 // wIndex MSB
                config_len[7:0],       // wLength(LSB)
                config_len[15:8]       // wLength(MSB)
            };   
            4'd5: active_req = sw_request;
            default: active_req = 64'd0;
        endcase
    end

    assign tx_byte = active_req[(4'd7 - byte_idx) * 8 +: 8];

    

    assign host_sw_rx_fifo_read = (sw_rx_fifo_read || host_rx_read);
    assign sw_rx_fifo_out = host_rx_fifo_out;
    assign sw_rx_fifo_empty = (host_rx_status == 2'b10);
    assign hs_interval = (sw_interval_buff >= 1 && sw_interval_buff <= 16)?(16'd1 << (sw_interval_buff - 1'b1)): 16'hffff;
   
   always @(posedge clk or negedge por_rst_n) begin
        if(host_sw_rx_read_done)
            host_sw_rx_read_done <= 1'b0;
        if(host_tx_next_packet)
            host_tx_next_packet <= 1'b0;
        if(!fifo_rst_n)
            fifo_rst_n <= 1'b1;
        if (!por_rst_n || !connected) begin
            fifo_rst_n <= 1'b1;
            state <= 4'd0;
            temp_state <= 5'd0;
            sof_count <= 20'd0;
            response_time <= 20'd0;
            gen_counter <= 5'd0;
            retry <= 2'd0;
            req_sel <= 4'd0;
            byte_idx <= 4'd0;
            frame_count <= 11'd1;
            byte_index <= 10'd0;
            host_rx_read <= 1'b0;
            host_sw_rx_read_done <= 1'b0;
            host_tx_next_packet <= 1'b0;
            host_tx_fifo_wr <= 1'b0;
            host_start_rst <= 1'b0;
            host_tx_pid <= 4'd0;
            host_tx_fifo_in <= 8'd0;
            sw_rx_type <= 3'b00;
            sw_rx_valid <= 1'b0;
            sw_status <= 3'b000;
            error <= 1'b0;
            data_toggle <= 1'b1;
            host_rx_accept_data <= 1'b0;
            config_len <= 16'd0;
            max_packetlength <= 8'd0;
            sw_endpoint_buff <= 5'd0;
            sw_interval_buff <= 8'd0;
            sw_interval_count <= 16'd0;
            sw_address_ack <= 1'b0;
            sof_state <= 3'd0;
            break <= 1'b0;
         end
         else if(error == 1'b1)begin
            response_time <= 20'd0;
            if(sw_reset)begin
                error <= 1'b0;
                sw_status <= PROTO_NOT_READY;
                host_start_rst <= 1'b1;
                state <= 4'd0;
                temp_state <= 5'd0;
                sof_count <= 20'd0;
                response_time <= 20'd0;
                gen_counter <= 5'd0;
                retry <= 2'd0;
                host_rx_read <= 1'b0;
                host_tx_fifo_wr <= 1'b0;
                sw_rx_valid <= 1'b0;
                data_toggle <= 1'b1;
                host_rx_accept_data <= 1'b0;
                sof_state <= 3'd0;
            end
         end
         else if (((sof_count >= HS_SOF_TIME && speed == 2'b11) || 
            (sof_count >= FS_SOF_TIME && speed != 2'b11)) && break) begin
            if(!host_reset_busy)begin
                if(sof_state == 3'd0 && idle)begin
                    host_tx_fifo_wr <= 1'b1;
                    host_tx_fifo_in <= frame_count[7:0];
                    sof_state <= 3'd1;
                end
                else if (sof_state == 3'd1) begin
                    host_tx_fifo_wr <= 1'b1;
                    host_tx_fifo_in <= {5'd0, frame_count[10:8]};
                    sof_state <= 3'd2;
                end
                else if (sof_state == 3'd2) begin
                    host_tx_pid <= PID_SOF;
                    host_tx_next_packet <= 1'b1;
                    host_tx_fifo_wr <= 1'b0;
                    sof_state <= 3'd3;
                end
                else if (!host_tx_busy && sof_state == 3'd3) begin
                    if(gen_counter != INTER_GAP)
                        gen_counter <= gen_counter + 1'b1;
                    else begin
                        frame_count <= frame_count + 1'b1;
                        sw_interval_count <= sw_interval_count + 1'b1;
                        sof_count <= 20'd0;
                        sof_state <= 3'd0;
                        break <= 1'b0;
                        gen_counter <= 5'd0;
                    end
                end
            end

         end
         else begin
            host_start_rst <= 1'b0;
            if (host_reset_busy)begin
                break <= 1'b0;
                sof_count <= 16'd0;
                frame_count <= 11'd0;
                sw_status <= PROTO_NOT_READY;
                state <= 4'd0;
                temp_state <= 5'd0;
            end
            else begin
                sof_count <= sof_count + 1'b1;
                if(((sof_count < HS_SOF_END_GAP && speed == 2'b11)
                    || (sof_count < FS_SOF_END_GAP && speed != 2'b11)) || !break)begin
                    case (state)
                        4'd0: begin
                            sw_status <= PROTO_NOT_READY;
                            case (temp_state)
                                5'd0: begin // setup stage
                                    break <= 1'b0;
                                    
                                    if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, 7'b0};
                                        temp_state <= 5'd1;
                                    end
                                end
                                5'd1: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_SETUP;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd2;
                                end
                                5'd2: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd3;
                                        req_sel <= 4'd0;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd3: begin // sw_request bytes
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else begin
                                        if(byte_idx < 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b1;
                                            host_tx_fifo_in <= tx_byte;
                                            byte_idx <= byte_idx + 4'd1;
                                        end
                                        else if (byte_idx == 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b0;
                                            if (idle) begin
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd4;
                                                byte_idx <= 4'b0000;
                                                host_tx_pid <= PID_DATA0;
                                                gen_counter <= 5'd0;
                                            end
                                        end
                                    end
                                end
                                5'd4:begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd5;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd5: begin // device acknowledgement 
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(host_rx_status == 2'b10)begin
                                        if (host_rx_pid == PID_ACK) begin
                                            break <= 1'b1;
                                            temp_state <= 5'd6;
                                            data_toggle <= 1'b1;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                state <= 4'd0;
                                                temp_state <= 5'd0;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            state <= 4'd0;
                                            temp_state <= 5'd0;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                5'd6: begin // data stage
                                    break <= 1'b0;
                                    
                                    if(idle)begin
                                        temp_state <= 5'd7;
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, 7'b0};
                                    end
                                end
                                5'd7: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_IN;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd8;
                                end
                                5'd8: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd9;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd9: begin // data packet from device & ack by host
                                    if (host_rx_data_pid_valid) begin
                                        if (host_rx_pid == PID_DATA1)begin
                                           host_rx_accept_data <= 1'b1; 
                                           response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd6;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if(host_rx_status == 2'b01 ||(host_rx_status == 2'b10 && gen_counter == 5'd9)
                                        ||(host_rx_status == 2'b10 && gen_counter == 5'd10))begin
                                        response_time <= 20'd0;
                                        host_rx_accept_data <= 1'b0;
                                        if (host_rx_pid == PID_DATA1) begin
                                            retry <= 2'b00;
                                            if(gen_counter < 5'd9)begin
                                                host_rx_read <= 1'b1;
                                                gen_counter <= gen_counter + 1'b1;
                                            end
                                            else if(gen_counter == 5'd9)begin
                                                break <= 1'b1;
                                                max_packetlength <= host_rx_fifo_out;
                                                host_rx_read <= 1'b0;
                                                gen_counter <= gen_counter +1'b1;
                                            end
                                            else begin
                                                break <= 1'b0;
                                                host_sw_rx_read_done <= 1'b1;
                                                fifo_rst_n <= 1'b0;
                                                host_tx_pid <= PID_ACK;
                                                gen_counter <= 5'd0;
                                                if (idle) begin
                                                    host_tx_next_packet <= 1'b1;
                                                    temp_state <= 5'd10;
                                                end
                                            end
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                host_sw_rx_read_done <= 1'b1;
                                                host_rx_accept_data <= 1'b0;
                                                temp_state <= 5'd6;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            host_rx_accept_data <= 1'b0;
                                            temp_state <= 5'd6;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                5'd10: begin
                                    break <= 1'b0;
                    
                                    
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (!host_tx_busy) begin
                                        temp_state <= 5'd11;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd11: begin // sw_status stage
                                    break <= 1'b0;
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(idle)begin
                                        
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, 7'b0};
                                        temp_state <= 5'd12;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd12: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_OUT;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd13;
                                end
                                5'd13: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd14;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd14: begin // no load packet
                                    host_tx_pid <= PID_DATA1;
                                    if(gen_counter != INTER_GAP && idle)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (idle) begin
                                        host_tx_next_packet <= 1'b1;
                                        temp_state <= 5'd15;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd15: begin // device acknowledgement
                                    
                                    host_tx_fifo_wr <= 1'b0;
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        if(host_rx_status == 2'b10)begin
                                            if (host_rx_pid == PID_ACK) begin
                                                break <= 1'b1;
                                                state <= 4'd1;
                                                temp_state <= 5'd0;
                                                gen_counter <= 5'd0;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= 2'b00;
                                                response_time <= 20'd0;
                                            end
                                            else begin
                                                if(retry >= 3) begin
                                                    error <= 1'b1;
                                                    sw_status <= PROTO_CRIT_ERROR;
                                                end
                                                else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd11;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                                gen_counter <= 5'd0;
                                                end
                                            end
                                        end
                                        else if (response_time >= RESPONSE_TIMEOUT) begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end 
                                            else begin
                                                break <= 1'b1;
                                                state <= 4'd0;
                                                temp_state <= 5'd11;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                                gen_counter <= 5'd0;
                                            end
                                        end
                                        else 
                                            response_time <= response_time + 1'b1;
                                    end
                                end
                                default: begin
                                    temp_state <= 5'd0;
                                end
                            endcase
                        end 
                        4'd1: begin // set address
                            case (temp_state)
                                5'd0: begin // setup stage
                                    break <= 1'b0;
                                    
                                    if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, 7'b0};
                                        temp_state <= 5'd1;
                                    end
                                end
                                5'd1: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_SETUP;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd2;
                                end
                                5'd2: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd3;
                                        req_sel <= 4'd1;
                                        gen_counter <= 5'd0;
                                    end     
                                end
                                5'd3: begin // sw_request bytes
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else begin
                                        if(byte_idx < 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b1;
                                            host_tx_fifo_in <= tx_byte;
                                            byte_idx <= byte_idx + 4'd1;
                                        end
                                        else if (byte_idx == 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b0;
                                            address_buff <= sw_vacant_address;
                                            host_tx_pid <= PID_DATA0;
                                            if (idle) begin
                                                sw_address_ack <= 1'b1;
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd4;
                                                gen_counter <= 5'd0;
                                                byte_idx <= 4'b0000;
                                            end
                                        end
                                    end
                                end
                                5'd4: begin
                                    sw_address_ack <= 1'b0;
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd5;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd5: begin // device acknowledgement
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(host_rx_status == 2'b10)begin
                                        if (host_rx_pid == PID_ACK) begin
                                            break <= 1'b1;
                                            temp_state <= 5'd6;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd0;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd0;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                5'd6: begin // sw_status stage
                                    break <= 1'b0;
                                    if (idle) begin
                                        
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, 7'b0};
                                        temp_state <= 5'd7;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd7: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_OUT;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd8;
                                end
                                5'd8: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd9;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd9: begin // no load packet
                                    host_tx_pid <= PID_DATA1;
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (idle) begin
                                        host_tx_next_packet <= 1'b1;
                                        temp_state <= 5'd10;
                                    end
                                end
                                5'd10: begin // device acknowledgement
                                    
                                    host_tx_fifo_wr <= 1'b0;
                                    if(host_rx_status == 2'b10)begin
                                        if (host_rx_pid == PID_ACK) begin
                                            break <= 1'b1;
                                            state <= 4'd2;
                                            temp_state <= 5'd0;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            response_time <= 20'd0;
                                            gen_counter <= 5'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd6;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                                gen_counter <= 5'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd6;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                            gen_counter <= 5'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                default: begin
                                    temp_state <= 5'd0;
                                end
                            endcase
                        end
                        4'd2: begin 
                            case (temp_state)
                                5'd0: begin // setup stage
                                    break <= 1'b0;
                                    
                                    if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd1;
                                    end
                                end
                                5'd1: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_SETUP;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd2;
                                end
                                5'd2: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd3;
                                        req_sel <= 4'd2;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd3: begin // sw_request bytes
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else begin
                                        if(byte_idx < 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b1;
                                            host_tx_fifo_in <= tx_byte;
                                            byte_idx <= byte_idx + 4'd1;
                                        end
                                        else if (byte_idx == 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b0;
                                            host_tx_pid <= PID_DATA0;
                                            if (idle) begin
                                                byte_idx <= 4'b0000;
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd4;
                                                gen_counter <= 5'd0;
                                            end
                                        end
                                    end
                                end
                                5'd4:begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd5;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd5: begin // device acknowledgement 
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(host_rx_status == 2'b10)begin
                                        if (host_rx_pid == PID_ACK) begin
                                            break <= 1'b1;
                                            temp_state <= 5'd8;
                                            data_toggle <= 1'b1;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd0;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd0;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                5'd6:  begin
                                    break <= 1'b0;
                                    host_tx_pid <= PID_ACK;
                                    if(idle)begin
                                        temp_state <= 5'd7;
                                        host_tx_next_packet <= 1'b1;
                                    end
                                end
                                5'd7: begin
                                    break <= 1'b0;
                                    
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd8;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd8: begin // data stage
                                    break <= 1'b0;
                                    
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd9;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd9: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_IN;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd10;
                                end
                                5'd10: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd11;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd11: begin // data packet from device & ack by host
                                    if (sw_rx_valid) begin
                                        break <= 1'b0;
                                        if (sw_rx_read_done) begin
                                            fifo_rst_n <= 1'b0;
                                            sw_rx_valid <= 1'b0;
                                            host_sw_rx_read_done <= 1'b1;
                                            byte_index <= 1'd0;
                                            host_tx_pid <= PID_ACK;
                                            if(idle)begin
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd12;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (host_rx_data_pid_valid) begin
                                        if ((data_toggle && host_rx_pid == PID_DATA1) || (!data_toggle && host_rx_pid == PID_DATA0)) begin
                                            host_rx_accept_data <= 1'b1;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                host_rx_accept_data <= 1'b0;
                                                temp_state <= 5'd6;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if(host_rx_status == 2'b01||(host_rx_status == 2'b10 && (byte_index + max_packetlength) >= 18))begin
                                        response_time <= 20'd0;
                                        if((host_rx_pid == PID_DATA1) || (host_rx_pid == PID_DATA0))begin
                                            if (data_toggle && (host_rx_pid == PID_DATA1) || (!data_toggle && (host_rx_pid == PID_DATA0))) begin
                                                retry <= 2'b00;
                                                data_toggle <= ~data_toggle;
                                                host_rx_accept_data <= 1'b0;
                                                if((byte_index + max_packetlength) >= 18 )begin
                                                    break <= 1'b1;
                                                    sw_rx_valid <= 1'b1;
                                                    sw_rx_type <= RX_DEV_DESC;
                                                end
                                                else begin
                                                    break <= 1'b1;
                                                    byte_index <= byte_index + max_packetlength;
                                                    host_sw_rx_read_done <= 1'b1;
                                                    temp_state <= 5'd6;
                                                end
                                                
                                            end
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                host_sw_rx_read_done <= 1'b1;
                                                temp_state <= 5'd8;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                        
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd8;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                5'd12: begin
                                    break <= 1'b0;
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else begin
                                        temp_state <= 5'd13;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd13: begin // sw_status stage
                                    break <= 1'b0;
                                    if(idle)begin
                                        
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd14;
                                    end
                                end
                                5'd14: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_OUT;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd15;
                                    
                                end
                                5'd15: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)
                                        temp_state <= 5'd16;
                                end
                                5'd16: begin // no load packet
                                    host_tx_pid <= PID_DATA1;
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(idle)begin
                                        host_tx_next_packet <= 1'b1;
                                        temp_state <= 5'd17;
                                    end
                                end
                                5'd17: begin // device acknowledgement
                                    
                                    host_tx_fifo_wr <= 1'b0;
                                    if(host_rx_status == 2'b10)begin
                                        if (host_rx_pid == PID_ACK) begin
                                            break <= 1'b1;
                                            state <= 4'd3;
                                            temp_state <= 5'd0;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            response_time <= 20'd0;
                                            gen_counter <= 5'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd13;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                                gen_counter <= 5'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd13;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                            gen_counter <= 5'd0;
                                        end
                                    end
                                    else
                                        response_time <= response_time + 1'b1;
                                end
                                default: begin
                                    temp_state <= 5'd0;
                                end
                            endcase
                        end
                        4'd3: begin
                            case (temp_state)
                                5'd0: begin // setup stage
                                    break <= 1'b0;
                                    if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd1;
                                    end
                                end
                                5'd1: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_SETUP;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd2;
                                end
                                5'd2: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd3;
                                        req_sel <= 4'd3;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd3: begin // sw_request bytes
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else begin
                                        if(byte_idx < 4'b1000)begin
                                            host_tx_fifo_in <= tx_byte;
                                            byte_idx <= byte_idx + 4'd1;
                                            host_tx_fifo_wr <= 1'b1;
                                        end
                                        else if (byte_idx == 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b0;
                                            host_tx_pid <= PID_DATA0;
                                            if(idle)begin
                                                byte_idx <= 4'b0000;
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd4;
                                                gen_counter <= 5'd0;
                                            end
                                        end
                                    end
                                end
                                5'd4:begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd5;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd5: begin // device acknowledgement 
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(host_rx_status == 2'b10)begin
                                        if (host_rx_pid == PID_ACK) begin
                                            break <= 1'b1;
                                            temp_state <= 5'd8;
                                            data_toggle <= 1'b1;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd0;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd0;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else
                                        response_time <= response_time + 1'b1;
                                end
                                5'd6:  begin
                                    break <= 1'b0;
                                    if(idle)begin
                                        temp_state <= 5'd7;
                                        host_tx_pid <= PID_ACK;
                                        host_tx_next_packet <= 1'b1;
                                    end
                                end
                                5'd7: begin
                                    break <= 1'b0;
                                    
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd8;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd8: begin // data stage
                                    break <= 1'b0;
                                    
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd9;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd9: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_IN;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd10;
                                end
                                5'd10: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd11;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd11: begin // data packet from device & ack by host
                                    if (host_rx_read) begin
                                        break <= 1'b0;
                                        if(gen_counter != 5'd3)
                                            gen_counter <= gen_counter + 1'b1;
                                        if (gen_counter == 5'd3)begin
                                            config_len[7:0] <= host_rx_fifo_out;
                                            gen_counter <= gen_counter + 1'b1;
                                        end
                                        else if (gen_counter == 5'd4)begin
                                            gen_counter <= 5'd0;
                                            fifo_rst_n <= 1'b0;
                                            config_len[15:8] <= host_rx_fifo_out;
                                            host_rx_read <= 1'b0;
                                            host_sw_rx_read_done <= 1'b1;
                                            byte_index <= 1'd0;
                                            host_tx_pid <= PID_ACK;
                                            response_time <= 20'd0;
                                            if(idle)begin
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd12;
                                            end
                                        end
                                        
                                    end
                                    else if (host_rx_data_pid_valid) begin
                                        if ((data_toggle && host_rx_pid == PID_DATA1) || (!data_toggle && host_rx_pid == PID_DATA0)) begin
                                            host_rx_accept_data <= 1'b1;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                host_rx_accept_data <= 1'b0;
                                                temp_state <= 5'd6;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if(host_rx_status == 2'b01 ||(host_rx_status == 2'b10 && (byte_index + max_packetlength) >= 9))begin
                                        response_time <= 20'd0;
                                        if((host_rx_pid == PID_DATA1) || (host_rx_pid == PID_DATA0))begin
                                            if (data_toggle && (host_rx_pid == PID_DATA1) || (!data_toggle && (host_rx_pid == PID_DATA0))) begin
                                                retry <= 2'b00;
                                                data_toggle <= ~data_toggle;
                                                host_rx_accept_data <= 1'b0;
                                                if((byte_index + max_packetlength) >= 9 )begin
                                                    break <= 1'b1;
                                                    host_rx_read <= 1;

                                                end
                                                else begin
                                                    break <= 1'b1;
                                                    byte_index <= byte_index + max_packetlength;
                                                    host_sw_rx_read_done <= 1'b1;
                                                    temp_state <= 5'd6;
                                                end
                                                
                                            end
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                host_sw_rx_read_done <= 1'b1;
                                                temp_state <= 5'd8;
                                                retry <= retry + 1;
                                            end
                                        end
                                        
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd8;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                5'd12: begin
                                    break <= 1'b0;
                    
                                    
                                    
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (idle) begin
                                        temp_state <= 5'd13;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd13: begin // sw_status stage
                                    break <= 1'b0;
                                    
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {1'b0, address_buff};
                                    temp_state <= 5'd14;
                                end
                                5'd14: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_OUT;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd15;
                                    
                                end
                                5'd15: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd16;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd16: begin // no load packet
                                    host_tx_pid <= PID_DATA1;
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(idle)begin
                                        host_tx_next_packet <= 1'b1;
                                        temp_state <= 5'd17;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd17: begin // device acknowledgement
                                    
                                    host_tx_fifo_wr <= 1'b0;
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else begin
                                        if(host_rx_status == 2'b10)begin
                                            if (host_rx_pid == PID_ACK) begin
                                                break <= 1'b1;
                                                state <= 4'd4;
                                                temp_state <= 5'd0;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= 2'b00;
                                                gen_counter <= 5'd0;
                                                response_time <= 20'd0;
                                            end
                                            else begin
                                                if(retry >= 3) begin
                                                    error <= 1'b1;
                                                    sw_status <= PROTO_CRIT_ERROR;
                                                end
                                                else begin
                                                    break <= 1'b1;
                                                    temp_state <= 5'd13;
                                                    host_sw_rx_read_done <= 1'b1;
                                                    retry <= retry + 1;
                                                    response_time <= 20'd0;
                                                    gen_counter <= 5'd0;
                                                end
                                            end
                                        end
                                        else if (response_time >= RESPONSE_TIMEOUT) begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd13;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                                gen_counter <= 5'd0;
                                            end
                                        end
                                        else 
                                            response_time <= response_time + 1'b1;
                                    end
                                end
                                default: begin
                                    temp_state <= 5'd0;
                                end
                            endcase
                        end
                        4'd4: begin
                            case (temp_state)
                                5'd0: begin // setup stage
                                    break <= 1'b0;
                                    
                                    if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd1;
                                    end
                                end
                                5'd1: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_SETUP;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd2;
                                end
                                5'd2: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd3;
                                        req_sel <= 4'd4;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd3: begin // sw_request bytes
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else begin
                                        if(byte_idx < 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b1;
                                            host_tx_fifo_in <= tx_byte;
                                            byte_idx <= byte_idx + 4'd1;
                                        end
                                        else if (byte_idx == 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b0;
                                            host_tx_pid <= PID_DATA0;
                                            if(idle)begin
                                                byte_idx <= 4'b0000;
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd4;
                                                gen_counter <= 5'd0;
                                            end
                                        end
                                    end
                                end
                                5'd4:begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd5;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd5: begin // device acknowledgement 
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(host_rx_status == 2'b10)begin
                                        if (host_rx_pid == PID_ACK) begin
                                            break <= 1'b1;
                                            temp_state <= 5'd8;
                                            data_toggle <= 1'b1;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd0;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd0;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                5'd6:  begin
                                    break <= 1'b0;
                                    if(idle)begin
                                        temp_state <= 5'd7;
                                        host_tx_pid <= PID_ACK;
                                        host_tx_next_packet <= 1'b1;
                                    end
                                end
                                5'd7: begin
                                    break <= 1'b0;
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd8;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd8: begin // data stage
                                    break <= 1'b0;
                                    
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd9;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd9: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_IN;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd10;
                                end
                                5'd10: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd11;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd11: begin // data packet from device & ack by host
                                    if (sw_rx_valid) begin
                                        break <= 1'b0;
                                        if (sw_rx_read_done) begin
                                            fifo_rst_n <= 1'b0;
                                            sw_rx_valid <= 1'b0;
                                            host_sw_rx_read_done <= 1'b1;
                                            byte_index <= 1'd0;
                                            host_tx_pid <= PID_ACK;
                                            if(idle)begin
                                                gen_counter <= 5'd0;
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd12;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (host_rx_data_pid_valid) begin
                                        if ((data_toggle && host_rx_pid == PID_DATA1) || (!data_toggle && host_rx_pid == PID_DATA0)) begin
                                            host_rx_accept_data <= 1'b1;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                host_rx_accept_data <= 1'b0;
                                                temp_state <= 5'd6;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if(host_rx_status == 2'b01 ||(host_rx_status == 2'b10 && (byte_index + max_packetlength) >= config_len))begin
                                        response_time <= 20'd0;
                                        host_rx_accept_data <= 1'b0;
                                        if (data_toggle && (host_rx_pid == PID_DATA1) || (!data_toggle && (host_rx_pid == PID_DATA0))) begin
                                            retry <= 2'b00;
                                            data_toggle <= ~data_toggle;
                                            host_rx_accept_data <= 1'b0;
                                            if((byte_index + max_packetlength) >= config_len )begin
                                                break <= 1'b1;
                                                sw_rx_valid <= 1'b1;
                                                sw_rx_type <= RX_CONFIG_DESC;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                byte_index <= byte_index + max_packetlength;
                                                host_sw_rx_read_done <= 1'b1;
                                                temp_state <= 5'd6;
                                            end  
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                host_sw_rx_read_done <= 1'b1;
                                                temp_state <= 5'd8;
                                                retry <= retry + 1;
                                            end
                                        end
                                        
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd8;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else
                                        response_time <= response_time + 1'b1;
                                end
                                5'd12: begin
                                    break <= 1'b0;
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (!host_tx_busy) begin
                                        temp_state <= 5'd13;
                                        gen_counter <= 5'd0;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd13: begin // sw_status stage
                                    break <= 1'b0;
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(idle)begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd14;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd14: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_OUT;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd15;
                                end
                                5'd15: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd16;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd16: begin // no load packet
                                    host_tx_pid <= PID_DATA1;
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(idle)begin
                                        host_tx_next_packet <= 1'b1;
                                        temp_state <= 5'd17;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd17: begin // device acknowledgement
                                    host_tx_fifo_wr <= 1'b0;
                                    if(host_rx_status == 2'b10)begin
                                        if (host_rx_pid == PID_ACK) begin
                                            break <= 1'b1;
                                            state <= 4'd5;
                                            temp_state <= 5'd0;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            gen_counter <= 5'd0;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                error <= 1'b1;
                                                sw_status <= PROTO_CRIT_ERROR;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd13;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            error <= 1'b1;
                                            sw_status <= PROTO_CRIT_ERROR;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd13;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                default: begin
                                    temp_state <= 5'd0;
                                end
                            endcase
                        end
                        4'd5: begin
                            break <= 1'b1;
                            sw_status <= PROTO_CAN_TAKE_REQ;
                            response_time <= 20'd0;
                            if (sw_request_valid) begin
                                state <= 4'd6;
                                temp_state <= 5'd0;
                            end
                            else if (sw_transfer_start) begin
                                sw_endpoint_buff <= sw_endpoint;
                                sw_interval_buff <= sw_interval;
                                case ({sw_transfer_type, sw_direction})
                                    {2'b01, 1'b1}:begin
                                        state <= 4'd7;
                                        temp_state <= 5'd8;
                                        sw_interval_count <= 16'd0;
                                        data_toggle <= 1'b0;
                                        sw_status <= PROTO_READY;
                                    end
                                    default: state <= 4'd5; 
                                endcase
                            end
                        end
                        4'd6: begin
                            sw_status <= PROTO_NOT_READY;
                            case (temp_state)
                                5'd0: begin // setup stage
                                    break <= 1'b0;
                                    config_len[7:0] <= sw_request[15:8];
                                    config_len[15:8] <= sw_request[7:0];
                                    
                                    if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd1;
                                    end
                                end
                                5'd1: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_SETUP;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd2;
                                end
                                5'd2: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd3;
                                        req_sel <= 4'd5;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd3: begin // request bytes
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else begin
                                        if(byte_idx < 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b1;
                                            host_tx_fifo_in <= tx_byte;
                                            byte_idx <= byte_idx + 4'd1;
                                        end
                                        else if (byte_idx == 4'b1000)begin
                                            host_tx_fifo_wr <= 1'b0;
                                            host_tx_pid <= PID_DATA0;
                                            if(idle)begin
                                                byte_idx <= 4'b0000;
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd4;
                                                gen_counter <= 5'd0;
                                            end
                                        end
                                    end
                                end
                                5'd4:begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd5;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd5: begin // device acknowledgement 
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(host_rx_status == 2'b10)begin
                                        if (host_rx_pid == PID_ACK) begin
                                            break <= 1'b1;
                                            data_toggle <= 1'b1;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            gen_counter <= 5'd0;
                                            response_time <= 20'd0;
                                            if (sw_request[15:0] == 16'd0)
                                                temp_state <= 5'd13;
                                            else
                                                temp_state <= 5'd8;
                                            
                                        end
                                        else if (host_rx_pid == PID_NAK) begin
                                            break <= 1'b1;
                                            sw_status <= PROTO_NOT_SUPPORTED;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            state <= 4'd5;
                                            temp_state <= 5'd0;
                                        end
                                        else if (host_rx_pid == PID_STALL) begin
                                            break <= 1'b1;
                                            sw_status <= PROTO_EP_STALLED;
                                            host_sw_rx_read_done <= 1'b1;
                                            retry <= 2'b00;
                                            state <= 4'd5;
                                            temp_state <= 5'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                state <= 4'd5;
                                                temp_state <= 5'd0; 
                                                sw_status <= PROTO_ERROR;
                                                retry <= 2'd0;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd0;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            state <= 4'd5;
                                            temp_state <= 5'd0; 
                                            sw_status <= PROTO_ERROR;
                                            retry <= 2'd0;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd0;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                5'd6:  begin
                                    break <= 1'b0;
                                    if(idle)begin
                                        temp_state <= 5'd7;
                                        host_tx_pid <= PID_ACK;
                                        host_tx_next_packet <= 1'b1;
                                    end
                                end
                                5'd7: begin
                                    break <= 1'b0;
                                    
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    if(!host_tx_busy)begin
                                        temp_state <= 5'd8;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd8: begin // data stage
                                    break <= 1'b0;
                                    
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd9;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd9: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_IN;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd10;
                                end
                                5'd10: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy) begin
                                        temp_state <= 5'd11;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd11: begin // data packet from device & ack by host
                                    if (sw_rx_valid) begin
                                        break <= 1'b0;
                                        if (sw_rx_read_done) begin
                                            fifo_rst_n <= 1'b0;
                                            sw_rx_valid <= 1'b0;
                                            host_sw_rx_read_done <= 1'b1;
                                            byte_index <= 1'd0;
                                            host_tx_pid <= PID_ACK;
                                            if(idle)begin
                                                gen_counter <= 20'd0;
                                                host_tx_next_packet <= 1'b1;
                                                temp_state <= 5'd12;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if (host_rx_data_pid_valid) begin
                                        if ((data_toggle && host_rx_pid == PID_DATA1) || (!data_toggle && host_rx_pid == PID_DATA0)) begin
                                            host_rx_accept_data <= 1'b1;
                                            response_time <= 20'd0;
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                state <= 4'd5;
                                                temp_state <= 5'd0; 
                                                sw_status <= PROTO_ERROR;
                                                retry <= 2'd0;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                host_rx_accept_data <= 1'b0;
                                                temp_state <= 5'd6;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                    end
                                    else if(host_rx_status == 2'b01 ||(host_rx_status == 2'b10 && (byte_index + max_packetlength) >= config_len ))begin
                                        response_time <= 20'd0;
                                        if((host_rx_pid == PID_DATA1) || (host_rx_pid == PID_DATA0))begin
                                            if (data_toggle && (host_rx_pid == PID_DATA1) || (!data_toggle && (host_rx_pid == PID_DATA0))) begin
                                                retry <= 2'b00;
                                                data_toggle <= ~data_toggle;
                                                host_rx_accept_data <= 1'b0;
                                                if((byte_index + max_packetlength) >= config_len )begin
                                                    break <= 1'b1;
                                                    sw_rx_valid <= 1'b1;
                                                    sw_rx_type <= RX_REQ_DATA;
                                                end
                                                else begin
                                                    break <= 1'b1;
                                                    byte_index <= byte_index + max_packetlength;
                                                    host_sw_rx_read_done <= 1'b1;
                                                    temp_state <= 5'd6;
                                                end
                                                
                                            end
                                        end
                                        else begin
                                            if(retry >= 3) begin
                                                state <= 4'd5;
                                                temp_state <= 5'd0; 
                                                sw_status <= PROTO_ERROR;
                                                retry <= 2'd0;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                host_sw_rx_read_done <= 1'b1;
                                                temp_state <= 5'd8;
                                                retry <= retry + 1;
                                            end
                                        end
                                    end
                                    else if (response_time >= RESPONSE_TIMEOUT) begin
                                        if(retry >= 3) begin
                                            state <= 4'd5;
                                            temp_state <= 5'd0; 
                                            sw_status <= PROTO_ERROR;
                                            retry <= 2'd0;
                                        end
                                        else begin
                                            break <= 1'b1;
                                            temp_state <= 5'd8;
                                            retry <= retry + 1;
                                            response_time <= 20'd0;
                                        end
                                    end
                                    else 
                                        response_time <= response_time + 1'b1;
                                end
                                5'd12: begin
                                    break <= 1'b0;
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if (!host_tx_busy) begin
                                        temp_state <= 5'd13;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd13: begin // sw_status stage
                                    break <= 1'b0;
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(idle) begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {1'b0, address_buff};
                                        temp_state <= 5'd14;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd14: begin
                                    host_tx_fifo_wr <= 1'b1;
                                    host_tx_fifo_in <= {5'd0, 3'b0};
                                    host_tx_pid <= PID_OUT;
                                    host_tx_next_packet <= 1'b1;
                                    temp_state <= 5'd15;
                                    
                                end
                                5'd15: begin
                                    host_tx_fifo_wr <= 1'b0;
                                    if(gen_counter == 5'd0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        temp_state <= 5'd16;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd16: begin // no load packet
                                    host_tx_pid <= PID_DATA1;
                                    if(gen_counter != INTER_GAP)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(idle)begin
                                        host_tx_next_packet <= 1'b1;
                                        temp_state <= 5'd17;
                                        gen_counter <= 5'd0;
                                    end
                                end
                                5'd17: begin // device acknowledgement
                                    host_tx_fifo_wr <= 1'b0;
                                    if(gen_counter == 0)
                                        gen_counter <= gen_counter + 1'b1;
                                    else if(!host_tx_busy)begin
                                        if(host_rx_status == 2'b10)begin
                                            if (host_rx_pid == PID_ACK) begin
                                                break <= 1'b1;
                                                state <= 4'd5;
                                                temp_state <= 5'd0;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= 2'b00;
                                                gen_counter <= 5'd0;
                                                response_time <= 20'd0;
                                            end
                                            else begin
                                                if(retry >= 3) begin
                                                    state <= 4'd5;
                                                    temp_state <= 5'd0; 
                                                    sw_status <= PROTO_ERROR;
                                                    retry <= 2'd0;
                                                end
                                                else begin
                                                    break <= 1'b1;
                                                    temp_state <= 5'd13;
                                                    host_sw_rx_read_done <= 1'b1;
                                                    retry <= retry + 1;
                                                    response_time <= 20'd0;
                                                end
                                            end
                                        end
                                        else if (response_time >= RESPONSE_TIMEOUT) begin
                                            if(retry >= 3) begin
                                                state <= 4'd5;
                                                temp_state <= 5'd0; 
                                                sw_status <= PROTO_ERROR;
                                                retry <= 2'd0;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                temp_state <= 5'd13;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                        else 
                                            response_time <= response_time + 1'b1;
                                    end
                                end
                                default: begin
                                    temp_state <= 5'd0;
                                end
                            endcase
                        end
                        4'd7: begin
                            if (sw_request_valid) begin
                                state <= 4'd6;
                                temp_state <= 5'd0;
                            end
                            else if((speed == 2'b11 && sw_interval_count == hs_interval) ||(speed != 2'b11 && sw_interval_count == sw_interval_buff))begin
                                case (temp_state)
                                    5'd7: begin
                                        break <= 1'b0;
                                        if(gen_counter == 5'd0)
                                            gen_counter <= gen_counter + 1'b1;
                                        if(!host_tx_busy)begin
                                            temp_state <= 5'd8;
                                            gen_counter <= 5'd0;
                                        end
                                    end
                                    5'd8: begin // data stage
                                        
                                        if (idle) begin
                                            host_tx_fifo_wr <= 1'b1;
                                            host_tx_fifo_in <= {sw_endpoint_buff[0], address_buff};
                                            temp_state <= 5'd9;
                                        end
                                    end
                                    5'd9: begin
                                        host_tx_fifo_wr <= 1'b1;
                                        host_tx_fifo_in <= {4'd0, sw_endpoint_buff[3:1]};
                                        host_tx_pid <= PID_IN;
                                        host_tx_next_packet <= 1'b1;
                                        temp_state <= 5'd10;
                                    end
                                    5'd10: begin
                                        host_tx_fifo_wr <= 1'b0;
                                        
                                        if(gen_counter == 5'd0)
                                            gen_counter <= gen_counter + 1'b1;
                                        else if(!host_tx_busy) begin
                                            temp_state <= 5'd11;
                                            gen_counter <= 5'd0;
                                        end
                                    end
                                    5'd11: begin // data packet from device & ack by host
                                        if (sw_rx_valid) begin
                                            if (sw_rx_read_done) begin
                                                fifo_rst_n <= 1'b0;
                                                sw_rx_valid <= 1'b0;
                                                sw_rx_type <= RX_TRANSFER_DATA;
                                                host_sw_rx_read_done <= 1'b1;
                                                byte_index <= 1'd0;
                                                host_tx_pid <= PID_ACK;
                                                if(idle)begin
                                                    host_tx_next_packet <= 1'b1;
                                                    temp_state <= 5'd7;
                                                    sw_interval_count <= 16'd0;
                                                    break <= 1'b1;
                                                    response_time <= 20'd0;
                                                end
                                            end
                                        end

                                        else if (host_rx_data_pid_valid) begin
                                            if ((data_toggle && host_rx_pid == PID_DATA1) || (!data_toggle && host_rx_pid == PID_DATA0)) begin
                                                host_rx_accept_data <= 1'b1;
                                                response_time <= 20'd0;
                                            end
                                            else begin
                                                if(retry >= 3) begin
                                                    state <= 4'd5;
                                                    temp_state <= 5'd0; 
                                                    sw_status <= PROTO_ERROR;
                                                    retry <= 2'd0;
                                                end
                                                else begin
                                                    break <= 1'b1;
                                                    host_rx_accept_data <= 1'b0;
                                                    state <= 4'd7;
                                                    temp_state <= 5'd7;
                                                    retry <= retry + 1;
                                                    response_time <= 20'd0;
                                                end
                                            end
                                        end
                                        else if(host_rx_status == 2'b01)begin
                                            response_time <= 20'd0;
                                            if((host_rx_pid == PID_DATA1) || (host_rx_pid == PID_DATA0))begin
                                                break <= 1'b1;
                                                retry <= 2'b00;
                                                data_toggle <= ~data_toggle;
                                                host_rx_accept_data <= 1'b0;
                                                sw_rx_valid <= 1'b1;

                                            end
                                            else if (host_rx_pid == PID_NAK) begin
                                                break <= 1'b1;
                                                sw_status <= PROTO_NOT_SUPPORTED;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= 2'b00;
                                                state <= 4'd5;
                                                temp_state <= 5'd0;
                                            end
                                            else if (host_rx_pid == PID_STALL) begin
                                                break <= 1'b1;
                                                sw_status <= PROTO_EP_STALLED;
                                                host_sw_rx_read_done <= 1'b1;
                                                retry <= 2'b00;
                                                state <= 4'd5;
                                                temp_state <= 5'd0;
                                            end
                                            else begin
                                                if(retry >= 3) begin
                                                    state <= 4'd5;
                                                    temp_state <= 5'd0; 
                                                    sw_status <= PROTO_ERROR;
                                                    retry <= 2'd0;
                                                end
                                                else begin
                                                    break <= 1'b1;
                                                    state <= 4'd7;
                                                    host_sw_rx_read_done <= 1'b1;
                                                    temp_state <= 5'd8;
                                                    retry <= retry + 1;
                                                    response_time <= 20'd0;
                                                end
                                            end
                                            
                                        end
                                        else if (response_time >= RESPONSE_TIMEOUT) begin
                                            if(retry >= 3) begin
                                                state <= 4'd5;
                                                temp_state <= 5'd0; 
                                                sw_status <= PROTO_ERROR;
                                                retry <= 2'd0;
                                            end
                                            else begin
                                                break <= 1'b1;
                                                state <= 4'd7;
                                                temp_state <= 5'd8;
                                                retry <= retry + 1;
                                                response_time <= 20'd0;
                                            end
                                        end
                                        else
                                            response_time <= response_time + 1'b1;
                                    end
                                    default: temp_state <= 5'd6;
                                endcase
                            end
                            else
                                break <= 1'b1;
                        end
                        default: state <= 4'd0; 
                    endcase
                end
            end
         end
   end

 endmodule