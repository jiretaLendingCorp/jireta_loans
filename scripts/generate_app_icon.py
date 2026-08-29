from PIL import Image
import math

src = "assets/images/logo.jpg"
dst = "assets/images/app_icon.png"
dst_foreground = "assets/images/app_icon_foreground.png"  # for adaptive if needed

im = Image.open(src).convert("RGB")
w, h = im.size
print(f"Source: {w}x{h}")

# Estimate background color from corners (average)
corners = [im.getpixel((0,0)), im.getpixel((w-1,0)), im.getpixel((0,h-1)), im.getpixel((w-1,h-1)),
           im.getpixel((5,5)), im.getpixel((w-6,5)), im.getpixel((5,h-6)), im.getpixel((w-6,h-6))]
avg_bg = tuple(int(sum(c)/len(corners)) for c in zip(*corners))
print(f"Avg bg (corners): {avg_bg}")

# Also sample top edge middle to be safe
# Use avg_bg as reference

def color_dist(c1, c2):
    return math.sqrt(sum((a-b)**2 for a,b in zip(c1,c2)))

# Find bounding box of non-background
# Threshold for background
THRESH = 35

# Quick scan: find bbox
# We'll scan pixels to find min/max x,y where pixel is not background
# For performance, sample every pixel but in Python loop will be slow for 2M pixels
# Use numpy if available, otherwise optimize with PIL

try:
    import numpy as np
    arr = np.array(im)  # h x w x 3
    bg_arr = np.array(avg_bg, dtype=np.float32)
    # compute distance
    dist = np.sqrt(np.sum((arr.astype(np.float32) - bg_arr)**2, axis=2))
    mask = dist > THRESH  # True where foreground
    # find bbox
    rows = np.any(mask, axis=1)
    cols = np.any(mask, axis=0)
    rmin, rmax = np.where(rows)[0][[0, -1]]
    cmin, cmax = np.where(cols)[0][[0, -1]]
    print(f"BBox (numpy): left={cmin} top={rmin} right={cmax} bottom={rmax}")
    bbox = (cmin, rmin, cmax+1, rmax+1)
except ImportError:
    print("numpy not available, falling back to PIL scan (slower)")
    # fallback manual scan
    pix = im.load()
    left = w
    right = 0
    top = h
    bottom = 0
    for y in range(h):
        for x in range(w):
            if color_dist(pix[x,y], avg_bg) > THRESH:
                if x < left: left = x
                if x > right: right = x
                if y < top: top = y
                if y > bottom: bottom = y
    bbox = (left, top, right+1, bottom+1)
    print(f"BBox (manual): {bbox}")

# Crop with small margin (1% of size) to avoid cutting star tips due to threshold
bw = bbox[2]-bbox[0]
bh = bbox[3]-bbox[1]
margin = int(min(bw,bh)*0.015)
bbox_expanded = (max(0,bbox[0]-margin), max(0,bbox[1]-margin), min(w,bbox[2]+margin), min(h,bbox[3]+margin))
print(f"Expanded bbox: {bbox_expanded} margin {margin}")

cropped = im.crop(bbox_expanded)
cw, ch = cropped.size
print(f"Cropped size: {cw}x{ch}")

# Replace near-background pixels with pure white (255,255,255) to unify with canvas
# Do this on cropped image
try:
    import numpy as np
    arr2 = np.array(cropped)
    bg_arr = np.array(avg_bg, dtype=np.float32)
    dist2 = np.sqrt(np.sum((arr2.astype(np.float32) - bg_arr)**2, axis=2))
    # where dist <= THRESH, set to white
    arr2[dist2 <= THRESH] = [255,255,255]
    cropped_white = Image.fromarray(arr2)
    print("Background replaced to pure white (numpy)")
except ImportError:
    # fallback
    cropped_white = cropped.copy()
    pix = cropped_white.load()
    for y in range(ch):
        for x in range(cw):
            if color_dist(pix[x,y], avg_bg) <= THRESH:
                pix[x,y] = (255,255,255)
    print("Background replaced to pure white (manual)")

# Now create 1024x1024 canvas white
CANVAS = 1024
PADDING_RATIO = 0.08  # 8% padding each side -> content 84% of canvas
content_size = int(CANVAS * (1 - PADDING_RATIO*2))

# Resize cropped to fit within content_size, preserving aspect ratio
# Use LANCZOS for high quality
ratio = min(content_size / cw, content_size / ch)
new_w = int(cw * ratio)
new_h = int(ch * ratio)
print(f"Resizing to {new_w}x{new_h} ratio {ratio:.4f}")

resized = cropped_white.resize((new_w, new_h), Image.LANCZOS)

# Create canvas
canvas = Image.new("RGB", (CANVAS, CANVAS), (255,255,255))
# Center paste
offset_x = (CANVAS - new_w)//2
offset_y = (CANVAS - new_h)//2
canvas.paste(resized, (offset_x, offset_y))
print(f"Pasted at {offset_x},{offset_y}")

canvas.save(dst, "PNG", optimize=True)
print(f"Saved {dst} {canvas.size}")

# Also create a version with slightly larger content for adaptive foreground (1024 with transparent bg)
# For adaptive, we want foreground with transparent background, centered
# Convert cropped_white to RGBA where white becomes transparent
# Create transparent version

try:
    import numpy as np
    arr3 = np.array(cropped_white.convert("RGBA"))
    # where RGB is white (255,255,255), set alpha 0
    white_mask = (arr3[:,:,0]==255) & (arr3[:,:,1]==255) & (arr3[:,:,2]==255)
    arr3[white_mask, 3] = 0
    cropped_trans = Image.fromarray(arr3, "RGBA")
    # resize
    resized_trans = cropped_trans.resize((new_w, new_h), Image.LANCZOS)
    canvas_trans = Image.new("RGBA", (CANVAS, CANVAS), (0,0,0,0))
    canvas_trans.paste(resized_trans, (offset_x, offset_y), resized_trans)
    canvas_trans.save(dst_foreground, "PNG", optimize=True)
    print(f"Saved transparent foreground {dst_foreground}")
except Exception as e:
    print(f"Failed to create transparent foreground: {e}")

# Also save a 512 version preview
canvas.resize((512,512), Image.LANCZOS).save("assets/images/app_icon_512.png", "PNG")
print("Saved 512 preview")

print("Done")
