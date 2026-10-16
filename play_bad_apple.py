"""Stream preconverted frames to EDGE Spartan 7. Standard Python + pyserial only."""
import argparse
from pathlib import Path
import struct
import time

HEADER = struct.Struct('<4sHHI')  # magic, fps, reserved, number of frames

def pack_packet(glyphs, elapsed, total):
    if len(glyphs) != 64 or any(b > 31 for b in glyphs):
        raise ValueError('A frame must contain 64 five-bit CGRAM rows')
    elapsed = min(5999, max(0, int(elapsed)))
    total = min(5999, max(0, int(total)))
    label = f' {elapsed//60:02d}:{elapsed%60:02d}/{total//60:02d}:{total%60:02d}'.encode('ascii')
    payload = glyphs + label
    return b'\xff' + payload + bytes([sum(payload) & 255])

def read_movie(path):
    data = Path(path).read_bytes()
    if len(data) < HEADER.size:
        raise ValueError('Truncated movie header')
    magic, fps, _, count = HEADER.unpack_from(data)
    if magic != b'BAL1' or not 1 <= fps <= 30 or count == 0:
        raise ValueError('Invalid BAL1 movie header')
    frames = data[HEADER.size:]
    if len(frames) != count * 64 or any(b > 31 for b in frames):
        raise ValueError('Invalid movie length or CGRAM byte')
    return fps, count, frames

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--port', default='COM5')
    p.add_argument('--file', type=Path, default=Path(__file__).with_name('bad_apple.bal'))
    p.add_argument('--test', action='store_true', help='Send an animated checkerboard for 10 seconds')
    p.add_argument('--invert', action='store_true', help='Invert LCD pixels')
    p.add_argument('--loop', action='store_true')
    p.add_argument('--list-ports', action='store_true')
    args = p.parse_args()
    try:
        import serial
        from serial.tools import list_ports
    except ImportError:
        p.exit(1, 'Install dependency: py -m pip install pyserial\n')
    if args.list_ports:
        for port in list_ports.comports(): print(port.device, port.description)
        return
    if args.test:
        fps, count = 10, 100
        frames = b''.join(bytes(21 if (r + i//5) % 2 else 10 for r in range(64)) for i in range(count))
    else:
        fps, count, frames = read_movie(args.file)
    total = count / fps
    try:
        with serial.Serial(args.port, 115200, timeout=1, write_timeout=2,
                           rtscts=False, dsrdtr=False, xonxoff=False) as uart:
            time.sleep(0.3)  # let LCD initialise after FPGA programming
            print(f'{args.port}: {count} frames, {fps} FPS, {total:.1f} seconds')
            print('Sending without ACK; this confirms PC writes, not LCD reception. Ctrl+C stops.')
            while True:
                start = time.perf_counter()
                i = 0
                last_second = -1
                while i < count:
                    delay = start + i/fps - time.perf_counter()
                    if delay > 0: time.sleep(delay)
                    # Skip stale frames if Windows scheduling stalls: do not build up latency.
                    i = max(i, int((time.perf_counter()-start)*fps))
                    if i >= count: break
                    glyphs = frames[i*64:(i+1)*64]
                    if args.invert: glyphs = bytes(b ^ 31 for b in glyphs)
                    packet = pack_packet(glyphs, i/fps, total)
                    if uart.write(packet) != len(packet): raise IOError('Incomplete UART write')
                    if int(i/fps) != last_second:
                        last_second = int(i/fps)
                        print(f'\rSent {i+1}/{count} frames ({i/fps:.1f}s)', end='', flush=True)
                    i += 1
                uart.flush()
                print('\nPlayback finished. LCD holds the last frame.')
                if not args.loop: break
    except (serial.SerialException, OSError) as exc:
        p.exit(1, f'\nSerial/file error: {exc}\nCheck COM5 and close other serial terminals.\n')

if __name__ == '__main__':
    try: main()
    except KeyboardInterrupt: print('\nStopped.')
