module mouse_protocol#(
    parameter CLK_FREQ = 48_000_000
 )(
    input clk, rst_n, connected, idle, 
    input [1:0] speed,

    input device_tx_busy, device_tx_fifo_full, device_rx_data_pid_valid,
    input [1:0] device_rx_status,
    input [7:0] device_rx_fifo_out,
    input [3:0] device_rx_pid,
    output reg device_rx_fifo_read, device_fifo_rst_n,
    output reg device_rx_read_done, device_rx_accept_data,
    output reg device_tx_next_packet, device_tx_fifo_wr,
    output reg [7:0] device_tx_fifo_in,
    output reg [3:0] device_tx_pid,

   input [63:0] ep1_in,
   input ep1_valid,
   output reg ep1_sent
 );
   localparam RESPONSE_TIMEOUT = (CLK_FREQ / 1000000)*10; // 10us(500 clk)
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

    localparam DEV_MAX_PACKET_LEN = 8'h08;

   wire [5:0]addr;
   reg [7:0] mouse_device_desc_rom, mouse_config_desc_rom, mouse_report_desc_rom;

   always @(*) begin
         case (addr)
            5'd0 : mouse_device_desc_rom = 8'h12; // bLength
            5'd1 : mouse_device_desc_rom = 8'h01; // bDescriptorType = DEVICE
            5'd2 : mouse_device_desc_rom = 8'h00; // bcdUSB low
            5'd3 : mouse_device_desc_rom = 8'h02; // bcdUSB high (USB 2.0)
            5'd4 : mouse_device_desc_rom = 8'h00; // bDeviceClass
            5'd5 : mouse_device_desc_rom = 8'h00; // bDeviceSubClass
            5'd6 : mouse_device_desc_rom = 8'h00; // bDeviceProtocol
            5'd7 : mouse_device_desc_rom = DEV_MAX_PACKET_LEN; // bMaxPacketSize0
            5'd8 : mouse_device_desc_rom = 8'hD2; // idVendor low
            5'd9 : mouse_device_desc_rom = 8'h04; // idVendor high (0x04D2)
            5'd10: mouse_device_desc_rom = 8'h02; // idProduct low
            5'd11: mouse_device_desc_rom = 8'h00; // idProduct high (0x0002)
            5'd12: mouse_device_desc_rom = 8'h00; // bcdDevice low
            5'd13: mouse_device_desc_rom = 8'h01; // bcdDevice high (0x0100)
            5'd14: mouse_device_desc_rom = 8'h00; // iManufacturer
            5'd15: mouse_device_desc_rom = 8'h00; // iProduct
            5'd16: mouse_device_desc_rom = 8'h00; // iSerialNumber
            5'd17: mouse_device_desc_rom = 8'h01; // bNumConfigurations
            default: mouse_device_desc_rom = 8'h00;
        endcase


         case (addr)
            // -- Configuration Descriptor --
            6'd0 : mouse_config_desc_rom = 8'h09; // bLength
            6'd1 : mouse_config_desc_rom = 8'h02; // bDescriptorType = CONFIGURATION
            6'd2 : mouse_config_desc_rom = 8'h22; // wTotalLength low (34)
            6'd3 : mouse_config_desc_rom = 8'h00; // wTotalLength high
            6'd4 : mouse_config_desc_rom = 8'h01; // bNumInterfaces
            6'd5 : mouse_config_desc_rom = 8'h01; // bConfigurationValue
            6'd6 : mouse_config_desc_rom = 8'h00; // iConfiguration
            6'd7 : mouse_config_desc_rom = 8'hA0; // bmAttributes
            6'd8 : mouse_config_desc_rom = 8'h32; // bMaxPower (100mA)
            // -- Interface Descriptor --
            6'd9 : mouse_config_desc_rom = 8'h09; // bLength
            6'd10: mouse_config_desc_rom = 8'h04; // bDescriptorType = INTERFACE
            6'd11: mouse_config_desc_rom = 8'h00; // bInterfaceNumber
            6'd12: mouse_config_desc_rom = 8'h00; // bAlternateSetting
            6'd13: mouse_config_desc_rom = 8'h01; // bNumEndpoints
            6'd14: mouse_config_desc_rom = 8'h03; // bInterfaceClass = HID
            6'd15: mouse_config_desc_rom = 8'h01; // bInterfaceSubClass = Boot
            6'd16: mouse_config_desc_rom = 8'h02; // bInterfaceProtocol = Mouse
            6'd17: mouse_config_desc_rom = 8'h00; // iInterface
            // -- HID Descriptor --
            6'd18: mouse_config_desc_rom = 8'h09; // bLength
            6'd19: mouse_config_desc_rom = 8'h21; // bDescriptorType = HID
            6'd20: mouse_config_desc_rom = 8'h11; // bcdHID low (0x0111)
            6'd21: mouse_config_desc_rom = 8'h01; // bcdHID high
            6'd22: mouse_config_desc_rom = 8'h00; // bCountryCode
            6'd23: mouse_config_desc_rom = 8'h01; // bNumDescriptors
            6'd24: mouse_config_desc_rom = 8'h22; // bDescriptorType[0] = Report
            6'd25: mouse_config_desc_rom = 8'h32; // wDescriptorLength low (0x0032=50)
            6'd26: mouse_config_desc_rom = 8'h00; // wDescriptorLength high
            // -- Endpoint Descriptor --
            6'd27: mouse_config_desc_rom = 8'h07; // bLength
            6'd28: mouse_config_desc_rom = 8'h05; // bDescriptorType = ENDPOINT
            6'd29: mouse_config_desc_rom = 8'h81; // bEndpointAddress = EP1 IN
            6'd30: mouse_config_desc_rom = 8'h03; // bmAttributes = Interrupt
            6'd31: mouse_config_desc_rom = 8'h08; // wMaxPacketSize low
            6'd32: mouse_config_desc_rom = 8'h00; // wMaxPacketSize high
            6'd33: mouse_config_desc_rom = (speed == 2'b11)? 8'h01: 8'h0A; // bInterval
            default: mouse_config_desc_rom = 8'h00;

         endcase

         case (addr)
            6'd0 : mouse_report_desc_rom = 8'h05; // Usage Page (Generic Desktop)
            6'd1 : mouse_report_desc_rom = 8'h01;
            6'd2 : mouse_report_desc_rom = 8'h09; // Usage (Mouse)
            6'd3 : mouse_report_desc_rom = 8'h02;
            6'd4 : mouse_report_desc_rom = 8'hA1; // Collection (Application)
            6'd5 : mouse_report_desc_rom = 8'h01;
            6'd6 : mouse_report_desc_rom = 8'h09; // Usage (Pointer)
            6'd7 : mouse_report_desc_rom = 8'h01;
            6'd8 : mouse_report_desc_rom = 8'hA1; // Collection (Physical)
            6'd9 : mouse_report_desc_rom = 8'h00;
            6'd10: mouse_report_desc_rom = 8'h05; // Usage Page (Buttons)
            6'd11: mouse_report_desc_rom = 8'h09;
            6'd12: mouse_report_desc_rom = 8'h19; // Usage Minimum (Button 1)
            6'd13: mouse_report_desc_rom = 8'h01;
            6'd14: mouse_report_desc_rom = 8'h29; // Usage Maximum (Button 3)
            6'd15: mouse_report_desc_rom = 8'h03;
            6'd16: mouse_report_desc_rom = 8'h15; // Logical Minimum (0)
            6'd17: mouse_report_desc_rom = 8'h00;
            6'd18: mouse_report_desc_rom = 8'h25; // Logical Maximum (1)
            6'd19: mouse_report_desc_rom = 8'h01;
            6'd20: mouse_report_desc_rom = 8'h95; // Report Count (3)
            6'd21: mouse_report_desc_rom = 8'h03;
            6'd22: mouse_report_desc_rom = 8'h75; // Report Size (1)
            6'd23: mouse_report_desc_rom = 8'h01;
            6'd24: mouse_report_desc_rom = 8'h81; // Input (Data,Var,Abs) - 3 buttons
            6'd25: mouse_report_desc_rom = 8'h02;
            6'd26: mouse_report_desc_rom = 8'h95; // Report Count (1)
            6'd27: mouse_report_desc_rom = 8'h01;
            6'd28: mouse_report_desc_rom = 8'h75; // Report Size (5)
            6'd29: mouse_report_desc_rom = 8'h05;
            6'd30: mouse_report_desc_rom = 8'h81; // Input (Const) - 5-bit padding
            6'd31: mouse_report_desc_rom = 8'h01;
            6'd32: mouse_report_desc_rom = 8'h05; // Usage Page (Generic Desktop)
            6'd33: mouse_report_desc_rom = 8'h01;
            6'd34: mouse_report_desc_rom = 8'h09; // Usage (X)
            6'd35: mouse_report_desc_rom = 8'h30;
            6'd36: mouse_report_desc_rom = 8'h09; // Usage (Y)
            6'd37: mouse_report_desc_rom = 8'h31;
            6'd38: mouse_report_desc_rom = 8'h15; // Logical Minimum (-127)
            6'd39: mouse_report_desc_rom = 8'h81;
            6'd40: mouse_report_desc_rom = 8'h25; // Logical Maximum (127)
            6'd41: mouse_report_desc_rom = 8'h7F;
            6'd42: mouse_report_desc_rom = 8'h75; // Report Size (8)
            6'd43: mouse_report_desc_rom = 8'h08;
            6'd44: mouse_report_desc_rom = 8'h95; // Report Count (2)
            6'd45: mouse_report_desc_rom = 8'h02;
            6'd46: mouse_report_desc_rom = 8'h81; // Input (Data,Var,Rel) - X,Y
            6'd47: mouse_report_desc_rom = 8'h06;
            6'd48: mouse_report_desc_rom = 8'hC0; // End Collection (Physical)
            6'd49: mouse_report_desc_rom = 8'hC0; // End Collection (Application)
            default: mouse_report_desc_rom = 8'h00;
        endcase
   end
