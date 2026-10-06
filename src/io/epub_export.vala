namespace Singularity.Apps.Publish {

    public class EpubExport {
        public Publication pub;
        public bool fixed_layout = false;
        public string identifier;
        private Gee.ArrayList<HtmlAsset> images = new Gee.ArrayList<HtmlAsset> ();
        private Gee.HashMap<string, string> image_names = new Gee.HashMap<string, string> ();
        private Gee.ArrayList<string> nav_entries = new Gee.ArrayList<string> ();
        private int note_n = 0;

        public EpubExport (Publication pub) {
            this.pub = pub;
            identifier = "urn:uuid:" + Uuid.string_random ();
        }

        private static string esc (string s) {
            return Markup.escape_text (s.replace (OBJ_STR, "").replace ("­", "").replace ("​", ""));
        }

        private string lang () {
            var basic = pub.styles.find_paragraph (StyleSheet.BASIC);
            if (basic != null && basic.chars.lang != null && basic.chars.lang != "") return basic.chars.lang.replace ("_", "-");
            return "en";
        }

        private static string css_name (string style) {
            var sb = new StringBuilder ("s-");
            unichar c;
            int i = 0;
            while (style.get_next_char (ref i, out c)) sb.append_unichar (c.isalnum () ? c.tolower () : '-');
            return sb.str;
        }

        private string color_css (string? spec) {
            var c = pub.resolve_screen (spec ?? ColorRef.BLACK);
            return "#%02x%02x%02x".printf ((int) Math.round (c.r * 255), (int) Math.round (c.g * 255), (int) Math.round (c.b * 255));
        }

        public string stylesheet () {
            var sb = new StringBuilder ();
            sb.append ("body{margin:0 5%;line-height:1.4}\nimg{max-width:100%;height:auto}\nfigure{margin:1em 0;text-align:center}\nfigcaption{font-size:.85em}\naside.footnote{font-size:.85em;border-top:1px solid #888;margin-top:1em;padding-top:.3em}\ntable{border-collapse:collapse;margin:1em 0}\ntd,th{border:1px solid #888;padding:.2em .4em}\n");
            double base_size = 10;
            var bp = ParaFormat.defaults ();
            var bc = CharFormat.defaults ();
            pub.styles.resolve_paragraph (StyleSheet.BASIC, bp, bc);
            if (!bc.size.is_nan () && bc.size > 0) base_size = bc.size;
            foreach (var ps in pub.styles.paragraph) {
                var pf = ParaFormat.defaults ();
                var cf = CharFormat.defaults ();
                pub.styles.resolve_paragraph (ps.name, pf, cf);
                sb.append (".%s{".printf (css_name (ps.name)));
                if (cf.font != null) sb.append ("font-family:'%s',serif;".printf (cf.font.replace ("'", "")));
                sb.append ("font-size:%sem;".printf (XmlOut.num (Math.round (cf.size / base_size * 100) / 100)));
                if (cf.bold == 1) sb.append ("font-weight:bold;");
                if (cf.italic == 1) sb.append ("font-style:italic;");
                if (cf.color != null) sb.append ("color:%s;".printf (color_css (cf.color)));
                string[] aligns = { "left", "center", "right", "justify", "justify" };
                sb.append ("text-align:%s;".printf (aligns[pf.align.clamp (0, 4)]));
                if (Math.fabs (pf.first_indent) > 0.01) sb.append ("text-indent:%sem;".printf (XmlOut.num (Math.round (pf.first_indent / base_size * 100) / 100)));
                if (pf.left_indent > 0.01) sb.append ("margin-left:%sem;".printf (XmlOut.num (Math.round (pf.left_indent / base_size * 100) / 100)));
                sb.append ("margin-top:%sem;margin-bottom:%sem;".printf (XmlOut.num (Math.round (pf.space_before / base_size * 100) / 100), XmlOut.num (Math.round (pf.space_after / base_size * 100) / 100)));
                sb.append ("}\n");
            }
            return sb.str;
        }

        private string run_html (Run r, CharFormat base_cf) {
            string text = esc (r.text).replace (" ", "<br/>").replace ("\t", "&#8195;");
            var f = ParaBuild.resolve_run (pub, base_cf, r);
            var css = new StringBuilder ();
            if (f.bold == 1 && base_cf.bold != 1) css.append ("font-weight:bold;");
            if (f.italic == 1 && base_cf.italic != 1) css.append ("font-style:italic;");
            if (f.underline == 1) css.append ("text-decoration:underline;");
            if (f.color != null && f.color != base_cf.color) css.append ("color:%s;".printf (color_css (f.color)));
            if (f.caps == 2) css.append ("font-variant:small-caps;");
            string inner = css.len > 0 ? "<span style=\"%s\">%s</span>".printf (css.str, text) : text;
            if (f.position == 1) inner = "<sup>%s</sup>".printf (inner);
            else if (f.position == 2) inner = "<sub>%s</sub>".printf (inner);
            if (f.link != null && f.link != "" && !f.link.has_prefix ("page:") && !f.link.has_prefix ("bookmark:")) inner = "<a href=\"%s\">%s</a>".printf (Markup.escape_text (HtmlExport.link_href (f.link)), inner);
            return inner;
        }

        private string paragraph_html (Paragraph p, StringBuilder notes, string file) {
            var pf = ParaFormat.defaults ();
            var cf = CharFormat.defaults ();
            pub.styles.resolve_paragraph (p.style, pf, cf);
            pf.apply (p.fmt);
            string role = PdfFinish.role_for (pub, p);
            string tag;
            switch (role) {
                case "H1": case "H2": case "H3": case "H4": case "H5": case "H6": tag = role.down (); break;
                case "BlockQuote": tag = "blockquote"; break;
                case "LI": tag = "li"; break;
                default: tag = "p"; break;
            }
            var sb = new StringBuilder ();
            foreach (var r in p.runs) {
                if (r.condition != "" && Conditions.hidden (pub, r.condition)) continue;
                if (r.note != null) {
                    note_n++;
                    string id = "fn%d".printf (note_n);
                    sb.append ("<a epub:type=\"noteref\" href=\"#%s\" id=\"ref-%s\"><sup>%d</sup></a>".printf (id, id, note_n));
                    notes.append ("<aside epub:type=\"footnote\" class=\"footnote\" id=\"%s\"><p><a href=\"#ref-%s\">%d</a> %s</p></aside>\n".printf (id, id, note_n, esc (r.note.plain_text ())));
                    continue;
                }
                if (r.anchor != null) {
                    var im = r.anchor as ImageFrame;
                    if (im != null) sb.append (image_html (im));
                    continue;
                }
                if (r.field != "") {
                    if (r.field.has_prefix (IndexMarker.PREFIX)) continue;
                    var fc = new FieldContext (pub);
                    string v = fc.resolve (r.field);
                    if (r.field == Fields.PAGE || r.field == Fields.PAGES) continue;
                    sb.append (esc (v));
                    continue;
                }
                sb.append (run_html (r, cf));
            }
            string body = sb.str;
            string idattr = "";
            if (tag.has_prefix ("h") && tag.length == 2) {
                string anchor = p.anchor != "" ? p.anchor : "h%d".printf (nav_entries.size + 1);
                idattr = " id=\"%s\"".printf (Markup.escape_text (anchor));
                int level = int.parse (tag.substring (1));
                string plain = p.text ().replace (OBJ_STR, "").strip ();
                if (plain != "") nav_entries.add ("%d\t%s#%s\t%s".printf (level, file, anchor, plain));
            } else if (p.anchor != "") {
                idattr = " id=\"%s\"".printf (Markup.escape_text (p.anchor));
            }
            if (body == "") body = "<br/>";
            return "<%s class=\"%s\"%s>%s</%s>".printf (tag, css_name (p.style), idattr, body, tag);
        }

        private string image_html (ImageFrame im) {
            var data = ImageStore.get_default ().bytes_for (pub, im);
            if (data == null) return "";
            string kind = ImageStore.sniff (data);
            string ext = kind == "jpeg" ? "jpg" : (kind == "svg" ? "svg" : (kind == "gif" ? "gif" : "png"));
            string key = im.link != "" ? im.link : im.media;
            if (!image_names.has_key (key)) {
                uint8[] bytes = data;
                if (ext == "png" && kind != "png") {
                    var inf = ImageStore.get_default ().info (pub, im);
                    if (inf == null || inf.surface == null) return "";
                    var pb = Exporter.surface_to_pixbuf (inf.surface, true);
                    try {
                        pb.save_to_buffer (out bytes, "png");
                    } catch (Error e) {
                        return "";
                    }
                }
                string name = "img%d.%s".printf (images.size + 1, ext);
                string mime = "image/png";
                if (ext == "jpg") mime = "image/jpeg";
                else if (ext == "svg") mime = "image/svg+xml";
                else if (ext == "gif") mime = "image/gif";
                images.add (new HtmlAsset (name, mime, bytes));
                image_names[key] = name;
            }
            if (im.alt_decorative) return "<img src=\"images/%s\" alt=\"\" role=\"presentation\"/>".printf (image_names[key]);
            return "<figure><img src=\"images/%s\" alt=\"%s\"/></figure>".printf (image_names[key], Markup.escape_text (im.alt_text));
        }

        private string table_html (TableItem t, StringBuilder notes, string file) {
            var sb = new StringBuilder ("<table>");
            for (int r = 0; r < t.rows; r++) {
                sb.append ("<tr>");
                for (int c = 0; c < t.cols; c++) {
                    var cell = t.cells[r][c];
                    if (cell.covered) continue;
                    string ct = r < t.header_rows ? "th" : "td";
                    sb.append ("<%s".printf (ct));
                    if (cell.col_span > 1) sb.append (" colspan=\"%d\"".printf (cell.col_span));
                    if (cell.row_span > 1) sb.append (" rowspan=\"%d\"".printf (cell.row_span));
                    sb.append (">");
                    foreach (var p in cell.story.paras) sb.append (esc (p.text ()));
                    sb.append ("</%s>".printf (ct));
                }
                sb.append ("</tr>");
            }
            sb.append ("</table>");
            return sb.str;
        }

        private string page_doc (string title, string body, string extra_head = "") {
            return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE html>\n<html xmlns=\"http://www.w3.org/1999/xhtml\" xmlns:epub=\"http://www.idpf.org/2007/ops\" xml:lang=\"%s\" lang=\"%s\">\n<head>\n<meta charset=\"utf-8\"/>\n%s<title>%s</title>\n<link rel=\"stylesheet\" type=\"text/css\" href=\"style.css\"/>\n</head>\n<body>\n%s</body>\n</html>\n".printf (lang (), lang (), extra_head, Markup.escape_text (title), body);
        }

        private Gee.ArrayList<string> reflow_chapters () {
            var chapters = new Gee.ArrayList<string> ();
            var current = new StringBuilder ();
            var notes = new StringBuilder ();
            var done_stories = new Gee.HashSet<int> ();
            string file = "chapter1.xhtml";
            for (int pi = 0; pi < pub.pages.size; pi++) {
                var items = new Gee.ArrayList<Item> ();
                foreach (var it in pub.pages[pi].items) if (!it.hidden && !it.nonprinting) items.add (it);
                items.sort ((a, b) => {
                    var ba = a.bounds (), bb = b.bounds ();
                    if (Math.fabs (ba.y - bb.y) > 12) return ba.y < bb.y ? -1 : 1;
                    return ba.x < bb.x ? -1 : (ba.x > bb.x ? 1 : 0);
                });
                foreach (var it in items) {
                    var tf = it as TextFrame;
                    if (tf != null) {
                        if (!done_stories.add (tf.story) || tf.story == pub.endnote_story) continue;
                        var st = pub.story (tf.story);
                        bool in_list = false;
                        foreach (var p in st.paras) {
                            bool starts_chapter = PdfFinish.role_for (pub, p) == "H1" && current.len > 0;
                            if (starts_chapter) {
                                if (in_list) current.append ("</ul>\n");
                                in_list = false;
                                current.append (notes.str);
                                notes.truncate (0);
                                chapters.add (current.str);
                                current.truncate (0);
                                file = "chapter%d.xhtml".printf (chapters.size + 1);
                            }
                            bool li = PdfFinish.role_for (pub, p) == "LI";
                            if (li && !in_list) current.append ("<ul>\n");
                            if (!li && in_list) current.append ("</ul>\n");
                            in_list = li;
                            current.append (paragraph_html (p, notes, file)).append ("\n");
                        }
                        if (in_list) current.append ("</ul>\n");
                        continue;
                    }
                    var im = it as ImageFrame;
                    if (im != null && !im.alt_decorative) {
                        current.append (image_html (im)).append ("\n");
                        continue;
                    }
                    var tb = it as TableItem;
                    if (tb != null) current.append (table_html (tb, notes, file)).append ("\n");
                }
            }
            current.append (notes.str);
            if (current.len > 0 || chapters.size == 0) chapters.add (current.str);
            return chapters;
        }

        private string nav_doc (Gee.List<string> files) {
            var sb = new StringBuilder ("<nav epub:type=\"toc\" id=\"toc\"><h1>%s</h1>\n<ol>\n".printf (Markup.escape_text (_("Contents"))));
            if (nav_entries.size == 0) {
                for (int i = 0; i < files.size; i++) sb.append ("<li><a href=\"%s\">%s</a></li>\n".printf (files[i], Markup.escape_text (fixed_layout ? _("Page %s").printf (pub.page_label (i)) : _("Part %d").printf (i + 1))));
            } else {
                foreach (string e in nav_entries) {
                    string[] f = e.split ("\t");
                    if (int.parse (f[0]) > 2) continue;
                    sb.append ("<li><a href=\"%s\">%s</a></li>\n".printf (Markup.escape_text (f[1]), Markup.escape_text (f[2])));
                }
            }
            sb.append ("</ol>\n</nav>\n");
            if (fixed_layout) {
                sb.append ("<nav epub:type=\"page-list\" hidden=\"\"><ol>\n");
                for (int i = 0; i < files.size; i++) sb.append ("<li><a href=\"%s\">%s</a></li>\n".printf (files[i], Markup.escape_text (pub.page_label (i))));
                sb.append ("</ol></nav>\n");
            }
            return page_doc (_("Contents"), sb.str);
        }

        public uint8[] build () throws Error {
            var zip = new ZipWriter ();
            zip.add_text ("mimetype", "application/epub+zip", false);
            zip.add_text ("META-INF/container.xml", "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\"><rootfiles><rootfile full-path=\"OEBPS/content.opf\" media-type=\"application/oebps-package+xml\"/></rootfiles></container>\n");
            var files = new Gee.ArrayList<string> ();
            var bodies = new Gee.ArrayList<string> ();
            string title = pub.meta.title != "" ? pub.meta.title : _("Publication");
            double pw = pub.settings.width, ph = pub.settings.height;
            if (fixed_layout) {
                var hx = new HtmlExport (pub);
                hx.xhtml = true;
                hx.navigation = false;
                hx.asset_prefix = "images/";
                hx.px = 1;
                for (int i = 0; i < pub.pages.size; i++) {
                    string name = "page%d.xhtml".printf (i + 1);
                    files.add (name);
                    string body = hx.page_html (i);
                    string head = "<meta name=\"viewport\" content=\"width=%d, height=%d\"/>\n<style>body{margin:0}.page{position:relative;overflow:hidden}</style>\n".printf ((int) Math.round (pub.page_w (i)), (int) Math.round (pub.page_h (i)));
                    bodies.add (page_doc ("%s, %s".printf (title, _("page %s").printf (pub.page_label (i))), body, head));
                }
                foreach (var a in hx.assets) images.add (a);
            } else {
                var chapters = reflow_chapters ();
                for (int i = 0; i < chapters.size; i++) {
                    string name = "chapter%d.xhtml".printf (i + 1);
                    files.add (name);
                    bodies.add (page_doc (title, "<section epub:type=\"chapter\">\n%s</section>\n".printf (chapters[i])));
                }
            }
            for (int i = 0; i < files.size; i++) zip.add_text ("OEBPS/" + files[i], bodies[i]);
            zip.add_text ("OEBPS/nav.xhtml", nav_doc (files));
            zip.add_text ("OEBPS/style.css", stylesheet ());
            foreach (var a in images) zip.add ("OEBPS/images/" + a.name, a.data, false);
            var opf = new StringBuilder ();
            string modified = new DateTime.now_utc ().format ("%Y-%m-%dT%H:%M:%SZ");
            opf.append ("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\" unique-identifier=\"bookid\" xml:lang=\"%s\"%s>\n".printf (lang (), fixed_layout ? " prefix=\"rendition: http://www.idpf.org/vocab/rendition/#\"" : ""));
            opf.append ("<metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\n<dc:identifier id=\"bookid\">%s</dc:identifier>\n<dc:title>%s</dc:title>\n<dc:language>%s</dc:language>\n".printf (identifier, Markup.escape_text (title), lang ()));
            if (pub.meta.author != "") opf.append ("<dc:creator>%s</dc:creator>\n".printf (Markup.escape_text (pub.meta.author)));
            if (pub.meta.subject != "") opf.append ("<dc:description>%s</dc:description>\n".printf (Markup.escape_text (pub.meta.subject)));
            opf.append ("<meta property=\"dcterms:modified\">%s</meta>\n".printf (modified));
            if (fixed_layout) opf.append ("<meta property=\"rendition:layout\">pre-paginated</meta>\n<meta property=\"rendition:orientation\">%s</meta>\n<meta property=\"rendition:spread\">%s</meta>\n".printf (pw > ph ? "landscape" : "portrait", pub.settings.facing ? "landscape" : "none"));
            opf.append ("</metadata>\n<manifest>\n<item id=\"nav\" href=\"nav.xhtml\" media-type=\"application/xhtml+xml\" properties=\"nav\"/>\n<item id=\"css\" href=\"style.css\" media-type=\"text/css\"/>\n");
            for (int i = 0; i < files.size; i++) opf.append ("<item id=\"c%d\" href=\"%s\" media-type=\"application/xhtml+xml\"/>\n".printf (i + 1, files[i]));
            for (int i = 0; i < images.size; i++) opf.append ("<item id=\"i%d\" href=\"images/%s\" media-type=\"%s\"/>\n".printf (i + 1, images[i].name, images[i].mime));
            opf.append ("</manifest>\n<spine>\n");
            for (int i = 0; i < files.size; i++) {
                string props = "";
                if (fixed_layout && pub.settings.facing) props = pub.is_left_page (i) ? " properties=\"page-spread-left\"" : " properties=\"page-spread-right\"";
                opf.append ("<itemref idref=\"c%d\"%s/>\n".printf (i + 1, props));
            }
            opf.append ("</spine>\n</package>\n");
            zip.add_text ("OEBPS/content.opf", opf.str);
            return zip.finish ();
        }

        public static void export (Publication pub, string path, bool fixed_layout) throws Error {
            var e = new EpubExport (pub);
            e.fixed_layout = fixed_layout;
            FileUtils.set_data (path, e.build ());
        }
    }
}
