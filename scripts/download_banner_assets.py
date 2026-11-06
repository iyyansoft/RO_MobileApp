import urllib.request
import urllib.parse
import re
import json
import os
import ssl
from PIL import Image, ImageFilter
import numpy as np

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

HEADERS = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8'
}

os.makedirs('assets/images/banners_hd', exist_ok=True)

def download_image(url, target_path):
    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, context=ctx, timeout=15) as resp:
            content = resp.read()
            with open(target_path, 'wb') as f:
                f.write(content)
            # Verify image can open
            im = Image.open(target_path)
            print(f"Downloaded {target_path}: {im.size} {im.format}")
            return True
    except Exception as e:
        print(f"Failed to download {url}: {e}")
        return False

# Wikimedia direct full-res images:
# 1. Commercial RO Plant:
url_commercial = "https://upload.wikimedia.org/wikipedia/commons/4/46/A_1000_liter_reverse_osmosis_plant_for_commercial_use.jpg"
download_image(url_commercial, "assets/images/banners_hd/raw_commercial_plant.jpg")

# 2. Modern RO Water Purifier:
url_purifier = "https://upload.wikimedia.org/wikipedia/commons/b/b2/Yen_Sun_Technology_YS-8103RWT_20201101.jpg"
download_image(url_purifier, "assets/images/banners_hd/raw_purifier.jpg")

# 3. Under-sink RO multi-stage system (spares / housings / tank):
url_system = "https://upload.wikimedia.org/wikipedia/commons/6/6f/Rodi.jpg"
download_image(url_system, "assets/images/banners_hd/raw_ro_system.jpg")

print("Base HD downloads completed!")

