namespace Singularity.Apps.Publish {

    public class HtmlAsset {
        public string name;
        public string mime;
        public uint8[] data;

        public HtmlAsset (string name, string mime, uint8[] data) {
            this.name = name;
            this.mime = mime;
            this.data = data;
        }
    }

    public class HtmlExport {
        public Publication pub;
        public double px = 96.0 / 72.0;
        public bool inline_assets = false;
        public string asset_prefix = "";
        public Gee.ArrayList<HtmlAsset> assets = new Gee.ArrayList<HtmlAsset> ();
        public Gee.ArrayList<int> pages = new Gee.ArrayList<int> ();
        public bool navigation = true;
        public bool xhtml = false;
        private LayoutCache cache;
        private Renderer renderer;
        private Gee.HashMap<string, string> asset_names = new Gee.HashMap<string, string> ();
        private int counter = 0;

        public HtmlExport (Publication pub) {
            this.pub = pub;
            cache = new LayoutCache (pub);
            renderer = new Renderer (pub, cache);
            renderer.opts.print = true;
            renderer.opts.overset_marks = false;
            renderer.opts.placeholders = false;
        }

        public static string esc (string s) {
            return s.replace ("&", "&amp;").replace ("<", "&lt;").replace (">", "&gt;").replace ("\"", "&quot;");
        }

        private string n (double v) {
            return XmlOut.num (Math.round (v * px * 100) / 100);
        }

        private string css_color (string spec) {
            var c = pub.resolve_screen (spec);
            if (c.a < 0.999) return "rgba(%d,%d,%d,%s)".printf ((int) Math.round (c.r * 255), (int) Math.round (c.g * 255), (int) Math.round (c.b * 255), XmlOut.num (Math.round (c.a * 1000) / 1000));
            return c.to_hex ();
        }

        public string asset (uint8[] data, string ext, string mime) {
            string key = Checksum.compute_for_data (ChecksumType.SHA1, data);
            if (asset_names.has_key (key)) return asset_names[key];
            string name = "asset-%03d.%s".printf (++counter, ext);
            assets.add (new HtmlAsset (name, mime, data));
            string url;
            if (inline_assets) url = "cid:" + name;
            else url = asset_prefix + name;
            asset_names[key] = url;
            return url;
        }

        public static string link_href (string link) {
            if (link.has_prefix ("page:")) return "#page-%d".printf (int.parse (link.substring (5)) + 1);
            if (link.has_prefix ("bookmark:")) return "#" + Renderer.dest_name (link.substring (9));
            if (!link.contains (":") && link.contains ("@")) return "mailto:" + link;
            if (!link.contains (":")) return "https://" + link;
            return link;
        }

        private string char_css (CharFormat f) {
            var sb = new StringBuilder ();
            sb.append ("font-family:'%s',sans-serif;".printf ((f.font ?? "Inter").replace ("'", "")));
            sb.append ("font-size:%spx;".printf (n (f.size)));
            if (f.bold == 1) sb.append ("font-weight:bold;");
            if (f.italic == 1) sb.append ("font-style:italic;");
            var deco = new StringBuilder ();
            if (f.underline == 1) deco.append ("underline ");
            if (f.strike == 1) deco.append ("line-through");
            if (deco.len > 0) sb.append ("text-decoration:%s;".printf (deco.str.strip ()));
            sb.append ("color:%s;".printf (css_color (f.color ?? ColorRef.BLACK)));
            if (!f.tracking.is_nan () && Math.fabs (f.tracking) > 0.01) sb.append ("letter-spacing:%sem;".printf (XmlOut.num (f.tracking / 1000)));
            if (f.caps == 1) sb.append ("text-transform:uppercase;");
            if (f.caps == 2) sb.append ("font-variant:small-caps;");
            if (f.position == 1) sb.append ("vertical-align:super;font-size:%spx;".printf (n (f.size * 0.62)));
            if (f.position == 2) sb.append ("vertical-align:sub;font-size:%spx;".printf (n (f.size * 0.62)));
            if (f.outline_color != null && f.outline_color != "" && !f.outline_width.is_nan () && f.outline_width > 0) sb.append ("-webkit-text-stroke:%spx %s;".printf (n (f.outline_width), css_color (f.outline_color)));
            if (f.text_shadow == 1) sb.append ("text-shadow:1px 1px 2px rgba(0,0,0,0.45);");
            if (f.glow_color != null && f.glow_color != "" && !f.glow_size.is_nan () && f.glow_size > 0) sb.append ("text-shadow:0 0 %spx %s;".printf (n (f.glow_size), css_color (f.glow_color)));
            return sb.str;
        }

