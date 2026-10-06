namespace Singularity.Apps.Publish {

    public class IndexMarker {
        public const string PREFIX = "idx:";
        public const int PAGE = 0;
        public const int SEE = 1;
        public const int SEE_ALSO = 2;

        public string[] topics = {};
        public int kind = PAGE;
        public string target = "";
        public string sort_as = "";

        public string to_field () {
            var parts = new Gee.ArrayList<string> ();
            parts.add (kind.to_string ());
            parts.add (Uri.escape_string (target, null, false));
            parts.add (Uri.escape_string (sort_as, null, false));
            foreach (string t in topics) parts.add (Uri.escape_string (t, null, false));
            return PREFIX + string.joinv ("|", parts.to_array ());
        }

        public static IndexMarker? parse (string field) {
            if (!field.has_prefix (PREFIX)) return null;
            string[] parts = field.substring (PREFIX.length).split ("|");
            if (parts.length < 4) return null;
            var m = new IndexMarker ();
            m.kind = int.parse (parts[0]).clamp (0, 2);
            m.target = Uri.unescape_string (parts[1]) ?? "";
            m.sort_as = Uri.unescape_string (parts[2]) ?? "";
            string[] t = {};
            for (int i = 3; i < parts.length && t.length < 4; i++) {
                string v = (Uri.unescape_string (parts[i]) ?? "").strip ();
                if (v != "") t += v;
            }
            if (t.length == 0) return null;
            m.topics = t;
            return m;
        }

        public static string field_for (string[] topics, int kind = PAGE, string target = "") {
            var m = new IndexMarker ();
            m.topics = topics;
            m.kind = kind;
            m.target = target;
            return m.to_field ();
        }
    }

    public class IndexNode {
        public string name;
        public string sort_key = "";
        public Gee.TreeSet<int> pages = new Gee.TreeSet<int> ();
        public Gee.ArrayList<string> see = new Gee.ArrayList<string> ();
        public Gee.ArrayList<string> see_also = new Gee.ArrayList<string> ();
        public Gee.HashMap<string, IndexNode> children = new Gee.HashMap<string, IndexNode> ();

        public IndexNode (string name) {
            this.name = name;
        }

        public IndexNode child (string name) {
            if (!children.has_key (name)) children[name] = new IndexNode (name);
            return children[name];
        }
    }

    public class IndexSettings {
        public string title = "";
        public string language = "";
        public bool headings = true;
        public int story = 0;

        public IndexSettings clone () {
            var s = new IndexSettings ();
            s.title = title;
            s.language = language;
            s.headings = headings;
            s.story = story;
            return s;
        }

        public void write (XmlOut x) {
            x.start ("index").a ("title", title).a ("language", language).ai ("headings", headings ? 1 : 0).ai ("story", story).end ();
        }

        public static IndexSettings read (Xml.Node* n) {
            var s = new IndexSettings ();
            s.title = XmlIn.attr (n, "title") ?? "";
            s.language = XmlIn.attr (n, "language") ?? "";
            s.headings = XmlIn.int_attr (n, "headings", 1) == 1;
            s.story = XmlIn.int_attr (n, "story", 0);
            return s;
        }
    }

    public class IndexBuilder {
        public const string HEAD_STYLE = "Index Section Head";
        public const string RANGE_DASH = "\u2013";

        public static string[] languages () {
            return { "", "en_US", "it_IT", "de_DE", "fr_FR", "es_ES", "pt_PT", "nl_NL", "sv_SE", "da_DK", "nb_NO", "fi_FI", "pl_PL", "cs_CZ" };
        }

        public static string level_style (Publication pub, int level) {
            string name = _("Index Level %d").printf (level);
            if (pub.styles.find_paragraph (name) == null) {
                var st = new ParagraphStyle (name, StyleSheet.BASIC);
                st.para.left_indent = (level - 1) * 12 + 12;
                st.para.first_indent = -12;
                st.para.space_after = 1;
                pub.styles.paragraph.add (st);
            }
            return name;
        }

        public static string head_style (Publication pub) {
            if (pub.styles.find_paragraph (HEAD_STYLE) == null) {
                var st = new ParagraphStyle (HEAD_STYLE, StyleSheet.BASIC);
                st.chars.bold = 1;
                st.para.space_before = 8;
                st.para.space_after = 2;
                st.para.keep_next = 1;
                pub.styles.paragraph.add (st);
            }
            return HEAD_STYLE;
        }

        public static IndexNode collect (Publication pub, LayoutCache cache, int skip_story) {
            var root = new IndexNode ("");
            foreach (var st in pub.stories.values) {
                if (st.id == skip_story) continue;
                bool any = false;
                foreach (var p in st.paras) foreach (var r in p.runs) if (r.field.has_prefix (IndexMarker.PREFIX)) any = true;
                if (!any || pub.thread_frames (st.id).size == 0) continue;
                var res = cache.story (st.id);
                for (int pi = 0; pi < st.paras.size; pi++) {
                    int off = 0;
                    foreach (var r in st.paras[pi].runs) {
                        int len = r.length ();
                        var m = r.field != "" ? IndexMarker.parse (r.field) : null;
                        if (m != null) {
                            var node = root;
                            for (int k = 0; k < m.topics.length; k++) {
                                node = node.child (m.topics[k]);
                                if (m.sort_as != "" && k == m.topics.length - 1) node.sort_key = m.sort_as;
                            }
                            if (m.kind == IndexMarker.SEE && m.target != "" && !node.see.contains (m.target)) node.see.add (m.target);
                            else if (m.kind == IndexMarker.SEE_ALSO && m.target != "" && !node.see_also.contains (m.target)) node.see_also.add (m.target);
                            else if (m.kind == IndexMarker.PAGE) {
                                int page = page_of (res, pi, off);
                                if (page >= 0) node.pages.add (page);
                            }
                        }
                        off += len;
                    }
                }
            }
            return root;
        }

        private static int page_of (StoryResult res, int para, int offset) {
            foreach (var fr in res.frames) {
                foreach (var l in fr.lines) {
                    if (l.is_drop || l.para != para) continue;
                    if (offset >= l.start && (offset < l.end || l.para_last)) return fr.page_index;
                }
            }
            return -1;
        }

        public static string pages_text (Publication pub, Gee.SortedSet<int> pages) {
            var parts = new Gee.ArrayList<string> ();
            int run_start = -1, prev = -2;
            foreach (int p in pages) {
                if (p == prev + 1) {
                    prev = p;
                    continue;
                }
                if (run_start >= 0) parts.add (range (pub, run_start, prev));
                run_start = p;
                prev = p;
            }
            if (run_start >= 0) parts.add (range (pub, run_start, prev));
            return string.joinv (", ", parts.to_array ());
        }

        private static string range (Publication pub, int a, int b) {
            if (a == b) return pub.page_label (a);
            return pub.page_label (a) + RANGE_DASH + pub.page_label (b);
        }

        public static Gee.ArrayList<IndexNode> sorted (IndexNode n, string language) {
            var list = new Gee.ArrayList<IndexNode> ();
            list.add_all (n.children.values);
            string? saved = Intl.setlocale (LocaleCategory.COLLATE, null);
            if (language != "") {
                if (Intl.setlocale (LocaleCategory.COLLATE, language + ".UTF-8") == null) Intl.setlocale (LocaleCategory.COLLATE, language + ".utf8");
            }
            var keys = new Gee.HashMap<IndexNode, string> ();
            foreach (var c in list) {
                string base_text = c.sort_key != "" ? c.sort_key : c.name;
                keys[c] = sort_key (base_text, language) + "\x01" + base_text.casefold ().collate_key ();
            }
            list.sort ((a, b) => {
                int r = strcmp (keys[a], keys[b]);
                return r != 0 ? r : strcmp (a.name, b.name);
            });
            if (saved != null) Intl.setlocale (LocaleCategory.COLLATE, saved);
            return list;
        }

        private static string tail_letters (string language) {
            string l = language.length >= 2 ? language.substring (0, 2) : "";
            switch (l) {
                case "sv":
                case "fi": return "åäö";
                case "da":
                case "nb":
                case "no": return "æøå";
                case "es": return "";
                case "pl": return "";
                default: return "";
            }
        }

        public static string sort_key (string text, string language) {
            string tail = tail_letters (language);
            bool spanish = language.has_prefix ("es");
            var sb = new StringBuilder ();
            unichar c;
            int i = 0;
            string folded = text.down ();
            while (folded.get_next_char (ref i, out c)) {
                int t = tail.index_of_char (c);
                if (t >= 0) {
                    sb.append_c ('{');
                    sb.append_c ((char) ('a' + tail.substring (0, t).char_count ()));
                    continue;
                }
                if (spanish && c == 0x00F1) {
                    sb.append ("n{");
                    continue;
                }
                string d = c.to_string ().normalize (-1, NormalizeMode.NFD);
                unichar b = d.get_char (0);
                if (b.isalnum ()) sb.append_unichar (b);
                else if (b.isspace ()) sb.append_c (' ');
            }
            return sb.str;
        }

        public static string group_letter (IndexNode n, string language = "") {
            string s = (n.sort_key != "" ? n.sort_key : n.name).strip ();
            if (s == "") return "#";
            unichar first = s.down ().get_char (0);
            if (tail_letters (language).index_of_char (first) >= 0 || (language.has_prefix ("es") && first == 0x00F1)) return first.toupper ().to_string ();
            string norm = s.normalize (-1, NormalizeMode.NFD);
            unichar b = norm.get_char (0);
            if (!b.isalpha ()) return _("Symbols");
            return b.toupper ().to_string ();
        }

        public static void fill (Publication pub, IndexSettings s, Story story, IndexNode root) {
            story.paras.clear ();
            if (s.title != "") story.paras.add (new Paragraph.with_text (s.title, pub.styles.find_paragraph ("Heading 2") != null ? "Heading 2" : head_style (pub)));
            string last_group = "";
            foreach (var n in sorted (root, s.language)) {
                if (s.headings) {
                    string g = group_letter (n, s.language);
                    if (g != last_group) {
                        story.paras.add (new Paragraph.with_text (g, head_style (pub)));
                        last_group = g;
                    }
                }
                emit (pub, s, story, n, 1);
            }
            if (story.paras.size == 0) story.paras.add (new Paragraph.with_text (_("No index entries yet"), StyleSheet.BASIC));
        }

        private static void emit (Publication pub, IndexSettings s, Story story, IndexNode n, int level) {
            var sb = new StringBuilder (n.name);
            string pages = pages_text (pub, n.pages);
            if (pages != "") sb.append (", " + pages);
            if (n.see.size > 0) sb.append (". " + _("See %s").printf (string.joinv ("; ", n.see.to_array ())));
            if (n.see_also.size > 0) sb.append (". " + _("See also %s").printf (string.joinv ("; ", n.see_also.to_array ())));
            story.paras.add (new Paragraph.with_text (sb.str, level_style (pub, level)));
            foreach (var c in sorted (n, s.language)) emit (pub, s, story, c, int.min (level + 1, 4));
        }

        public static int generate (Publication pub, IndexSettings s) {
            if (s.story == 0 || !pub.stories.has_key (s.story) || pub.thread_frames (s.story).size == 0) {
                string master = pub.pages.size > 0 ? pub.pages[pub.pages.size - 1].master : (pub.masters.size > 0 ? pub.masters[0].id : "");
                var pg = pub.add_page (-1, master);
                int pi = pub.pages.index_of (pg);
                var m = pub.margin_rect (pi);
                var frame = pub.add_text_frame (pg.items, m.x, m.y, m.w, m.h);
                frame.columns = 2;
                frame.name = _("Index");
                s.story = frame.story;
            }
            var cache = new LayoutCache (pub);
            var root = collect (pub, cache, s.story);
            fill (pub, s, pub.story (s.story), root);
            pub.index = s;
            return root.children.size;
        }
    }
}
