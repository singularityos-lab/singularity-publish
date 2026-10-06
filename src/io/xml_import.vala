namespace Singularity.Apps.Publish {

    public class XmlImport {
        public const string IGNORE = "-";
        public const string IMAGE = "@image";

        public Publication pub;
        public Gee.HashMap<string, string> map = new Gee.HashMap<string, string> ();
        public string base_dir = "";
        private Story story;
        private Paragraph? cur = null;

        public XmlImport (Publication pub) {
            this.pub = pub;
        }

        public static Gee.ArrayList<string> tags (string xml) throws Error {
            var list = new Gee.ArrayList<string> ();
            Xml.Doc* doc = NativeFormat.parse_keep_space (xml);
            collect (doc->get_root_element (), list);
            delete doc;
            return list;
        }

        private static void collect (Xml.Node* n, Gee.ArrayList<string> list) {
            for (Xml.Node* c = n; c != null; c = c->next) {
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                if (!list.contains (c->name)) list.add (c->name);
                collect (c->children, list);
            }
        }

        public void auto_map (Gee.List<string> tag_list) {
            foreach (string t in tag_list) {
                if (map.has_key (t)) continue;
                foreach (var ps in pub.styles.paragraph) if (ps.name.down () == t.down () || ps.name.down ().replace (" ", "") == t.down ().replace ("-", "").replace ("_", "")) map[t] = ps.name;
                if (map.has_key (t)) continue;
                foreach (var cs in pub.styles.character) if (cs.name.down () == t.down ()) map[t] = "char:" + cs.name;
                if (!map.has_key (t) && (t == "img" || t == "image" || t == "figure" || t == "graphic")) map[t] = IMAGE;
            }
        }

        public string serialize_map () {
            var keys = new Gee.ArrayList<string> ();
            keys.add_all (map.keys);
            keys.sort ();
            string[] parts = {};
            foreach (string k in keys) parts += "%s=%s".printf (Uri.escape_string (k, null, false), Uri.escape_string (map[k], null, false));
            return string.joinv (";", parts);
        }

        public void load_map (string s) {
            foreach (string part in s.split (";")) {
                int eq = part.index_of ("=");
                if (eq <= 0) continue;
                map[Uri.unescape_string (part.substring (0, eq)) ?? ""] = Uri.unescape_string (part.substring (eq + 1)) ?? "";
            }
        }

        private bool is_paragraph_style (string tag) {
            return map.has_key (tag) && map[tag] != IGNORE && map[tag] != IMAGE && !map[tag].has_prefix ("char:");
        }

        private void new_para (string style) {
            cur = new Paragraph (style);
            cur.runs.clear ();
            story.paras.add (cur);
        }

        private void add_text (string text, string cstyle) {
            string t = text.replace ("\r", "").replace ("\n", " ").replace ("\t", " ");
            while (t.contains ("  ")) t = t.replace ("  ", " ");
            if (t.strip () == "" && (cur == null || cur.runs.size == 0)) return;
            if (cur == null) new_para (StyleSheet.BASIC);
            var r = new Run (cur.runs.size == 0 ? t.chug () : t);
            r.cstyle = cstyle;
            cur.runs.add (r);
        }

        private void walk (Xml.Node* n, string cstyle) {
            for (Xml.Node* c = n; c != null; c = c->next) {
                if (c->type == Xml.ElementType.TEXT_NODE || c->type == Xml.ElementType.CDATA_SECTION_NODE) {
                    add_text (c->content ?? "", cstyle);
                    continue;
                }
                if (c->type != Xml.ElementType.ELEMENT_NODE) continue;
                string tag = c->name;
                string target = map.has_key (tag) ? map[tag] : "";
                if (target == IGNORE) continue;
                if (target == IMAGE) {
                    string? href = XmlIn.attr (c, "href") ?? XmlIn.attr (c, "src") ?? XmlIn.attr (c, "file");
                    if (href != null && href != "") {
                        string path = Path.is_absolute (href) || base_dir == "" ? href : Path.build_filename (base_dir, href);
                        var im = new ImageFrame ();
                        im.id = pub.next_id ();
                        im.link = path;
                        im.w = 200;
                        im.h = 120;
                        im.fit = FitMode.FIT;
                        im.alt_text = XmlIn.attr (c, "alt") ?? "";
                        if (cur == null || cur.runs.size > 0) new_para (StyleSheet.BASIC);
                        cur.runs.add (new Run.anchored (im, new AnchorSpec ()));
                        cur = null;
                    }
                    continue;
                }
                if (is_paragraph_style (tag)) {
                    new_para (target);
                    cur.anchor = XmlIn.attr (c, "id") ?? "";
                    walk (c->children, cstyle);
                    cur = null;
                    continue;
                }
                string cs = target.has_prefix ("char:") ? target.substring (5) : cstyle;
                walk (c->children, cs);
            }
        }

        public int run (string xml, Story target) throws Error {
            story = target;
            story.paras.clear ();
            Xml.Doc* doc = NativeFormat.parse_keep_space (xml);
            try {
                var root = doc->get_root_element ();
                walk (root, "");
            } finally {
                delete doc;
            }
            var keep = new Gee.ArrayList<Paragraph> ();
            foreach (var p in story.paras) {
                if (p.runs.size == 0) continue;
                var last = p.runs[p.runs.size - 1];
                if (last.anchor == null) last.text = last.text.chomp ();
                p.normalize ();
                keep.add (p);
            }
            story.paras.clear ();
            story.paras.add_all (keep);
            if (story.paras.size == 0) story.paras.add (new Paragraph.with_text (""));
            pub.xml_map = serialize_map ();
            return keep.size;
        }
    }
}
