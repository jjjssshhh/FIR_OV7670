`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/28/2026 07:33:06 AM
// Design Name: 
// Module Name: make_sio_c
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module make_sio_c(my_vga_if.make_sioc mi0);
    
    logic [7:0] intc_cnt;
    
     //10us counter 100khz
    always@(posedge mi0.clk , negedge mi0.rstn)begin
        if(!mi0.rstn)begin
            intc_cnt <= 0; 
            mi0.SIO_C <= 1;//new
        end else if(mi0.c_en)begin
            if(intc_cnt >= 8'd119)begin
                intc_cnt <= 0;
                mi0.SIO_C <= ~mi0.SIO_C;
            end else  intc_cnt <= intc_cnt + 1;
            
        end else mi0.SIO_C <= 1;
    end
endmodule

//input SIO_C
module edge_detector_n(my_vga_if.edged mi0);
    
    logic res;
   
    always@(posedge mi0.clk , negedge mi0.rstn)begin
        if(!mi0.rstn)begin
            res <= 0;
        //end else if(mi0.c_en)begin
        end else begin
            res <= mi0.SIO_C;
        end
    end
    
    assign mi0.sio_c_n_edge = (res == 1 && mi0.SIO_C == 0) ? 1:0 ;
    assign mi0.sio_c_p_edge = (res == 0 && mi0.SIO_C == 1) ? 1:0 ;
endmodule


