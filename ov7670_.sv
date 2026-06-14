`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/27/2026 11:39:55 PM
// Design Name: 
// Module Name: ov7670_
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
    실제 핀
    OV7670 Controller
    SCL, SDA
    VS,HS
    PCLK,MCLK
    [7:0] D x 2bytes
    
    Date sheet
    SCCB_E
    SIO_C
    SIO_D
    SIO0_OE_M_
    SIO0_OE_S_
*/
module OV_write(my_vga_if.sccb_write mi0);

    /*
        QVGA셋팅, RGB444셋팅
        
        명령단계에서 SIO_C는 10us임
        1000배
        
        동작 24Mhz
        
        I2C 7bit MSB First
    */
    //localparam ID_address = 8'h42; //0x42 + Write
    //localparam Sub_address = 8'h12;//COM7 register address
    //localparam COM7 = 8'h14;//QVGA, RGB set
    logic [10:0] timing_cnt;
    logic [4:0] phase1_cnt;//7bit+w/R + Don't care
    logic one_shot;
    logic last_chk;
    
    logic [7:0] clk_10u_cnt ;
    
    typedef enum logic [3:0]
    {
        IDLE,
        START,
        ONE,
        WRITE_ID,
        WRITE_SUB,
        WRITE_DATA,
        LAST1,
        LAST2,
        LAST3
    } STATE_write;
    
    STATE_write st;//24Mhz - 41.67ns
    always@(posedge mi0.clk , negedge mi0.rstn)begin
        if(!mi0.rstn || !mi0.sccb_write_rstn)begin
            st <= IDLE;
            mi0.sio_d_write_en <= 0;
            mi0.sio_dout_write <= {8{1'b1}};
            timing_cnt <= 0;
            phase1_cnt <= 0;
            clk_10u_cnt <= 0;
            one_shot <= 0;
            mi0.sccb_write_done <= 0;
            last_chk <= 0;
            //mi0.c_wt_en <= 0;
        end else if(mi0.sccb_write_en)begin
        
            case(st)
                IDLE:begin
                    mi0.sio_d_write_en <= 0;
                    mi0.c_wt_en <= 0;
                    if(!one_shot) begin
                        one_shot <= 1;
                        st <= START;
                    end
                end
                START:begin
                    // SIO_D는 출력설정
                    mi0.sio_d_write_en <= 1;
                    mi0.sio_dout_write <= 1;//new
                    mi0.c_wt_en <= 0;
                    if(timing_cnt >= 29) begin//1.25us유지
                        mi0.sio_dout_write <= 0;//new
                        timing_cnt <= 0;
                        st <= ONE;
                    end
                    else timing_cnt <= timing_cnt + 1;
                end
                ONE:begin
                    // SIO_C작동시작
                    mi0.c_wt_en <= 1;
                    st <= WRITE_ID;
                end
                WRITE_ID:begin
                    //SIO_C =1 마다 비트 하나씩 7번 전송 마지막은 W(0)
                    // 0x21 << 1 = 0x42 = 0b0100_001X(0)
                    // SIOC_C = 0일때 D에 대입
                    // 클럭의 값을 조건으로 하지말고 엣지 검출
                    if(mi0.sio_c_n_edge)begin
                        if(phase1_cnt == 8)begin//9bit
                            mi0.sio_d_write_en <= 0;
                            phase1_cnt <= 0;
                            st <= WRITE_SUB;
                        end
                        else if(phase1_cnt <= 7) begin
                            mi0.sio_dout_write <= mi0.ID_address[7-phase1_cnt];//MSB부터 (I2C)
                            phase1_cnt <= phase1_cnt + 1;
                        end 
                    end
                end
                WRITE_SUB:begin
                    //Sub_address접근.
                     if(mi0.sio_c_n_edge)begin
                        if(phase1_cnt == 8)begin
                            mi0.sio_d_write_en <= 0;
                            phase1_cnt <= 0;
                            st <= WRITE_DATA;
                        end
                        else if(phase1_cnt <= 7) begin
                            mi0.sio_d_write_en <= 1;//new
                            mi0.sio_dout_write <= mi0.Sub_address[7-phase1_cnt];
                            phase1_cnt <= phase1_cnt + 1;
                        end
                    end
                end
                WRITE_DATA:begin
                    //레지스터 값 대입.
                     if(mi0.sio_c_n_edge)begin
                        if(phase1_cnt == 8)begin
                            mi0.sio_d_write_en <= 0;//SIO_D = x
                            phase1_cnt <= 9;
                            st <= LAST1;
                        end
                        else if(phase1_cnt <= 7) begin
                            mi0.sio_d_write_en <= 1;//new
                            mi0.sio_dout_write <= mi0.COM7[7-phase1_cnt];
                            phase1_cnt <= phase1_cnt + 1;
                        end
                    end
                end
                LAST1:begin
                    if(mi0.sio_c_n_edge)begin
                        mi0.sio_d_write_en <= 1;
                        mi0.sio_dout_write <= 0;
                        last_chk <= 1;
                    end
                    if(last_chk)begin
                        if(timing_cnt >= 29)begin
                            mi0.c_wt_en <= 0;//new
                            last_chk <= 0;
                            timing_cnt <= 0;
                            st <= LAST2;
                        end else timing_cnt <= timing_cnt + 1;
                    end 
                end
                LAST2:begin//Don't care bit Tmack = 1.25us
                    if(mi0.sio_c_p_edge)begin
                        mi0.sio_d_write_en <= 1;
                        mi0.sio_dout_write <= 1;
                        last_chk <= 1;
                    end
                    if(last_chk)begin
                        if(timing_cnt >= 29)begin
                            last_chk <= 0;
                            timing_cnt <= 0;
                            mi0.sio_d_write_en <= 0;//new
                            mi0.sccb_write_done <= 1;
                            st <= IDLE;
                        end else timing_cnt <= timing_cnt + 1;
                    end 
                end
//                LAST3:begin
//                    if(timing_cnt >= 29)begin
//                        timing_cnt <= 0;
//                        mi0.sio_d_write_en <= 0;
//                        mi0.sccb_write_done <= 1;
//                        st <= IDLE;
//                    end else timing_cnt <= timing_cnt + 1;
//                end
            endcase
        end
    end
    
    
endmodule

