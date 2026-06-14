`timescale 1ns / 1ps


module line_bram
(
    input pclk,
    input s_valid,
    input [8:0] s_waddr, s_raddr,
    input [11:0] s_wdata,
    input s_wen,
    output logic m_valid,
    output logic [11:0] m_rdata
);
    (*ram_style = "block"*) logic [11:0] mem[0:319];
    initial begin
        for (int i = 0; i < 320; i++) mem[i] = 12'h0;
    end
    always@(posedge pclk)begin
        if(s_wen) mem[s_waddr] <= s_wdata;
        m_valid <= s_valid;
        m_rdata <= mem[s_raddr];
    end

endmodule


// raw data의 간단한 ISP(Image Signal Processing)처리
// Image_conv에서 데이터받아서 라인버퍼로 가우시안 블러처리
// 320*224 -> 318*222
module FIR_LPF(my_vga_if.fir_lpf m);

    wire [11:0] tmp_row0, tmp_row1,tmp_row2;//지연 삭제temp
    logic [11:0] window[0:2][0:2];
    logic [1:0]  wr_row;
    wire  [1:0]  r1, r2;
    logic [8:0]  col;
    logic        st_w;
    logic        row0_valid, row1_valid, row2_valid;
    logic        line_valid, line_ready;
    logic        window_valid, window_ready;
    logic        sum_valid, sum_ready;
    logic        result_valid, result_ready;

    assign r1 = (wr_row == 0) ? 2 : wr_row - 1;
    assign r2 = (wr_row == 2) ? 0 : wr_row + 1;

    assign line_valid    = m.s_lpf_valid;
    assign m.s_lpf_ready = line_ready;

    wire  [8:0]  col_raddr = (col == 319) ? 9'd0 : col + 1;
    // line_bram; LUT사용량 폭발로 라인 bram필수 
    line_bram b0(.pclk(m.pclk), .s_valid(row0_valid), .s_waddr(col), .s_raddr(col_raddr),
                            .s_wdata(m.in_dt), .s_wen(row0_valid), .m_valid(), .m_rdata(tmp_row0));
    line_bram b1(.pclk(m.pclk), .s_valid(row1_valid), .s_waddr(col), .s_raddr(col_raddr),
                            .s_wdata(m.in_dt), .s_wen(row1_valid), .m_valid(), .m_rdata(tmp_row1));
    line_bram b2(.pclk(m.pclk), .s_valid(row2_valid), .s_waddr(col), .s_raddr(col_raddr),
                            .s_wdata(m.in_dt), .s_wen(row2_valid), .m_valid(), .m_rdata(tmp_row2));
    wire  [11:0] bram_r1  = (r1==0) ? tmp_row0 : (r1==1) ? tmp_row1 : tmp_row2;
    wire  [11:0] bram_r2  = (r2==0) ? tmp_row0 : (r2==1) ? tmp_row1 : tmp_row2;
    logic [11:0] d1_cur, d2_cur;
    logic [11:0] d1_r1, d2_r1;
    logic [11:0] d1_r2, d2_r2;
    /*
        bram3개를 사용해서 in_dt는 항상 라인을 저장한다. 현재사용할 라인도 다,다다음에 사용하기떄문에 저장해야 한다.
        실제 window를 만들 때는 현재 쓰고있는 bram을 제외한 2개의 라인bram과 in_dt를 활용해서 window를 구성한다.  
    */
    always@(posedge m.pclk, negedge m.rstn) begin
        if(!m.rstn)begin
            wr_row <= 0; col <= 0; st_w <= 0; window_valid <= 0;
            row0_valid <= 0; row1_valid <= 0; row2_valid <= 0;
        end
        else if(m.finish) begin
            wr_row <= 0; col <= 0; st_w <= 0; window_valid <= 0;
            row0_valid <= 0; row1_valid <= 0; row2_valid <= 0;
        end
        else if(line_valid && line_ready)begin
            row0_valid <= 0; row1_valid <= 0; row2_valid <= 0;
            if(wr_row == 0)begin
                row0_valid <= 1;
            end
            else if(wr_row == 1)begin
                row1_valid <= 1;
            end    
            else begin
                row2_valid <= 1;
            end
            
            // col/row 카운터
            window_valid <= 0;
            if(col == 319) begin
                col <= 0;
                wr_row <= (wr_row == 2) ? 0 : wr_row + 1;
                if(wr_row == 1) st_w <= 1;
            end else begin
                col <= col + 1;
            end
            
            // d1/d2 shift: bram_q=col, d1=col-1, d2=col-2
            d1_cur <= m.in_dt;  d2_cur <= d1_cur;
            d1_r1  <= bram_r1;  d2_r1  <= d1_r1;
            d1_r2  <= bram_r2;  d2_r2  <= d1_r2;

            // window 채우기
            if(st_w && col >= 2) begin
                window_valid <= 1;
                window[0][2] <= bram_r2;  window[0][1] <= d1_r2;    window[0][0] <= d2_r2;
                window[1][2] <= bram_r1;  window[1][1] <= d1_r1;    window[1][0] <= d2_r1;
                window[2][2] <= m.in_dt;    window[2][1] <= d1_cur;  window[2][0] <= d2_cur;
            end

        end
        else begin
            window_valid <= 0;
        end
    end

    // !window_valid : 내가 데이터를 가지고 있지 않아서 덮어쓰기 되지않으니 데이터를 줘도 된다.
    // window_ready : 내가 데이터를 가지고 있어도 3단으로 넘길꺼니까 너는 나에게 데이터를 줘도 된다.
    assign line_ready = !window_valid || window_ready;

    // 가우시안 필터 (center=x1, edge=>>1, corner=>>2)
    // 1 2 1
    // 2 4 2
    // 1 2 1
    logic [3:0] r_conv[0:2][0:2], g_conv[0:2][0:2], b_conv[0:2][0:2];

    always@(posedge m.pclk, negedge m.rstn) begin
        if(!m.rstn) begin
            sum_valid <= 0;
        end
        else if(window_valid && window_ready) begin
            sum_valid <= 1;
            r_conv[0][0] <= window[0][0][11:8] >> 2; r_conv[0][1] <= window[0][1][11:8] >> 1; r_conv[0][2] <= window[0][2][11:8] >> 2;
            r_conv[1][0] <= window[1][0][11:8] >> 1; r_conv[1][1] <= window[1][1][11:8];       r_conv[1][2] <= window[1][2][11:8] >> 1;
            r_conv[2][0] <= window[2][0][11:8] >> 2; r_conv[2][1] <= window[2][1][11:8] >> 1; r_conv[2][2] <= window[2][2][11:8] >> 2;

            g_conv[0][0] <= window[0][0][7:4] >> 2; g_conv[0][1] <= window[0][1][7:4] >> 1; g_conv[0][2] <= window[0][2][7:4] >> 2;
            g_conv[1][0] <= window[1][0][7:4] >> 1; g_conv[1][1] <= window[1][1][7:4];       g_conv[1][2] <= window[1][2][7:4] >> 1;
            g_conv[2][0] <= window[2][0][7:4] >> 2; g_conv[2][1] <= window[2][1][7:4] >> 1; g_conv[2][2] <= window[2][2][7:4] >> 2;

            b_conv[0][0] <= window[0][0][3:0] >> 2; b_conv[0][1] <= window[0][1][3:0] >> 1; b_conv[0][2] <= window[0][2][3:0] >> 2;
            b_conv[1][0] <= window[1][0][3:0] >> 1; b_conv[1][1] <= window[1][1][3:0];       b_conv[1][2] <= window[1][2][3:0] >> 1;
            b_conv[2][0] <= window[2][0][3:0] >> 2; b_conv[2][1] <= window[2][1][3:0] >> 1; b_conv[2][2] <= window[2][2][3:0] >> 2;
        end
        else begin
            sum_valid <= 0;
        end
    end

    assign window_ready = !sum_valid || sum_ready;

    // 행별 합산 후 >>2, 최대 (3+7+3)>>2=3, (7+15+7)>>2=7 -> 4비트 충분
    logic [4:0] r_sum[0:2], g_sum[0:2], b_sum[0:2];

    always@(posedge m.pclk, negedge m.rstn) begin
        if(!m.rstn) begin
            for(int i=0; i<3; i=i+1) begin
                r_sum[i] <= 0; g_sum[i] <= 0; b_sum[i] <= 0;
            end
            result_valid <= 0;
        end
        else if(sum_valid && sum_ready) begin
            result_valid <= 1;
            for(int i=0; i<3; i=i+1) begin
                r_sum[i] <= (r_conv[i][0] + r_conv[i][1] + r_conv[i][2]) >> 2;
                g_sum[i] <= (g_conv[i][0] + g_conv[i][1] + g_conv[i][2]) >> 2;
                b_sum[i] <= (b_conv[i][0] + b_conv[i][1] + b_conv[i][2]) >> 2;
            end
        end
        else begin
            result_valid <= 0;
        end
    end

    assign sum_ready = !result_valid || result_ready;

    // result: 3행 합산, 최대 3+7+3=13 -> 4비트 내
    logic lpf_valid;

    always@(posedge m.pclk, negedge m.rstn) begin
        if(!m.rstn) begin
            m.lpf_addra <= 0;
            lpf_valid <= 0;
        end
        else if(m.finish) begin
            m.lpf_addra <= 0;
            lpf_valid <= 0;
        end
        else if(result_valid && result_ready) begin
            lpf_valid <= 1;
            m.fir_lpf_tdata[11:8] <= r_sum[0] + r_sum[1] + r_sum[2];
            m.fir_lpf_tdata[7:4]  <= g_sum[0] + g_sum[1] + g_sum[2];
            m.fir_lpf_tdata[3:0]  <= b_sum[0] + b_sum[1] + b_sum[2];
            m.lpf_addra <= (m.lpf_addra == 70595) ? 0 : m.lpf_addra + 1;
        end
        else lpf_valid <= 0;
    end

    assign result_ready  = !m.m_lpf_valid || m.m_lpf_ready;
    assign m.m_lpf_valid = lpf_valid;

endmodule



// ======================================================



// FIR_LPF에서 데이터 받아서 샤프닝으로 엣지 강조처리
// 318*222 -> 316*220
module FIR_HPF(my_vga_if.fir_hpf m);

    wire [11:0] tmp_row0, tmp_row1, tmp_row2;
    logic [11:0] window[0:2][0:2];
    logic [1:0]  wr_row;
    wire  [1:0]  r1, r2;
    logic [8:0]  col;
    logic        st_w;
    logic        row0_valid, row1_valid, row2_valid;
    logic        line_valid, line_ready;
    logic        window_valid, window_ready;
    logic        sum_valid, sum_ready;
    logic        result_valid, result_ready;

    assign r1 = (wr_row == 0) ? 2 : wr_row - 1;
    assign r2 = (wr_row == 2) ? 0 : wr_row + 1;

    assign line_valid    = m.s_hpf_valid;
    assign m.s_hpf_ready = line_ready;

    wire  [8:0]  col_raddr = (col == 317) ? 9'd0 : col + 1;
    wire  [11:0] bram_r1  = (r1==0) ? tmp_row0 : (r1==1) ? tmp_row1 : tmp_row2;
    wire  [11:0] bram_r2  = (r2==0) ? tmp_row0 : (r2==1) ? tmp_row1 : tmp_row2;
    logic [11:0] d1_cur, d2_cur;
    logic [11:0] d1_r1, d2_r1;
    logic [11:0] d1_r2, d2_r2;

    line_bram b0(.pclk(m.pclk), .s_valid(row0_valid), .s_waddr(col), .s_raddr(col_raddr),
                 .s_wdata(m.fir_lpf_tdata), .s_wen(row0_valid), .m_valid(), .m_rdata(tmp_row0));
    line_bram b1(.pclk(m.pclk), .s_valid(row1_valid), .s_waddr(col), .s_raddr(col_raddr),
                 .s_wdata(m.fir_lpf_tdata), .s_wen(row1_valid), .m_valid(), .m_rdata(tmp_row1));
    line_bram b2(.pclk(m.pclk), .s_valid(row2_valid), .s_waddr(col), .s_raddr(col_raddr),
                 .s_wdata(m.fir_lpf_tdata), .s_wen(row2_valid), .m_valid(), .m_rdata(tmp_row2));

    // Line Buffer
    always@(posedge m.pclk, negedge m.rstn) begin
        if(!m.rstn) begin
            wr_row <= 0; col <= 0; st_w <= 0; window_valid <= 0;
            row0_valid <= 0; row1_valid <= 0; row2_valid <= 0;
        end
        else if(m.finish) begin
            wr_row <= 0; col <= 0; st_w <= 0; window_valid <= 0;
            row0_valid <= 0; row1_valid <= 0; row2_valid <= 0;
        end
        else if(line_valid && line_ready) begin
            // BRAM 쓰기
            row0_valid <= 0; row1_valid <= 0; row2_valid <= 0;
            if(wr_row == 0)      row0_valid <= 1;
            else if(wr_row == 1) row1_valid <= 1;
            else                 row2_valid <= 1;

            // col/row 카운터 (LPF 출력 318픽셀/라인 기준)
            window_valid <= 0;
            if(col == 317) begin
                col <= 0;
                wr_row <= (wr_row == 2) ? 0 : wr_row + 1;
                if(wr_row == 1) st_w <= 1;
            end else begin
                col <= col + 1;
            end

            // d1/d2 shift
            d1_cur <= m.fir_lpf_tdata;  d2_cur <= d1_cur;
            d1_r1  <= bram_r1;          d2_r1  <= d1_r1;
            d1_r2  <= bram_r2;          d2_r2  <= d1_r2;

            // window 채우기
            if(st_w && col >= 2) begin
                window_valid <= 1;
                window[2][2] <= m.fir_lpf_tdata;  window[2][1] <= d1_cur;  window[2][0] <= d2_cur;
                window[1][2] <= bram_r1;           window[1][1] <= d1_r1;   window[1][0] <= d2_r1;
                window[0][2] <= bram_r2;           window[0][1] <= d1_r2;   window[0][0] <= d2_r2;
            end
        end
        else begin
            window_valid <= 0;
        end
    end

    // !window_valid : 내가 데이터를 가지고 있지 않아서 덮어쓰기 되지않으니 데이터를 줘도 된다.
    // window_ready : 내가 데이터를 가지고 있어도 3단으로 넘길꺼니까 너는 나에게 데이터를 줘도 된다.
    assign line_ready = !window_valid || window_ready;

    // 샤프닝 필터 (라플라시안 기반)
    // 다 더하면 -4 + 5 = 1!!
    //  0  -1   0
    // -1   5  -1
    //  0  -1   0
    // 4비트 채널: 5x15=75 -> signed[7:0] 충분
    logic signed [7:0] r_conv[0:2][0:2], g_conv[0:2][0:2], b_conv[0:2][0:2];

    always@(posedge m.pclk, negedge m.rstn) begin
        if(!m.rstn) begin
            sum_valid <= 0;
        end
        else if(window_valid && window_ready) begin
            sum_valid <= 1;
            // R 채널
            r_conv[0][0] <=  0;
            r_conv[0][1] <= -$signed({1'b0, window[0][1][11:8]});
            r_conv[0][2] <=  0;
            r_conv[1][0] <= -$signed({1'b0, window[1][0][11:8]});
            r_conv[1][1] <=  5 * $signed({1'b0, window[1][1][11:8]});//5
            r_conv[1][2] <= -$signed({1'b0, window[1][2][11:8]});
            r_conv[2][0] <=  0;
            r_conv[2][1] <= -$signed({1'b0, window[2][1][11:8]});
            r_conv[2][2] <=  0;
            // G 채널
            g_conv[0][0] <=  0;
            g_conv[0][1] <= -$signed({1'b0, window[0][1][7:4]});
            g_conv[0][2] <=  0;
            g_conv[1][0] <= -$signed({1'b0, window[1][0][7:4]});
            g_conv[1][1] <=  5 * $signed({1'b0, window[1][1][7:4]});//5
            g_conv[1][2] <= -$signed({1'b0, window[1][2][7:4]});
            g_conv[2][0] <=  0;
            g_conv[2][1] <= -$signed({1'b0, window[2][1][7:4]});
            g_conv[2][2] <=  0;
            // B 채널
            b_conv[0][0] <=  0;
            b_conv[0][1] <= -$signed({1'b0, window[0][1][3:0]});
            b_conv[0][2] <=  0;
            b_conv[1][0] <= -$signed({1'b0, window[1][0][3:0]});
            b_conv[1][1] <=  5 * $signed({1'b0, window[1][1][3:0]});//5
            b_conv[1][2] <= -$signed({1'b0, window[1][2][3:0]});
            b_conv[2][0] <=  0;
            b_conv[2][1] <= -$signed({1'b0, window[2][1][3:0]});
            b_conv[2][2] <=  0;
        end
        else begin
            sum_valid <= 0;
        end
    end

    assign window_ready = !sum_valid || sum_ready;

    // 행별 합산, 최대 -15+75-15=45, 최소 -30 -> signed[8:0] 충분
    logic signed [8:0] r_sum[0:2], g_sum[0:2], b_sum[0:2];

    always@(posedge m.pclk, negedge m.rstn) begin
        if(!m.rstn) begin
            for(int i=0; i<3; i=i+1) begin
                r_sum[i] <= 0; g_sum[i] <= 0; b_sum[i] <= 0;
            end
            result_valid <= 0;
        end
        else if(sum_valid && sum_ready) begin
            result_valid <= 1;
            for(int i=0; i<3; i=i+1) begin
                r_sum[i] <= r_conv[i][0] + r_conv[i][1] + r_conv[i][2];
                g_sum[i] <= g_conv[i][0] + g_conv[i][1] + g_conv[i][2];
                b_sum[i] <= b_conv[i][0] + b_conv[i][1] + b_conv[i][2];
            end
        end
        else begin
            result_valid <= 0;
        end
    end

    assign sum_ready = !result_valid || result_ready;

    // total: 최대 0+45+0=45, 최소 -15-30-15=-60 -> signed[9:0] 충분
    logic hpf_valid;
    logic signed [9:0] r_total, g_total, b_total;
    assign r_total = r_sum[0] + r_sum[1] + r_sum[2];
    assign g_total = g_sum[0] + g_sum[1] + g_sum[2];
    assign b_total = b_sum[0] + b_sum[1] + b_sum[2];

    always@(posedge m.pclk, negedge m.rstn) begin
        if(!m.rstn) begin
            m.hpf_addra <= 0;
            hpf_valid   <= 0;
        end
        else if(m.finish) begin
            m.hpf_addra <= 0;
            hpf_valid   <= 0;
        end
        else if(result_valid && result_ready) begin
            hpf_valid <= 1;
            m.fir_hpf_tdata[11:8] <= (r_total < 0) ? 4'h0 : (r_total > 15) ? 4'hF : r_total[3:0];
            m.fir_hpf_tdata[7:4]  <= (g_total < 0) ? 4'h0 : (g_total > 15) ? 4'hF : g_total[3:0];
            m.fir_hpf_tdata[3:0]  <= (b_total < 0) ? 4'h0 : (b_total > 15) ? 4'hF : b_total[3:0];
            m.hpf_addra <= (m.hpf_addra == 69519) ? 0 : m.hpf_addra + 1;
        end
        else hpf_valid <= 0;
    end

    assign result_ready  = !m.m_hpf_valid || m.m_hpf_ready;
    assign m.m_hpf_valid = hpf_valid;

endmodule
