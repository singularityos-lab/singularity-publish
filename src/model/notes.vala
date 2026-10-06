namespace Singularity.Apps.Publish {

    public class FootnoteOptions {
        public const string STYLE = "Footnote";
        public const string FIELD = "footnote";
        public const string END_FIELD = "endnote";
        public const string END_STYLE = "Endnote";

        public int numbering = 0;
        public int start = 1;
        public int restart = 0;
        public string para_style = STYLE;
        public string ref_style = "";
        public string prefix = "";
        public string suffix = "";
        public string separator_text = "\u2002";
        public bool rule = true;
        public double rule_weight = 0.5;
        public double rule_length = 72;
        public string rule_color = ColorRef.BLACK;
        public double space_before = 8;
        public double space_between = 2;
        public bool split = true;

        public FootnoteOptions clone () {
            var o = new FootnoteOptions ();
            o.numbering = numbering;
            o.start = start;
            o.restart = restart;
            o.para_style = para_style;
            o.ref_style = ref_style;
            o.prefix = prefix;
            o.suffix = suffix;
            o.separator_text = separator_text;
            o.rule = rule;
            o.rule_weight = rule_weight;
            o.rule_length = rule_length;
            o.rule_color = rule_color;
            o.space_before = space_before;
            o.space_between = space_between;
            o.split = split;
            return o;
        }

        public bool is_default () {
            var d = new FootnoteOptions ();
            return numbering == d.numbering && start == d.start && restart == d.restart && para_style == d.para_style && ref_style == d.ref_style && prefix == d.prefix && suffix == d.suffix && separator_text == d.separator_text && rule == d.rule && rule_weight == d.rule_weight && rule_length == d.rule_length && rule_color == d.rule_color && space_before == d.space_before && space_between == d.space_between && split == d.split;
        }

        public string format (int n) {
            switch (numbering) {
                case 1: return NumberFormat.roman (n).down ();
                case 2: return NumberFormat.roman (n);
                case 3: return NumberFormat.alpha (n).down ();
                case 4: return NumberFormat.alpha (n);
                case 5:
                    string[] marks = { "*", "†", "‡", "§", "‖", "¶" };
                    int k = (n - 1) % marks.length;
                    int times = (n - 1) / marks.length + 1;
                    var sb = new StringBuilder ();
                    for (int i = 0; i < times; i++) sb.append (marks[k]);
                    return sb.str;
                default: return n.to_string ();
            }
        }

        public static string[] numbering_labels () {
            return { "1, 2, 3", "i, ii, iii", "I, II, III", "a, b, c", "A, B, C", "*, †, ‡" };
        }

        public static string[] restart_labels () {
            return { _("Never"), _("Every Page"), _("Every Section"), _("Every Story") };
        }

        public void write (XmlOut x) {
            x.start ("footnotes").ai ("numbering", numbering).ai ("start", start).ai ("restart", restart).a ("para-style", para_style).a ("ref-style", ref_style);
            x.a ("prefix", prefix).a ("suffix", suffix).a ("separator", separator_text).ai ("rule", rule ? 1 : 0).ad ("rule-weight", rule_weight).ad ("rule-length", rule_length).a ("rule-color", rule_color);
            x.ad ("space-before", space_before).ad ("space-between", space_between).ai ("split", split ? 1 : 0);
            x.end ();
        }

        public static FootnoteOptions read (Xml.Node* n) {
            var o = new FootnoteOptions ();
            if (n == null) return o;
            o.numbering = XmlIn.int_attr (n, "numbering", 0);
            o.start = XmlIn.int_attr (n, "start", 1);
            o.restart = XmlIn.int_attr (n, "restart", 0);
            o.para_style = XmlIn.attr (n, "para-style") ?? STYLE;
            o.ref_style = XmlIn.attr (n, "ref-style") ?? "";
            o.prefix = XmlIn.attr (n, "prefix") ?? "";
            o.suffix = XmlIn.attr (n, "suffix") ?? "";
            o.separator_text = XmlIn.attr (n, "separator") ?? "\u2002";
            o.rule = XmlIn.int_attr (n, "rule", 1) == 1;
            o.rule_weight = XmlIn.double_attr (n, "rule-weight", 0.5);
            o.rule_length = XmlIn.double_attr (n, "rule-length", 72);
            o.rule_color = XmlIn.attr (n, "rule-color") ?? ColorRef.BLACK;
            o.space_before = XmlIn.double_attr (n, "space-before", 8);
            o.space_between = XmlIn.double_attr (n, "space-between", 2);
            o.split = XmlIn.int_attr (n, "split", 1) == 1;
            return o;
        }
    }

    public class NoteRef {
        public int disp;
        public Story note;
        public int number;

        public NoteRef (int disp, Story note, int number) {
            this.disp = disp;
            this.note = note;
            this.number = number;
        }
    }

    public class Footnotes {
        public static void ensure_style (Publication pub) {
            if (pub.styles.find_paragraph (FootnoteOptions.STYLE) != null) return;
            var s = new ParagraphStyle (FootnoteOptions.STYLE);
            s.based_on = StyleSheet.BASIC;
            s.chars.size = 8;
            s.para.leading = 10;
            s.para.space_after = 1;
            pub.styles.paragraph.add (s);
        }

        public static Run make_endnote (Publication pub, string text) {
            if (pub.styles.find_paragraph (FootnoteOptions.END_STYLE) == null) {
                var s = new ParagraphStyle (FootnoteOptions.END_STYLE);
                s.based_on = StyleSheet.BASIC;
                s.chars.size = 9;
                s.para.space_after = 3;
                pub.styles.paragraph.add (s);
            }
            var r = new Run.field_run (FootnoteOptions.END_FIELD);
            r.note = new Story.from_text (0, text, FootnoteOptions.END_STYLE);
            return r;
        }

        public static bool is_endnote (Run r) {
            return r.note != null && r.field == FootnoteOptions.END_FIELD;
        }

        public static Gee.HashMap<Story, int> number_endnotes (Publication pub) {
            var map = new Gee.HashMap<Story, int> ();
            int n = 0;
            foreach (var st in stories_in_order (pub)) {
                if (st.id == pub.endnote_story) continue;
                foreach (var p in st.paras) foreach (var r in p.runs) if (is_endnote (r)) map[r.note] = ++n;
            }
            return map;
        }

        public static int update_endnotes (Publication pub, string heading) {
            var nums = number_endnotes (pub);
            var ordered = new Gee.ArrayList<Story> ();
            foreach (var st in stories_in_order (pub)) {
                if (st.id == pub.endnote_story) continue;
                foreach (var p in st.paras) foreach (var r in p.runs) if (is_endnote (r)) ordered.add (r.note);
            }
            if (ordered.size == 0 && pub.endnote_story == 0) return 0;
            Story target;
            if (pub.endnote_story == 0 || !pub.stories.has_key (pub.endnote_story) || pub.thread_frames (pub.endnote_story).size == 0) {
                string master = pub.pages.size > 0 ? pub.pages[pub.pages.size - 1].master : (pub.masters.size > 0 ? pub.masters[0].id : "");
                var pg = pub.add_page (-1, master);
                int pi = pub.pages.index_of (pg);
                var m = pub.margin_rect (pi);
                var frame = pub.add_text_frame (pg.items, m.x, m.y, m.w, m.h);
                pub.endnote_story = frame.story;
                frame.name = _("Endnotes");
            }
            target = pub.story (pub.endnote_story);
            target.paras.clear ();
            var head = new Paragraph.with_text (heading, pub.styles.find_paragraph ("Heading 2") != null ? "Heading 2" : StyleSheet.BASIC);
            if (head.style == StyleSheet.BASIC) head.runs[0].fmt.bold = 1;
            target.paras.add (head);
            foreach (var note in ordered) {
                bool first = true;
                foreach (var np in note.paras) {
                    var para = np.clone ();
                    if (para.style == StyleSheet.BASIC) para.style = FootnoteOptions.END_STYLE;
                    if (first) para.runs.insert (0, new Run ("%d.\u2002".printf (nums[note])));
                    first = false;
                    target.paras.add (para);
                }
            }
            return ordered.size;
        }

        public static Run make_run (Publication pub, string text) {
            ensure_style (pub);
            var note = new Story.from_text (0, text, pub.footnotes.para_style);
            var r = new Run.field_run (FootnoteOptions.FIELD);
            r.note = note;
            return r;
        }

        public static Gee.ArrayList<Story> stories_in_order (Publication pub) {
            var list = new Gee.ArrayList<Story> ();
            var seen = new Gee.HashSet<int> ();
            for (int pi = 0; pi < pub.pages.size; pi++) {
                var frames = new Gee.ArrayList<TextFrame> ();
                pub.walk ((r) => {
                    var t = r.item as TextFrame;
                    if (t != null && r.page == pub.pages[pi]) frames.add (t);
                    return true;
                });
                frames.sort ((a, b) => {
                    if (Math.fabs (a.y - b.y) > 1) return a.y < b.y ? -1 : 1;
                    return a.x < b.x ? -1 : (a.x > b.x ? 1 : 0);
                });
                foreach (var t in frames) {
                    if (!seen.add (t.story) || !pub.stories.has_key (t.story)) continue;
                    list.add (pub.stories[t.story]);
                }
            }
            foreach (var s in pub.stories.values) if (seen.add (s.id)) list.add (s);
            return list;
        }

        public static Gee.HashMap<Story, int> number_all (Publication pub, Gee.Map<Story, int>? pages = null) {
            var map = new Gee.HashMap<Story, int> ();
            var o = pub.footnotes;
            int n = o.start - 1;
            int last_section = -1, last_page = -2;
            foreach (var st in stories_in_order (pub)) {
                if (o.restart == 3) n = o.start - 1;
                foreach (var p in st.paras) foreach (var r in p.runs) {
                    if (r.note == null || is_endnote (r)) continue;
                    if (pages != null && pages.has_key (r.note)) {
                        int pg = pages[r.note];
                        if (o.restart == 1 && pg != last_page) n = o.start - 1;
                        if (o.restart == 2) {
                            int sec = pub.sections.index_of (pub.section_for (pg));
                            if (sec != last_section) n = o.start - 1;
                            last_section = sec;
                        }
                        last_page = pg;
                    }
                    n++;
                    map[r.note] = n;
                }
            }
            return map;
        }

        public static Story prepared (Publication pub, Story note, int number) {
            var s = note.clone ();
            var o = pub.footnotes;
            if (s.paras.size == 0) s.paras.add (new Paragraph.with_text ("", o.para_style));
            foreach (var p in s.paras) if (p.style == StyleSheet.BASIC && pub.styles.find_paragraph (o.para_style) != null) p.style = o.para_style;
            var first = s.paras[0];
            var mark = new Run (o.prefix + o.format (number) + o.suffix + o.separator_text);
            if (o.ref_style != "") mark.cstyle = o.ref_style;
            first.runs.insert (0, mark);
            return s;
        }

        public static int count (Story st) {
            int n = 0;
            foreach (var p in st.paras) foreach (var r in p.runs) if (r.note != null) n++;
            return n;
        }
    }
}
