from PIL import Image, ImageDraw, ImageFilter
import math

def bleed_edges(img: Image.Image, iterations: int = 3) -> Image.Image:
    # Expand non-transparent colors into neighboring transparent pixels to prevent texture seams
    result = img.copy()
    for _ in range(iterations):
        alpha = result.split()[-1]
        dilated_alpha = alpha.filter(ImageFilter.MaxFilter(3))
        # Where original alpha is 0 but dilated is > 0, blur RGB from neighbors
        rgb = result.convert("RGB").filter(ImageFilter.GaussianBlur(1))
        # Recombine
        rgba = rgb.convert("RGBA")
        rgba.putalpha(alpha)
        # Composite under
        bg = rgb.convert("RGBA")
        bg.putalpha(dilated_alpha)
        result = Image.alpha_composite(bg, result)
    return result

def generate_hand_texture(source_path: str, output_path: str):
    src = Image.open(source_path).convert("RGBA")
    w, h = src.size
    out = Image.new("RGBA", (w, h))
    
    src_pixels = src.load()
    out_pixels = out.load()
    
    for y in range(h):
        for x in range(w):
            r, g, b, a = src_pixels[x, y]
            if a == 0:
                continue
            is_blue_armor = (b > r + 15) and (b > 35)
            is_glove = (x < 190 and y > 340)
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            
            if is_blue_armor:
                # Assault Armor dark metal alloy: base RGB (48, 42, 54)
                base_r, base_g, base_b = 48, 42, 54
                contrast_lum = math.pow(lum, 1.25)
                final_r = int(min(255, base_r * contrast_lum * 2.8))
                final_g = int(min(255, base_g * contrast_lum * 2.7))
                final_b = int(min(255, base_b * contrast_lum * 3.0))
                
                # Polished metal specular highlight
                if lum > 0.65:
                    t = (lum - 0.65) / 0.35
                    final_r = int(final_r * (1 - t) + 185 * t)
                    final_g = int(final_g * (1 - t) + 182 * t)
                    final_b = int(final_b * (1 - t) + 190 * t)
                out_pixels[x, y] = (final_r, final_g, final_b, a)
            elif is_glove:
                # Matte dark tactical glove with subtle carbon grip pattern
                glove_lum = math.pow(lum, 1.35)
                pattern = 4 if ((x // 4 + y // 4) % 2 == 0) else -4
                final_r = int(max(0, min(255, 26 + 45 * glove_lum + pattern)))
                final_g = int(max(0, min(255, 24 + 42 * glove_lum + pattern)))
                final_b = int(max(0, min(255, 28 + 48 * glove_lum + pattern)))
                out_pixels[x, y] = (final_r, final_g, final_b, a)
            else:
                # Undersuit and wrist rubber gasket
                dark_lum = math.pow(lum, 1.3)
                final_r = int(min(255, 22 + 35 * dark_lum))
                final_g = int(min(255, 20 + 33 * dark_lum))
                final_b = int(min(255, 25 + 38 * dark_lum))
                out_pixels[x, y] = (final_r, final_g, final_b, a)
                
    draw = ImageDraw.Draw(out)
    
    # 1. Iconic glowing orange power stripe on outer forearm bracer
    draw.rectangle([252, 175, 266, 315], fill=(215, 95, 25, 255))
    draw.rectangle([256, 180, 262, 310], fill=(255, 175, 55, 255))
    # Silver structural bevel border
    draw.rectangle([250, 173, 252, 317], fill=(175, 172, 180, 255))
    draw.rectangle([266, 173, 268, 317], fill=(175, 172, 180, 255))
    
    # 2. Wrist cuff panel line & mechanical bolts
    draw.line([(195, 345), (410, 345)], fill=(15, 15, 18, 255), width=2)
    draw.line([(195, 347), (410, 347)], fill=(160, 158, 165, 255), width=1)
    for bx in [220, 290, 360]:
        draw.rectangle([bx, 341, bx + 4, 344], fill=(195, 195, 205, 255))

    out = bleed_edges(out, 3)
    out.save(output_path, "PNG")
    print(f"Generated hand texture: {output_path}")


def generate_foot_texture(source_path: str, output_path: str):
    src = Image.open(source_path).convert("RGBA")
    w, h = src.size
    out = Image.new("RGBA", (w, h))
    
    src_pixels = src.load()
    out_pixels = out.load()
    
    for y in range(h):
        for x in range(w):
            r, g, b, a = src_pixels[x, y]
            if a == 0:
                continue
            is_blue_armor = (b > r + 10) and (b > 35)
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            
            if is_blue_armor:
                base_r, base_g, base_b = 48, 42, 54
                contrast_lum = math.pow(lum, 1.2)
                final_r = int(min(255, base_r * contrast_lum * 2.8))
                final_g = int(min(255, base_g * contrast_lum * 2.7))
                final_b = int(min(255, base_b * contrast_lum * 3.0))
                
                if lum > 0.60:
                    t = (lum - 0.60) / 0.40
                    final_r = int(final_r * (1 - t) + 185 * t)
                    final_g = int(final_g * (1 - t) + 182 * t)
                    final_b = int(final_b * (1 - t) + 190 * t)
                out_pixels[x, y] = (final_r, final_g, final_b, a)
            else:
                # Heavy combat boot tread sole & ankle lining
                sole_lum = math.pow(lum, 1.3)
                final_r = int(min(255, 20 + 30 * sole_lum))
                final_g = int(min(255, 18 + 28 * sole_lum))
                final_b = int(min(255, 22 + 32 * sole_lum))
                out_pixels[x, y] = (final_r, final_g, final_b, a)
                
    draw = ImageDraw.Draw(out)
    
    # 1. Ankle side orange chevron / insignia
    draw.polygon([(178, 68), (218, 103), (208, 113), (168, 78)], fill=(215, 95, 25, 255))
    draw.polygon([(182, 73), (212, 100), (206, 106), (176, 79)], fill=(255, 175, 55, 255))
    
    # 2. Boot instep heavy tactical plate
    draw.rectangle([236, 344, 276, 366], fill=(215, 95, 25, 255))
    draw.rectangle([240, 348, 272, 362], fill=(255, 175, 55, 255))
    draw.rectangle([234, 342, 278, 344], fill=(180, 178, 185, 255))
    draw.rectangle([234, 366, 278, 368], fill=(180, 178, 185, 255))
    
    # 3. Boot sole tread line
    draw.line([(50, 480), (460, 480)], fill=(12, 12, 15, 255), width=3)
    draw.line([(50, 483), (460, 483)], fill=(120, 118, 125, 255), width=1)

    out = bleed_edges(out, 3)
    out.save(output_path, "PNG")
    print(f"Generated foot texture: {output_path}")


def generate_body_texture(source_path: str, output_path: str):
    src = Image.open(source_path).convert("RGBA")
    w, h = src.size
    out = Image.new("RGBA", (w, h))
    
    src_pixels = src.load()
    out_pixels = out.load()
    
    for y in range(h):
        for x in range(w):
            r, g, b, a = src_pixels[x, y]
            if a == 0:
                continue
            is_blue_armor = (b > r + 10) and (b > 35)
            lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
            
            if is_blue_armor:
                base_r, base_g, base_b = 48, 42, 54
                contrast_lum = math.pow(lum, 1.25)
                final_r = int(min(255, base_r * contrast_lum * 2.8))
                final_g = int(min(255, base_g * contrast_lum * 2.7))
                final_b = int(min(255, base_b * contrast_lum * 3.0))
                
                if lum > 0.62:
                    t = (lum - 0.62) / 0.38
                    final_r = int(final_r * (1 - t) + 185 * t)
                    final_g = int(final_g * (1 - t) + 182 * t)
                    final_b = int(final_b * (1 - t) + 190 * t)
                out_pixels[x, y] = (final_r, final_g, final_b, a)
            else:
                dark_lum = math.pow(lum, 1.3)
                final_r = int(min(255, 22 + 32 * dark_lum))
                final_g = int(min(255, 20 + 30 * dark_lum))
                final_b = int(min(255, 24 + 34 * dark_lum))
                out_pixels[x, y] = (final_r, final_g, final_b, a)
                
    draw = ImageDraw.Draw(out)
    # Thigh side orange armor stripe (x: [340, 360], y: [130, 240])
    draw.polygon([(340, 135), (358, 145), (345, 230), (328, 220)], fill=(215, 95, 25, 255))
    draw.polygon([(344, 140), (354, 148), (342, 222), (332, 215)], fill=(255, 175, 55, 255))
    draw.line([(340, 133), (359, 143), (346, 232), (327, 221), (340, 133)], fill=(180, 178, 185, 255), width=1)

    out = bleed_edges(out, 3)
    out.save(output_path, "PNG")
    print(f"Generated body texture: {output_path}")


if __name__ == "__main__":
    generate_hand_texture(
        "assets/models/player/animated/armor_textures/hand_f539ff620e61_2x.png",
        "assets/callOfMini/enhanced/Assault Armor/hand_assault.png"
    )
    generate_foot_texture(
        "assets/models/player/animated/armor_textures/foot_3d4c778949e5_2x.png",
        "assets/callOfMini/enhanced/Assault Armor/foot_assault.png"
    )
    generate_body_texture(
        "assets/models/player/animated/armor_textures/body_41c59e886aaa_2x.png",
        "assets/callOfMini/enhanced/Assault Armor/body_assault.png"
    )

