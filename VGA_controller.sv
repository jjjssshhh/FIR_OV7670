`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/24/2026 09:44:43 AM
// Design Name: 
// Module Name: VGA_controller
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


module VGA_controller_b ( my_vga_if.bot mi0 );

    logic [1:0] finish_sync;
    always@(posedge mi0.clk_vga,negedge mi0.rstn)begin
        if(!mi0.rstn)begin
            finish_sync <= 0;
        end else begin
            finish_sync[0] <= mi0.finish;
            finish_sync[1] <= finish_sync[0];
        end
    end
    
//    /*
//        Image_conv에서 온 room_ff의 CDC문제를 해결
//    */
//    logic [1:0] room_ff;
//    always@(posedge mi0.clk_vga or negedge mi0.rstn)begin
//        if(!mi0.rstn)begin
//            room_ff <= 0;
//        end
//        else begin
//            room_ff[0] <= mi0.room_chk;
//            room_ff[1] <= room_ff[0];
//        end
//    end
    
    /*
        Vsync, Hsync
        Vsync는 2클럭동안 0 이며 주기는 clk_vga 800클럭이다.
        Hsync는 Vsync가 0에서 시작하여 96클럭부터 500클럭까지 
    */
    logic [9:0] Vsync_cnt;
    logic [9:0] Hsync_cnt;
    always@(posedge mi0.clk_vga or negedge mi0.rstn)begin
        if(!mi0.rstn)begin
            Vsync_cnt <= 0;
            Hsync_cnt <= 0;
        end
        else begin
            if(Hsync_cnt == 799)begin
                Hsync_cnt <= 0;
                
                if(Vsync_cnt == 524)begin
                    Vsync_cnt <= 0;
                end else Vsync_cnt <= Vsync_cnt + 1;
                
            end else begin
                Hsync_cnt <= Hsync_cnt + 1;
            end
            
        end
    end
    
    /*
        실제 Hsync,Vsync Assignment
        1    2 변할때 데이터 즉시 대입 필요.
        95 96
    */
    always@(posedge mi0.clk_vga or negedge mi0.rstn)begin
        if(!mi0.rstn)begin
            mi0.Hsync <= 1;//default 1
            mi0.Vsync <= 1;
        end
        else begin
            mi0.Vsync <= (Vsync_cnt < 2) ? 0 : 1; //2
            mi0.Hsync <= (Hsync_cnt < 96) ? 0 : 1; //96
        end
    end
    
    /*
        room_chk(room_ff[1])를 활용하여 일부분만 있기
        addrb
        초기화 할 때 addrb를 어떻게 초기화 할것인가.
        
    */
    //assign offset <= (room_ff[1]==0) ? 72000 : 0;
    always@(posedge mi0.clk_vga or negedge mi0.rstn)begin
        if(!mi0.rstn)begin
            mi0.addrb <= 0;
        end
        else begin
            //room_ff는 Camera_Vs의 p_edge기준으로 결정. VGA의 Vsync타이밍과 달라서 같은영역에 침범한다.
            /*
                VGA의 프레임을 정하는 순간
                룸이 바뀌었는지 확인 && 
            */
            if(Vsync_cnt == 0)begin
                mi0.addrb <= 0;
            end else begin
                if(mi0.sw == 2'b00) begin
                    // raw 320x224
                    if((Vsync_cnt >= 162) && (Vsync_cnt < 386) &&
                            (Hsync_cnt >= 303) && (Hsync_cnt < 623))begin
                        if(mi0.addrb >= 71679) mi0.addrb <= 0;
                        else                   mi0.addrb <= mi0.addrb + 1;
                    end
                end else if(mi0.sw == 2'b01) begin
                    // LPF+HPF 316x220
                    if((Vsync_cnt >= 164) && (Vsync_cnt < 384) &&
                            (Hsync_cnt >= 305) && (Hsync_cnt < 621))begin
                        if(mi0.addrb >= 69519) mi0.addrb <= 0;
                        else                   mi0.addrb <= mi0.addrb + 1;
                    end
                end else begin
                    // LPF only 318x222
                    if((Vsync_cnt >= 163) && (Vsync_cnt < 385) &&
                            (Hsync_cnt >= 304) && (Hsync_cnt < 622))begin
                        if(mi0.addrb >= 70595) mi0.addrb <= 0;
                        else                   mi0.addrb <= mi0.addrb + 1;
                    end
                end
            end
            // BRAM 1클럭+VGA레지스터 1클럭=총 2클럭 레이턴시. addrb 2클럭 앞서므로 RGB는 +2
            if(mi0.sw == 2'b00) begin
                // raw 320x224, RGB 305~624
                if((Hsync_cnt >= 305 && Hsync_cnt < 625) &&
                   (Vsync_cnt >= 162 && Vsync_cnt < 386))begin
                    mi0.vgaRed   <= mi0.doutb[11:8];
                    mi0.vgaGreen <= mi0.doutb[7:4];
                    mi0.vgaBlue  <= mi0.doutb[3:0];
                end else begin
                    mi0.vgaRed   <= 0;
                    mi0.vgaGreen <= 0;
                    mi0.vgaBlue  <= 0;
                end
            end else if(mi0.sw == 2'b01) begin
                // LPF+HPF 316x220, RGB 307~622
                if((Hsync_cnt >= 307 && Hsync_cnt < 623) &&
                   (Vsync_cnt >= 164 && Vsync_cnt < 384))begin
                    mi0.vgaRed   <= mi0.doutb[11:8];
                    mi0.vgaGreen <= mi0.doutb[7:4];
                    mi0.vgaBlue  <= mi0.doutb[3:0];
                end else begin
                    mi0.vgaRed   <= 0;
                    mi0.vgaGreen <= 0;
                    mi0.vgaBlue  <= 0;
                end
            end else begin
                // LPF only 318x222, RGB 306~623
                if((Hsync_cnt >= 306 && Hsync_cnt < 624) &&
                   (Vsync_cnt >= 163 && Vsync_cnt < 385))begin
                    mi0.vgaRed   <= mi0.doutb[11:8];
                    mi0.vgaGreen <= mi0.doutb[7:4];
                    mi0.vgaBlue  <= mi0.doutb[3:0];
                end else begin
                    mi0.vgaRed   <= 0;
                    mi0.vgaGreen <= 0;
                    mi0.vgaBlue  <= 0;
                end
            end

        end
    end
    
endmodule

