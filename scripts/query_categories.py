import urllib.request
import urllib.parse
import json

def get_category_files(cat):
    url = f"https://commons.wikimedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:{urllib.parse.quote(cat)}&cmtype=file&cmlimit=15&format=json"
    req = urllib.request.Request(url, headers={'User-Agent': 'NeeroPlusEcommerce/2.0 (contact@neeroplus.in)'})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            items = data.get('query', {}).get('categorymembers', [])
            print(f"Category '{cat}': {len(items)} files")
            for item in items[:6]:
                print("  ", item['title'])
    except Exception as e:
        print("Error:", e)

get_category_files("Water filters")
get_category_files("Reverse osmosis")
get_category_files("Water purification")
get_category_files("Pumps")

