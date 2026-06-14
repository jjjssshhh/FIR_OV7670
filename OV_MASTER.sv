//`timescale 1ns / 1ps
////////////////////////////////////////////////////////////////////////////////////
//// Company: 
//// Engineer: 
//// 
//// Create Date: 03/29/2026 11:50:23 AM
//// Design Name: 
//// Module Name: OV_MASTER
//// Project Name: 
//// Target Devices: 
//// Tool Versions: 
//// Description: 
//// 
//// Dependencies: 
//// 
//// Revision:
//// Revision 0.01 - File Created
//// Additional Comments:
//// 
////////////////////////////////////////////////////////////////////////////////////


module OV_MASTER(my_vga_if.sccb_master mi0);

    //명령 숫자
    logic [5:0] COMMAND;
    logic [15:0] COMMAND_reg;
    
  always@(*) begin
      case(COMMAND)
          0:  COMMAND_reg = {8'h12, 8'h80}; // 소프트 리셋 (WAIT1에서 100ms 대기)
          1:  COMMAND_reg = {8'h12, 8'h04}; // COM7: QVGA(bit4=1) + RGB(bit2=1) 14
          2:  COMMAND_reg = {8'h11, 8'h80}; // CLKRC: PLL 바이패스, fclk=24MHz 80 
          3:  COMMAND_reg = {8'h40, 8'hD0}; // COM15: RGB565 Full Range
          4: COMMAND_reg = {8'h13, 8'hE7}; // COM8: AGC/AEC/AWB On E7; E5는 색이 탁해짐
          5: COMMAND_reg = {8'h01, 8'h40}; // Blue Gain
          6: COMMAND_reg = {8'h02, 8'h60}; // Red Gain
          7:  COMMAND_reg = {8'h0C, 8'h00}; // COM3: Scaling Disable
          8:  COMMAND_reg = {8'h3E, 8'h19}; // COM14: PCLK /2 → 12MHz 19
          9: COMMAND_reg = {8'h3D, 8'hC0}; // COM13: Gamma + UV 자동보정
          10:  COMMAND_reg = {8'hB0, 8'h84}; // 무의미 한듯?
          11:  COMMAND_reg = {8'h17, 8'h11}; // HREF: 원본 fine-tune (320px/line 기준)
          12:  COMMAND_reg = {8'h18, 8'h61}; // 내부 타이밍 보조
          13:  COMMAND_reg = {8'h32, 8'hA4};

          default: COMMAND_reg = 16'hFFFF;
      endcase
  end

//always@(*) begin
//    case(COMMAND)
//        0: COMMAND_reg = {8'h12, 8'h80}; // Reset
        
//        // 1. VGA 모드 및 RGB565 설정
//        1: COMMAND_reg = {8'h12, 8'h14}; // COM7: VGA 모드 + RGB 선택
//        2: COMMAND_reg = {8'h40, 8'hD0}; // COM15: RGB565 + Full Range
//        3: COMMAND_reg = {8'h8C, 8'h00}; // RGB444 Disable
        
//        // 2. 타이밍 및 클럭 (VGA는 분주 없이 빠르게)
//        4: COMMAND_reg = {8'h11, 8'h80}; // CLKRC: No Division (VGA 속도)80
//        5: COMMAND_reg = {8'h15, 8'h00}; // COM10: PCLK 제어 (기본) 10 PCLK의 반전과 Image_conv의 rgb에 상관관계 있는듯.
//        6: COMMAND_reg = {8'h0C, 8'h00}; // COM3: Scaling Disable (VGA는 스케일링 불필요)
//        7: COMMAND_reg = {8'h3E, 8'h19}; // COM14: PCLK 분주 해제00
//        8: COMMAND_reg = {8'h32, 8'hB6}; // 수평동기화
//        9: COMMAND_reg = {8'h71, 8'h35}; //new
//        // 3. 화질 자동 조절
//        10: COMMAND_reg = {8'h13, 8'hE7}; // COM8: AGC/AEC/AWB On
        
//        default : COMMAND_reg = 16'hFFFF;
//    endcase
//end

/*
    올바른 조합 11:80, 3E:19, 15:00 <= 사선이 발생하지 않음.
    클럭 분주, PCLK분주비가 맞아야 함.
*/
    
    typedef enum logic [4:0]
    {
        IDLE1,
        WRITE1,
        READ1,
        COM1,
        PASS,
        FAIL,
        WAIT1
    } STATE_master;
    
    STATE_master st_master;//ov7670.sv
    
    /*
        자동 제어 or 버튼 제어
    */
    logic loop_en;
    logic [4:0] idx;
    logic [31:0] timer;//239980 10ms
    // pclk?? clk????
    always@(posedge mi0.clk, negedge mi0.rstn)begin //pclk..
        if(!mi0.rstn)begin
            st_master <= IDLE1;
            loop_en <= 1;
            mi0.sccb_write_rstn <= 0;
            mi0.sccb_read_rstn <= 0;
            mi0.sccb_write_en <= 0;
            mi0.sccb_read_en <= 0;
             COMMAND <= 0;
             mi0.sccb_master_done <= 0;
             idx <= 0;
             mi0.led_clk1 <= 0;
             timer <= 0;
        end else begin
            case(st_master)
                IDLE1:begin  
                    //mi0.led <= 4'b0001;
                    mi0.sccb_write_rstn <= 0;
                    mi0.sccb_read_rstn <= 0;
                    if(loop_en)begin//======================================================
                        st_master <= WRITE1;
                    end
                end//idle1
                WRITE1:begin
                    //mi0.led <= 4'b0010;
                    mi0.sccb_write_rstn <= 1;
                    mi0.sccb_write_en   <= 1;//동시에 주면 안된다.
                    mi0.ID_address        <= {(8'h21 << 1) | 1'b0}; //Write : 0
                    mi0.Sub_address     <= COMMAND_reg[15:8];
                    mi0.COM7                <= COMMAND_reg[7:0];
                    if(mi0.sccb_write_done) begin
                        st_master <= READ1;
                        mi0.sccb_write_rstn <= 0;
                    end
                end//write1
                READ1:begin
                    mi0.sccb_read_en    <= 1;
                    mi0.sccb_read_rstn  <= 1;
                    mi0.ID_address         <= {(8'h21 << 1) | 1'b1}; //Read : 1
                    if(mi0.sccb_read_done) begin//0B -> 39?
                        mi0.sccb_read_rstn <= 0;
                        //st_master <= COM1;
                        if( {mi0.Sub_address,mi0.COM7} == {8'h12,8'h80})begin
                            st_master <= WAIT1;
                        end else st_master <= COM1;
                     end
                end//read1
                COM1:begin
                   if(COMMAND == 13)begin
                     loop_en <= 0;
                     mi0.led_clk1 <= 1;
                     mi0.sccb_master_done <= 1;
                  end else COMMAND <= COMMAND + 1;
//                    if(mi0.read_data == mi0.COM7)begin
//                       if(COMMAND == 16)begin//10
//                         loop_en <= 0;
//                         mi0.led_clk1 <= 1;
//                         mi0.sccb_master_done <= 1;
//                      end else COMMAND <= COMMAND + 1;                       
//                    end else begin
//                        loop_en <= 0;
//                    end
                    st_master <= IDLE1;
                end//com1
                WAIT1:begin//5ms
                    if(timer >= 32'd2_400_000)begin
                        timer <= 0;
                        st_master <= IDLE1;
                        COMMAND <= COMMAND + 1;
                    end else timer <= timer + 1;
                end
            endcase
        end
    end
    
endmodule