        private string para_css (ParaFormat pf, double leading, bool first_in_frame) {
            var sb = new StringBuilder ("margin:0;");
            string[] aligns = { "left", "center", "right", "justify", "justify" };
            sb.append ("text-align:%s;".printf (aligns[pf.align.clamp (0, 4)]));
            if (pf.left_indent > 0.01) sb.append ("padding-left:%spx;".printf (n (pf.left_indent)));
            if (pf.right_indent > 0.01) sb.append ("padding-right:%spx;".printf (n (pf.right_indent)));
            if (Math.fabs (pf.first_indent) > 0.01) sb.append ("text-indent:%spx;".printf (n (pf.first_indent)));
            if (pf.space_before > 0.01 && !first_in_frame) sb.append ("margin-top:%spx;".printf (n (pf.space_before)));
            if (pf.space_after > 0.01) sb.append ("margin-bottom:%spx;".printf (n (pf.space_after)));
            if (leading > 0.01) sb.append ("line-height:%spx;".printf (n (leading)));
            return sb.str;
        }

        private string story_html (Story st, int page_index) {
            var sb = new StringBuilder ();
            var fc = new FieldContext (pub);
            fc.page_index = page_index;
            var counter_l = new ListCounter ();
            for (int i = 0; i < st.paras.size; i++) {
                var p = st.paras[i];
                var b = ParaBuild.build (pub, p, i, fc, counter_l, false);
                var pf = b.pf;
                string tag = FontScheme.is_heading_style (p.style) ? (p.style.contains ("2") ? "h2" : "h1") : "p";
                sb.append ("<%s style=\"%s\">".printf (tag, para_css (pf, pf.leading, i == 0)));
                if (b.text == "") sb.append (xhtml ? "<br/>" : "<br>");
                foreach (var sp in b.spans) {
                    if (sp.end <= sp.start) continue;
                    string t = b.text.substring (sp.start, sp.end - sp.start).replace ("­", "").replace ("​", "");
                    string body = esc (t).replace (" ", xhtml ? "<br/>" : "<br>").replace ("\t", "&#8195;");
                    string span = "<span style=\"%s\">%s</span>".printf (char_css (sp.fmt), body);
                    if (sp.fmt.link != null && sp.fmt.link != "") span = "<a href=\"%s\">%s</a>".printf (esc (link_href (sp.fmt.link)), span);
                    sb.append (span);
                }
                sb.append ("</%s>".printf (tag));
            }
            return sb.str;
        }

        private string box_css (Item it) {
            var sb = new StringBuilder ("position:absolute;");
            sb.append ("left:%spx;top:%spx;width:%spx;height:%spx;".printf (n (it.x), n (it.y), n (it.w), n (it.h)));
            if (it.rotation != 0) sb.append ("transform:rotate(%sdeg);".printf (XmlOut.num (it.rotation)));
            if (it.opacity < 0.999) sb.append ("opacity:%s;".printf (XmlOut.num (it.opacity)));
            return sb.str;
        }

        private string snapshot (Item it, bool master, int page_index, out Rect where) {
            double pad = 4;
            if (it.shadow.enabled) pad = double.max (pad, it.shadow.blur * 2 + double.max (Math.fabs (it.shadow.dx), Math.fabs (it.shadow.dy)) + 2);
            if (it.effects.glow) pad = double.max (pad, it.effects.glow_size * 2 + 4);
            var bb = it.bounds ();
            double extra_h = it.effects.reflection ? it.h * it.effects.reflection_size + it.effects.reflection_distance : 0;
            where = Rect (bb.x - pad, bb.y - pad, bb.w + 2 * pad, bb.h + 2 * pad + extra_h);
            double sc = 2 * px;
            int w = int.max (1, (int) Math.ceil (where.w * sc)), h = int.max (1, (int) Math.ceil (where.h * sc));
            var surf = new Cairo.ImageSurface (Cairo.Format.ARGB32, w, h);
            var cr = new Cairo.Context (surf);
            cr.scale (sc, sc);
            cr.translate (-where.x, -where.y);
            renderer.draw_item (cr, it, master, page_index);
            surf.flush ();
            uint8[] png = {};
            surf.write_to_png_stream ((data) => {
                uint8[] chunk = data;
                var joined = new uint8[png.length + chunk.length];
                Memory.copy (joined, png, png.length);
                Memory.copy (&joined[png.length], chunk, chunk.length);
                png = joined;
                return Cairo.Status.SUCCESS;
            });
            return asset (png, "png", "image/png");
        }

