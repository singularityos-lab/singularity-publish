namespace Singularity.Apps.Publish {

    public class AccessibilityChecker {
        public Publication pub;
        public Preflight target;
        public double min_size = 8;
        private LayoutCache? cache = null;

        public AccessibilityChecker (Publication pub, Preflight target) {
            this.pub = pub;
            this.target = target;
        }

        public static double luminance (Rgba c) {
            double[] v = { c.r, c.g, c.b };
            for (int i = 0; i < 3; i++) v[i] = v[i] <= 0.03928 ? v[i] / 12.92 : Math.pow ((v[i] + 0.055) / 1.055, 2.4);
            return 0.2126 * v[0] + 0.7152 * v[1] + 0.0722 * v[2];
        }

        public static double contrast (Rgba a, Rgba b) {
            double la = luminance (a), lb = luminance (b);
            double hi = double.max (la, lb), lo = double.min (la, lb);
            return (hi + 0.05) / (lo + 0.05);
        }

        public static bool vague_link (string text) {
            string t = text.strip ().down ().replace (".", "").replace (":", "");
            string[] bad = { "click here", "here", "link", "more", "read more", "this", "this link", "clicca qui", "qui", "go", "details" };
            foreach (string b in bad) if (t == b) return true;
            return t.has_prefix ("http://") || t.has_prefix ("https://") || t.has_prefix ("www.");
        }

        private Rgba background_for (Item frame, Gee.List<Item> siblings) {
            if (frame.fill.kind == FillKind.SOLID && frame.fill.color != ColorRef.NONE) return blend (pub.resolve_screen (frame.fill.color), Rgba (1, 1, 1, 1));
            var center = frame.center ();
            Rgba bg = Rgba (1, 1, 1, 1);
            foreach (var it in siblings) {
                if (it == frame) break;
                if (it.hidden || !it.hit (center.x, center.y)) continue;
                if (it.fill.kind == FillKind.SOLID && it.fill.color != ColorRef.NONE) bg = blend (pub.resolve_screen (it.fill.color), bg);
                else if ((it.fill.kind == FillKind.LINEAR || it.fill.kind == FillKind.RADIAL) && it.fill.stops.size > 0) bg = blend (pub.resolve_screen (it.fill.stops[0].color), bg);
            }
            return bg;
        }

        private static Rgba blend (Rgba top, Rgba under) {
            double a = top.a;
            return Rgba (top.r * a + under.r * (1 - a), top.g * a + under.g * (1 - a), top.b * a + under.b * (1 - a), 1);
        }

        private void add (Severity s, IssueKind k, string msg, int page, int item) {
            target.add (s, k, msg, page, item);
        }

        public void run () {
            cache = new LayoutCache (pub);
            if (pub.meta.title.strip () == "") add (Severity.WARNING, IssueKind.NO_TITLE, _("The publication has no title; set one in File, Properties so screen readers can announce it"), -1, -1);
            for (int pi = 0; pi < pub.pages.size; pi++) {
                var all = new Gee.ArrayList<Item> ();
                all.add_all (pub.master_items_for (pi));
                all.add_all (pub.pages[pi].items);
                foreach (var it in pub.pages[pi].items) check (it, pi, all);
            }
        }

        private void check (Item it, int page, Gee.List<Item> siblings) {
            if (it.hidden) return;
            var g = it as GroupItem;
            if (g != null) {
                bool picture_group = false;
                foreach (var c in g.children) if (c is ImageFrame) picture_group = true;
                if (!picture_group || g.alt_text.strip () == "") foreach (var c in g.children) check (c, page, g.children);
                return;
            }
            var im = it as ImageFrame;
            if (im != null && im.has_image () && !im.alt_decorative && im.alt_text.strip () == "") {
                string name = im.link != "" ? Path.get_basename (im.link) : _("Embedded picture");
                add (Severity.WARNING, IssueKind.ALT_TEXT, _("Picture \"%s\" has no alternative text").printf (name), page, im.id);
            }
            var s = it as ShapeItem;
            if (s != null && !s.alt_decorative && s.alt_text.strip () == "") {
                var wa = s as WordArtItem;
                if (wa != null) add (Severity.WARNING, IssueKind.ALT_TEXT, _("WordArt \"%s\" has no alternative text").printf (wa.text), page, s.id);
                else if (s.w * s.h > 2500 && s.shape != ShapeKind.LINE && (s.fill.kind == FillKind.PICTURE || s.fill.kind == FillKind.TEXTURE)) add (Severity.INFO, IssueKind.ALT_TEXT, _("A shape with a picture fill has no alternative text; mark it decorative if it carries no meaning"), page, s.id);
            }
            var tb = it as TableItem;
            if (tb != null) {
                if (tb.header_rows == 0) add (Severity.WARNING, IssueKind.TABLE_HEADER, _("A table has no header row"), page, tb.id);
                for (int r = 0; r < tb.rows; r++) {
                    bool empty = true;
                    foreach (var c in tb.cells[r]) if (!c.covered && !c.story.is_empty ()) empty = false;
                    if (empty && tb.rows > 1) {
                        add (Severity.INFO, IssueKind.TABLE_HEADER, _("Row %d of a table is blank").printf (r + 1), page, tb.id);
                        break;
                    }
                }
            }
            var t = it as TextFrame;
            if (t != null) check_text (t, page, siblings);
            if (it.link != "" && it.alt_text.strip () == "" && !(it is TextFrame)) add (Severity.WARNING, IssueKind.LINK_TEXT, _("A linked object has no alternative text describing where the link goes"), page, it.id);
        }

        private void check_text (TextFrame t, int page, Gee.List<Item> siblings) {
            var st = pub.story (t.story);
            if (st.frames.size > 0 && st.frames[0] != t.id) return;
            var bg = background_for (t, siblings);
            bool low_contrast = false, small = false, vague = false;
            foreach (var p in st.paras) {
                var pf = ParaFormat.defaults ();
                var cf = CharFormat.defaults ();
                pub.styles.resolve_paragraph (p.style, pf, cf);
                foreach (var r in p.runs) {
                    if (r.text.strip () == "" && r.field == "") continue;
                    var f = ParaBuild.resolve_run (pub, cf, r);
                    var col = blend (pub.resolve_screen (f.color ?? ColorRef.BLACK), bg);
                    bool large = f.size >= 18 || (f.size >= 14 && f.bold == 1);
                    double ratio = contrast (col, bg);
                    if (ratio < (large ? 3.0 : 4.5)) low_contrast = true;
                    if (f.size < min_size) small = true;
                    if (f.link != null && f.link != "" && vague_link (r.text)) vague = true;
                }
            }
            string snippet = st.plain_text ().strip ();
            if (snippet.char_count () > 32) snippet = snippet.substring (0, snippet.index_of_nth_char (32)) + "…";
            if (low_contrast) add (Severity.WARNING, IssueKind.CONTRAST, _("Text \"%s\" is hard to read against its background").printf (snippet), page, t.id);
            if (small) add (Severity.INFO, IssueKind.SMALL_TEXT, _("Text \"%s\" is smaller than %d pt").printf (snippet, (int) min_size), page, t.id);
            if (vague) add (Severity.INFO, IssueKind.LINK_TEXT, _("A hyperlink in \"%s\" does not describe its destination").printf (snippet), page, t.id);
        }
    }
}
