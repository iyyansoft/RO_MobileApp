import urllib.request
import urllib.parse
import json

def search_github(q):
    url = f"https://api.github.com/search/code?q={urllib.parse.quote(q)}+path:assets+extension:png"
    req = urllib.request.Request(url, headers={'User-Agent': 'NeeroPlus/1.0'})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            print(f"GitHub search '{q}': {data.get('total_count', 0)} items")
            for item in data.get('items', [])[:4]:
                raw_url = item['html_url'].replace('github.com', 'raw.githubusercontent.com').replace('/blob/', '/')
                print("  ", item['name'], raw_url)
    except Exception as e:
        print("GitHub error:", e)

search_github("water purifier")
search_github("ro membrane")
search_github("carbon filter")