        private string wrap_link (Item it, string html) {
            if (it.link == "") return html;
            return "<a href=\"%s\" title=\"%s\">%s</a>".printf (esc (link_href (it.link)), esc (it.alt_text), html);
        }

        private string alt_of (Item it) {
            if (it.alt_decorative) return "";
            if (it.alt_text != "") return it.alt_text;
            var wa = it as WordArtItem;
            if (wa != null) return wa.text;
            return "";
        }

        private bool simple_image (ImageFrame im) {
            return !im.adjusted () && im.clip_shape == "" && !im.shape_ellipse && !im.effects.any () && !im.shadow.enabled && im.fit != FitMode.MANUAL && !im.border_art.visible () && im.merge_field == "";
        }

        private string item_html (Item it, bool master, int page_index) {
            if (it.hidden || it.nonprinting) return "";
            var layer = pub.layer (it.layer);
            if (layer != null && (!layer.visible || !layer.printable)) return "";
            var g = it as GroupItem;
            if (g != null && !g.effects.any () && !g.shadow.enabled && g.rotation == 0 && g.link == "") {
                var sb = new StringBuilder ();
                foreach (var c in renderer.ordered (g.children)) sb.append (item_html (c, master, page_index));
                return sb.str;
            }
            var t = it as TextFrame;
            if (t != null && !t.effects.any () && !t.vertical) {
                var res = master ? cache.master_story (t.story, page_index) : cache.story (t.story);
                var fr = res.frame_result (t.id);
                var sb = new StringBuilder ();
                var css = new StringBuilder (box_css (it));
                css.append ("box-sizing:border-box;overflow:hidden;");
                css.append ("padding:%spx %spx %spx %spx;".printf (n (t.inset_top), n (t.inset_right), n (t.inset_bottom), n (t.inset_left)));
                if (t.fill.kind == FillKind.SOLID && t.fill.color != ColorRef.NONE) css.append ("background:%s;".printf (css_color (t.fill.color)));
                if (t.stroke.visible ()) css.append ("border:%spx solid %s;".printf (n (t.stroke.width), css_color (t.stroke.color)));
                if (t.columns > 1) css.append ("column-count:%d;column-gap:%spx;".printf (t.columns, n (t.gutter)));
                if (t.valign == 1) css.append ("display:flex;flex-direction:column;justify-content:center;");
                if (t.valign == 2) css.append ("display:flex;flex-direction:column;justify-content:flex-end;");
                if (res.scale < 0.999 || res.scale > 1.001) css.append ("font-size:%s%%;".printf (XmlOut.num (Math.round (res.scale * 100))));
                sb.append ("<div class=\"frame\" style=\"%s\"><div>".printf (css.str));
                if (fr != null && !fr.empty) {
                    var st = pub.story (t.story);
                    var part = st.copy_range (fr.first, fr.last);
                    sb.append (story_html (part, page_index));
                }
                sb.append ("</div></div>");
                return wrap_link (it, sb.str);
            }
            var im = it as ImageFrame;
            if (im != null && im.has_image () && simple_image (im)) {
                var data = ImageStore.get_default ().bytes_for (pub, im);
                if (data != null) {
                    string ext = ImageStore.sniff (data);
                    if (ext == "") ext = "png";
                    string mime = ext == "jpg" ? "image/jpeg" : "image/" + ext;
                    string url = asset (data, ext, mime);
                    string fit = im.fit == FitMode.FIT ? "contain" : (im.fit == FitMode.STRETCH ? "fill" : "cover");
                    var css = new StringBuilder (box_css (it));
                    css.append ("object-fit:%s;object-position:%s%% %s%%;".printf (fit, XmlOut.num (Math.round (im.focus_x * 100)), XmlOut.num (Math.round (im.focus_y * 100))));
                    if (im.stroke.visible ()) css.append ("box-sizing:border-box;border:%spx solid %s;".printf (n (im.stroke.width), css_color (im.stroke.color)));
                    return wrap_link (it, "<img src=\"%s\" alt=\"%s\" style=\"%s\"%s>".printf (esc (url), esc (alt_of (it)), css.str, xhtml ? "/" : ""));
                }
            }
            var tb = it as TableItem;
            if (tb != null && tb.rotation == 0 && !tb.effects.any ()) {
                var sb = new StringBuilder ();
                sb.append ("<table style=\"%sborder-collapse:collapse;table-layout:fixed;\">".printf (box_css (it)));
                for (int r = 0; r < tb.rows; r++) {
                    sb.append ("<tr style=\"height:%spx\">".printf (n (tb.row_h[r])));
                    for (int c = 0; c < tb.cols; c++) {
                        var cell = tb.cells[r][c];
                        if (cell.covered) continue;
                        string tag = r < tb.header_rows ? "th" : "td";
                        string fill = cell.fill;
                        if (fill == ColorRef.NONE) {
                            if (r < tb.header_rows && tb.header_fill != ColorRef.NONE) fill = tb.header_fill;
                            else if (r >= tb.header_rows && (r - tb.header_rows) % 2 == 1 && tb.alt_fill != ColorRef.NONE) fill = tb.alt_fill;
                        }
                        var css = new StringBuilder ("padding:%spx;vertical-align:%s;font-weight:normal;".printf (n (tb.cell_inset), cell.valign == 1 ? "middle" : (cell.valign == 2 ? "bottom" : "top")));
                        if (tb.border_width > 0 && tb.border_color != ColorRef.NONE) css.append ("border:%spx solid %s;".printf (n (tb.border_width), css_color (tb.border_color)));
                        if (fill != ColorRef.NONE) css.append ("background:%s;".printf (css_color (fill)));
                        if (r == 0) css.append ("width:%spx;".printf (n (tb.col_w[c])));
                        sb.append ("<%s colspan=\"%d\" rowspan=\"%d\" style=\"%s\">%s</%s>".printf (tag, cell.col_span, cell.row_span, css.str, story_html (cell.story, page_index), tag));
                    }
                    sb.append ("</tr>");
                }
                sb.append ("</table>");
                return wrap_link (it, sb.str);
            }
            var shp = it as ShapeItem;
            if (shp != null && shp.shape == ShapeKind.RECT && shp.fill.kind == FillKind.SOLID && !shp.effects.any () && !shp.shadow.enabled && !shp.border_art.visible () && shp.corner == CornerKind.NONE) {
                var css = new StringBuilder (box_css (it));
                css.append ("box-sizing:border-box;background:%s;".printf (css_color (shp.fill.color)));
                if (shp.stroke.visible ()) css.append ("border:%spx solid %s;".printf (n (shp.stroke.width), css_color (shp.stroke.color)));
                string role = alt_of (it) != "" ? " role=\"img\" aria-label=\"%s\"".printf (esc (alt_of (it))) : " aria-hidden=\"true\"";
                return wrap_link (it, "<div%s style=\"%s\"></div>".printf (role, css.str));
            }
            Rect where;
            string url = snapshot (it, master, page_index, out where);
            string css = "position:absolute;left:%spx;top:%spx;width:%spx;height:%spx;".printf (n (where.x), n (where.y), n (where.w), n (where.h));
            return wrap_link (it, "<img src=\"%s\" alt=\"%s\" style=\"%s\"%s>".printf (esc (url), esc (alt_of (it)), css, xhtml ? "/" : ""));
        }

