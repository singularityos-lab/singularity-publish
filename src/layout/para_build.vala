namespace Singularity.Apps.Publish {

    public class Span {
        public int start;
        public int end;
        public CharFormat fmt;

        public Span (int start, int end, CharFormat fmt) {
            this.start = start;
            this.end = end;
            this.fmt = fmt;
        }
    }

    public class ListCounter {
        public int[] counts = new int[9];
        public bool active = false;

        public void reset () {
            for (int i = 0; i < 9; i++) counts[i] = 0;
            active = false;
        }
    }

    public class AnchorRef {
        public int disp;
        public Item item;
        public AnchorSpec spec;

        public AnchorRef (int disp, Item item, AnchorSpec spec) {
            this.disp = disp;
            this.item = item;
            this.spec = spec;
        }
    }

    public class ParaBuild {
        public Gee.ArrayList<AnchorRef> anchors = new Gee.ArrayList<AnchorRef> ();
        public Gee.ArrayList<NoteRef> notes = new Gee.ArrayList<NoteRef> ();
        public int para_index;
        public ParaFormat pf;
        public CharFormat base_cf;
        public string text = "";
        public Gee.ArrayList<Span> spans = new Gee.ArrayList<Span> ();
        public int[] story_to_disp = {};
        public int[] disp_story = {};
        public int prefix_bytes = 0;
        public int length_chars = 0;
        public int drop_bytes = 0;
        public double max_size = 0;
        public bool has_prefix_tab = false;
        public double scale = 1;

        public int disp_of (int story_offset) {
            if (story_to_disp.length == 0) return prefix_bytes;
            return story_to_disp[story_offset.clamp (0, story_to_disp.length - 1)];
        }

        public int story_of (int disp) {
            if (disp <= prefix_bytes) return 0;
            if (disp >= text.length) return length_chars;
            int d = disp.clamp (0, disp_story.length - 1);
            while (d > 0 && disp_story[d] < 0) d--;
            return disp_story[d] < 0 ? 0 : disp_story[d];
        }

        public static string list_marker (ParaFormat pf, int number) {
            if (pf.list_type == 1) return pf.bullet != null && pf.bullet != "" ? pf.bullet : "•";
            switch (pf.number_format) {
                case 1: return "%d)".printf (number);
                case 2: return NumberFormat.alpha (number).down () + ".";
                case 3: return NumberFormat.alpha (number) + ".";
                case 4: return NumberFormat.roman (number).down () + ".";
                case 5: return NumberFormat.roman (number) + ".";
                default: return "%d.".printf (number);
            }
        }

        public static ParaBuild build (Publication pub, Paragraph p, int index, FieldContext fc, ListCounter counter, bool hyphenate_on, double scale = 1) {
            var b = new ParaBuild ();
            b.para_index = index;
            var pf = ParaFormat.defaults ();
            var cf = CharFormat.defaults ();
            pub.styles.resolve_paragraph (p.style, pf, cf);
            pf.apply (p.fmt);
            if (pf.direction == 1 && pf.align <= 0) pf.align = (int) TextAlign.RIGHT;
            b.scale = scale;
            if (Math.fabs (scale - 1) > 1e-6) {
                if (pf.leading > 0.01) pf.leading *= scale;
                pf.space_before *= scale;
                pf.space_after *= scale;
                cf.size *= scale;
            }
            b.pf = pf;
            b.base_cf = cf;
            var sb = new StringBuilder ();
            var map = new Gee.ArrayList<int> ();
            var owners = new Gee.ArrayList<int> ();
            if (pf.list_type > 0) {
                int level = pf.list_level.clamp (0, 8);
                if (pf.list_type == 2) {
                    if (!counter.active) counter.reset ();
                    counter.active = true;
                    if (p.fmt.number_start >= 0) counter.counts[level] = p.fmt.number_start - 1;
                    else if (counter.counts[level] == 0 && pf.number_start > 1) counter.counts[level] = pf.number_start - 1;
                    counter.counts[level]++;
                    for (int l = level + 1; l < 9; l++) counter.counts[l] = 0;
                } else {
                    counter.active = false;
                }
                string marker = list_marker (pf, pf.list_type == 2 ? counter.counts[level] : 0);
                var first_fmt = cf.clone ();
                if (p.runs.size > 0) {
                    var rf = resolve_run (pub, cf, p.runs[0], scale);
                    first_fmt.font = rf.font;
                    first_fmt.size = rf.size;
                    first_fmt.color = rf.color;
                }
                string prefix = marker + "\t";
                b.has_prefix_tab = true;
                sb.append (prefix);
                b.spans.add (new Span (0, prefix.length, first_fmt));
                for (int i = 0; i < prefix.length; i++) owners.add (-1);
                b.prefix_bytes = prefix.length;
            } else {
                counter.active = false;
                if (pf.list_type == 0) counter.reset ();
            }
            int story_off = 0;
            foreach (var r in p.runs) {
                var rf = resolve_run (pub, cf, r, scale);
                b.max_size = double.max (b.max_size, rf.size);
                int start = (int) sb.len;
                if (r.condition != "" && Conditions.hidden (pub, r.condition)) {
                    int n = r.length ();
                    for (int i = 0; i < n; i++) {
                        map.add ((int) sb.len);
                        story_off++;
                    }
                    continue;
                }
                if (r.anchor != null && r.anchor_spec != null) {
                    map.add ((int) sb.len);
                    b.anchors.add (new AnchorRef ((int) sb.len, r.anchor, r.anchor_spec));
                    sb.append ("\uFFFC");
                    for (int i = 0; i < 3; i++) owners.add (story_off);
                    story_off++;
                } else if (r.note != null) {
                    bool endnote = r.field == FootnoteOptions.END_FIELD;
                    int number = endnote ? fc.endnote_number (r.note) : fc.note_number (r.note);
                    var o = pub.footnotes;
                    string v = endnote ? number.to_string () : o.prefix + o.format (number) + o.suffix;
                    map.add ((int) sb.len);
                    if (!endnote) b.notes.add (new NoteRef ((int) sb.len, r.note, number));
                    sb.append (v);
                    for (int i = 0; i < v.length; i++) owners.add (story_off);
                    story_off++;
                    var nf = rf.clone ();
                    if (o.ref_style != "") pub.styles.resolve_character (o.ref_style, nf);
                    else nf.position = 1;
                    b.spans.add (new Span (start, (int) sb.len, nf));
                    continue;
                } else if (r.field != "") {
                    string v = fc.resolve (r.field);
                    if (v == "") v = "\u200B";
                    map.add ((int) sb.len);
                    sb.append (v);
                    for (int i = 0; i < v.length; i++) owners.add (story_off);
                    story_off++;
                    if (r.field.has_prefix (Fields.XREF_PREFIX)) {
                        int target = fc.xref_page (r.field);
                        if (target >= 0 && (rf.link == null || rf.link == "")) {
                            var lf = rf.clone ();
                            lf.link = "page:%d".printf (target);
                            b.spans.add (new Span (start, (int) sb.len, lf));
                            continue;
                        }
                    }
                } else {
                    unichar c;
                    int i = 0;
                    while (r.text.get_next_char (ref i, out c)) {
                        map.add ((int) sb.len);
                        int before = (int) sb.len;
                        if (c == OBJ_CHAR) sb.append ("\u200B");
                        else sb.append_unichar (c);
                        for (int k = before; k < sb.len; k++) owners.add (story_off);
                        story_off++;
                    }
                }
                if (sb.len > start) b.spans.add (new Span (start, (int) sb.len, rf));
            }
            map.add ((int) sb.len);
            if (b.max_size <= 0) b.max_size = cf.size;
            b.length_chars = story_off;
            b.text = sb.str;
            b.story_to_disp = map.to_array ();
            b.disp_story = owners.to_array ();
            var overlays = StyleRules.overlays (pub, p.style, b.text, b.prefix_bytes);
            if (overlays.size > 0) b.apply_overlays (pub, overlays);
            if (hyphenate_on && pf.hyphenate == 1) b.insert_hyphens (cf.lang ?? "en", pub.hyph_exceptions);
            if (pf.drop_lines >= 2 && pf.drop_chars > 0 && b.length_chars > 0) {
                int n = int.min (pf.drop_chars, b.length_chars);
                b.drop_bytes = b.disp_of (n) - b.prefix_bytes;
            }
            return b;
        }

        private void apply_overlays (Publication pub, Gee.List<StyleOverlay> overlays) {
            var cuts = new Gee.TreeSet<int> ();
            foreach (var sp in spans) {
                cuts.add (sp.start);
                cuts.add (sp.end);
            }
            foreach (var o in overlays) {
                cuts.add (o.start.clamp (0, text.length));
                cuts.add (o.end.clamp (0, text.length));
            }
            var result = new Gee.ArrayList<Span> ();
            foreach (var sp in spans) {
                int a = sp.start;
                foreach (int c in cuts) {
                    if (c <= a || c > sp.end) continue;
                    var f = sp.fmt;
                    foreach (var o in overlays) {
                        if (o.start <= a && o.end >= c) {
                            f = f.clone ();
                            var own = new CharFormat ();
                            pub.styles.resolve_character (o.cstyle, own);
                            f.apply (own);
                            if (!own.size.is_nan ()) max_size = double.max (max_size, f.size);
                        }
                    }
                    result.add (new Span (a, c, f));
                    a = c;
                }
                if (a < sp.end) result.add (new Span (a, sp.end, sp.fmt));
            }
            spans = result;
        }

        public static CharFormat resolve_run (Publication pub, CharFormat para_cf, Run r, double scale = 1) {
            var f = para_cf.clone ();
            if (r.cstyle != "") pub.styles.resolve_character (r.cstyle, f);
            if (Math.fabs (scale - 1) > 1e-6) {
                var own = new CharFormat ();
                if (r.cstyle != "") pub.styles.resolve_character (r.cstyle, own);
                own.apply (r.fmt);
                if (!own.size.is_nan ()) f.size = own.size * scale;
                var rest = r.fmt.clone ();
                rest.size = double.NAN;
                f.apply (rest);
                if (!f.baseline_shift.is_nan ()) f.baseline_shift *= scale;
                return f;
            }
            f.apply (r.fmt);
            return f;
        }

        private void insert_hyphens (string lang, Gee.Map<string, string> doc_exceptions) {
            var h = Hyphenator.for_language (lang);
            if (h == null && doc_exceptions.size == 0) return;
            int lmin = pf.hyph_before > 0 ? pf.hyph_before : 2;
            int rmin = pf.hyph_after > 0 ? pf.hyph_after : 2;
            int minw = pf.hyph_min_word > 0 ? pf.hyph_min_word : 5;
            bool caps = pf.hyph_caps != 0;
            var sb = new StringBuilder ();
            var owners = new Gee.ArrayList<int> ();
            int[] old_to_new = new int[text.length + 1];
            int i = 0;
            int n = text.length;
            while (i < n) {
                unichar c = text.get_char (i);
                if (c.isalpha () && i >= prefix_bytes) {
                    int j = i;
                    while (j < n) {
                        unichar d = text.get_char (j);
                        if (!d.isalpha ()) break;
                        j += d.to_utf8 (null);
                    }
                    string word = text.substring (i, j - i);
                    int[] pts = {};
                    string low = word.down ();
                    if (doc_exceptions.has_key (low)) pts = Hyphenator.explicit_points (doc_exceptions[low]);
                    else if (h != null && (caps || !word.get_char (0).isupper ())) pts = h.points_with (word, lmin, rmin, minw);
                    int ci = 0;
                    int pi = 0;
                    int k = i;
                    while (k < j) {
                        if (pi < pts.length && pts[pi] == ci) {
                            sb.append ("\u00AD");
                            for (int q = 0; q < 2; q++) owners.add (disp_story[k]);
                            pi++;
                        }
                        unichar d = text.get_char (k);
                        int len = d.to_utf8 (null);
                        for (int q = 0; q < len; q++) {
                            old_to_new[k + q] = (int) sb.len + q;
                            owners.add (disp_story[k + q]);
                        }
                        sb.append_unichar (d);
                        k += len;
                        ci++;
                    }
                    i = j;
                    continue;
                }
                int clen = c.to_utf8 (null);
                for (int q = 0; q < clen; q++) {
                    old_to_new[i + q] = (int) sb.len + q;
                    owners.add (disp_story[i + q]);
                }
                sb.append_unichar (c);
                i += clen;
            }
            old_to_new[n] = (int) sb.len;
            if (sb.len == text.length) return;
            for (int m = 0; m < story_to_disp.length; m++) story_to_disp[m] = old_to_new[story_to_disp[m]];
            foreach (var s in spans) {
                s.start = old_to_new[s.start];
                s.end = old_to_new[s.end];
            }
            foreach (var ar in anchors) ar.disp = old_to_new[ar.disp];
            foreach (var nr in notes) nr.disp = old_to_new[nr.disp];
            text = sb.str;
            disp_story = owners.to_array ();
        }
    }
}
