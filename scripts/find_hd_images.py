import urllib.request
import urllib.parse
import json
import os

def get_image_url(title):
    url = f"https://commons.wikimedia.org/w/api.php?action=query&titles={urllib.parse.quote(title)}&prop=imageinfo&iiprop=url|size&format=json"
    req = urllib.request.Request(url, headers={'User-Agent': 'NeeroRO/1.0'})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            pages = data.get('query', {}).get('pages', {})
            for pid, pdata in pages.items():
                info = pdata.get('imageinfo', [{}])[0]
                return info.get('url'), info.get('width'), info.get('height')
    except Exception as e:
        print("Error fetching", title, e)
    return None, 0, 0

images = [
    'File:A 1000 liter reverse osmosis plant for commercial use.jpg',
    'File:Reverse Osmosis Skid.jpg',
    'File:Rodi.jpg',
    'File:Haushalts-Wasserfilter.jpg',
    'File:Yen Sun Technology YS-8103RWT 20201101.jpg'
]

for title in images:
    url, w, h = get_image_url(title)
    print(f"{title}: {w}x{h} -> {url}")

