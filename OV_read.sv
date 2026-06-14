`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/28/2026 08:37:28 AM
// Design Name: 
// Module Name: OV_read
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


module OV_read(my_vga_if.sccb_read mi0);


    logic [10:0] timing_cnt;
    logic [4:0] phase1_cnt;//7bit+w/R + Don't care
    logic one_shot;
    
    logic [7:0] clk_10u_cnt ;
    logic sio_d_read; // 3-state buffer reader
    assign sio_d_read = mi0.SIO_D_in;
    logic last_chk;
    
    typedef enum logic [3:0]
    {
        IDLE,
        START,
        ONE,
        WRITE_ID,
        READ_DATA,
        LAST1,
        LAST2,
        LAST3
    } STATE_read;

    STATE_read st;//24Mhz - 41.67ns
    always@(posedge mi0.clk , negedge mi0.rstn)begin
        if(!mi0.rstn | !mi0.sccb_read_rstn)begin
            st <= IDLE;
            mi0.sio_d_read_en <= 0;
            mi0.sio_dout_read <= {8{1'b1}};
            timing_cnt <= 0;
            phase1_cnt <= 0;
            clk_10u_cnt <= 0;
            one_shot <= 0;
            mi0.sccb_read_done <= 0;
            last_chk <= 0;
            //mi0.c_rd_en <= 0;
        end else if(mi0.sccb_read_en)begin
        
            case(st)
                IDLE:begin
                    mi0.sio_d_read_en <= 0;
                    mi0.c_rd_en <= 0;
                    if(!one_shot) begin
                        one_shot <= 1;
                        st <= START;
                    end
                end
                START:begin
                    // SIO_D는 출력설정
                    mi0.sio_d_read_en <= 1;
                    mi0.sio_dout_read <= 1;//new
                    mi0.c_rd_en <= 0;
                    if(timing_cnt >= 29) begin//1.25us유지
                        mi0.sio_dout_read <= 0;//new
                        timing_cnt <= 0;
                        st <= ONE;
                    end
                    else timing_cnt <= timing_cnt + 1;
                end
                ONE:begin
                    // SIO_C작동시작
                    mi0.c_rd_en <= 1;
                    st <= WRITE_ID;
                end
                WRITE_ID:begin
                    //SIO_C =1 마다 비트 하나씩 7번 전송 마지막은 W(0)
                    // 0x21 << 1 = 0x42 = 0b0100_001X(0)
                    // SIOC_C = 0일때 D에 대입
                    // 클럭의 값을 조건으로 하지말고 엣지 검출
                    if(mi0.sio_c_n_edge)begin
                        if(phase1_cnt == 9)begin
                            phase1_cnt <= 0;
                            st <= READ_DATA;
                        end
                        else if(phase1_cnt == 8)begin
                            mi0.sio_d_read_en <= 0;//주도권 Out
                            phase1_cnt <= 9;
                            //st <= READ_DATA;
                        end
                        else if(phase1_cnt <= 7) begin
                            mi0.sio_dout_read <= mi0.ID_address[7-phase1_cnt];
                            phase1_cnt <= phase1_cnt + 1;
                        end 
                    end
                end              
                READ_DATA:begin
                    /*
                        Read 는 SIO_C = 1에서 읽어야 하고
                        SIO_D = 1은 SIO_C = 0에서 전송해야 한다.
                    */
                    if(mi0.sio_c_p_edge)begin
                        if(phase1_cnt <= 7) begin
                            mi0.read_data[7-phase1_cnt] <= sio_d_read;
                            phase1_cnt <= phase1_cnt + 1;
                        end 
                    end
                    else if(mi0.sio_c_n_edge)begin
                        if(phase1_cnt == 8)begin
                            mi0.sio_d_read_en <= 1;
                            mi0.sio_dout_read <= 1;//SIOD = 1
                            phase1_cnt <= 0;
                            st <= LAST1;
                        end
                    end
                end  
                LAST1:begin
                    if(mi0.sio_c_n_edge)begin
                        mi0.sio_d_read_en <= 1;
                        mi0.sio_dout_read <= 0;
                        last_chk <= 1;
                    end
                    if(last_chk)begin
                        if(timing_cnt >= 29)begin
                            mi0.c_rd_en <= 0;//new
                            last_chk <= 0;
                            timing_cnt <= 0;
                            st <= LAST2;
                        end else timing_cnt <= timing_cnt + 1;
                    end 
                end
                LAST2:begin//Don't care bit Tmack = 1.25us
                    if(mi0.sio_c_p_edge)begin
                        mi0.sio_d_read_en <= 1;
                        mi0.sio_dout_read <= 1;
                        last_chk <= 1;
                    end
                    if(last_chk)begin
                        if(timing_cnt >= 29)begin
                            last_chk <= 0;
                            timing_cnt <= 0;
                            mi0.sio_d_read_en <= 0;//new
                            mi0.sccb_read_done <= 1;
                            st <= IDLE;
                        end else timing_cnt <= timing_cnt + 1;
                    end 
                end
            endcase
        end
    end
    
endmodule

