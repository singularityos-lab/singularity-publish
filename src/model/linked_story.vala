namespace Singularity.Apps.Publish {

    public class LinkedStory {
        public const string EXT = "sstory";
        public const string ROOT = "publish-story";

        public static string to_xml (Publication pub, Story st) {
            var x = new XmlOut ();
            x.start (ROOT).ai ("version", 1);
            x.start ("styles");
            var used = new Gee.HashSet<string> ();
            foreach (var p in st.paras) foreach (var s in pub.styles.para_chain (p.style)) used.add (s.name);
            foreach (var ps in pub.styles.paragraph) {
                if (!used.contains (ps.name)) continue;
                x.start ("paragraph-style").a ("name", ps.name).a ("based-on", ps.based_on);
                ps.para.write (x);
                x.start ("chars");
                ps.chars.write (x);
                x.end ();
                x.end ();
            }
            x.end ();
            x.start ("text");
            NativeFormat.write_paras (x, st);
            x.end ();
            x.end ();
            return x.finish ();
        }

        public static void read_into (Publication pub, Story st, string xml) throws Error {
            Xml.Doc* doc = NativeFormat.parse_keep_space (xml);
            try {
                var root = doc->get_root_element ();
                if (root->name != ROOT) throw new FormatError.INVALID (_("This is not a Publish story file."));
                foreach (var pn in XmlIn.elements (XmlIn.child (root, "styles"), "paragraph-style")) {
                    string name = XmlIn.attr (pn, "name") ?? "";
                    if (name == "" || pub.styles.find_paragraph (name) != null) continue;
                    var ps = new ParagraphStyle (name, XmlIn.attr (pn, "based-on") ?? "");
                    ps.para = ParaFormat.read (pn);
                    var cn = XmlIn.child (pn, "chars");
                    if (cn != null) ps.chars = CharFormat.read (cn);
                    pub.styles.paragraph.add (ps);
                }
                var tn = XmlIn.child (root, "text");
                if (tn == null) throw new FormatError.INVALID (_("The story file has no text."));
                NativeFormat.read_paras (tn, st);
            } finally {
                delete doc;
            }
        }

        public static void export (Publication pub, Story st, string path) throws Error {
            FileUtils.set_contents (path, to_xml (pub, st));
            st.link_path = path;
            st.link_stamp = ImageStore.stamp_for (path);
        }

        public static bool modified (Publication pub, Story st) {
            if (st.link_path == "") return false;
            string p = ImageStore.resolve_link (pub, st.link_path);
            return FileUtils.test (p, FileTest.IS_REGULAR) && ImageStore.stamp_for (p) != st.link_stamp;
        }

        public static void update (Publication pub, Story st) throws Error {
            string p = ImageStore.resolve_link (pub, st.link_path);
            string xml;
            FileUtils.get_contents (p, out xml);
            read_into (pub, st, xml);
            st.link_stamp = ImageStore.stamp_for (p);
        }

        public static void write_back (Publication pub, Story st) throws Error {
            if (st.link_path == "") return;
            string p = ImageStore.resolve_link (pub, st.link_path);
            FileUtils.set_contents (p, to_xml (pub, st));
            st.link_stamp = ImageStore.stamp_for (p);
        }

        public static int update_all (Publication pub) {
            int n = 0;
            foreach (var st in pub.stories.values) {
                if (!modified (pub, st)) continue;
                try {
                    update (pub, st);
                    n++;
                } catch (Error e) {
                }
            }
            return n;
        }

        public static Publication open_for_writing (string path) throws Error {
            string xml;
            FileUtils.get_contents (path, out xml);
            return from_story_xml (xml, path);
        }

        public static Publication from_story_xml (string xml, string path) throws Error {
            var s = new DocSettings ();
            s.width = 420;
            s.height = 595;
            s.set_margins (36);
            var p = Publication.create (s, 1);
            var m = p.margin_rect (0);
            var t = p.add_text_frame (p.pages[0].items, m.x, m.y, m.w, m.h);
            t.auto_height = true;
            var st = p.story (t.story);
            read_into (p, st, xml);
            st.link_path = path;
            st.link_stamp = ImageStore.stamp_for (path);
            p.meta.title = Path.get_basename (path);
            return p;
        }
    }
}
