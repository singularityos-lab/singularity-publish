namespace Singularity.Apps.Publish {

    public class ReviewComment {
        public int page;
        public double x;
        public double y;
        public double w = 0;
        public double h = 0;
        public string author = "";
        public string text = "";
        public string kind = "Text";
        public string date = "";
        public string quoted = "";
        public bool resolved = false;
        public Gee.ArrayList<ReviewComment> replies = new Gee.ArrayList<ReviewComment> ();

        public ReviewComment clone () {
            var c = new ReviewComment ();
            c.page = page;
            c.x = x;
            c.y = y;
            c.w = w;
            c.h = h;
            c.author = author;
            c.text = text;
            c.kind = kind;
            c.date = date;
            c.quoted = quoted;
            c.resolved = resolved;
            foreach (var r in replies) c.replies.add (r.clone ());
            return c;
        }

        public void write (XmlOut x) {
            x.start ("comment").ai ("page", page).ad ("x", this.x).ad ("y", y).ad ("w", w).ad ("h", h).a ("author", author).a ("kind", kind).a ("date", date).a ("quoted", quoted).ai ("resolved", resolved ? 1 : 0);
            x.element ("text", text);
            foreach (var r in replies) r.write (x);
            x.end ();
        }

        public static ReviewComment read (Xml.Node* n) {
            var c = new ReviewComment ();
            c.page = XmlIn.int_attr (n, "page", 0);
            c.x = XmlIn.double_attr (n, "x", 0);
            c.y = XmlIn.double_attr (n, "y", 0);
            c.w = XmlIn.double_attr (n, "w", 0);
            c.h = XmlIn.double_attr (n, "h", 0);
            c.author = XmlIn.attr (n, "author") ?? "";
            c.kind = XmlIn.attr (n, "kind") ?? "Text";
            c.date = XmlIn.attr (n, "date") ?? "";
            c.quoted = XmlIn.attr (n, "quoted") ?? "";
            c.resolved = XmlIn.int_attr (n, "resolved", 0) == 1;
            var tn = XmlIn.child (n, "text");
            c.text = tn != null ? XmlIn.text (tn) : "";
            foreach (var rn in XmlIn.elements (n, "comment")) c.replies.add (read (rn));
            return c;
        }
    }

    public class Review {
        public static void write (Publication pub, XmlOut x) {
            if (pub.comments.size == 0) return;
            x.start ("review");
            foreach (var c in pub.comments) c.write (x);
            x.end ();
        }

        public static void read (Publication pub, Xml.Node* n) {
            if (n == null) return;
            foreach (var cn in XmlIn.elements (n, "comment")) pub.comments.add (ReviewComment.read (cn));
        }

        public static int import_pdf (Publication pub, string path, bool replace_existing = false) throws Error {
            var doc = Singularity.Pdf.Document.open_file (path);
            doc.load_all ();
            var ex = new Exporter (pub, new ExportOptions ());
            var sheets = ex.sheets ();
            var place = PdfFinish.placements (sheets);
            var by_pdf_page = new Gee.HashMap<int, int> ();
            foreach (var e in place.entries) by_pdf_page[e.value.pdf_page] = e.key;
            var list = Singularity.Pdf.Annotations.list (doc);
            var made = new Gee.HashMap<string, ReviewComment> ();
            var seen = new Gee.HashSet<string> ();
            foreach (var c in pub.comments) seen.add ("%d:%s:%s".printf (c.page, c.author, c.text));
            int added = 0;
            var ordered = new Gee.ArrayList<Singularity.Pdf.AnnotInfo> ();
            foreach (var a in list) if (!a.is_reply) ordered.add (a);
            foreach (var a in list) if (a.is_reply) ordered.add (a);
            foreach (var a in ordered) {
                bool markup = false;
                foreach (string t in Singularity.Pdf.Annotations.MARKUP_TYPES) if (t == a.subtype) markup = true;
                if (!markup || a.subtype == "Redact") continue;
                if (!by_pdf_page.has_key (a.page)) continue;
                int pg = by_pdf_page[a.page];
                var pl = place[pg];
                var c = new ReviewComment ();
                c.page = pg;
                c.x = (a.rect.x1 - pl.x) / pl.scale;
                c.y = (pl.sheet_h - a.rect.y2 - pl.y) / pl.scale;
                c.w = (a.rect.x2 - a.rect.x1) / pl.scale;
                c.h = (a.rect.y2 - a.rect.y1) / pl.scale;
                c.author = a.author;
                c.text = a.contents;
                c.kind = a.subtype;
                c.date = a.modified;
                if (a.subtype == "Highlight" || a.subtype == "Underline" || a.subtype == "StrikeOut" || a.subtype == "Squiggly") c.quoted = text_under (pub, pg, c.x, c.y, c.w, c.h);
                string key = "%d:%s:%s".printf (c.page, c.author, c.text);
                if (a.is_reply) {
                    string parent_key = "%d".printf (a.reply_to);
                    if (made.has_key (parent_key)) {
                        made[parent_key].replies.add (c);
                        added++;
                    }
                    continue;
                }
                if (!replace_existing && seen.contains (key)) continue;
                pub.comments.add (c);
                made["%d".printf (a.reference.num)] = c;
                added++;
            }
            return added;
        }

        public static string text_under (Publication pub, int page, double x, double y, double w, double h) {
            var cache = new LayoutCache (pub);
            var sb = new StringBuilder ();
            foreach (var it in pub.pages[page].items) {
                var t = it as TextFrame;
                if (t == null) continue;
                var fr = cache.story (t.story).frame_result (t.id);
                if (fr == null) continue;
                foreach (var l in fr.lines) {
                    double ly = t.y + l.baseline;
                    if (ly < y || ly - l.ascent > y + h + 2) continue;
                    int i0 = l.hit (x - t.x), i1 = l.hit (x + w - t.x);
                    var st = pub.story (t.story);
                    if (l.para < 0 || l.para >= st.paras.size) continue;
                    string pt = st.paras[l.para].text ();
                    int a = pt.index_of_nth_char (i0.clamp (0, pt.char_count ())), b = pt.index_of_nth_char (i1.clamp (0, pt.char_count ()));
                    if (b > a) sb.append (pt.substring (a, b - a));
                }
            }
            return sb.str.strip ();
        }
    }
}
