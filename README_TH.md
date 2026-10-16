# Bad Apple บน EDGE Spartan 7 / LCD 16×2 / COM5

ชุดนี้ใช้วิดีโอที่คุณส่งมา แปลงเป็นภาพขาวดำ 20×16 พิกเซล 10 FPS
จำนวน 2,191 เฟรม ระยะเวลาประมาณ 219.1 วินาที (3:39)
ภาพแสดงใน 4 ช่องแรกของทั้ง 2 แถว ด้านขวาแสดง Bad Apple! และเวลา
ไม่มีเสียง และไม่ต้องเปิดไฟล์ MP4 ระหว่างเล่น เพราะแปลงเฟรมไว้แล้ว

## ไฟล์ที่ต้องใช้

- bad_apple_top.vhd: วงจรครบในไฟล์เดียว ตั้ง Top เป็น bad_apple_top
- edge_spartan7.xdc: ขา CLOCK, reset, UART RX และ LCD
- bad_apple.bal: ข้อมูลเฟรมที่แปลงแล้วจากวิดีโอของคุณ
- play_bad_apple.py: ส่งเฟรมผ่าน COM5; ต้องติดตั้ง pyserial
- play_COM5.bat: ดับเบิลคลิกเล่นภาพ
- test_COM5.bat: ส่งลายตารางเคลื่อนไหว 10 วินาทีเพื่อทดสอบ
- convert_video.py: แปลง MP4 อื่นเพิ่มเติม (ต้องมี opencv-python)
- tb_bad_apple.vhd, simulate.tcl: ชุดทดสอบ VHDL สำหรับ Vivado
- preview.gif: ตัวอย่างพิกเซลที่แปลงแล้วช่วงวินาทีที่ 35–41 ไม่ใช่ผลจากบอร์ดจริง

## 1. เตรียมบอร์ด

1. ใช้ช่อง USB PROG UART มุมซ้ายบน ต่อคอมพิวเตอร์ (พอร์ต COM5)
2. ใช้ LCD ที่เสียบอยู่เดิม ไม่ต้องเพิ่มสาย UART
3. คู่มือผู้ผลิตกำหนดให้ย้าย jumper J4 จาก E ไป D เพื่อปิด LED ที่ใช้ขาร่วมกับ LCD
   ปิดไฟบอร์ดก่อนเปลี่ยน jumper; ตรวจตำแหน่งตามสกรีน/คู่มือ ไม่สับสนกับชื่อขา FPGA J4
4. เปิดไฟบอร์ด ใช้ clock 50 MHz เดิม

## 2. สร้างโปรเจกต์ใน Vivado

1. Create Project → RTL Project ตั้งชื่อ bad_apple
2. เลือก FPGA part ตัวเดียวกับโปรเจกต์เดิมที่โหลดบนบอร์ดนี้ได้
   ชื่อ EDGE Spartan 7 ไม่ใช่ชื่อ part; หากไม่แน่ใจดู Project Settings ของงานเดิม
3. Add Sources → Add or Create Design Sources → เพิ่ม bad_apple_top.vhd เท่านั้น
4. Add Sources → Add or Create Constraints → เพิ่ม edge_spartan7.xdc
5. คลิกขวา bad_apple_top → Set as Top
6. Run Synthesis → Run Implementation → Generate Bitstream
7. Open Hardware Manager → Open Target → Auto Connect → Program Device เลือก .bit ที่สร้าง
8. รอประมาณ 0.1 วินาที จอควรมี Bad Apple! และ Waiting...

ไฟล์นี้มีการ initialise LCD ในตัว ไม่ต้องต่อโมดูล Hello World หรือ init_done เดิม
อย่าเพิ่ม XDC เดิมซ้ำ เพราะอาจกำหนดขาเดียวกันให้หลายพอร์ต
กดปุ่มที่ผูกกับ J12 เพื่อ reset วงจรนี้ (active high) แล้วปล่อยปุ่ม
การ program แบบ JTAG ต้องทำใหม่หลังปิดไฟ ถ้ายังไม่ได้เขียน configuration ลง Flash

## 3. ติดตั้งและทดสอบส่งภาพ

แตก ZIP ก่อนใช้งาน เปิด PowerShell ในโฟลเดอร์ bad_apple_fpga แล้วรัน:

```powershell
py -m pip install pyserial
py play_bad_apple.py --list-ports
py play_bad_apple.py --port COM5 --test
```

จอควรแสดงตารางสลับลายประมาณ 10 วินาที จากนั้นเล่นวิดีโอ:

```powershell
py play_bad_apple.py --port COM5
```

หรือดับเบิลคลิก play_COM5.bat หลังติดตั้ง pyserial แล้ว
หากไม่มีคำสั่ง py แต่มี python ให้แทนคำว่า py ด้วย python
หยุดด้วย Ctrl+C ภาพสุดท้ายจะค้างอยู่บนจอ

ตัวเลือก:

```powershell
py play_bad_apple.py --port COM5 --loop
py play_bad_apple.py --port COM5 --invert
```

## 4. หลักการและการกำหนดขา

คอมพิวเตอร์ส่งเฟรม → FT2232 บนบอร์ด → UART receiver → ตรวจแพ็กเก็ต →
เก็บเฟรมครบ → คัดลอกเฟรมสำหรับแสดง → เขียน CGRAM และข้อความบน LCD

| สัญญาณ | ขา FPGA |
|---|---|
| clk, 50 MHz | H11 |
| rst, active high | J12 |
| uart_rx, 115200 8N1 | G1 |
| lcd_rs | M5 |
| lcd_e | P5 |
| lcd_data[0..7] | M4, L5, P11, N11, P13, M14, M12, K12 |

