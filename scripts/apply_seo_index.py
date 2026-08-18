import json
import re

with open('scripts/generated_seo_items.json', 'r', encoding='utf-8') as f:
    items_schema = json.load(f)

with open('scripts/generated_seo_html.html', 'r', encoding='utf-8') as f:
    seo_html = f.read()

index_path = 'gec_compass_app/web/index.html'
with open(index_path, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update Title and Primary SEO tags
content = re.sub(
    r'<title>.*?</title>',
    '<title>GEC Maps | GECT Compass | GECT Maps & GEC Compass – Official Campus Navigation</title>',
    content
)

content = re.sub(
    r'<meta name="title" content=".*?">',
    '<meta name="title" content="GEC Maps | GECT Compass | GECT Maps & GEC Compass – GEC Thrissur Campus Navigation">',
    content
)

content = re.sub(
    r'<meta name="description"\s+content=".*?">',
    '<meta name="description"\n    content="GEC Maps & GECT Compass (GECT Maps / GEC Compass) – Official interactive campus navigation and indoor room finder for Government Engineering College Thrissur (GEC Thrissur). Locate all 70+ departments, labs, classrooms, hostels, canteens, and gates with real-time GPS & offline walking directions.">',
    content,
    flags=re.DOTALL
)

content = re.sub(
    r'<meta name="keywords"\s+content=".*?">',
    '<meta name="keywords"\n    content="gec maps, gect compass, gect maps, gec compass, gecmaps, gectcompass, gec map, gect map, gec maps thrissur, gect maps thrissur, gec compass thrissur, gect compass thrissur, gectcr maps, gectcr compass, gec thrissur maps, gect thrissur compass, government engineering college thrissur map, gec campus map, gec indoor navigation, gect navigation app, gec thrissur location, gec route finder, gec campus navigation, gec compass app, gect compass apk, gec tcr maps, gectcr navigation, gec thrissur navigation, engineering college thrissur compass">',
    content,
    flags=re.DOTALL
)

# OpenGraph & Twitter
content = re.sub(
    r'<meta property="og:title" content=".*?">',
    '<meta property="og:title" content="GEC Maps | GECT Compass | GECT Maps & GEC Compass">',
    content
)

content = re.sub(
    r'<meta property="og:description"\s+content=".*?">',
    '<meta property="og:description"\n    content="GEC Maps & GECT Compass (GECT Maps / GEC Compass) – Interactive campus navigation for Government Engineering College Thrissur. Locate all 70+ departments, labs, classrooms, hostels, and amenities with real-time GPS & offline routing.">',
    content,
    flags=re.DOTALL
)

content = re.sub(
    r'<meta name="twitter:title" content=".*?">',
    '<meta name="twitter:title" content="GEC Maps | GECT Compass | GECT Maps & GEC Compass">',
    content
)

content = re.sub(
    r'<meta name="twitter:description"\s+content=".*?">',
    '<meta name="twitter:description"\n    content="GEC Maps & GECT Compass (GECT Maps / GEC Compass) – Interactive campus navigation for Government Engineering College Thrissur. Locate all 70+ departments, labs, classrooms, hostels, and amenities with real-time GPS & offline routing.">',
    content,
    flags=re.DOTALL
)

# 2. Update JSON-LD structured data to include ItemList
# Locate JSON-LD block
json_ld_match = re.search(r'<script type="application/ld\+json">\s*(\{.*?\})\s*</script>', content, re.DOTALL)
if json_ld_match:
    json_ld_data = json.loads(json_ld_match.group(1))
    # Replace or append ItemList
    new_graph = [item for item in json_ld_data.get('@graph', []) if item.get('@type') != 'ItemList']
    new_graph.append(items_schema)
    json_ld_data['@graph'] = new_graph
    
    formatted_json_ld = json.dumps(json_ld_data, indent=2)
    replacement = f'<script type="application/ld+json">\n{formatted_json_ld}\n  </script>'
    content = content[:json_ld_match.start()] + replacement + content[json_ld_match.end():]

# 3. Update Crawlable Semantic HTML block
seo_content_match = re.search(r'<div id="seo-content" class="seo-crawlable-content">.*?</div>', content, re.DOTALL)
if seo_content_match:
    new_seo_block = f'''<div id="seo-content" class="seo-crawlable-content">
    <header>
      <h1>GEC Maps | GECT Compass | GECT Maps &amp; GEC Compass – GEC Thrissur Campus Navigation</h1>
      <p>Welcome to <strong>GEC Maps</strong> &amp; <strong>GECT Compass</strong> (also widely searched as <strong>GECT Maps</strong>, <strong>GEC Compass</strong>, or <strong>gect compasss</strong>) — the official digital campus navigation map, indoor room finder, and offline walking guide for <strong>Government Engineering College (GEC) Thrissur</strong>, Kerala, India.</p>
    </header>
    <main>
      <section>
        <h2>About GEC Maps &amp; GECT Compass</h2>
        <p>GEC Maps and GECT Compass deliver real-time interactive indoor and outdoor spatial guidance across the 120-acre lush campus of Government Engineering College Thrissur. Designed by Gectians, GEC Maps lets students, faculty, alumni, parents, and campus visitors navigate to any department, research laboratory, classroom, seminar hall, hostel, mess, canteen, ATM, sports ground, or entrance gate with live compass orientation and shortest-path walking routes.</p>
      </section>

{seo_html}
      <section>
        <h2>Frequently Asked Questions (FAQ) - GEC Maps &amp; GECT Compass</h2>
        <dl>
          <dt><strong>Q: What is GEC Maps / GECT Compass?</strong></dt>
          <dd>A: GEC Maps (also known as GECT Compass, GECT Maps, GEC Compass, or gect compasss) is the official interactive navigation application for Government Engineering College Thrissur (GEC TCR). It provides GPS-guided blue-dot location tracking, compass bearing heading, and turn-by-turn walking routes to all campus places.</dd>

          <dt><strong>Q: How can I use GEC Maps / GECT Compass online?</strong></dt>
          <dd>A: Open <a href="https://gecmaps.vercel.app/">https://gecmaps.vercel.app/</a> in any mobile or desktop web browser to start exploring the campus map immediately with zero installation required.</dd>

          <dt><strong>Q: Where can I download the official GECT Compass Android APK?</strong></dt>
          <dd>A: You can download the latest compressed Android APK directly from <a href="https://gecmaps.vercel.app/app-release.apk">https://gecmaps.vercel.app/app-release.apk</a>.</dd>

          <dt><strong>Q: Does GEC Maps work offline on campus?</strong></dt>
          <dd>A: Yes, GEC Maps caches the full road graph, topological walkways, and building database offline on your device, so you can search and route without active cellular internet.</dd>
        </dl>
      </section>

      <section>
        <h2>Quick Links &amp; Resources</h2>
        <ul>
          <li><a href="https://gecmaps.vercel.app/">GEC Maps &amp; GECT Compass Web App Homepage</a></li>
          <li><a href="https://gecmaps.vercel.app/about">About GECT Compass &amp; Developer Team</a></li>
          <li><a href="https://gecmaps.vercel.app/app-release.apk">Download Android APK (Direct Download)</a></li>
          <li><a href="https://gecmaps.vercel.app/sitemap.xml">GECT Compass Campus XML Sitemap</a></li>
          <li><a href="http://gectcr.ac.in/" rel="external">Government Engineering College Thrissur Official Website</a></li>
        </ul>
      </section>
    </main>
    <footer>
      <p>© 2026 Government Engineering College Thrissur (GEC Thrissur). GEC Maps &amp; GECT Compass Navigation System. Developed with pride by Gectians.</p>
    </footer>
  </div>'''
    content = content[:seo_content_match.start()] + new_seo_block + content[seo_content_match.end():]

with open(index_path, 'w', encoding='utf-8') as f:
    f.write(content)

print("Successfully updated gec_compass_app/web/index.html with full SEO improvements and 72 indexed locations!")
