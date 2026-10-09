
module async_fifo #(
    parameter DEPTH = 16,
    parameter WIDTH = 8,
    parameter PTR_WIDTH = 4 
)(
    input wire wr_clk, rd_clk, rst_n, wr_en, rd_en,
    input wire [WIDTH-1:0] din,
    output wire full, empty,
    output reg [WIDTH-1:0] dout
);

    reg [WIDTH-1:0] fifo_mem [0:DEPTH-1];
    reg [PTR_WIDTH:0] wr_ptr, rd_ptr, wr_ptr_gray, rd_ptr_gray, wr_sync1, rd_sync1, wr_sync2, rd_sync2;


    always @(posedge wr_clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            wr_ptr_gray <= 0;
            rd_sync1 <= 0;
            rd_sync2 <= 0;
            
        end
        else begin
            rd_sync1 <= rd_ptr_gray;
            rd_sync2 <= rd_sync1;
            if (wr_en && !full) begin
                fifo_mem[wr_ptr[PTR_WIDTH-1:0]] <= din;
                wr_ptr <= wr_ptr + 1'b1;
                wr_ptr_gray <= ({wr_ptr + 1'b1} >> 1) ^ {wr_ptr + 1'b1};
            
            end
        end
    end

    always @(posedge rd_clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr <= 0;
            rd_ptr_gray <= 0;
            wr_sync1 <= 0;
            wr_sync2 <= 0;
            dout   <= {WIDTH{1'b0}};
        end
        else begin
            wr_sync1 <= wr_ptr_gray;
            wr_sync2 <= wr_sync1; 
            if (rd_en && !empty) begin
                dout   <= fifo_mem[rd_ptr[PTR_WIDTH-1:0]];
                rd_ptr <= rd_ptr + 1'b1;
                rd_ptr_gray <= ({rd_ptr + 1'b1} >> 1) ^ {rd_ptr + 1'b1};
            end
        end
    end
    
    assign empty = (wr_sync2 == rd_ptr_gray);
    
    assign full = (wr_ptr_gray == {~rd_sync2[PTR_WIDTH:PTR_WIDTH-1], rd_sync2[PTR_WIDTH-2:0]});
endmodule
