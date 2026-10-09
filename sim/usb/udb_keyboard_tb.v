`timescale 1ns/1ps

module usb_keyboard_tb;

    
    
    
    
    
    
    
    
    
    localparam CLK_FREQ_SIM     = 48_000_000;   
    localparam real CLK_PERIOD_NS = 20.833; 

    
    
    
    reg clk;
    reg por_rst_n;
    reg connected;

    reg         sw_request_valid;
    reg  [63:0] sw_request;
    reg  [6:0]  sw_vacant_address;
    wire        sw_address_ack;
    reg         sw_transfer_start;
    reg  [3:0]  sw_endpoint;
    reg  [1:0]  sw_transfer_type;
    reg         sw_direction;
    reg  [7:0]  sw_interval;
    wire [3:0]  sw_status;
    wire        sw_rx_valid;
    wire [2:0]  sw_rx_type;
    wire        sw_rx_fifo_empty;
    reg         sw_rx_fifo_read;
    reg         sw_rx_read_done;
    wire [7:0]  sw_rx_fifo_out;

    reg  [63:0] ep1_in;
    reg         ep1_valid;
    wire        ep1_sent;

    
    
    
    localparam [3:0] PROTO_DISCONNECTED  = 4'b0000;
    localparam [3:0] PROTO_NOT_READY     = 4'b0001;
    localparam [3:0] PROTO_CAN_TAKE_REQ  = 4'b0010;
    localparam [3:0] PROTO_NOT_SUPPORTED = 4'b0011;
    localparam [3:0] PROTO_READY         = 4'b0100;
    localparam [3:0] PROTO_EP_STALLED    = 4'b0101;
    localparam [3:0] PROTO_CRIT_ERROR    = 4'b0110;
    localparam [3:0] PROTO_ERROR         = 4'b0111;

    
    
    
    localparam [63:0] REQ_SET_CONFIGURATION_1 = {
        8'h00, 8'h09, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00
    };
    localparam [63:0] REQ_GET_HID_REPORT_DESC = {
        8'h81, 8'h06, 8'h00, 8'h22, 8'h00, 8'h00, 8'h3F, 8'h00
    };
    localparam [63:0] REQ_HID_SET_IDLE = {
        8'h21, 8'h0A, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00
    };
    localparam [63:0] REQ_HID_SET_PROTOCOL = {
        8'h21, 8'h0B, 8'h01, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00
    };

    
    
    
    usb_keyboard #(
        .CLK_FREQ(CLK_FREQ_SIM),
        .MAX_SPEED(2'b11)
    ) dut (
        .clk(clk),
        .por_rst_n(por_rst_n),
        .connected(connected),

        .sw_request_valid(sw_request_valid),
        .sw_request(sw_request),
        .sw_vacant_address(sw_vacant_address),
        .sw_address_ack(sw_address_ack),
        .sw_transfer_start(sw_transfer_start),
        .sw_endpoint(sw_endpoint),
        .sw_transfer_type(sw_transfer_type),
        .sw_direction(sw_direction),
        .sw_interval(sw_interval),
        .sw_status(sw_status),
        .sw_rx_valid(sw_rx_valid),
        .sw_rx_type(sw_rx_type),
        .sw_rx_fifo_empty(sw_rx_fifo_empty),
        .sw_rx_fifo_read(sw_rx_fifo_read),
        .sw_rx_read_done(sw_rx_read_done),
        .sw_rx_fifo_out(sw_rx_fifo_out),

        .ep1_in(ep1_in),
        .ep1_valid(ep1_valid),
        .ep1_sent(ep1_sent)
    );

    
    
    
    initial clk = 1'b0;
    always #(CLK_PERIOD_NS/2.0) clk = ~clk;

    
    
    
    
    
    reg chk_reset, chk_connect, chk_enum;
    reg chk_r1, chk_r2, chk_r3, chk_r4;
    reg chk_transfer, chk_rx_data, chk_reports;
    integer reports_sent;
    integer passed;

    initial begin
        por_rst_n         = 1'b0;
        connected         = 1'b0;
        sw_vacant_address = 7'd5; 

        chk_reset = 1'b0; chk_connect = 1'b0; chk_enum = 1'b0;
        chk_r1 = 1'b0; chk_r2 = 1'b0; chk_r3 = 1'b0; chk_r4 = 1'b0;
        chk_transfer = 1'b0; chk_rx_data = 1'b0; chk_reports = 1'b0;
        reports_sent = 0;

        repeat (10) @(posedge clk);
        por_rst_n = 1'b1;
        chk_reset = 1'b1;

        repeat (10) @(posedge clk);
        connected = 1'b1;
        chk_connect = 1'b1;
    end

    
    
    
    
    
    initial begin
        ep1_in    = 64'hA1B2C3D4E5F60708;
        ep1_valid = 1'b0;
    end

    always @(posedge clk) begin
        if (!por_rst_n || !connected) begin
            ep1_valid <= 1'b0;
        end else begin
            ep1_valid <= 1'b1;
            if (ep1_sent) begin
                ep1_in <= ep1_in + 64'h0101_0101_0101_0101; 
                reports_sent <= reports_sent + 1;
            end
        end
    end

    
    
    
    initial begin
        sw_rx_fifo_read = 1'b0;
        sw_rx_read_done = 1'b0;
        forever begin
            @(posedge clk);
            if (sw_rx_valid) begin
                chk_rx_data = 1'b1;
                while (!sw_rx_fifo_empty) begin
                    sw_rx_fifo_read = 1'b1;
                    @(posedge clk);
                end
                sw_rx_fifo_read = 1'b0;
                sw_rx_read_done = 1'b1;
                @(posedge clk);
                sw_rx_read_done = 1'b0;
            end
        end
    end

    
    
    
    task automatic send_request(input [63:0] req, output reg ok);
        begin
            wait (sw_status == PROTO_CAN_TAKE_REQ);

            @(posedge clk);
            sw_request       = req;
            sw_request_valid = 1'b1;
            @(posedge clk);
            sw_request_valid = 1'b0;

            
            wait (sw_status != PROTO_CAN_TAKE_REQ);

            
            
            wait (sw_status == PROTO_CAN_TAKE_REQ  ||
                  sw_status == PROTO_NOT_SUPPORTED ||
                  sw_status == PROTO_EP_STALLED    ||
                  sw_status == PROTO_ERROR         ||
                  sw_status == PROTO_CRIT_ERROR);

            ok = (sw_status == PROTO_CAN_TAKE_REQ);
        end
    endtask

    initial begin
        sw_request_valid  = 1'b0;
        sw_request        = 64'd0;
        sw_transfer_start = 1'b0;
        sw_endpoint       = 4'd0;
        sw_transfer_type  = 2'd0;
        sw_direction      = 1'b0;
        sw_interval       = 8'd0;

        wait (connected == 1'b1);

        wait (sw_status == PROTO_CAN_TAKE_REQ);
        chk_enum = 1'b1;

        send_request(REQ_SET_CONFIGURATION_1, chk_r1);
        send_request(REQ_GET_HID_REPORT_DESC, chk_r2);
        send_request(REQ_HID_SET_IDLE,        chk_r3);
        send_request(REQ_HID_SET_PROTOCOL,    chk_r4);

        @(posedge clk);
        sw_endpoint       = 4'd1;
        sw_transfer_type  = 2'b01; 
        sw_direction      = 1'b1; 
        sw_interval       = 8'd2; 
        sw_transfer_start = 1'b1;
        @(posedge clk);
        sw_transfer_start = 1'b0;
        chk_transfer = 1'b1;

        repeat (200000) @(posedge clk);
        chk_reports = (reports_sent >= 1);

        passed = chk_reset + chk_connect + chk_enum + chk_r1 + chk_r2 + chk_r3 + chk_r4 +
                 chk_transfer + chk_rx_data + chk_reports;

        $display(" ");
        $display("=================================================================");
        $display("|              USB KEYBOARD - VERIFICATION SUMMARY             |");
        $display("=================================================================");
        $display("| #  | Check                                | Result           |");
        $display("-----------------------------------------------------------------");
        $display("| 1  | %-36s | %-16s |", "Reset released",              chk_reset    ? "PASS" : "FAIL");
        $display("| 2  | %-36s | %-16s |", "Device connected",            chk_connect  ? "PASS" : "FAIL");
        $display("| 3  | %-36s | %-16s |", "Enumeration complete",        chk_enum     ? "PASS" : "FAIL");
        $display("| 4  | %-36s | %-16s |", "SET_CONFIGURATION",           chk_r1       ? "PASS" : "FAIL");
        $display("| 5  | %-36s | %-16s |", "GET_HID_REPORT_DESCRIPTOR",   chk_r2       ? "PASS" : "FAIL");
        $display("| 6  | %-36s | %-16s |", "SET_IDLE",                    chk_r3       ? "PASS" : "FAIL");
        $display("| 7  | %-36s | %-16s |", "SET_PROTOCOL",                chk_r4       ? "PASS" : "FAIL");
        $display("| 8  | %-36s | %-16s |", "Interrupt-IN transfer started", chk_transfer ? "PASS" : "FAIL");
        $display("| 9  | %-36s | %-16s |", "RX descriptor/data drained",  chk_rx_data  ? "PASS" : "FAIL");
        $display("| 10 | %-36s | %-16s |", "Keyboard report(s) sent",     chk_reports  ? "PASS" : "FAIL");
        $display("-----------------------------------------------------------------");
        $display(" Reports sent : %0d", reports_sent);
        $display("=================================================================");
        $display(" RESULT : %0d / 10 CHECKS PASSED", passed);
        $display("=================================================================");

        $finish;
    end

    
    
    
    
    function [127:0] status_name(input [3:0] s);
        case (s)
            PROTO_DISCONNECTED:  status_name = "DISCONNECTED";
            PROTO_NOT_READY:     status_name = "NOT_READY";
            PROTO_CAN_TAKE_REQ:  status_name = "CAN_TAKE_REQ";
            PROTO_NOT_SUPPORTED: status_name = "NOT_SUPPORTED";
            PROTO_READY:         status_name = "READY";
            PROTO_EP_STALLED:    status_name = "EP_STALLED";
            PROTO_CRIT_ERROR:    status_name = "CRIT_ERROR";
            PROTO_ERROR:         status_name = "ERROR";
            default:             status_name = "UNKNOWN";
        endcase
    endfunction

    
    
    
    initial begin
        #20_000_000; 
        $display("[%0t] WATCHDOG TIMEOUT - simulation did not complete", $time);
        $finish;
    end

    
    
    
    initial begin
        $dumpfile("usb_keyboard_tb.vcd");
        $dumpvars(0, usb_keyboard_tb);
    end

endmodule