reg state;
      reg [3:0] temp_state, sub_state;
      reg [6:0] dev_address;
      reg [6:0] dev_address_buff;
      reg [3:0] endpoint;
      reg [15:0] gen_counter;
      reg [7:0] configuration;
      reg data_toggle;
      reg [15:0] response_time;
      reg [63:0] request;
      reg [7:0] idle_rate;
      reg protocol_sel;
      reg [7:0] report_id;
      reg [15:0] request_count;
      wire [7:0]ep1_byte;
      reg [10:0] sof_frame;
      assign ep1_byte = ep1_in[gen_counter*8 +: 8];
      assign addr = request_count + gen_counter;

   always @(posedge clk or negedge rst_n) begin
      if(device_rx_read_done)
         device_rx_read_done <= 1'b0;
      if(!device_fifo_rst_n)
         device_fifo_rst_n <= 1'b1;
      if(device_tx_next_packet)
         device_tx_next_packet <= 1'b0;
      if (!rst_n || !connected) begin
         sof_frame <= 11'd0;
         device_tx_next_packet <= 1'b0;
         device_fifo_rst_n <= 1'b1;
         device_rx_read_done <= 1'b0;
         state <= 1'b0;
         temp_state <= 4'd0;
         sub_state <= 4'd0;
         dev_address <= 7'd0;
         dev_address_buff <= 7'd0;
         endpoint <= 4'd0;
         gen_counter <= 16'd0;
         configuration <= 8'd0;
         data_toggle <= 1'b0;
         response_time <= 16'd0;
         request <= 64'd0;
         idle_rate <= 8'd0;
         protocol_sel <= 1'b0;
         report_id <= 8'd0;
         device_rx_fifo_read <= 1'b0;
         
         device_rx_accept_data <= 1'b0;
         
         device_tx_fifo_wr <= 1'b0;
         device_tx_fifo_in <= 8'd0;
         device_tx_pid <= 4'd0;
         ep1_sent <= 1'b0;
         
         request_count <= 16'd0;
      end
      else if ((device_rx_status == 2'b01|| (device_rx_status == 2'b10 && gen_counter == 16'd3)) && device_rx_pid == PID_SOF ) begin
         if (gen_counter !=16'd3)begin
            gen_counter <= gen_counter +1'b1;
            device_rx_fifo_read <= 1'b1;
         end
         if(gen_counter == 16'd2)begin
            sof_frame[7:0] <=device_rx_fifo_out; 
         end
         if(gen_counter == 16'd3)begin
            device_rx_read_done <= 1'b1;
            device_fifo_rst_n <= 1'b0;
            device_rx_fifo_read <= 1'b0;
            sof_frame[10:8] <= device_rx_fifo_out[2:0];
            gen_counter <= 16'd0;
         end
      end
      else if (device_rx_status == 2'b01 && device_rx_pid == PID_SETUP && !state) begin
            state <= 1'b1;
            temp_state <= 4'd0;
            sub_state <= 4'd0;
            gen_counter <= 16'd0;
      end
      else if (!state) begin
         case (temp_state)
            4'd0: begin
               ep1_sent <= 1'b0;
               
               if (device_rx_status == 2'b01) begin
                  case (device_rx_pid)
                     PID_IN: begin
                        temp_state <= 4'd1;
                        sub_state <= 4'd0;
                     end
                     default: temp_state <= 4'd0; 
                  endcase
               end
            end 
            4'd1: begin
               case (sub_state)
                  4'd0: begin
                     device_rx_fifo_read <= 1'b1;
                     if (gen_counter !=16'd3)
                        gen_counter <= gen_counter +1'b1;
                     if(gen_counter == 16'd2)begin
                        dev_address_buff <= device_rx_fifo_out[6:0];
                        endpoint[0] <= device_rx_fifo_out[7];
                     end
                     if(gen_counter == 16'd3)begin
                        device_rx_read_done <= 1'b1;
                        device_fifo_rst_n <= 1'b0;
                        endpoint[3:1] <= device_rx_fifo_out[2:0];
                        gen_counter <= 16'd0;
                        sub_state <= 4'd1;
                     end
                  end
                  4'd1: begin
                     
                     device_rx_fifo_read <= 1'b0;
                     if (configuration == 8'd1 && endpoint == 4'b1 && dev_address == dev_address_buff) begin
                        if(!ep1_valid)begin
                           device_tx_pid <= PID_NAK;
                           if(idle)begin
                              device_tx_next_packet <= 1'b1;
                              temp_state <= 4'd0;
                              sub_state <= 4'd0;
                           end
                        end
                        else if (gen_counter < 16'd7) begin
                           device_tx_fifo_wr <= 1'b1;
                           device_tx_fifo_in <= ep1_byte;
                           gen_counter <= gen_counter + 1'b1;
                        end
                        else if (gen_counter == 16'd7) begin
                           device_tx_fifo_wr <= 1'b1;
                           device_tx_fifo_in <= ep1_byte;
                           gen_counter <= gen_counter + 1'b1;
                        end
                        else if (gen_counter > 16'd7) begin
                           device_tx_fifo_wr <= 1'b0;
                           device_tx_pid <= data_toggle? PID_DATA1 : PID_DATA0;
                           if(idle)begin
                              device_tx_next_packet <= 1'b1;
                              gen_counter <= 16'd0;
                              sub_state <= 4'd2;
                           end
                        end
                     end
                     else begin
                        temp_state <= 4'd0;
                        sub_state <= 4'd0;
                     end
                  end
                  4'd2: begin
                     device_tx_fifo_wr <= 1'b0;
                     device_tx_next_packet <= 1'd0;
                     if (device_rx_status == 2'b10) begin
                        if (device_rx_pid == PID_ACK) begin
                           device_rx_read_done <= 1'b1;
                           temp_state <= 4'd0;
                           sub_state <= 4'd0;
                           data_toggle <= ~data_toggle;
                           ep1_sent <= 1'b1;
                        end
                        else begin
                           temp_state <= 4'd0;
                           sub_state <= 4'd0;
                        end
                     end
                     else if (device_rx_status == 2'b01 || device_rx_status == 2'b11) begin
                           temp_state <= 4'd0;
                           sub_state <= 4'd0;
                     end
                  end
                  default: temp_state <= 4'b0; 
               endcase
            end
            default: temp_state <= 4'd0;
         endcase
      end
      else if (state) begin
         case (temp_state)
            4'd0: begin
               if (device_rx_status == 2'b01 || (device_rx_status == 2'b10 && gen_counter == 16'd3)) begin
                  if (device_rx_pid == PID_SETUP) begin
                     if (gen_counter !=16'd3)begin
                        gen_counter <= gen_counter +1'b1;
                        device_rx_fifo_read <= 1'b1;
                     end
                     if(gen_counter == 16'd2)begin
                        dev_address_buff <= device_rx_fifo_out[6:0];
                        endpoint[0] <= device_rx_fifo_out[7];
                     end
                     if(gen_counter == 16'd3)begin
                        device_fifo_rst_n <= 1'b0;
                        device_rx_fifo_read <= 1'b0;
                        device_rx_read_done <= 1'b1;
                        device_fifo_rst_n <= 1'b0;
                        endpoint[3:1] <= device_rx_fifo_out[2:0];
                        gen_counter <= 16'd0;
                        temp_state <= 4'd1;
                     end
                  end
               end
            end
            4'd1: begin
               
               if (dev_address == dev_address_buff && endpoint == 4'd0) begin
                  if (device_rx_data_pid_valid) begin
                     if (device_rx_pid == PID_DATA0) begin
                        device_rx_accept_data <= 1'b1;
                     end
                     else begin
                        sub_state <= 4'd0;
                        temp_state <= 4'd0;
                        state <= 1'b0;
                        data_toggle <= 1'b0;
                     end
                  end
                  if (device_rx_status == 2'b01 || (device_rx_status == 2'b10 && gen_counter == 16'd9)) begin
                     if(gen_counter != 16'd9)begin
                        device_rx_fifo_read <= 1'b1;
                        gen_counter <= gen_counter + 1'b1;
                        if (gen_counter > 16'd1)
                           request[(7 - (gen_counter - 16'd2)) * 8 +: 8] <= device_rx_fifo_out;
                     end
                     else if (gen_counter == 16'd9) begin
                        device_fifo_rst_n <= 1'b0;
                        device_rx_fifo_read <= 1'b0;
                        request[(7 - (gen_counter - 16'd2)) * 8 +: 8] <= device_rx_fifo_out;
                        temp_state <= 4'd2;
                        sub_state <= 4'd0;
                        gen_counter <= 16'd0;
                        device_rx_read_done <= 1'b1;
                        device_rx_accept_data <= 1'b0;
                        if ((request[63:48] == {8'h00, 8'h05} || 
                              request[63:48] == {8'h00, 8'h09} ||
                              request[63:48] == {8'h21, 8'h0A} ||
                              request[63:48] == {8'h21, 8'h0B}) && (request[15:0] == 16'd0))
                           temp_state <= 4'd2;
                        else if(request[63:32] == {8'h80, 8'h06, 8'h00, 8'h01} || 
                              request[63:32] == {8'h80, 8'h06, 8'h00, 8'h02} ||
                              request[63:32] == {8'h81, 8'h06, 8'h00, 8'h22})
                           temp_state <= 4'd3;
                        else if(idle)begin
                           
                           device_tx_pid <= PID_NAK;
                           device_tx_next_packet <= 1'b1;
                           sub_state <= 4'd0;
                           temp_state <= 4'd0;
                           state <= 1'b0;
                           data_toggle <= 1'b0;
                        end
                     end
                  end
               end
               else begin
                  sub_state <= 4'd0;
                  temp_state <= 4'd0;
                  state <= 1'b0;
                  data_toggle <= 1'b0;
               end
            end
            4'd2: begin
               case (sub_state)
                  4'd0: begin
                     data_toggle <= 1'b1;
                     device_tx_pid <= PID_ACK;
                     if(idle)begin
                        device_tx_next_packet <= 1'b1;
                        sub_state <= 4'd1;
                     end
                  end
                  4'd1: begin
                     
                     device_tx_fifo_wr <= 1'b0;
                     if (device_rx_status == 2'b01 || (device_rx_status == 2'b10 && gen_counter == 16'd3)) begin
                        if (device_rx_pid == PID_OUT) begin
                           if (gen_counter !=16'd3)begin
                              gen_counter <= gen_counter +1'b1;
                              device_rx_fifo_read <= 1'b1;
                           end
                           if(gen_counter == 16'd2)begin
                              dev_address_buff <= device_rx_fifo_out[6:0];
                              endpoint[0] <= device_rx_fifo_out[7];
                           end
                           if(gen_counter == 16'd3)begin
                              device_rx_read_done <= 1'b1;
                              device_fifo_rst_n <= 1'b0;
                              device_rx_fifo_read <= 1'b0;
                              endpoint[3:1] <= device_rx_fifo_out[2:0];
                              gen_counter <= 16'd0;
                              sub_state <= 4'd2;
                           end
                        end
                     end
                  end
                  4'd2: begin
                     
                     if (dev_address == dev_address_buff && endpoint == 4'd0) begin
                        if (device_rx_data_pid_valid) begin
                           if (device_rx_pid == PID_DATA1) begin
                              device_rx_accept_data <= 1'b1;
                           end
                           else begin
                              sub_state <= 4'd0;
                              temp_state <= 4'd0;
                              state <= 1'b0;
                              data_toggle <= 1'b0;
                           end
                        end
                        else if (device_rx_status == 2'b10 && device_rx_accept_data)begin
                           sub_state <= 4'd3;
                           device_rx_read_done <= 1'b1;
                           device_rx_accept_data <= 1'b0;
                        end
                     end
                     else begin
                        sub_state <= 4'd0;
                        temp_state <= 4'd0;
                        state <= 1'b0;
                        data_toggle <= 1'b0;
                     end
                  end
                  4'd3: begin
                     
                     if(idle)begin
                        device_tx_pid <= PID_ACK;
                        device_tx_next_packet <= 1'b1;
                        sub_state <= 4'd0;
                        temp_state <= 4'd0;
                        state <= 1'b0;
                        data_toggle <= 1'b0;
                     end
                     case (request[63:48])
                        {8'h00, 8'h05}: dev_address <= request[46:40];
                        {8'h00, 8'h09}: configuration <= request[47:40];
                        {8'h21, 8'h0A}: begin
                           idle_rate <= request[39:32];
                           report_id <= request[47:40];
                        end
                        {8'h21, 8'h0B}: protocol_sel <= request[40];
                        default: ;
                     endcase
                  end
                  default: begin
                     sub_state <= 4'd0;
                     temp_state <= 4'd0;
                     state <= 1'b0;
                     data_toggle <= 1'b0;
                  end
               endcase
            end
            4'd3: begin
               case (sub_state)
                     4'd0: begin
                        device_tx_pid <= PID_ACK;
                        if(idle)begin
                           device_tx_next_packet <= 1'b1;
                           sub_state <= 4'd1;
                           data_toggle <= 1'b1;
                        end
                     end 
                     4'd1: begin
                        
                        device_tx_fifo_wr <= 1'b0; 
                        if (device_rx_status == 2'b01 || (device_rx_status == 2'b10 && gen_counter == 16'd3)) begin
                           if (device_rx_pid == PID_IN) begin
                              if (gen_counter !=16'd3)begin
                                 gen_counter <= gen_counter +1'b1;
                                 device_rx_fifo_read <= 1'b1;
                              end
                              if(gen_counter == 16'd2)begin
                                 dev_address_buff <= device_rx_fifo_out[6:0];
                                 endpoint[0] <= device_rx_fifo_out[7];
                              end
                              if(gen_counter == 16'd3)begin
                                 device_rx_read_done <= 1'b1;
                                 device_fifo_rst_n <= 1'b0;
                                 device_rx_fifo_read <= 1'b0;
                                 endpoint[3:1] <= device_rx_fifo_out[2:0];
                                 gen_counter <= 16'd0;
                                 sub_state <= 4'd2;
                              end
                           end
                        end   
                     end
                     4'd2: begin
                        
                        if (dev_address == dev_address_buff && endpoint == 4'd0) begin
                           if (({request[7:0], request[15:8]} - request_count) >= DEV_MAX_PACKET_LEN) begin
                              if (gen_counter < (DEV_MAX_PACKET_LEN - 1'b1)) begin
                                 device_tx_fifo_wr <= 1'b1;
                                 gen_counter <= gen_counter + 1'b1;
                                 case (request[63:32])
                                    {8'h80, 8'h06, 8'h00, 8'h01}: device_tx_fifo_in <= mouse_device_desc_rom;
                                    {8'h80, 8'h06, 8'h00, 8'h02}: device_tx_fifo_in <= mouse_config_desc_rom;
                                    {8'h81, 8'h06, 8'h00, 8'h22}: device_tx_fifo_in <= mouse_report_desc_rom;
                                    default: device_tx_fifo_in <= 8'h00;
                                 endcase
                              end
                              else if (gen_counter == (DEV_MAX_PACKET_LEN - 1'b1) ) begin
                                 device_tx_fifo_wr <= 1'b1;
                                 case (request[63:32])
                                    {8'h80, 8'h06, 8'h00, 8'h01}: device_tx_fifo_in <= mouse_device_desc_rom;
                                    {8'h80, 8'h06, 8'h00, 8'h02}: device_tx_fifo_in <= mouse_config_desc_rom;
                                    {8'h81, 8'h06, 8'h00, 8'h22}: device_tx_fifo_in <= mouse_report_desc_rom;
                                 endcase
                                 gen_counter <= gen_counter + 1'b1;
                              end
                              else if (gen_counter == DEV_MAX_PACKET_LEN) begin
                                 device_tx_fifo_wr <= 1'b0;
                                 if(idle)begin
                                    device_tx_pid <= data_toggle? PID_DATA1 : PID_DATA0;
                                    device_tx_next_packet <= 1'b1;
                                    gen_counter <= 16'd0;
                                    sub_state <= 4'd3;
                                 end
                              end
                           end
                           else begin
                              if (gen_counter < (({request[7:0], request[15:8]} - request_count) - 1'b1)) begin
                                 device_tx_fifo_wr <= 1'b1;
                                 gen_counter <= gen_counter + 1'b1;
                                 case (request[63:32])
                                    {8'h80, 8'h06, 8'h00, 8'h01}: device_tx_fifo_in <= mouse_device_desc_rom;
                                    {8'h80, 8'h06, 8'h00, 8'h02}: device_tx_fifo_in <= mouse_config_desc_rom;
                                    {8'h81, 8'h06, 8'h00, 8'h22}: device_tx_fifo_in <= mouse_report_desc_rom;
                                    default: device_tx_fifo_in <= 8'h00;
                                 endcase
                              end
                              else if (gen_counter == (({request[7:0], request[15:8]} - request_count) - 1'b1)) begin
                                 device_tx_fifo_wr <= 1'b1;
                                 case (request[63:32])
                                    {8'h80, 8'h06, 8'h00, 8'h01}: device_tx_fifo_in <= mouse_device_desc_rom;
                                    {8'h80, 8'h06, 8'h00, 8'h02}: device_tx_fifo_in <= mouse_config_desc_rom;
                                    {8'h81, 8'h06, 8'h00, 8'h22}: device_tx_fifo_in <= mouse_report_desc_rom;
                                    default: device_tx_fifo_in <= 8'h00;
                                 endcase
                                 gen_counter <= gen_counter + 1'b1;
                              end
                              else if (gen_counter == ({request[7:0], request[15:8]} - request_count)) begin
                                 device_tx_fifo_wr <= 1'b0;
                                 if(idle)begin
                                    device_tx_pid <= data_toggle? PID_DATA1 : PID_DATA0;
                                    device_tx_next_packet <= 1'b1;
                                    gen_counter <= 16'd0;
                                    sub_state <= 4'd3;
                                 end
                              end
                           end
                        end
                        else begin
                           sub_state <= 4'd0;
                           temp_state <= 4'd0;
                           state <= 1'b0;
                           data_toggle <= 1'b0;
                        end
                     end
                     4'd3: begin
                        if (device_rx_status != 2'd0) begin
                           device_rx_read_done <= 1'b1;
                           if(device_rx_pid == PID_ACK)begin
                              data_toggle <= ~data_toggle;
                              if ({request[7:0], request[15:8]} > (request_count + DEV_MAX_PACKET_LEN)) begin
                                 request_count <= request_count + DEV_MAX_PACKET_LEN;
                                 sub_state <= 4'd1;
                              end
                              else begin
                                 request_count <= 16'd0;
                                 sub_state <= 4'd4;
                              end
                           end
                           else if (device_rx_pid == PID_OUT) begin
                              sub_state <= 4'd4;
                              request_count <= 16'd0;
                           end
                           else if (device_rx_pid == PID_IN) begin
                              sub_state <= 4'd1;
                           end
                        end
                     end
                     4'd4: begin
                        device_tx_fifo_wr <= 1'b0;
                        if (device_rx_status == 2'b01 || (device_rx_status == 2'b10 && gen_counter == 16'd3)) begin
                           if (device_rx_pid == PID_OUT) begin
                              if (gen_counter !=16'd3)begin
                                 gen_counter <= gen_counter +1'b1;
                                 device_rx_fifo_read <= 1'b1;
                              end
                              if(gen_counter == 16'd2)begin
                                 dev_address_buff <= device_rx_fifo_out[6:0];
                                 endpoint[0] <= device_rx_fifo_out[7];
                              end
                              if(gen_counter == 16'd3)begin
                                 device_rx_read_done <= 1'b1;
                                 device_fifo_rst_n <= 1'b0;
                                 device_rx_fifo_read <= 1'b0;
                                 endpoint[3:1] <= device_rx_fifo_out[2:0];
                                 gen_counter <= 16'd0;
                                 sub_state <= 4'd5;
                              end
                           end
                        end
                     end
                     4'd5: begin
                        
                        if (dev_address == dev_address_buff && endpoint == 4'd0) begin
                           if (device_rx_data_pid_valid) begin
                              if (device_rx_pid == PID_DATA1) begin
                                 device_rx_accept_data <= 1'b1;
                              end
                              else begin
                                 sub_state <= 4'd0;
                                 temp_state <= 4'd0;
                                 state <= 1'b0;
                                 data_toggle <= 1'b0;
                              end
                           end
                           else if (device_rx_status == 2'b10 && device_rx_accept_data)begin
                              sub_state <= 4'd6;
                              device_rx_read_done <= 1'b1;
                              device_rx_accept_data <= 1'b0;
                           end

                        end
                        else begin
                           sub_state <= 4'd0;
                           temp_state <= 4'd0;
                           state <= 1'b0;
                           data_toggle <= 1'b0;
                        end
                     end
                     4'd6: begin
                        
                        if(idle)begin
                           device_tx_pid <= PID_ACK;
                           device_tx_next_packet <= 1'b1;
                           sub_state <= 4'd0;
                           temp_state <= 4'd0;
                           state <= 1'b0;
                           data_toggle <= 1'b0;
                        end
                     end
                     default: begin
                        sub_state <= 4'd0;
                        temp_state <= 4'd0;
                        state <= 1'b0;
                        data_toggle <= 1'b0;
                     end
                  endcase
            end
            default:begin
               sub_state <= 4'd0;
               temp_state <= 4'd0;
               state <= 1'b0;
               data_toggle <= 1'b0;
            end 
         endcase
      end
   end

endmodule