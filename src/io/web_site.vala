namespace Singularity.Apps.Publish {

    public class WebSite {
        public static string page_file (int i) {
            return i == 0 ? "index.html" : "page-%d.html".printf (i + 1);
        }

        private static string esc (string s) {
            return Markup.escape_text (s);
        }

        public static int export (Publication pub, string dir) throws Error {
            DirUtils.create_with_parents (dir, 0755);
            string assets = Path.build_filename (dir, "assets");
            DirUtils.create_with_parents (assets, 0755);
            string title = pub.meta.title != "" ? pub.meta.title : _("Publication");
            var hx = new HtmlExport (pub);
            hx.asset_prefix = "assets/";
            hx.navigation = false;
            string lang = "en";
            var basic = pub.styles.find_paragraph (StyleSheet.BASIC);
            if (basic != null && basic.chars.lang != null && basic.chars.lang != "") lang = basic.chars.lang.replace ("_", "-");
            var sitemap = new StringBuilder ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">\n");
            for (int i = 0; i < pub.pages.size; i++) {
                var sb = new StringBuilder ();
                sb.append ("<!DOCTYPE html>\n<html lang=\"%s\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n".printf (esc (lang)));
                sb.append ("<meta name=\"generator\" content=\"Singularity Publish\">\n");
                if (pub.meta.subject != "") sb.append ("<meta name=\"description\" content=\"%s\">\n".printf (esc (pub.meta.subject)));
                sb.append ("<title>%s</title>\n".printf (esc (pub.pages.size > 1 ? "%s, %s".printf (title, _("page %s").printf (pub.page_label (i))) : title)));
                sb.append ("<link rel=\"stylesheet\" href=\"assets/site.css\">\n</head>\n<body>\n<header><a class=\"home\" href=\"index.html\">%s</a><nav aria-label=\"%s\">".printf (esc (title), esc (_("Pages"))));
                if (i > 0) sb.append ("<a rel=\"prev\" href=\"%s\">%s</a>".printf (page_file (i - 1), esc (_("Previous"))));
                sb.append ("<span>%s</span>".printf (esc (_("%s of %d").printf (pub.page_label (i), pub.pages.size))));
                if (i + 1 < pub.pages.size) sb.append ("<a rel=\"next\" href=\"%s\">%s</a>".printf (page_file (i + 1), esc (_("Next"))));
                sb.append ("</nav></header>\n<main><div class=\"fit\" style=\"--w:%s;--h:%s\">\n".printf (XmlOut.num (pub.page_w (i) * hx.px), XmlOut.num (pub.page_h (i) * hx.px)));
                sb.append (hx.page_html (i));
                sb.append ("</div></main>\n<script>function fit(){document.querySelectorAll('.fit').forEach(function(f){var w=parseFloat(getComputedStyle(f).getPropertyValue('--w'));var s=Math.min(1,(window.innerWidth-24)/w);f.style.transform='scale('+s+')';f.style.height=(parseFloat(getComputedStyle(f).getPropertyValue('--h'))*s)+'px';});}window.addEventListener('resize',fit);fit();</script>\n</body>\n</html>\n");
                FileUtils.set_contents (Path.build_filename (dir, page_file (i)), sb.str);
                sitemap.append ("<url><loc>%s</loc></url>\n".printf (page_file (i)));
            }
            sitemap.append ("</urlset>\n");
            FileUtils.set_contents (Path.build_filename (dir, "sitemap.xml"), sitemap.str);
            foreach (var a in hx.assets) FileUtils.set_data (Path.build_filename (assets, a.name), a.data);
            FileUtils.set_contents (Path.build_filename (assets, "site.css"), "body{margin:0;background:#eceef1;font-family:sans-serif}\nheader{position:sticky;top:0;z-index:5;display:flex;gap:16px;align-items:center;justify-content:space-between;background:#fff;padding:8px 16px;box-shadow:0 1px 3px rgba(0,0,0,.2)}\nheader a{color:#0b62c4;text-decoration:none;margin:0 6px}\n.home{font-weight:bold}\nmain{display:flex;justify-content:center;padding:12px}\n.fit{transform-origin:top left;width:calc(var(--w)*1px)}\n.page{position:relative;background:#fff;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.25)}\n");
            return pub.pages.size;
        }
    }
}
