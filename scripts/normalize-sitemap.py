from pathlib import Path
import xml.etree.ElementTree as ET


SITE_URL = "https://joonion.github.io/hands-on-paper-writing/"
SITEMAP = Path(__file__).resolve().parents[1] / "_site" / "sitemap.xml"
NAMESPACE = "http://www.sitemaps.org/schemas/sitemap/0.9"


def main() -> None:
    if not SITEMAP.is_file():
        raise FileNotFoundError(f"Sitemap not found: {SITEMAP}")

    ET.register_namespace("", NAMESPACE)
    tree = ET.parse(SITEMAP)
    locations = tree.findall(f".//{{{NAMESPACE}}}loc")
    index_url = f"{SITE_URL}index.html"
    index_locations = [location for location in locations if location.text == index_url]
    root_locations = [location for location in locations if location.text == SITE_URL]

    if len(index_locations) == 1 and not root_locations:
        index_locations[0].text = SITE_URL
        tree.write(SITEMAP, encoding="utf-8", xml_declaration=True)
        return

    if not index_locations and len(root_locations) == 1:
        return

    raise RuntimeError(
        "Expected exactly one homepage URL in sitemap.xml: "
        f"index={len(index_locations)}, root={len(root_locations)}"
    )


if __name__ == "__main__":
    main()
