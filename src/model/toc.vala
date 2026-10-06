namespace Singularity.Apps.Publish {

    public class TocLevel {
        public string style;
        public int level;
        public string entry_style;

        public TocLevel (string style, int level, string entry_style) {
            this.style = style;
            this.level = level;
            this.entry_style = entry_style;
        }
    }

    public class TocEntry {
        public int level;
        public string text;
        public int page;
        public string entry_style;

        public TocEntry (int level, string text, int page, string entry_style) {
            this.level = level;
            this.text = text;
            this.page = page;
            this.entry_style = entry_style;
        }
    }

    public class TocSettings {
        public string title = "";
        public string title_style = "";
        public bool page_numbers = true;
        public string leader = ".";
        public int story = 0;
        public Gee.ArrayList<TocLevel> levels = new Gee.ArrayList<TocLevel> ();

        public TocSettings clone () {
            var t = new TocSettings ();
            t.title = title;
            t.title_style = title_style;
            t.page_numbers = page_numbers;
            t.leader = leader;
            t.story = story;
            foreach (var l in levels) t.levels.add (new TocLevel (l.style, l.level, l.entry_style));
            return t;
        }

        public TocLevel? level_for (string style) {
            foreach (var l in levels) if (l.style == style) return l;
            return null;
        }

        public void write (XmlOut x) {
            x.start ("toc").a ("title", title).a ("title-style", title_style).ai ("page-numbers", page_numbers ? 1 : 0).a ("leader", leader).ai ("story", story);
            foreach (var l in levels) x.start ("level").a ("style", l.style).ai ("level", l.level).a ("entry-style", l.entry_style).end ();
            x.end ();
        }

        public static TocSettings read (Xml.Node* n) {
            var t = new TocSettings ();
            t.title = XmlIn.attr (n, "title") ?? "";
            t.title_style = XmlIn.attr (n, "title-style") ?? "";
            t.page_numbers = XmlIn.int_attr (n, "page-numbers", 1) == 1;
            t.leader = XmlIn.attr (n, "leader") ?? ".";
            t.story = XmlIn.int_attr (n, "story", 0);
            foreach (var ln in XmlIn.elements (n, "level")) t.levels.add (new TocLevel (XmlIn.attr (ln, "style") ?? "", XmlIn.int_attr (ln, "level", 1), XmlIn.attr (ln, "entry-style") ?? ""));
            return t;
        }
    }

    public class Toc {
        public static Gee.ArrayList<TocEntry> collect (Publication pub, TocSettings s, LayoutCache cache) {
            var list = new Gee.ArrayList<TocEntry> ();
            var seen = new Gee.HashSet<string> ();
            for (int pi = 0; pi < pub.pages.size; pi++) {
                var frames = new Gee.ArrayList<TextFrame> ();
                foreach (var it in pub.pages[pi].items) {
                    var t = it as TextFrame;
                    if (t != null && t.story != s.story) frames.add (t);
                }
                frames.sort ((a, b) => {
                    if (Math.fabs (a.y - b.y) > 2) return a.y < b.y ? -1 : 1;
                    return a.x < b.x ? -1 : (a.x > b.x ? 1 : 0);
                });
                foreach (var t in frames) {
                    var fr = cache.story (t.story).frame_result (t.id);
                    if (fr == null) continue;
                    var st = pub.story (t.story);
                    foreach (var l in fr.lines) {
                        if (l.is_drop || l.para < 0 || l.para >= st.paras.size) continue;
                        string key = "%d:%d".printf (t.story, l.para);
                        if (seen.contains (key)) continue;
                        var para = st.paras[l.para];
                        var lv = s.level_for (para.style);
                        if (lv == null) continue;
                        seen.add (key);
                        string text = para.text ().replace (OBJ_STR, "").replace (" ", " ").strip ();
                        if (text == "") continue;
                        list.add (new TocEntry (lv.level, text, pi, lv.entry_style));
                    }
                }
            }
            return list;
        }

        public static string entry_style_for (Publication pub, int level) {
            string name = _("TOC Level %d").printf (level);
            var st = pub.styles.find_paragraph (name);
            if (st == null) {
                st = new ParagraphStyle (name, StyleSheet.BASIC);
                st.para.left_indent = (level - 1) * 14;
                if (level == 1) st.chars.bold = 1;
                st.para.space_after = 3;
                pub.styles.paragraph.add (st);
            }
            return name;
        }

        public static void fill_story (Publication pub, TocSettings s, Story story, Gee.List<TocEntry> entries, double width) {
            story.paras.clear ();
            if (s.title != "") {
                string ts = s.title_style != "" && pub.styles.find_paragraph (s.title_style) != null ? s.title_style : (pub.styles.find_paragraph ("Heading 2") != null ? "Heading 2" : StyleSheet.BASIC);
                story.paras.add (new Paragraph.with_text (s.title, ts));
            }
            foreach (var e in entries) {
                string style = e.entry_style != "" && pub.styles.find_paragraph (e.entry_style) != null ? e.entry_style : entry_style_for (pub, e.level);
                var para = new Paragraph (style);
                para.runs.clear ();
                para.runs.add (new Run (e.text));
                if (s.page_numbers) {
                    para.runs.add (new Run ("\t" + pub.page_label (e.page)));
                    var tabs = new Gee.ArrayList<TabStop> ();
                    tabs.add (new TabStop (double.max (20, width - 1), TabKind.RIGHT, s.leader));
                    para.fmt.tabs = TabStop.serialize (tabs);
                }
                story.paras.add (para);
            }
            if (story.paras.size == 0) story.paras.add (new Paragraph.with_text (_("No entries: apply the chosen paragraph styles to headings"), StyleSheet.BASIC));
        }

        public static TextFrame? frame_of (Publication pub, int story_id) {
            if (story_id == 0 || !pub.stories.has_key (story_id)) return null;
            var st = pub.story (story_id);
            if (st.frames.size == 0) return null;
            var r = pub.find_item (st.frames[0]);
            return r != null ? r.item as TextFrame : null;
        }

        public static int update (Publication pub, TocSettings s) {
            var frame = frame_of (pub, s.story);
            if (frame == null) return -1;
            var cache = new LayoutCache (pub);
            var entries = collect (pub, s, cache);
            double width = frame.w - frame.inset_left - frame.inset_right;
            if (frame.columns > 1) width = (width - frame.gutter * (frame.columns - 1)) / frame.columns;
            fill_story (pub, s, pub.story (s.story), entries, width);
            return entries.size;
        }
    }
}
