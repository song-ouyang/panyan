from pathlib import Path
import math
import struct
import wave

OUT = Path(__file__).resolve().parents[1] / "miniprogram" / "assets" / "sounds"
OUT.mkdir(parents=True, exist_ok=True)
RATE = 22050

def render(name, notes):
    samples = []
    for frequency, duration in notes:
        count = int(RATE * duration)
        for i in range(count):
            attack = min(1.0, i / (RATE * .012))
            release = min(1.0, (count - i) / (RATE * .05))
            envelope = attack * release * .25
            value = math.sin(2 * math.pi * frequency * i / RATE)
            value += .24 * math.sin(4 * math.pi * frequency * i / RATE)
            samples.append(int(32767 * envelope * value))
        samples.extend([0] * int(RATE * .018))
    with wave.open(str(OUT / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(struct.pack("<h", max(-32768, min(32767, x))) for x in samples))

render("success.wav", [(523.25, .11), (659.25, .11), (783.99, .20)])
render("milestone.wav", [(523.25, .09), (659.25, .09), (783.99, .10), (1046.50, .25)])
