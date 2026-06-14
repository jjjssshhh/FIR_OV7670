import numpy as np
import matplotlib.pyplot as plt
import matplotlib.gridspec as gridspec
import os

SIM_DIR = "/home/jsh-laptop/workspace_ondevice_2/fpga/self_study/OV7670_6/OV7670_6.sim/sim_1/behav/xsim"
LPF_W, LPF_H = 318, 18   # 20행 입력 → LPF 18행 (320-2)
HPF_W, HPF_H = 316, 16   # LPF 18행 → HPF 16행 (318-2)

IN_W,  IN_H  = 320, 20   # 입력

def load_12bit(path, w, h):
    """12비트 픽셀값을 R4G4B4로 분리해 H×W×3 uint8 반환 (x값 제거)"""
    with open(path) as f:
        lines = [l.strip() for l in f if l.strip() not in ('x', 'X', '')]
    vals = np.array(lines, dtype=np.uint16)
    # 실제 픽셀 수에 맞게 h 재계산
    actual_h = len(vals) // w
    vals = vals[:actual_h * w]
    img = np.zeros((actual_h, w, 3), dtype=np.uint8)
    img[:, :, 0] = ((vals >> 8) & 0xF).reshape(actual_h, w) * 17  # R
    img[:, :, 1] = ((vals >> 4) & 0xF).reshape(actual_h, w) * 17  # G
    img[:, :, 2] = ( vals       & 0xF).reshape(actual_h, w) * 17  # B
    return img

def make_input(w, h):
    """TB와 동일한 4x4 체커보드 생성"""
    img = np.zeros((h, w, 3), dtype=np.uint8)
    for r in range(h):
        for c in range(w):
            if ((r // 4) + (c // 4)) % 2:
                img[r, c] = [255, 255, 255]
    return img

lpf_path = os.path.join(SIM_DIR, "lpf_out.txt")
hpf_path = os.path.join(SIM_DIR, "hpf_out.txt")

img_in  = make_input(IN_W, IN_H)
img_lpf = load_12bit(lpf_path, LPF_W, LPF_H)
img_hpf = load_12bit(hpf_path, HPF_W, HPF_H)

fig = plt.figure(figsize=(14, 6))
gs  = gridspec.GridSpec(1, 3, figure=fig)

axes = [fig.add_subplot(gs[i]) for i in range(3)]
titles  = ["입력 (320×20)\n4×4 체커보드", "LPF 출력 (318×18)\nGaussian Blur", "HPF 출력 (316×16)\nSharpening"]
images  = [img_in, img_lpf, img_hpf]

for ax, title, img in zip(axes, titles, images):
    ax.imshow(img, interpolation='nearest', aspect='auto')
    ax.set_title(title, fontsize=11)
    ax.set_xlabel(f"cols={img.shape[1]}")
    ax.set_ylabel(f"rows={img.shape[0]}")

plt.suptitle("FIR 필터 시뮬레이션 출력 검증", fontsize=13, fontweight='bold')
plt.tight_layout()
out = "/home/jsh-laptop/workspace_ondevice_2/fpga/self_study/OV7670_6/fir_vis_result.png"
plt.savefig(out, dpi=120)
print(f"저장 완료: {out}")
plt.show()

# import os
#
# SIM_DIR = "/home/jsh-laptop/workspace_ondevice_2/fpga/self_study/OV7670_6/OV7670_6.sim/sim_1/behav/xsim"
# lpf_path = os.path.join(SIM_DIR, "lpf_out.txt")
# hpf_path = os.path.join(SIM_DIR, "hpf_out.txt")
#
#
# def analyze_pixel_count(file_path, name):
#     if not os.path.exists(file_path):
#         print(f"[{name}] 파일이 존재하지 않습니다.")
#         return
#
#     with open(file_path) as f:
#         # 'x', 'X' 또는 공백을 제외한 실제 유효 데이터만 필터링
#         lines = [l.strip() for l in f if l.strip() not in ('x', 'X', '')]
#
#     total_pixels = len(lines)
#     print(f"\n=== {name} 파일 데이터 분석 ===")
#     print(f"총 추출된 유효 픽셀 수: {total_pixels} 개")
#
#     # 원본 가로 해상도가 320이므로, 320개 기준으로 나누었을 때 몇 행이 나오는지 확인
#     print(f"가로 320 기준 배치를 할 경우: {total_pixels / 320:.2f} 행 데이터")
#     print(f"가로 318 기준 배치를 할 경우: {total_pixels / 318:.2f} 행 데이터")
#     print(f"가로 316 기준 배치를 할 경우: {total_pixels / 316:.2f} 행 데이터")
#
#     # 텍스트 파일의 앞부분 10개 값 확인용
#     print(f"앞부분 5개 샘플 값: {lines[:5]}")
#
#
# # LPF와 HPF 결과 파일 분석 시작
# analyze_pixel_count(lpf_path, "LPF (블러)")
# analyze_pixel_count(hpf_path, "HPF (샤프닝)")
