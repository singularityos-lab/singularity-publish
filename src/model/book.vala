namespace Singularity.Apps.Publish {

    public class BookEntry {
        public string path;
        public bool include = true;

        public BookEntry (string path) {
            this.path = path;
        }
    }

    public class Book {
        public const string EXTENSION = "spbook";

        public string path = "";
        public string name = "";
        public Gee.ArrayList<BookEntry> docs = new Gee.ArrayList<BookEntry> ();
        public int style_source = 0;
        public bool continuous = true;

        public static Book load (string path) throws Error {
            string text;
            FileUtils.get_contents (path, out text);
            Xml.Doc* doc = XmlIn.parse (text);
            var b = new Book ();
            b.path = path;
            try {
                var root = doc->get_root_element ();
                if (root->name != "book") throw new FormatError.INVALID (_("This is not a Publish book."));
                b.name = XmlIn.attr (root, "name") ?? "";
                b.style_source = XmlIn.int_attr (root, "style-source", 0);
                b.continuous = XmlIn.int_attr (root, "continuous", 1) == 1;
                foreach (var dn in XmlIn.elements (root, "document")) {
                    string rel = XmlIn.attr (dn, "path") ?? "";
                    if (rel == "") continue;
                    var e = new BookEntry (Path.is_absolute (rel) ? rel : Path.build_filename (Path.get_dirname (path), rel));
                    e.include = XmlIn.int_attr (dn, "include", 1) == 1;
                    b.docs.add (e);
                }
            } finally {
                delete doc;
            }
            return b;
        }

        public string relative (string doc_path) {
            string dir = Path.get_dirname (path);
            if (dir != "" && doc_path.has_prefix (dir + "/")) return doc_path.substring (dir.length + 1);
            return doc_path;
        }

        public void save () throws Error {
            var x = new XmlOut ();
            x.start ("book").a ("name", name).ai ("style-source", style_source).ai ("continuous", continuous ? 1 : 0);
            foreach (var e in docs) x.start ("document").a ("path", relative (e.path)).ai ("include", e.include ? 1 : 0).end ();
            x.end ();
            FileUtils.set_contents (path, x.finish ());
        }

        public Publication open_doc (int i) throws Error {
            uint8[] data;
            FileUtils.get_data (docs[i].path, out data);
            var p = NativeFormat.read (data);
            p.base_dir = Path.get_dirname (docs[i].path);
            return p;
        }

        public void save_doc (int i, Publication p) throws Error {
            FileUtils.set_data (docs[i].path, NativeFormat.write (p));
        }

        public Gee.ArrayList<int> included () {
            var l = new Gee.ArrayList<int> ();
            for (int i = 0; i < docs.size; i++) if (docs[i].include) l.add (i);
            return l;
        }

        public int paginate () throws Error {
            int next = 1;
            foreach (int i in included ()) {
                var p = open_doc (i);
                if (p.sections.size == 0) p.sections.add (new Section (0));
                var first = p.sections[0];
                if (continuous) {
                    first.start_number = next;
                    first.continue_numbering = false;
                }
                save_doc (i, p);
                next = (continuous ? next : 1) + p.pages.size;
            }
            return next - 1;
        }

        public static int copy_styles (Publication src, Publication dst) {
            int n = 0;
            foreach (var ps in src.styles.paragraph) {
                var old = dst.styles.find_paragraph (ps.name);
                if (old != null) dst.styles.paragraph[dst.styles.paragraph.index_of (old)] = ps.clone ();
                else dst.styles.paragraph.add (ps.clone ());
                n++;
            }
            foreach (var cs in src.styles.character) {
                var old = dst.styles.find_character (cs.name);
                if (old != null) dst.styles.character[dst.styles.character.index_of (old)] = cs.clone ();
                else dst.styles.character.add (cs.clone ());
                n++;
            }
            foreach (var sw in src.swatches) {
                var old = dst.swatch (sw.name);
                if (old != null) dst.swatches[dst.swatches.index_of (old)] = sw.clone ();
                else dst.swatches.add (sw.clone ());
                n++;
            }
            foreach (var os in src.object_styles) {
                var old = dst.object_style (os.name);
                if (old != null) dst.object_styles[dst.object_styles.index_of (old)] = os.clone ();
                else dst.object_styles.add (os.clone ());
                n++;
            }
            foreach (var cs in src.cell_styles) {
                var old = TableStyles.find_cell (dst, cs.name);
                if (old != null) dst.cell_styles[dst.cell_styles.index_of (old)] = cs.clone ();
                else dst.cell_styles.add (cs.clone ());
                n++;
            }
            foreach (var ts in src.table_styles) {
                var old = TableStyles.find_table (dst, ts.name);
                if (old != null) dst.table_styles[dst.table_styles.index_of (old)] = ts.clone ();
                else dst.table_styles.add (ts.clone ());
                n++;
            }
            return n;
        }

        public int sync_styles () throws Error {
            if (style_source < 0 || style_source >= docs.size) return 0;
            var src = open_doc (style_source);
            int done = 0;
            for (int i = 0; i < docs.size; i++) {
                if (i == style_source || !docs[i].include) continue;
                var p = open_doc (i);
                copy_styles (src, p);
                TableStyles.update_all (p);
                save_doc (i, p);
                done++;
            }
            return done;
        }

        private static void remap (Publication src, Publication dst, Item it, Gee.HashMap<int, int> ids, Gee.HashMap<int, int> story_ids) {
            int old = it.id;
            it.id = dst.next_id ();
            ids[old] = it.id;
            var t = it as TextFrame;
            if (t != null) {
                if (!story_ids.has_key (t.story)) story_ids[t.story] = dst.next_id ();
                t.story = story_ids[t.story];
            }
            var tb = it as TableItem;
            if (tb != null) foreach (var row in tb.cells) foreach (var c in row) c.story.id = dst.next_id ();
            var g = it as GroupItem;
            if (g != null) foreach (var c in g.children) remap (src, dst, c, ids, story_ids);
        }

        public static void append (Publication dst, Publication src, string master_prefix) {
            var ids = new Gee.HashMap<int, int> ();
            var story_ids = new Gee.HashMap<int, int> ();
            var masters = new Gee.HashMap<string, string> ();
            foreach (var m in src.masters) {
                var nm = m.clone ();
                nm.id = master_prefix + m.id;
                masters[m.id] = nm.id;
                foreach (var it in nm.items) remap (src, dst, it, ids, story_ids);
                foreach (var it in nm.left_items) remap (src, dst, it, ids, story_ids);
                dst.masters.add (nm);
            }
            foreach (var nm in dst.masters) if (masters.has_key (nm.based_on) && nm.id.has_prefix (master_prefix)) nm.based_on = masters[nm.based_on];
            int offset = dst.pages.size;
            foreach (var pg in src.pages) {
                var np = pg.clone ();
                np.id = dst.next_id ();
                np.master = masters.has_key (pg.master) ? masters[pg.master] : "";
                np.overridden.clear ();
                foreach (var it in np.items) remap (src, dst, it, ids, story_ids);
                dst.pages.add (np);
            }
            foreach (var e in story_ids.entries) {
                if (!src.stories.has_key (e.key)) continue;
                var st = src.stories[e.key].clone ();
                st.id = e.value;
                var frames = new Gee.ArrayList<int> ();
                foreach (int f in st.frames) if (ids.has_key (f)) frames.add (ids[f]);
                st.frames = frames;
                dst.stories[st.id] = st;
            }
            foreach (var sec in src.sections) {
                var ns = sec.clone ();
                ns.start_page = sec.start_page + offset;
                if (offset > 0 && sec.start_page == 0) {
                    foreach (var old in dst.sections) if (old.start_page == ns.start_page) {
                        dst.sections.remove (old);
                        break;
                    }
                }
                dst.sections.add (ns);
            }
            copy_missing_styles (src, dst);
            foreach (var kv in src.media.entries) if (!dst.media.has_key (kv.key)) dst.media[kv.key] = kv.value;
        }

        private static void copy_missing_styles (Publication src, Publication dst) {
            foreach (var ps in src.styles.paragraph) if (dst.styles.find_paragraph (ps.name) == null) dst.styles.paragraph.add (ps.clone ());
            foreach (var cs in src.styles.character) if (dst.styles.find_character (cs.name) == null) dst.styles.character.add (cs.clone ());
            foreach (var sw in src.swatches) if (dst.swatch (sw.name) == null) dst.swatches.add (sw.clone ());
            foreach (var os in src.object_styles) if (dst.object_style (os.name) == null) dst.object_styles.add (os.clone ());
            foreach (var cs in src.cell_styles) if (TableStyles.find_cell (dst, cs.name) == null) dst.cell_styles.add (cs.clone ());
            foreach (var ts in src.table_styles) if (TableStyles.find_table (dst, ts.name) == null) dst.table_styles.add (ts.clone ());
        }

        public Publication combine () throws Error {
            var list = included ();
            if (list.size == 0) throw new FormatError.INVALID (_("The book has no documents to include."));
            var first = open_doc (list[0]);
            var all = first.clone ();
            all.base_dir = first.base_dir;
            for (int k = 1; k < list.size; k++) {
                var p = open_doc (list[k]);
                fix_links (p);
                append (all, p, "B%d.".printf (k));
            }
            all.sections.sort ((a, b) => a.start_page - b.start_page);
            if (name != "") all.meta.title = name;
            return all;
        }

        private static void fix_links (Publication p) {
            if (p.base_dir == "") return;
            p.walk ((r) => {
                var im = r.item as ImageFrame;
                if (im != null && im.link != "" && !Path.is_absolute (im.link)) im.link = Path.build_filename (p.base_dir, im.link);
                return true;
            });
        }

        public int generate_toc (int target, TocSettings s) throws Error {
            var all = combine ();
            var cache = new LayoutCache (all);
            var probe = s.clone ();
            probe.story = -1;
            var entries = Toc.collect (all, probe, cache);
            var p = open_doc (target);
            if (s.story == 0 || !p.stories.has_key (s.story) || p.thread_frames (s.story).size == 0) {
                var pg = p.add_page (0, p.pages.size > 0 ? p.pages[0].master : "");
                var m = p.margin_rect (0);
                var frame = p.add_text_frame (pg.items, m.x, m.y, m.w, m.h);
                frame.name = _("Contents");
                s.story = frame.story;
            }
            var frame = Toc.frame_of (p, s.story);
            double width = frame != null ? frame.w - frame.inset_left - frame.inset_right : 300;
            var labels = new Gee.ArrayList<TocEntry> ();
            foreach (var e in entries) labels.add (e);
            Toc.fill_story (all, s, p.story (s.story), labels, width);
            copy_missing_styles (all, p);
            p.toc = s;
            save_doc (target, p);
            return entries.size;
        }

        public int generate_index (int target, IndexSettings s) throws Error {
            var all = combine ();
            var cache = new LayoutCache (all);
            var root = IndexBuilder.collect (all, cache, -1);
            var p = open_doc (target);
            if (s.story == 0 || !p.stories.has_key (s.story) || p.thread_frames (s.story).size == 0) {
                var pg = p.add_page (-1, p.pages.size > 0 ? p.pages[p.pages.size - 1].master : "");
                int pi = p.pages.index_of (pg);
                var m = p.margin_rect (pi);
                var frame = p.add_text_frame (pg.items, m.x, m.y, m.w, m.h);
                frame.columns = 2;
                frame.name = _("Index");
                s.story = frame.story;
            }
            IndexBuilder.fill (all, s, p.story (s.story), root);
            copy_missing_styles (all, p);
            p.index = s;
            save_doc (target, p);
            return root.children.size;
        }

        public int export_pdf (string out_path, ExportOptions opts) throws Error {
            var all = combine ();
            return new Exporter (all, opts).export_pdf (out_path);
        }
    }
}
