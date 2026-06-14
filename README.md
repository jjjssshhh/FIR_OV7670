# OV7670_FIR

OV7670 카메라 영상을 실시간으로 VGA 출력하면서 스위치로 FIR 필터를 전환하는 FPGA 프로젝트.  
가우시안 블러(LPF)와 샤프닝(HPF)을 AXI-Stream 파이프라인으로 구현하였다.

## 필터 모드

| SW3 | SW2 | 모드 | 출력 해상도 |
|-----|-----|------|------------|
| 0 | 0 | Raw | 320×224 |
| 0 | 1 | LPF + HPF | 316×220 |
| 1 | 0 | LPF only | 318×222 |

## 구성

| 파일 | 설명 |
|---|---|
| `VGA.sv` | 시스템 인터페이스 + 최상위 모듈, BRAM 3-way 입력 mux |
| `VGA_controller.sv` | 640×480@60Hz VGA 타이밍, sw 모드별 출력 윈도우 제어 |
| `Image_conv.sv` | PCLK 동기 픽셀 캡처, RGB565 → RGB444 변환, 더블버퍼 관리 |
| `FIR_LHPF.sv` | 가우시안 LPF(3×3) + 라플라시안 HPF(3×3), AXI-Stream 핸드쉐이크 파이프라인 |
| `OV_MASTER.sv` | SCCB 초기화 시퀀서 |
| `OV_read.sv` | SCCB 읽기 |
| `ov7670_.sv` | SCCB 쓰기 |
| `make_sio_c.sv` | SIO_C 클럭 생성 |
| `Basys-3-Master.xdc` | 핀 제약 |
| `fir_vis.py` | TB 시뮬레이션 출력(12bit 픽셀)을 읽어 LPF/HPF 결과를 시각화하는 Python 스크립트 |
| `fir_vis_result.png` | fir_vis.py 실행 결과 이미지 |

## 주요 설계 포인트

- **AXI-Stream 파이프라인**: valid/ready 핸드쉐이크로 LPF → HPF 백프레셔 처리. sw=LPF only 시 s_hpf_valid=0, m_lpf_ready=1로 HPF 우회
- **BRAM 라인버퍼**: 초기 LUT 배열 방식(LUT 172% 초과)을 `(* ram_style = "block" *)` 어트리뷰트로 BRAM 강제 전환하여 해결
- **1D 선형 주소 방식**: hpf_addra / lpf_addra를 픽셀 출력마다 단순 증가, 상한에서 0 리셋. VGA_controller의 addrb 윈도우와 1:1 대응
- **모드별 윈도우 오프셋**: 필터 경계 제거로 출력 크기가 모드마다 다름. VGA_controller에서 sw별 Vsync/Hsync 범위와 addrb 상한을 각각 지정
- **BRAM 2클럭 레이턴시**: addrb 인가 시점보다 RGB 출력 윈도우를 2클럭 늦게 열어 타이밍 보정
- **GRAYSCALE이 아닌 RGB : RGB환경에서의 FIR처리결과를 확인가능
## 개발 환경

- **Tool**: Vivado 2024.2
- **Target Board**: Basys3 (Artix-7 xc7a35t)
