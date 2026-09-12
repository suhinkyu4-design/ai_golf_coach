from PIL import Image, ImageDraw, ImageFont
import os

width = 1000
height = 750
img = Image.new('RGB', (width, height), color='#191E21')
draw = ImageDraw.Draw(img)

try:
    font_large = ImageFont.truetype("malgun.ttf", 36)
    font_med = ImageFont.truetype("malgun.ttf", 22)
    font_small = ImageFont.truetype("malgun.ttf", 15)
except Exception:
    font_large = font_med = font_small = ImageFont.load_default()

# Header
draw.rectangle([0, 0, width, 60], fill='#000000')
draw.text((20, 10), "TWOVISION NX PLUS", fill='#00BFFF', font=font_large)
draw.text((500, 18), "스윙 밸런스  |  센서 영상 보기  |  나스모 비교 보기", fill='#FFFFFF', font=font_small)

# Top Left Player / Video Placeholder
draw.rectangle([20, 80, 480, 400], fill='#2A3238', outline='#405058', width=2)
draw.text((160, 220), "[ 골프 스윙 영상 ]", fill='#A0B0B8', font=font_med)

# Top Right Swing Balance
draw.rectangle([500, 80, 980, 400], fill='#20282E', outline='#405058', width=2)
draw.text((650, 100), "스윙 밸런스", fill='#FFFFFF', font=font_med)
draw.text((580, 320), "왼발  82", fill='#FFFF00', font=font_large)
draw.text((800, 320), "오른발  18", fill='#FFFFFF', font=font_large)

# Bottom Data Grid
y_start = 420
draw.rectangle([20, y_start, 740, 680], fill='#222A30', outline='#405058', width=2)

metrics = [
    ("볼 스피드", "55.4 m/s", 40, y_start + 20),
    ("헤드 스피드", "36.0 m/s", 180, y_start + 20),
    ("스매쉬 팩터", "1.5 degree", 320, y_start + 20),
    ("캐리", "157.2 m", 460, y_start + 20),
    ("비거리", "166.7 m", 600, y_start + 20),

    ("페이스 각도", "0.0 degree", 40, y_start + 120),
    ("발사각", "15 degree", 180, y_start + 120),
    ("방향각", "0.0 degree", 320, y_start + 120),
    ("백스핀", "4380.8 rpm", 460, y_start + 120),
    ("사이드 스핀", "0.0 rpm", 600, y_start + 120),
]

for label, val, x, y in metrics:
    draw.text((x, y), label, fill='#90A0A8', font=font_small)
    draw.text((x, y + 25), val, fill='#FFFFFF', font=font_med)

# Flight Path
draw.rectangle([760, y_start, 980, 680], fill='#183D48', outline='#00BFFF', width=2)
draw.text((800, y_start + 30), "스트레이트", fill='#00F0FF', font=font_med)

output_path = r"C:\Users\IBCenter\Downloads\twovision_nx_score.jpg"
img.save(output_path, "JPEG", quality=95)
print(f"Saved: {output_path}")