        public string page_html (int pi) {
            var sb = new StringBuilder ();
            double w = pub.settings.width, h = pub.settings.height;
            sb.append ("<section class=\"page\" id=\"page-%d\" aria-label=\"%s\" style=\"width:%spx;height:%spx\">\n".printf (pi + 1, esc (_("Page %s").printf (pub.page_label (pi))), n (w), n (h)));
            var all = new Gee.ArrayList<Item> ();
            var masters = new Gee.HashSet<Item> ();
            foreach (var it in pub.master_items_for (pi)) {
                all.add (it);
                masters.add (it);
            }
            all.add_all (pub.pages[pi].items);
            foreach (var it in renderer.ordered (all)) sb.append (item_html (it, masters.contains (it), pi)).append ("\n");
            foreach (var b in pub.bookmarks) if (b.page == pi) sb.append ("<a class=\"bookmark\" id=\"%s\" style=\"position:absolute;left:%spx;top:%spx\"></a>\n".printf (Renderer.dest_name (b.name), n (b.x), n (b.y)));
            sb.append ("</section>\n");
            return sb.str;
        }

        public string document (string title) {
            var sb = new StringBuilder ();
            string lang = "en";
            var basic = pub.styles.find_paragraph (StyleSheet.BASIC);
            if (basic != null && basic.chars.lang != null && basic.chars.lang != "") lang = basic.chars.lang;
            sb.append ("<!DOCTYPE html>\n<html lang=\"%s\">\n<head>\n<meta charset=\"utf-8\">\n".printf (esc (lang)));
            sb.append ("<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n");
            sb.append ("<meta name=\"generator\" content=\"Singularity Publish\">\n");
            if (pub.meta.author != "") sb.append ("<meta name=\"author\" content=\"%s\">\n".printf (esc (pub.meta.author)));
            if (pub.meta.subject != "") sb.append ("<meta name=\"description\" content=\"%s\">\n".printf (esc (pub.meta.subject)));
            sb.append ("<title>%s</title>\n".printf (esc (title)));
            sb.append ("<style>\nbody{margin:0;background:#e9e9ec;font-family:sans-serif}\nnav{position:sticky;top:0;background:#fff;padding:8px 16px;box-shadow:0 1px 3px rgba(0,0,0,.2);z-index:10}\nnav a{margin-right:12px;color:#0b62c4;text-decoration:none}\nmain{display:flex;flex-direction:column;align-items:center;gap:24px;padding:24px 0}\n.page{position:relative;background:#fff;overflow:hidden;box-shadow:0 2px 8px rgba(0,0,0,.25)}\n.frame p,.frame h1,.frame h2{font-size:inherit}\n.frame>div{width:100%}\na img{border:0}\n</style>\n</head>\n<body>\n");
            var list = pages.size > 0 ? pages : all_pages ();
            if (navigation && list.size > 1) {
                sb.append ("<nav aria-label=\"%s\">".printf (esc (_("Pages"))));
                foreach (int pi in list) sb.append ("<a href=\"#page-%d\">%s</a>".printf (pi + 1, esc (pub.page_label (pi))));
                sb.append ("</nav>\n");
            }
            sb.append ("<main>\n");
            foreach (int pi in list) sb.append (page_html (pi));
            sb.append ("</main>\n</body>\n</html>\n");
            return sb.str;
        }

