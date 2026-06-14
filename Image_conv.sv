`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/29/2026 12:46:07 PM
// Design Name: 
// Module Name: Image_conv
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

/*
    Hs, Vs 
    image_data 8bit -> 12bit convertion
    xxxx rrrr  , gggg bbbb
*/
module Image_conv(my_vga_if.image_cov m);

    logic rgb;
    logic [4:0] red;
    logic [2:0] green;
    logic edge_reg;
    logic p_edge;
    logic [1:0] sync_pclk;
    // 2단 싱크로
    always@(posedge m.pclk , negedge m.rstn)begin
        if(!m.rstn)begin
            sync_pclk <= 0;
        end else begin
            //sync_pclk[0] <= m.uart_done;//m.sccb_master_done
            sync_pclk[0] <= m.sccb_master_done;//m.sccb_master_done
            sync_pclk[1] <= sync_pclk[0];
        end
    end
    
    logic first;
    logic ov_block;
    logic [7:0] sync_data;
    // 이걸?
    always@(posedge m.pclk , negedge m.rstn)begin
        if(!m.rstn)begin
            rgb <= 0;
            m.in_dt <= 0;
            m.wt_valid <= 0;
            m.addra <= 0;
            m.finish <= 0;
            m.led_clk2 <= 0;
            edge_reg <= 0;
            p_edge <= 0;
            first <= 0;
            ov_block <= 0;
            red <= 0;
            green <= 0;
            sync_data <= 0;
        end else begin
            sync_data <= m.image_data;//HS판단기준과 똑같이 1클럭 밀어버림
            
            edge_reg <= m.Camera_Vs; // 카메라의 Vs는 Active High 평소에 0
            p_edge <= ({edge_reg, m.Camera_Vs} == 2'b01); //rising edge찾기 -1 clk지연
            
            //case(m.sccb_master_done)
            case(sync_pclk[1])
                0:begin
                    //waiting master_done
                end
                1:begin
                    //다음 줄 시작전 초기화
                    if(p_edge)begin
                        m.addra <= 0;
                        ov_block <= 0;
                        if(!first)begin
                            first <= 1;
                            m.finish <= 0;
                        end else m.finish <= 1;//pulse

                        m.wt_valid <= 0;
                        m.led_clk2 <= 1;
                    end else begin
                        m.finish <= 0;
                    end
                    /*
                        PCLKdml pedge와 HS와 data와의 관게가 중요하다.
                        PCLK의 posedge마다 data가 나오고 HS는 계속1이다.
                        HS가 1이 되는 타이밍이 posedge가 아니라 negedge이면 발생하는 문제인데
                        PCLK이 posedge까지 기다리지 않고 실행되기 때문에 처음값은 X로 R-G가 뒤바뀌는 것이다.
                        PCLK 0 1 0 1 0 1 0 1
                        HS    0 0 1 1 1 1 1 1
                        data x d x d x d x d   HS1되기 전  data는 x임
                    */
                    if(m.Camera_Hs)begin//!m.Camera_Vs
                         if(!rgb)begin
                            rgb <= 1;
                            m.wt_valid <= 0;
                            red   <= sync_data[7:4];    // RGB의 핵심 m.image_data사용시 밀리는것임 HS를 보고 한클럭뒤에 하기 때문
                            green <= sync_data[2:0]; // DFF임
                        end else begin
                            rgb <= 0;
                            m.in_dt[11:8] <= red;
                            m.in_dt[7:4]  <= {green, sync_data[7]};
                            m.in_dt[3:0]  <= sync_data[4:1];
                            if(ov_block) begin // 이미지 상하 겹침 방지용 - 무조건 한프레임에 한번만 쓰기 
                                m.wt_valid <= 0;
                            end else begin
                                m.wt_valid <= 1;
                                if(m.addra >= 71679) begin // 320*224-1
                                    m.addra <= 0;
                                    m.wt_valid <= 0;
                                    ov_block <= 1;
                                end else begin
                                    m.addra <= m.addra + 1;
                                end
                            end
                        end//!rgb
                    end else begin  // Camera_Hs = 0
                        rgb <= 0;//0이면 무지개 
                        red <= 0;
                        green <= 0;
                        m.in_dt <= 12'd0;//new
                        m.wt_valid <= 0;
                    end
                end
            endcase
        end
    end
    
    
endmodule