R/W ของ LCD ต่อ GND บนบอร์ดอยู่แล้ว จึงไม่มีพอร์ต lcd_rw
F2 เป็นสาย UART TX ตามชื่อสัญญาณใน XDC ผู้ผลิต และไม่ได้ใช้งานในชุดนี้
ใช้ clock 50 MHz เดียวทั้งวงจร มี clock enable ระดับ 1 us สำหรับ LCD

แพ็กเก็ตมี 78 ไบต์:
- FF: จุดเริ่มเฟรม
- 64 ไบต์: CGRAM แต่ละค่า 0..31; ลำดับตัวอักษร 0..7 ตัวละ 8 แถว
- 12 ไบต์: ASCII เช่น ` 00:38/03:39`
- 1 ไบต์: ผลรวม payload 76 ไบต์ modulo 256

ตัวอักษร 0,1,2,3 อยู่แถวบน และ 4,5,6,7 อยู่แถวล่าง
บิต 4 เป็นพิกเซลซ้ายสุด บิต 0 เป็นขวาสุด
ส่ง 780 ไบต์/วินาทีที่ 10 FPS รวม start/stop ของ UART เป็น 7,800 บิต/วินาที
frame buffer ป้องกันข้อมูลแพ็กเก็ตที่ยังรับไม่ครบปะปนกับภาพที่กำลังเขียน
LCD ยังเขียน CGRAM ทีละไบต์ จึงไม่ใช่การสลับภาพพร้อมกันทุกพิกเซล
ไม่มี ACK กลับ: ข้อความ Sent ใน Python บอกการส่งจากคอมพิวเตอร์ ไม่ยืนยันว่าจอได้รับ

## 5. การจำลองและสถานะตรวจสอบ

สิ่งที่ตรวจแล้วในสภาพแวดล้อมสร้างไฟล์:
- แปลงจากวิดีโอจริง 2,191 เฟรม
- ถอดข้อมูลทุกเฟรมย้อนกลับ เปรียบเทียบพิกเซลครบกับภาพขาวดำต้นทาง
- ตรวจขนาดแพ็กเก็ต 78 ไบต์, checksum และการไม่ชน marker ใน payload ครบทุกเฟรม
- ตรวจไวยากรณ์ Python และโครงสร้างไฟล์ BAL1

ยังไม่ได้ compile/simulate/synthesise VHDL ด้วย Vivado/GHDL และยังไม่ได้ทดสอบบนบอร์ดจริง
สภาพแวดล้อมสร้างไฟล์ไม่มี simulator ที่ใช้งานได้ จึงไม่มีไฟล์ .bit แนบมา
ต้องผ่าน Synthesis, Implementation และ timing checks ใน Vivado ของคุณก่อนใช้จริง

วิธีรัน testbench ใน Vivado:
1. เพิ่ม tb_bad_apple.vhd ใน Simulation Sources เท่านั้น ตั้ง file type เป็น VHDL 2008
2. ตั้ง Simulation Top เป็น tb_bad_apple
3. Run Behavioral Simulation แล้วสั่ง `run 300 ms` ใน Tcl Console
4. หากผ่าน จะเห็น PASS: UART reception, checksum rejection, packet resync, CGRAM and E timing

หรือ source simulate.tcl จาก Tcl Console ของโปรเจกต์ที่เพิ่ม bad_apple_top.vhd แล้ว
Testbench ตรวจเฟรมดี, checksum ผิด, เฟรมขาดแล้วเริ่มใหม่ และความกว้างพัลส์ E
เป็นชุดทดสอบที่แนบให้รัน ยังไม่ใช่หลักฐานว่าการจำลองผ่านแล้ว

## 6. แก้ปัญหา

- ไม่เห็น Bad Apple!/Waiting... ก่อนส่ง: ตรวจว่าใช้ top/XDC นี้, jumper LED, LCD และไฟเลี้ยง
- มีชื่อเพลงแต่ภาพไม่มา: ตรวจ COM5, bitstream ใหม่, UART RX G1 และ clock 50 MHz
- COM5 Access denied: ปิด Serial Monitor, PuTTY หรือโปรแกรมที่เปิด COM5 อยู่
- ภาพแรกมืด: ตอนเริ่มวิดีโอมีภาพดำ ลอง --test เพื่อแยกปัญหาการสื่อสาร
- ภาพกลับสี: ใช้ --invert
- ไม่มีเสียง: ชุดนี้ส่งเฉพาะภาพ LCD ยังไม่มีวงจรเล่นเสียงหรือการซิงก์เสียง
- ขึ้น synthesis error: เก็บข้อความ error ตัวแรกและบรรทัดที่แจ้งเพื่อแก้ต่อ

## 7. แปลงวิดีโออื่น (ไม่จำเป็นสำหรับไฟล์ที่เตรียมแล้ว)

```powershell
py -m pip install opencv-python
py convert_video.py "video.mp4" --output another.bal --fps 10
py play_bad_apple.py --port COM5 --file another.bal
```

## แหล่งอ้างอิงขาบอร์ด

https://allaboutfpga.com/edge-spartan-7-fpga-kit-xdc-pin-details/
https://allaboutfpga.com/edge-spartan-7-fpga-development-board-user-manual/
https://allaboutfpga.com/edge-spartan-7-fpga-kit-demonstration-manual/
เทียบขา LCD, reset และ clock กับ lcd_print_hello(1).xdc ที่คุณใช้อยู่ด้วย