        private Gee.ArrayList<int> all_pages () {
            var l = new Gee.ArrayList<int> ();
            for (int i = 0; i < pub.pages.size; i++) l.add (i);
            return l;
        }

        public static string export (Publication pub, string html_path, Gee.List<int>? pages = null) throws Error {
            var ex = new HtmlExport (pub);
            string dir = Path.get_dirname (html_path);
            string base_name = Path.get_basename (html_path);
            int dot = base_name.last_index_of (".");
            if (dot > 0) base_name = base_name.substring (0, dot);
            string files = base_name + "_files";
            ex.asset_prefix = Uri.escape_string (files, null, true) + "/";
            if (pages != null) ex.pages.add_all (pages);
            string html = ex.document (pub.meta.title != "" ? pub.meta.title : base_name);
            if (ex.assets.size > 0) {
                string fdir = Path.build_filename (dir, files);
                DirUtils.create_with_parents (fdir, 0755);
                foreach (var a in ex.assets) FileUtils.set_data (Path.build_filename (fdir, a.name), a.data);
            }
            FileUtils.set_contents (html_path, html);
            return html_path;
        }

        public static string render_inline (Publication pub, Gee.List<int> pages, out Gee.ArrayList<HtmlAsset> parts) {
            var ex = new HtmlExport (pub);
            ex.inline_assets = true;
            ex.navigation = false;
            ex.pages.add_all (pages);
            string html = ex.document (pub.meta.title != "" ? pub.meta.title : _("Publication"));
            parts = ex.assets;
            return html;
        }
    }
}
