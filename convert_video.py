"""Optional: convert another MP4 to BAL1. pip install opencv-python"""
import argparse
import math
from pathlib import Path
from play_bad_apple import HEADER

def encode_pixels(pixels):
    result = bytearray()
    for char in range(8):
        x0, y0 = (char % 4)*5, (char // 4)*8
        for row in range(8):
            value = 0
            for col in range(5):
                value = (value << 1) | int(pixels[y0+row][x0+col] >= 128)
            result.append(value)
    return bytes(result)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('video',type=Path)
    p.add_argument('--output',type=Path,default=Path('bad_apple.bal'))
    p.add_argument('--fps',type=int,default=10,choices=range(1,21))
    a=p.parse_args()
    import cv2
    cap=cv2.VideoCapture(str(a.video))
    if not cap.isOpened(): raise SystemExit('Cannot open video')
    source_fps=cap.get(cv2.CAP_PROP_FPS)
    if not math.isfinite(source_fps) or source_fps<=0: raise SystemExit('Invalid source FPS')
    frames=bytearray(); source_index=0; output_index=0
    try:
        while True:
            ok,image=cap.read()
            if not ok: break
            while output_index/a.fps <= source_index/source_fps + 1e-8:
                gray=cv2.cvtColor(image,cv2.COLOR_BGR2GRAY)
                small=cv2.resize(gray,(20,16),interpolation=cv2.INTER_AREA)
                frames.extend(encode_pixels(small)); output_index+=1
            source_index+=1
    finally: cap.release()
    if not output_index: raise SystemExit('No frames decoded')
    a.output.write_bytes(HEADER.pack(b'BAL1',a.fps,0,output_index)+frames)
    print(f'Saved {output_index} frames to {a.output}')

if __name__=='__main__': main()
