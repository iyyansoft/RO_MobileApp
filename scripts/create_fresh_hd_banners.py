import os
from PIL import Image, ImageFilter, ImageOps
import numpy as np
from scipy.ndimage import binary_dilation, binary_fill_holes

out_dir = 'assets/images/banners_hd'
os.makedirs(out_dir, exist_ok=True)

def pad_and_save(img, path, pad=16):
    w, h = img.size
    padded = Image.new('RGBA', (w + pad * 2, h + pad * 2), (0, 0, 0, 0))
    padded.paste(img, (pad, pad), img)
    padded.save(path)
    print(f"Saved {path}: size={padded.size}")

# -------------------------------------------------------------------
# 1. BANNER 0: Activated Carbon Block Filter
# Using high-res isolated cylinder from catalog sprite (comp_3_83x238)
# It's an authentic black activated carbon block with mesh texture
# -------------------------------------------------------------------
im_carbon = Image.open('temp_components/comp_3_83x238.png').convert('RGBA')
arr_c = np.array(im_carbon, dtype=np.float32)
# Clean outer edges
hc, wc, _ = arr_c.shape
alpha_c = arr_c[:, :, 3]
alpha_c[:3, :] = 0.0
alpha_c[-3:, :] = 0.0
alpha_c[:, :3] = 0.0
alpha_c[:, -3:] = 0.0
arr_c[:, :, 3] = alpha_c
pad_and_save(Image.fromarray(arr_c.astype(np.uint8)), os.path.join(out_dir, 'banner_carbon_filter.png'))

# -------------------------------------------------------------------
# 2. BANNER 1: Commercial RO Plant
# Using crop_commercial.jpg (high resolution 720x640)
# Extract the industrial RO plant frame and skid
# -------------------------------------------------------------------
im_plant = Image.open('assets/images/banners_fresh/crop_commercial.jpg').convert('RGBA')
arr_p = np.array(im_plant, dtype=np.float32)
hp, wp, _ = arr_p.shape

# The plant stands in the middle against light wall
# Background is light grey/beige wall: R > 150, G > 145, B > 140 and low variance
bg_est = arr_p[0:15, 0:15, :3].mean(axis=(0, 1))
dist_p = np.linalg.norm(arr_p[:, :, :3] - bg_est, axis=2)

# Blue tanks: B > R + 25, B > 90
is_blue_tank = (arr_p[:, :, 2] > arr_p[:, :, 0] + 20) & (arr_p[:, :, 2] > 80)
# Dark steel frame & motor: R < 70, G < 70, B < 70
is_frame = (arr_p[:, :, 0] < 80) & (arr_p[:, :, 1] < 80) & (arr_p[:, :, 2] < 80)
# Pipes and gauges:
is_plant = is_blue_tank | is_frame | (dist_p > 45)

# Center bounding region of the plant (exclude far edges of room)
is_plant[:, :80] = False
is_plant[:, wp - 80:] = False
is_plant[:40, :] = False
is_plant[hp - 40:, :] = False

is_plant = binary_fill_holes(binary_dilation(is_plant, iterations=2))

alpha_p = np.zeros((hp, wp), dtype=np.float32)
alpha_p[is_plant] = 255.0
im_ap = Image.fromarray(alpha_p.astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))
arr_p[:, :, 3] = np.array(im_ap)

# Crop tight to non-zero
non_z = np.where(arr_p[:, :, 3] > 30)
if len(non_z[0]) > 0:
    y0, y1 = non_z[0].min(), non_z[0].max()
    x0, x1 = non_z[1].min(), non_z[1].max()
    im_plant_crop = Image.fromarray(arr_p.astype(np.uint8)).crop((x0, y0, x1 + 1, y1 + 1))
else:
    im_plant_crop = Image.fromarray(arr_p.astype(np.uint8))

# Resize to suitable banner proportion (~300px height)
im_plant_crop.thumbnail((400, 320), Image.Resampling.LANCZOS)
pad_and_save(im_plant_crop, os.path.join(out_dir, 'banner_commercial_plant.png'))

# -------------------------------------------------------------------
# 3. BANNER 2: RO Membrane Element
# Using comp_12_155x239 (authentic blue spiral wound RO membrane)
# -------------------------------------------------------------------
im_mem = Image.open('temp_components/comp_12_155x239.png').convert('RGBA')
arr_m = np.array(im_mem, dtype=np.float32)
hm, wm, _ = arr_m.shape
alpha_m = arr_m[:, :, 3]
alpha_m[:3, :] = 0.0
alpha_m[-3:, :] = 0.0
alpha_m[:, :3] = 0.0
alpha_m[:, -3:] = 0.0
arr_m[:, :, 3] = alpha_m
pad_and_save(Image.fromarray(arr_m.astype(np.uint8)), os.path.join(out_dir, 'banner_membrane.png'))

# -------------------------------------------------------------------
# 4. BANNER 3: High Pressure RO Booster Pump
# Using comp_14_242x190 (authentic diaphragm booster pump)
# -------------------------------------------------------------------
im_pump = Image.open('temp_components/comp_14_242x190.png').convert('RGBA')
arr_pu = np.array(im_pump, dtype=np.float32)
hpu, wpu, _ = arr_pu.shape
alpha_pu = arr_pu[:, :, 3]
alpha_pu[:3, :] = 0.0
alpha_pu[-3:, :] = 0.0
alpha_pu[:, :3] = 0.0
alpha_pu[:, -3:] = 0.0
arr_pu[:, :, 3] = alpha_pu
pad_and_save(Image.fromarray(arr_pu.astype(np.uint8)), os.path.join(out_dir, 'banner_booster_pump.png'))

# -------------------------------------------------------------------
# 5. BANNER 4: Smart Cabinet RO Water Purifier
# Using purifier_cutout.png (high resolution 1254x1254 transparent)
# -------------------------------------------------------------------
im_pur = Image.open('assets/images/purifier_cutout.png').convert('RGBA')
arr_pur = np.array(im_pur)
non_z_pur = np.where(arr_pur[:, :, 3] > 20)
y0, y1 = non_z_pur[0].min(), non_z_pur[0].max()
x0, x1 = non_z_pur[1].min(), non_z_pur[1].max()
crop_pur = im_pur.crop((x0, y0, x1 + 1, y1 + 1))
crop_pur.thumbnail((450, 340), Image.Resampling.LANCZOS)
pad_and_save(crop_pur, os.path.join(out_dir, 'banner_purifier.png'))

# -------------------------------------------------------------------
# 6. BANNER 5: Multi-Stage Sediment & Spares
# Combination of sediment filter cartridge (comp_0) and wound filter (comp_1)
# -------------------------------------------------------------------
im_sed = Image.open('temp_components/comp_0_66x243.png').convert('RGBA')
im_wound = Image.open('temp_components/comp_1_69x241.png').convert('RGBA')

# Compose the two cartridges side-by-side with nice overlap
w_sed, h_sed = im_sed.size
w_wnd, h_wnd = im_wound.size
combo_w = w_sed + w_wnd - 25
combo_h = max(h_sed, h_wnd)

combo = Image.new('RGBA', (combo_w, combo_h), (0, 0, 0, 0))
combo.paste(im_wound, (w_sed - 25, 0), im_wound) # wound in back
combo.paste(im_sed, (0, 0), im_sed)            # spun in front
pad_and_save(combo, os.path.join(out_dir, 'banner_sediment_spares.png'))

print("All 6 fresh HD banner assets created successfully!")
