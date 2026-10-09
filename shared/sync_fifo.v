
module sync_fifo #(
    parameter DEPTH = 1024,
    parameter WIDTH = 8,
    parameter PTR_WIDTH = 10
)(
    input wire clk, rst_n, wr_en, rd_en,
    input wire [WIDTH-1:0] din,
    output wire full, empty,
    output reg [WIDTH-1:0] dout
);

    reg [WIDTH-1:0] fifo_mem [0:DEPTH-1];
    reg [PTR_WIDTH:0] wr_ptr, rd_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            dout   <= {WIDTH{1'b0}};
        end
        else begin
            if (wr_en && !full) begin
                fifo_mem[wr_ptr[PTR_WIDTH-1:0]] <= din;
                wr_ptr <= wr_ptr + 1'b1;
            end
            
            if (rd_en && !empty) begin
                dout   <= fifo_mem[rd_ptr[PTR_WIDTH-1:0]];
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end


    assign empty = (wr_ptr == rd_ptr);
    
    assign full  = (wr_ptr[PTR_WIDTH-1:0] == rd_ptr[PTR_WIDTH-1:0]) && (wr_ptr[PTR_WIDTH] != rd_ptr[PTR_WIDTH]);

endmodule
